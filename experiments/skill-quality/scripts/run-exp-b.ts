/**
 * run-exp-b.ts — Exp-B: Haiku Oracle Calibration (Layer 2.5 prerequisite)
 *
 * Usage:
 *   npx tsx scripts/run-exp-b.ts [--classes A,B,C] [--k 5]
 *                                [--fixtures experiments/skill-quality/fixtures/exp-b]
 *                                [--out artifacts/runs/exp-b]
 *
 * Reads .env automatically via lib/env.ts.
 * Checkpoint/resume: skips (class, model, fixtureId) combos with existing result.json.
 *
 * Class A: binary-gate (freshnessCheck) — exact scoring
 * Class B: invariant-check (reviewPlan) — partial scoring {verdict, failing_invariants}
 * Class C: branch-selection (verifyDod) — exact scoring
 */

import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createLlmClient } from '../lib/llm-client.js';
import { scoreResponse } from '../lib/score.js';
import { validateEnv, getModelPrimary, getModelSecondary } from '../lib/env.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const EXP_ROOT = join(__dirname, '..');

// ── CLI arg parsing ───────────────────────────────────────────────────────────

function parseArgs() {
  const argv = process.argv.slice(2);
  const get = (flag: string, def: string) => {
    const i = argv.indexOf(flag);
    return i >= 0 ? argv[i + 1]! : def;
  };
  return {
    classes: get('--classes', 'A,B,C').split(',').map(s => s.trim()),
    k: parseInt(get('--k', '5'), 10),
    fixturesDir: join(EXP_ROOT, get('--fixtures', 'fixtures/exp-b')),
    outDir: join(EXP_ROOT, get('--out', 'artifacts/runs/exp-b')),
  };
}

// ── Fixture types ─────────────────────────────────────────────────────────────

interface FixtureA {
  id: string;
  taskClass: 'A';
  taskType: 'binary-gate';
  templateMeta: { slug: string; lastUsed: string; applicableWhen: string };
  recentChanges: string[];
  answer: string;
  answerType: 'exact';
}

interface FixtureB {
  id: string;
  taskClass: 'B';
  taskType: 'invariant-check';
  specSection: string;
  plan: unknown;
  answer: { verdict: string; failing_invariants: string[] };
  answerType: 'partial';
}

interface FixtureC {
  id: string;
  taskClass: 'C';
  taskType: 'branch-selection';
  specSection: string;
  state: { exitCode: number; attempts_so_far: number };
  answer: string;
  answerType: 'exact';
}

type AnyFixture = FixtureA | FixtureB | FixtureC;

// ── Helpers ───────────────────────────────────────────────────────────────────

async function fileExists(path: string): Promise<boolean> {
  try { await access(path); return true; } catch { return false; }
}

async function loadFixtures(dir: string): Promise<AnyFixture[]> {
  const { readdir } = await import('node:fs/promises');
  const files = (await readdir(dir)).filter(f => f.endsWith('.json')).sort();
  return Promise.all(
    files.map(async f => JSON.parse(await readFile(join(dir, f), 'utf-8')) as AnyFixture),
  );
}

async function loadVariantV0(): Promise<string> {
  const path = join(EXP_ROOT, 'variants', 'task-from-template-v0.md');
  return readFile(path, 'utf-8');
}

// ── Prompt builders ───────────────────────────────────────────────────────────

function buildPromptA(variantContent: string, fixture: FixtureA): string {
  const { templateMeta, recentChanges } = fixture;
  const changesList = recentChanges.map(c => `  - ${c}`).join('\n');
  return [
    'You are executing the freshnessCheck step of task-from-template.',
    '',
    variantContent,
    '',
    'Template:',
    `  slug: ${templateMeta.slug}`,
    `  lastUsed: ${templateMeta.lastUsed}`,
    `  applicableWhen: ${templateMeta.applicableWhen}`,
    '',
    `Recent git changes since ${templateMeta.lastUsed}:`,
    changesList || '  (no changes)',
    '',
    'Based on the freshnessCheck spec above, output ONLY valid JSON:',
    '{"answer": "FRESH"} or {"answer": "STALE", "reason": "<one line>"}',
  ].join('\n');
}

function buildPromptB(fixture: FixtureB): string {
  return [
    'You are reviewing a task implementation plan against the reviewPlan specification.',
    '',
    '## Spec',
    fixture.specSection,
    '',
    '## Plan to Review',
    '```json',
    JSON.stringify(fixture.plan, null, 2),
    '```',
    '',
    'Check whether this plan satisfies all invariants in the spec.',
    'Output ONLY valid JSON with this structure:',
    '{"verdict": "APPROVED" | "NEEDS_REVISION", "failing_invariants": ["<invariant expression>", ...]}',
    '',
    'If the plan is APPROVED, "failing_invariants" must be an empty array [].',
    'For NEEDS_REVISION, list each violated invariant expression exactly as it appears in the spec (e.g. "¬empty(phases)", "isShellCmd(dod[0])").',
  ].join('\n');
}

