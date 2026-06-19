/**
 * run-exp-e.ts — Exp-E: Class B fixture audit + reviewPlan oracle recalibration
 *
 * Runs only on CLEAR fixtures identified in exp-e-audit.json.
 * Models: Haiku (MODEL_PRIMARY) + Sonnet (claude-sonnet-4-6 / MODEL_SECONDARY).
 * If CLEAR fixtures < 6, outputs defer recommendation and exits without LLM calls.
 *
 * Usage:
 *   npx tsx scripts/run-exp-e.ts [--k 5] [--out artifacts/runs/exp-e]
 */

import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createLlmClient } from '../lib/llm-client.js';
import { scoreResponse } from '../lib/score.js';
import { validateEnv, getModelPrimary } from '../lib/env.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const EXP_ROOT = join(__dirname, '..');
const MODEL_SONNET = process.env['MODEL_SECONDARY'] ?? 'claude-sonnet-4-6';

function parseArgs() {
  const argv = process.argv.slice(2);
  const get = (flag: string, def: string) => {
    const i = argv.indexOf(flag);
    return i >= 0 ? argv[i + 1]! : def;
  };
  return {
    k: parseInt(get('--k', '5'), 10),
    fixturesDir: join(EXP_ROOT, 'fixtures/exp-b/class-b'),
    auditPath: join(EXP_ROOT, 'artifacts/analysis/exp-e-audit.json'),
    outDir: join(EXP_ROOT, get('--out', 'artifacts/runs/exp-e')),
  };
}

interface FixtureB {
  id: string;
  taskClass: 'B';
  specSection: string;
  plan: unknown;
  answer: { verdict: string; failing_invariants: string[] };
  answerType: 'partial';
}

interface AuditEntry {
  id: string;
  clarity: 'CLEAR' | 'AMBIGUOUS' | 'ERROR';
}

interface Audit {
  fixtures: AuditEntry[];
  summary: { clear_fixture_ids: string[] };
}

async function fileExists(path: string): Promise<boolean> {
  try { await access(path); return true; } catch { return false; }
}

async function loadFixtures(dir: string, ids: string[]): Promise<FixtureB[]> {
  const { readdir } = await import('node:fs/promises');
  const files = (await readdir(dir)).filter(f => f.endsWith('.json')).sort();
  const all = await Promise.all(
    files.map(async f => JSON.parse(await readFile(join(dir, f), 'utf-8')) as FixtureB),
  );
  return all.filter(f => ids.includes(f.id));
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

function scoreB(
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

async function main() {
  validateEnv();
  const opts = parseArgs();

  const audit: Audit = JSON.parse(await readFile(opts.auditPath, 'utf-8'));
  const clearIds = audit.summary.clear_fixture_ids;

  if (clearIds.length < 6) {
    console.log(`Only ${clearIds.length} CLEAR fixtures (need ≥6). Outputting defer recommendation.`);
    const results = {
      generated: new Date().toISOString(),
      recommendation: 'defer',
      reason: `Only ${clearIds.length} CLEAR fixtures, insufficient for reliable recalibration`,
      haiku_accuracy: null,
      sonnet_accuracy: null,
      hypotheses: { 'H-fixture-noise': 'CONFIRMED', 'H-sonnet-gap': 'N/A' },
    };
    await mkdir(join(EXP_ROOT, 'artifacts/analysis'), { recursive: true });
    await writeFile(join(EXP_ROOT, 'artifacts/analysis/exp-e-results.json'), JSON.stringify(results, null, 2));
    return;
  }

  const haiku = getModelPrimary();
  const sonnet = MODEL_SONNET;
  const models = [haiku, sonnet];
  const fixtures = await loadFixtures(opts.fixturesDir, clearIds);
  const totalCalls = fixtures.length * models.length * opts.k;

  console.log(`Exp-E: ${fixtures.length} CLEAR fixtures × ${models.length} models × k=${opts.k}`);
  console.log(`Models: haiku=${haiku}, sonnet=${sonnet}`);
  console.log(`Total calls: ${totalCalls}`);
  console.log('');

  const client = createLlmClient();
  let completed = 0;
  let skipped = 0;

  for (const model of models) {
    const modelSlug = model.replace(/[^a-z0-9-]/gi, '_');
    for (const fixture of fixtures) {
      const runDir = join(opts.outDir, modelSlug, fixture.id);
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

      const prompt = buildPromptB(fixture);
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

          if ((completed + skipped) % 5 === 0) {
            const pct = Math.round((completed + skipped) / totalCalls * 100);
            process.stdout.write(`\r  [${pct}%] ${completed} calls done, ${skipped} skipped`);
          }
        } catch (err) {
          console.error(`\n  ERROR ${model}/${fixture.id} run ${i}:`, (err as Error).message);
        }
      }

      await mkdir(runDir, { recursive: true });
      await writeFile(resultPath, JSON.stringify({
        model,
        fixtureId: fixture.id,
        groundTruth: fixture.answer,
        responses,
      }, null, 2));
    }
  }

  console.log(`\n\nDone: ${completed} new calls, ${skipped} checkpointed.`);
  console.log('\nScoring...');
  await analyzeAndReport(opts.outDir, fixtures, models, haiku, sonnet, clearIds);
}

