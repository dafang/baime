/**
 * run-exp-f.ts — Exp-F: Verify whether reference/ is reliably loaded in skill activation path
 *
 * Tests whether splitting implementation content into reference/ hurts accuracy by comparing:
 *   Variant A: Full SKILL.md with Implementation inline (249 lines, equivalent to Exp-A V2)
 *   Variant B: Spec-only SKILL.md (≤40 lines) — reference/ content NOT injected
 *
 * The runner simulates the skill activation path by injecting SKILL.md content into context,
 * which is what the Claude Code harness does. Variant B tests what happens when only the
 * spec (≤40 lines) is available — matching what would occur if reference/ is NOT auto-loaded.
 *
 * H-ref: variant_b_accuracy < variant_a_accuracy - 10pp (reference/ not auto-loaded)
 * H-load: variant_b_accuracy >= variant_a_accuracy - 5pp (reference/ load effective)
 *
 * Usage:
 *   npx tsx exp-f/run-exp-f.ts [--k 5] [--out ../artifacts/runs/exp-f]
 */

import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createLlmClient } from '../lib/llm-client.js';
import { extractAnswer, scoreResponse } from '../lib/score.js';
import { validateEnv, getModelPrimary } from '../lib/env.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const EXP_ROOT = join(__dirname, '..');

function parseArgs() {
  const argv = process.argv.slice(2);
  const get = (flag: string, def: string) => {
    const i = argv.indexOf(flag);
    return i >= 0 ? argv[i + 1]! : def;
  };
  return {
    k: parseInt(get('--k', '5'), 10),
    fixturesDir: join(EXP_ROOT, 'fixtures/exp-a'),
    outDir: join(EXP_ROOT, get('--out', 'artifacts/runs/exp-f')),
    variantADir: join(__dirname, 'variant-a'),
    variantBDir: join(__dirname, 'variant-b'),
  };
}

interface Fixture {
  id: string;
  taskClass: string;
  templateMeta: { slug: string; lastUsed: string; applicableWhen: string };
  recentChanges: string[];
  answer: string;
  answerType: 'exact';
}

async function fileExists(path: string): Promise<boolean> {
  try { await access(path); return true; } catch { return false; }
}

async function loadFixtures(dir: string): Promise<Fixture[]> {
  const { readdir } = await import('node:fs/promises');
  const files = (await readdir(dir)).filter(f => f.endsWith('.json')).sort();
  return Promise.all(
    files.map(async f => JSON.parse(await readFile(join(dir, f), 'utf-8')) as Fixture),
  );
}

function buildPrompt(skillContent: string, fixture: Fixture): string {
  const { templateMeta, recentChanges } = fixture;
  const changesList = recentChanges.map(c => `  - ${c}`).join('\n');
  return [
    'You are executing the freshnessCheck step of task-from-template.',
    'The following is the SKILL.md content loaded by the skill activation system:',
    '',
    '--- SKILL.md START ---',
    skillContent,
    '--- SKILL.md END ---',
    '',
    'Now perform the freshnessCheck for this template:',
    '',
    'Template:',
    `  slug: ${templateMeta.slug}`,
    `  lastUsed: ${templateMeta.lastUsed}`,
    `  applicableWhen: ${templateMeta.applicableWhen}`,
    '',
    `Recent git changes since ${templateMeta.lastUsed}:`,
    changesList || '  (no changes)',
    '',
    'Output ONLY valid JSON:',
    '{"answer": "FRESH"} or {"answer": "STALE", "reason": "<one line>"}',
  ].join('\n');
}

async function main() {
  validateEnv();
  const opts = parseArgs();
  const client = createLlmClient();
  const model = getModelPrimary();

  const variantAContent = await readFile(join(opts.variantADir, 'SKILL.md'), 'utf-8');
  const variantBContent = await readFile(join(opts.variantBDir, 'SKILL.md'), 'utf-8');

  const variants = [
    { name: 'variant-a', content: variantAContent, label: 'full-implementation' },
    { name: 'variant-b', content: variantBContent, label: 'spec-only-no-reference' },
  ] as const;

  const fixtures = await loadFixtures(opts.fixturesDir);

  const totalCalls = fixtures.length * variants.length * opts.k;
  console.log(`Exp-F: ${fixtures.length} fixtures × ${variants.length} variants × k=${opts.k} = ${totalCalls} calls`);
  console.log(`Model: ${model}`);
  console.log(`Variant A: ${variantAContent.split('\n').length} lines (full implementation)`);
  console.log(`Variant B: ${variantBContent.split('\n').length} lines (spec-only, no reference/)`);
  console.log('');

  let completed = 0;
  let skipped = 0;

  for (const variant of variants) {
    for (const fixture of fixtures) {
      const runDir = join(opts.outDir, variant.name, fixture.id);
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

      const prompt = buildPrompt(variant.content, fixture);

      for (let i = 0; i < needed; i++) {
        try {
          const resp = await client.chat({
            model,
            messages: [{ role: 'user', content: prompt }],
          });
          responses.push(resp.content);
          completed++;

          if ((completed + skipped) % 5 === 0) {
            const pct = Math.round((completed + skipped) / totalCalls * 100);
            process.stdout.write(`\r  [${pct}%] ${completed} done, ${skipped} skipped`);
          }
        } catch (err) {
          console.error(`\n  ERROR ${variant.name}/${fixture.id} run ${i}:`, (err as Error).message);
        }
      }

      await mkdir(runDir, { recursive: true });
      await writeFile(resultPath, JSON.stringify({
        variant: variant.name,
        label: variant.label,
        model,
        fixtureId: fixture.id,
        groundTruth: fixture.answer,
        responses,
      }, null, 2));
    }
  }

  console.log(`\n\nDone: ${completed} new, ${skipped} checkpointed.`);
  console.log('\nScoring...');
  await analyze(opts.outDir, opts.fixturesDir, model);
}