function buildPromptC(fixture: FixtureC): string {
  return [
    'You are evaluating the verifyDod branch selection according to the spec.',
    '',
    '## Spec',
    fixture.specSection,
    '',
    '## Current State',
    '```json',
    JSON.stringify(fixture.state, null, 2),
    '```',
    '',
    'Given this state, which branch does the spec select?',
    'Output ONLY valid JSON:',
    '{"answer": "checkDod" | "fix_retry" | "raise_Stuck"}',
  ].join('\n');
}

// ── Answer extractors ─────────────────────────────────────────────────────────

function extractAnswerA(response: string): unknown {
  const jsonMatch = response.match(/\{[^{}]*"answer"\s*:[^{}]*\}/);
  if (jsonMatch) {
    try { return JSON.parse(jsonMatch[0]).answer; } catch {}
  }
  const fenceMatch = response.match(/```(?:json)?\s*(\{[\s\S]*?\})\s*```/);
  if (fenceMatch) {
    try { return JSON.parse(fenceMatch[1]!).answer; } catch {}
  }
  return null;
}

function extractAnswerB(response: string): { verdict?: string; items?: string[] } | null {
  const tryParse = (s: string) => {
    try {
      const obj = JSON.parse(s);
      if (obj && typeof obj === 'object' && 'verdict' in obj) {
        return {
          verdict: obj.verdict,
          items: Array.isArray(obj.failing_invariants) ? obj.failing_invariants : [],
        };
      }
    } catch {}
    return null;
  };

  const fenceMatch = response.match(/```(?:json)?\s*(\{[\s\S]*?\})\s*```/);
  if (fenceMatch) {
    const r = tryParse(fenceMatch[1]!);
    if (r) return r;
  }

  const jsonMatch = response.match(/\{[\s\S]*"verdict"[\s\S]*\}/);
  if (jsonMatch) {
    const r = tryParse(jsonMatch[0]);
    if (r) return r;
  }

  return null;
}

function extractAnswerC(response: string): unknown {
  return extractAnswerA(response);
}

// ── Scoring ───────────────────────────────────────────────────────────────────

function scoreResponseB(
  extracted: { verdict?: string; items?: string[] } | null,
  groundTruth: { verdict: string; failing_invariants: string[] },
): number {
  if (!extracted) return 0;
  return scoreResponse(
    extracted,
    { verdict: groundTruth.verdict, items: groundTruth.failing_invariants },
    'partial',
  );
}

// ── Main ──────────────────────────────────────────────────────────────────────

const MODEL_UPPER = process.env['MODEL_UPPER'] ?? 'claude-sonnet-4-6';

async function main() {
  validateEnv();
  const opts = parseArgs();
  const client = createLlmClient();
  const primary = getModelPrimary();
  const secondary = getModelSecondary();

  const classModels: Record<string, string[]> = {
    A: [primary, secondary],
    B: [primary, secondary],
    C: [primary, secondary, MODEL_UPPER],
  };

  let totalFixtures = 0;
  for (const cls of opts.classes) {
    const fixtures = await loadFixtures(join(opts.fixturesDir, `class-${cls.toLowerCase()}`));
    totalFixtures += fixtures.length * classModels[cls]!.length * opts.k;
  }

  console.log(`Exp-B: ${opts.classes.join('/')} classes, k=${opts.k}`);
  console.log(`Total calls: ${totalFixtures}`);
  console.log(`Output: ${opts.outDir}`);
  console.log('');

  let completed = 0;
  let skipped = 0;
  const variantV0 = await loadVariantV0();

  for (const cls of opts.classes) {
    const classDir = join(opts.fixturesDir, `class-${cls.toLowerCase()}`);
    const fixtures = await loadFixtures(classDir);
    const models = classModels[cls]!;

    for (const fixture of fixtures) {
      for (const model of models) {
        const modelSlug = model.replace(/[^a-z0-9-]/gi, '_');
        const runDir = join(opts.outDir, cls, modelSlug, fixture.id);
        const resultPath = join(runDir, 'result.json');

        let responses: string[] = [];
        if (await fileExists(resultPath)) {
          const existing = JSON.parse(await readFile(resultPath, 'utf-8')) as { responses: string[] };
          responses = existing.responses ?? [];
        }

        const needed = opts.k - responses.length;
        if (needed <= 0) {
          skipped += opts.k;
          continue;
        }

        let prompt: string;
        if (fixture.taskClass === 'A') {
          prompt = buildPromptA(variantV0, fixture as FixtureA);
        } else if (fixture.taskClass === 'B') {
          prompt = buildPromptB(fixture as FixtureB);
        } else {
          prompt = buildPromptC(fixture as FixtureC);
        }

        const isGlm = model.toLowerCase().includes('glm');
        const extra_body = isGlm ? { thinking: { type: 'disabled' } } : undefined;

        for (let i = 0; i < needed; i++) {
          try {
            const resp = await client.chat({
              model,
              messages: [{ role: 'user', content: prompt }],
              ...(extra_body ? { extra_body } : {}),
            });
            responses.push(resp.content);
            completed++;

            if ((completed + skipped) % 10 === 0) {
              const pct = Math.round((completed + skipped) / totalFixtures * 100);
              process.stdout.write(`\r  [${pct}%] ${completed} calls done, ${skipped} skipped`);
            }
          } catch (err) {
            console.error(`\n  ERROR ${cls}/${model}/${fixture.id} run ${i}:`, (err as Error).message);
          }
        }

        await mkdir(runDir, { recursive: true });
        await writeFile(resultPath, JSON.stringify({
          taskClass: cls,
          model,
          fixtureId: fixture.id,
          groundTruth: fixture.answer,
          responses,
        }, null, 2));
        await writeFile(join(runDir, 'task.json'), JSON.stringify({ task: fixture }, null, 2));
      }
    }
  }

  console.log(`\n\nDone: ${completed} new calls, ${skipped} checkpointed.`);

  console.log('\nScoring results...');
  await scoreAndReport(opts.outDir, opts.fixturesDir, opts.classes, classModels, variantV0);
}