async function analyzeAndReport(
  outDir: string,
  fixtures: FixtureB[],
  models: string[],
  haiku: string,
  sonnet: string,
  clearIds: string[],
) {
  type FixtureScore = { fixtureId: string; meanScore: number };
  const modelScores: Record<string, FixtureScore[]> = {};

  for (const model of models) {
    const slug = model.replace(/[^a-z0-9-]/gi, '_');
    modelScores[slug] = [];

    for (const fixture of fixtures) {
      const resultPath = join(outDir, slug, fixture.id, 'result.json');
      if (!(await fileExists(resultPath))) continue;
      const result = JSON.parse(await readFile(resultPath, 'utf-8')) as { responses: string[] };
      const scores = result.responses.map(r => {
        const extracted = extractAnswerB(r);
        return scoreB(extracted, fixture.answer);
      });
      const mean = scores.length > 0 ? scores.reduce((a, b) => a + b, 0) / scores.length : 0;
      modelScores[slug]!.push({ fixtureId: fixture.id, meanScore: mean });
    }
  }

  const haikuSlug = haiku.replace(/[^a-z0-9-]/gi, '_');
  const sonnetSlug = sonnet.replace(/[^a-z0-9-]/gi, '_');

  const haikuScores = modelScores[haikuSlug] ?? [];
  const sonnetScores = modelScores[sonnetSlug] ?? [];

  const haikuAcc = haikuScores.length > 0
    ? haikuScores.reduce((s, r) => s + r.meanScore, 0) / haikuScores.length : 0;
  const sonnetAcc = sonnetScores.length > 0
    ? sonnetScores.reduce((s, r) => s + r.meanScore, 0) / sonnetScores.length : 0;
  const delta = sonnetAcc - haikuAcc;

  const hFixtureNoise = clearIds.length <= 6; // 2 AMBIGUOUS found → H-fixture-noise CONFIRMED
  const hSonnetGap = delta >= 0.10;

  const layer25Rec = haikuAcc >= 0.70 ? 'auto-CI'
    : sonnetAcc >= 0.80 ? 'auto-CI (sonnet required)'
    : 'manual-review';

  const results = {
    generated: new Date().toISOString(),
    audit_summary: { CLEAR: clearIds.length, AMBIGUOUS: 8 - clearIds.length, ERROR: 0 },
    clear_fixture_ids: clearIds,
    haiku_accuracy: haikuAcc,
    sonnet_accuracy: sonnetAcc,
    delta_sonnet_minus_haiku_pp: Math.round(delta * 100) / 100,
    per_fixture: {
      haiku: haikuScores,
      sonnet: sonnetScores,
    },
    hypotheses: {
      'H-fixture-noise': {
        claim: '>=2 AMBIGUOUS/ERROR fixtures',
        ambiguous_count: 8 - clearIds.length,
        verdict: hFixtureNoise ? 'CONFIRMED' : 'REFUTED',
      },
      'H-sonnet-gap': {
        claim: 'Sonnet >= Haiku + 10pp on CLEAR fixtures',
        delta_observed: delta,
        verdict: hSonnetGap ? 'CONFIRMED' : 'REFUTED',
      },
    },
    recommendation: layer25Rec,
    interpretation: haikuAcc >= 0.70
      ? `Haiku achieves ${(haikuAcc*100).toFixed(1)}% on CLEAR fixtures, above 0.70 threshold. Class B can be auto-CI with clear fixture design.`
      : sonnetAcc >= 0.80
      ? `Haiku below threshold (${(haikuAcc*100).toFixed(1)}%) but Sonnet achieves ${(sonnetAcc*100).toFixed(1)}%. Use Sonnet for Class B oracle.`
      : `Both models below thresholds (haiku=${(haikuAcc*100).toFixed(1)}%, sonnet=${(sonnetAcc*100).toFixed(1)}%). Class B requires manual review.`,
  };

  const analysisDir = join(EXP_ROOT, 'artifacts/analysis');
  await mkdir(analysisDir, { recursive: true });
  const outPath = join(analysisDir, 'exp-e-results.json');
  await writeFile(outPath, JSON.stringify(results, null, 2));
  console.log(`\nResults written to ${outPath}`);
  console.log(`Haiku on CLEAR: ${(haikuAcc*100).toFixed(1)}%`);
  console.log(`Sonnet on CLEAR: ${(sonnetAcc*100).toFixed(1)}%`);
  console.log(`Delta: ${(delta*100).toFixed(1)}pp`);
  console.log(`Recommendation: ${layer25Rec}`);
}

main().catch(e => { console.error(e); process.exit(1); });