async function analyze(outDir: string, fixturesDir: string, model: string) {
  const { readdir } = await import('node:fs/promises');
  const files = (await readdir(fixturesDir)).filter(f => f.endsWith('.json')).sort();
  const fixtures = await Promise.all(
    files.map(async f => JSON.parse(await readFile(join(fixturesDir, f), 'utf-8')) as Fixture),
  );

  type FixResult = { fixtureId: string; groundTruth: string; meanScore: number };

  async function scoreVariant(variant: string): Promise<FixResult[]> {
    const results: FixResult[] = [];
    for (const fixture of fixtures) {
      const resultPath = join(outDir, variant, fixture.id, 'result.json');
      if (!(await fileExists(resultPath))) continue;
      const data = JSON.parse(await readFile(resultPath, 'utf-8')) as { responses: string[] };
      const scores = data.responses.map(r => scoreResponse(extractAnswer(r), fixture.answer, 'exact'));
      const mean = scores.length > 0 ? scores.reduce((a, b) => a + b, 0) / scores.length : 0;
      results.push({ fixtureId: fixture.id, groundTruth: fixture.answer, meanScore: mean });
    }
    return results;
  }

  const aResults = await scoreVariant('variant-a');
  const bResults = await scoreVariant('variant-b');

  const acc = (rs: FixResult[]) =>
    rs.length > 0 ? rs.reduce((s, r) => s + r.meanScore, 0) / rs.length : 0;

  const variantAAcc = acc(aResults);
  const variantBAcc = acc(bResults);
  const delta = variantAAcc - variantBAcc;

  const hRefConfirmed = delta >= 0.10;
  const hLoadConfirmed = delta < 0.05;

  const out = {
    generated: new Date().toISOString(),
    model,
    exp_a_reference: { accuracy: 0.92, variant: 'full-implementation' },
    exp_d_p_spec_reference: { accuracy: 0.70, variant: 'spec-only' },
    variant_a_accuracy: Math.round(variantAAcc * 1000) / 1000,
    variant_b_accuracy: Math.round(variantBAcc * 1000) / 1000,
    delta_pp: Math.round(delta * 100) / 100,
    per_fixture: {
      'variant-a': aResults,
      'variant-b': bResults,
    },
    hypotheses: {
      'H-ref': {
        description: 'variant_b_accuracy < variant_a_accuracy - 10pp (reference/ not auto-loaded)',
        verdict: hRefConfirmed ? 'CONFIRMED' : 'REFUTED',
        delta_observed: delta,
        threshold: 0.10,
      },
      'H-load': {
        description: 'variant_b_accuracy >= variant_a_accuracy - 5pp (reference/ load effective)',
        verdict: hLoadConfirmed ? 'CONFIRMED' : 'REFUTED',
        delta_observed: delta,
        threshold: 0.05,
      },
    },
    hypothesis: hRefConfirmed ? 'H-ref CONFIRMED' : (hLoadConfirmed ? 'H-load CONFIRMED' : 'INCONCLUSIVE'),
    interpretation: hRefConfirmed
      ? `reference/ content NOT loaded by skill activation: ${Math.round(delta * 100)}pp drop without it. Recommendation: abolish ≤40-line constraint; keep implementation in SKILL.md.`
      : hLoadConfirmed
      ? `reference/ content effectively loaded: only ${Math.round(delta * 100)}pp gap. ≤40-line constraint is viable.`
      : `Gap of ${Math.round(delta * 100)}pp is inconclusive (between 5pp and 10pp thresholds).`,
    architecture_recommendation: hRefConfirmed
      ? 'Abolish ≤40-line constraint. Implementation content must stay in SKILL.md.'
      : 'Retain ≤40-line constraint with mandatory reference/ load verification in contracts.',
  };

  const analysisDir = join(EXP_ROOT, 'artifacts', 'analysis');
  await mkdir(analysisDir, { recursive: true });
  const outPath = join(analysisDir, 'exp-f-results.json');
  await writeFile(outPath, JSON.stringify(out, null, 2));

  console.log(`\nResults: ${outPath}`);
  console.log(`Variant A (inline):    ${variantAAcc.toFixed(3)}`);
  console.log(`Variant B (spec-only): ${variantBAcc.toFixed(3)}`);
  console.log(`Delta: ${(delta * 100).toFixed(1)}pp`);
  console.log(`H-ref: ${out.hypotheses['H-ref'].verdict}`);
  console.log(`Hypothesis: ${out.hypothesis}`);
}

main().catch(e => { console.error(e); process.exit(1); });