// ── Scoring + report ──────────────────────────────────────────────────────────

async function scoreAndReport(
  outDir: string,
  fixturesDir: string,
  classes: string[],
  classModels: Record<string, string[]>,
  _variantV0: string,
) {
  type Acc = { sum: number; count: number };
  const classModelAcc: Record<string, Record<string, Acc>> = {};

  for (const cls of classes) {
    classModelAcc[cls] = {};
    const fixtures = await loadFixtures(join(fixturesDir, `class-${cls.toLowerCase()}`));
    for (const model of classModels[cls]!) {
      const modelSlug = model.replace(/[^a-z0-9-]/gi, '_');
      classModelAcc[cls]![modelSlug] = { sum: 0, count: 0 };

      for (const fixture of fixtures) {
        const runDir = join(outDir, cls, modelSlug, fixture.id);
        const resultPath = join(runDir, 'result.json');
        if (!(await fileExists(resultPath))) continue;

        const result = JSON.parse(await readFile(resultPath, 'utf-8')) as { responses: string[] };
        const scores = result.responses.map(r => {
          if (fixture.taskClass === 'B') {
            const extracted = extractAnswerB(r);
            return scoreResponseB(extracted, fixture.answer as { verdict: string; failing_invariants: string[] });
          } else {
            const extracted = fixture.taskClass === 'C' ? extractAnswerC(r) : extractAnswerA(r);
            return scoreResponse(extracted, fixture.answer, fixture.answerType as 'exact');
          }
        });
        const mean = scores.length > 0 ? scores.reduce((a, b) => a + b, 0) / scores.length : 0;
        classModelAcc[cls]![modelSlug]!.sum += mean;
        classModelAcc[cls]![modelSlug]!.count++;
      }
    }
  }

  const classAccuracy: Record<string, Record<string, number>> = {};
  for (const cls of classes) {
    classAccuracy[cls] = {};
    for (const model of classModels[cls]!) {
      const slug = model.replace(/[^a-z0-9-]/gi, '_');
      const acc = classModelAcc[cls]![slug]!;
      classAccuracy[cls]![slug] = acc.count > 0 ? acc.sum / acc.count : 0;
    }
  }

  const primary = getModelPrimary();
  const primarySlug = primary.replace(/[^a-z0-9-]/gi, '_');

  const thresholds: Record<string, number> = { A: 0.85, B: 0.70, C: 0.80 };
  const hypotheses: Record<string, { verdict: string; haiku_f1: number; threshold: number }> = {};
  const recommendations: Record<string, string> = {};

  for (const cls of ['A', 'B', 'C']) {
    const f1 = classAccuracy[cls]?.[primarySlug] ?? 0;
    const threshold = thresholds[cls]!;
    const confirmed = f1 >= threshold;
    hypotheses[`H-oracle-${cls}`] = {
      verdict: confirmed ? 'CONFIRMED' : 'REJECTED',
      haiku_f1: f1,
      threshold,
    };
    recommendations[cls] = confirmed ? 'auto-CI' : 'manual-review';
  }

  const upperSlug = MODEL_UPPER.replace(/[^a-z0-9-]/gi, '_');
  const haikuC = classAccuracy['C']?.[primarySlug] ?? 0;
  const sonnetC = classAccuracy['C']?.[upperSlug] ?? 0;

  const results = {
    generated: new Date().toISOString(),
    class_accuracy: classAccuracy,
    hypotheses,
    cross_model_rho: null,
    haiku_vs_sonnet_C: { haiku: haikuC, sonnet: sonnetC, gap: sonnetC - haikuC },
    layer25_recommendations: recommendations,
  };

  const analysisDir = join(EXP_ROOT, 'artifacts', 'analysis');
  await mkdir(analysisDir, { recursive: true });
  const outPath = join(analysisDir, 'exp-b-results.json');
  await writeFile(outPath, JSON.stringify(results, null, 2));
  console.log(`\nResults written to ${outPath}`);
  console.log(JSON.stringify(hypotheses, null, 2));
  console.log('Recommendations:', recommendations);
}

main().catch(e => { console.error(e); process.exit(1); });
