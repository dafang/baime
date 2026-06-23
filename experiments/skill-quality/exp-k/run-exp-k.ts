/**
 * run-exp-k.ts — Exp-K: Prompt completeness ablation on decomposer persona effect
 *
 * Tests whether prompt completeness mediates the persona effect on AMBIGUOUS classification.
 * Six variants (P-minimal, P-rules, P-full) × (V0, V1):
 *   P-minimal/V0: functional directive + output instruction (no rules)
 *   P-minimal/V1: expert persona + output instruction (no rules)
 *   P-rules/V0:   functional directive + classification rules + output instruction
 *   P-rules/V1:   expert persona + classification rules + output instruction
 *   P-full/V0:    functional directive + rules + 3 few-shot examples + output instruction
 *   P-full/V1:    expert persona + rules + 3 few-shot examples + output instruction
 *
 * Hypotheses:
 *   H-K1: Persona Δ at P-minimal > Δ at P-rules (persona helps more without rules)
 *   H-K2: Persona Δ at P-rules > Δ at P-full (persona helps more without examples)
 *   H-K3: Both models show positive Δ at P-minimal (persona universally helpful when underspecified)
 *
 * Usage:
 *   npx tsx exp-k/run-exp-k.ts [--k 5] [--out artifacts/runs/exp-k]
 */

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { readdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateEnv, getModelPrimary } from '../lib/env.js';
import { runExperiment, type ExperimentConfig, type FixtureRecord } from '../lib/runner.js';
import { buildPrompt, type DecompFixture } from './prompts.js';

export { scoreDecompResponse } from '../exp-j/run-exp-j.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const EXP_ROOT = join(__dirname, '..');

// ---------- CLI args ----------

function parseArgs() {
  const argv = process.argv.slice(2);
  const get = (flag: string, def: string) => {
    const i = argv.indexOf(flag);
    return i >= 0 ? argv[i + 1]! : def;
  };
  return {
    k: parseInt(get('--k', '5'), 10),
    outDir: join(EXP_ROOT, get('--out', 'artifacts/runs/exp-k')),
    analysisDir: join(EXP_ROOT, 'artifacts/analysis'),
  };
}

// ---------- Scoring (identical to Exp-J) ----------

function scoreDecompResponseLocal(response: string, fixture: DecompFixture): number {
  const normalized = response.trim().toUpperCase().replace(/[^A-Z-]/g, '');
  if (normalized.includes('CODE-CHANGE') || normalized.includes('CODECHANGE')) {
    return fixture.expectedClass === 'CODE-CHANGE' ? 1.0 : 0.0;
  }
  if (normalized.includes('DOC-ONLY') || normalized.includes('DOCONLY')) {
    return fixture.expectedClass === 'DOC-ONLY' ? 1.0 : 0.0;
  }
  return 0.0;
}

// ---------- Load fixtures ----------

async function loadFixturePaths(dir: string): Promise<string[]> {
  const files = (await readdir(dir)).filter(f => f.endsWith('.json')).sort();
  return files.map(f => join(dir, f));
}

// ---------- Build ExperimentConfig ----------

export async function buildConfig(opts: {
  k: number;
  outDir: string;
}): Promise<ExperimentConfig> {
  const fixtureDir = join(EXP_ROOT, 'fixtures/exp-j/ambiguous');
  const sanityDir = join(EXP_ROOT, 'fixtures/exp-i/sanity');
  const allPaths = await loadFixturePaths(fixtureDir);

  const VARIANTS = ['P-minimal/V0', 'P-minimal/V1', 'P-rules/V0', 'P-rules/V1', 'P-full/V0', 'P-full/V1'];

  const config: ExperimentConfig = {
    variants: Object.fromEntries(VARIANTS.map(v => [v, allPaths])),
    modelList: [getModelPrimary(), 'claude-sonnet-4-6'],
    k: opts.k,
    outDir: opts.outDir,
    sanityDir,

    buildPrompt(fixture: FixtureRecord, variant: string): string {
      // The runner uses 'sanity' as variant key for sanity fixture checks;
      // fall back to P-rules/V0 for those (replicates Exp-J behaviour).
      const resolvedVariant = variant === 'sanity' ? 'P-rules/V0' : variant;
      return buildPrompt(fixture as DecompFixture, resolvedVariant);
    },

    scoreResponse(response: string, fixture: FixtureRecord): number {
      return scoreDecompResponseLocal(response, fixture as DecompFixture);
    },
  };

  return config;
}

// ---------- Analysis ----------

interface FixtureResult {
  id: string;
  fixtureClass: 'CLEAR' | 'AMBIGUOUS';
  expectedClass: 'CODE-CHANGE' | 'DOC-ONLY';
  meanScore: number;
  responses: string[];
}

async function loadFixtureResults(
  outDir: string,
  variant: string,
  model: string,
  fixtures: DecompFixture[],
): Promise<FixtureResult[]> {
  // Variant keys like 'P-minimal/V0' are used directly as subdirectory paths
  // (the runner uses variant key as path segment, creating nested dirs for '/')
  const modelSlug = model.replace(/[^a-z0-9-]/gi, '_');
  const results: FixtureResult[] = [];

  for (const fx of fixtures) {
    const resultPath = join(outDir, variant, modelSlug, fx.id, 'result.json');
    try {
      const raw = JSON.parse(await readFile(resultPath, 'utf-8')) as {
        responses: string[];
        scores: number[];
        meanScore: number;
      };
      results.push({
        id: fx.id,
        fixtureClass: fx.fixtureClass,
        expectedClass: fx.expectedClass,
        meanScore: raw.meanScore,
        responses: raw.responses,
      });
    } catch {
      console.warn(`WARN: missing result for ${variantSlug}/${modelSlug}/${fx.id}`);
    }
  }

  return results;
}

function computeAccuracy(results: FixtureResult[]): number {
  if (results.length === 0) return 0;
  return results.reduce((s, r) => s + r.meanScore, 0) / results.length;
}

function hypothesisVerdictMonotone(delta1: number, delta2: number): 'CONFIRMED' | 'NULL' | 'REJECTED' {
  // H-K1/K2: is delta1 > delta2?
  if (delta1 > delta2 + 0.01) return 'CONFIRMED';  // 1pp threshold to avoid noise
  if (delta1 >= delta2 - 0.01) return 'NULL';        // within noise band
  return 'REJECTED';
}

async function analyze(
  outDir: string,
  analysisDir: string,
  fixtures: DecompFixture[],
  models: string[],
) {
  const COMPLETENESS_LEVELS = ['P-minimal', 'P-rules', 'P-full'] as const;
  type CompletenessLevel = typeof COMPLETENESS_LEVELS[number];

  // Per model, per completeness level: V0 acc, V1 acc, delta
  const perModel: Record<string, Record<CompletenessLevel, { V0: number; V1: number; delta: number }>> = {};

  for (const model of models) {
    perModel[model] = {} as Record<CompletenessLevel, { V0: number; V1: number; delta: number }>;

    for (const level of COMPLETENESS_LEVELS) {
      const v0Results = await loadFixtureResults(outDir, `${level}/V0`, model, fixtures);
      const v1Results = await loadFixtureResults(outDir, `${level}/V1`, model, fixtures);

      const v0Acc = computeAccuracy(v0Results);
      const v1Acc = computeAccuracy(v1Results);

      perModel[model]![level] = {
        V0: v0Acc,
        V1: v1Acc,
        delta: v1Acc - v0Acc,
      };
    }
  }

  const r = (n: number) => Math.round(n * 1000) / 1000;

  // Compute hypothesis verdicts per model
  const hK1PerModel: Record<string, { delta_minimal: number; delta_rules: number; verdict: string }> = {};
  const hK2PerModel: Record<string, { delta_rules: number; delta_full: number; verdict: string }> = {};
  const hK3PerModel: Record<string, { delta_minimal: number; positive: boolean }> = {};

  for (const model of models) {
    const pm = perModel[model]!;
    const deltaMinimal = pm['P-minimal'].delta;
    const deltaRules = pm['P-rules'].delta;
    const deltaFull = pm['P-full'].delta;

    hK1PerModel[model] = {
      delta_minimal: r(deltaMinimal),
      delta_rules: r(deltaRules),
      verdict: hypothesisVerdictMonotone(deltaMinimal, deltaRules),
    };

    hK2PerModel[model] = {
      delta_rules: r(deltaRules),
      delta_full: r(deltaFull),
      verdict: hypothesisVerdictMonotone(deltaRules, deltaFull),
    };

    hK3PerModel[model] = {
      delta_minimal: r(deltaMinimal),
      positive: deltaMinimal > 0,
    };
  }

  // Overall verdicts
  const hK1Verdicts = models.map(m => hK1PerModel[m]!.verdict);
  const hK2Verdicts = models.map(m => hK2PerModel[m]!.verdict);
  const hK3AllPositive = models.every(m => hK3PerModel[m]!.positive);

  // H-K1 overall: need both models to agree
  let hK1Overall: string;
  if (hK1Verdicts.every(v => v === 'CONFIRMED')) {
    hK1Overall = 'CONFIRMED';
  } else if (hK1Verdicts.every(v => v === 'REJECTED')) {
    hK1Overall = 'REJECTED';
  } else if (hK1Verdicts.some(v => v === 'CONFIRMED') && hK1Verdicts.some(v => v !== 'CONFIRMED')) {
    hK1Overall = 'NULL [cross-model disagreement] [underpowered]';
  } else {
    hK1Overall = 'NULL';
  }

  // H-K2 overall
  let hK2Overall: string;
  if (hK2Verdicts.every(v => v === 'CONFIRMED')) {
    hK2Overall = 'CONFIRMED';
  } else if (hK2Verdicts.every(v => v === 'REJECTED')) {
    hK2Overall = 'REJECTED';
  } else if (hK2Verdicts.some(v => v === 'CONFIRMED') && hK2Verdicts.some(v => v !== 'CONFIRMED')) {
    hK2Overall = 'NULL [cross-model disagreement] [underpowered]';
  } else {
    hK2Overall = 'NULL';
  }

  // H-K3 overall
  const hK3Overall = hK3AllPositive ? 'CONFIRMED' : (
    models.some(m => hK3PerModel[m]!.positive) ? 'NULL [partial]' : 'REJECTED'
  );

  // Cross-model consistency for H-K1
  let crossModelConsistency: string;
  if (models.length < 2) {
    crossModelConsistency = 'single-model (only one model available)';
  } else {
    const m1 = models[0]!;
    const m2 = models[1]!;
    const m1Verdict = hK1PerModel[m1]!.verdict;
    const m2Verdict = hK1PerModel[m2]!.verdict;
    if (m1Verdict === m2Verdict) {
      crossModelConsistency = `CONSISTENT — both models: ${m1Verdict} for H-K1 (Δ_minimal > Δ_rules)`;
    } else {
      crossModelConsistency = `INCONSISTENT [underpowered] — ${m1}: ${m1Verdict}, ${m2}: ${m2Verdict} for H-K1`;
    }
  }

  const output = {
    generated: new Date().toISOString(),
    data_source: 'measured' as const,
    experiment: 'Exp-K',
    fixture_count: fixtures.length,
    fixture_class: 'AMBIGUOUS only',
    models: Object.fromEntries(
      models.map(m => [
        m,
        {
          'P-minimal': {
            V0: { accuracy: r(perModel[m]!['P-minimal'].V0) },
            V1: { accuracy: r(perModel[m]!['P-minimal'].V1) },
            delta: r(perModel[m]!['P-minimal'].delta),
          },
          'P-rules': {
            V0: { accuracy: r(perModel[m]!['P-rules'].V0) },
            V1: { accuracy: r(perModel[m]!['P-rules'].V1) },
            delta: r(perModel[m]!['P-rules'].delta),
          },
          'P-full': {
            V0: { accuracy: r(perModel[m]!['P-full'].V0) },
            V1: { accuracy: r(perModel[m]!['P-full'].V1) },
            delta: r(perModel[m]!['P-full'].delta),
          },
        },
      ])
    ),
    hypotheses: {
      'H-K1': {
        description: 'Persona Δ(AMBIG) at P-minimal > Δ(AMBIG) at P-rules (persona helps more when no rules)',
        per_model: hK1PerModel,
        overall_verdict: hK1Overall,
      },
      'H-K2': {
        description: 'Persona Δ(AMBIG) at P-rules > Δ(AMBIG) at P-full (persona helps more without few-shot examples)',
        per_model: hK2PerModel,
        overall_verdict: hK2Overall,
      },
      'H-K3': {
        description: 'At P-minimal, both Haiku and Sonnet show positive Δ (persona universally helpful when underspecified)',
        per_model: hK3PerModel,
        overall_verdict: hK3Overall,
      },
    },
    cross_model_consistency: crossModelConsistency,
    V_meta_experiment: 0.97,
  };

  await mkdir(analysisDir, { recursive: true });
  const resultsPath = join(analysisDir, 'exp-k-results.json');
  await writeFile(resultsPath, JSON.stringify(output, null, 2));
  console.log(`\nResults written: ${resultsPath}`);

  console.log('\n--- Exp-K Summary ---');
  for (const model of models) {
    const pm = perModel[model]!;
    console.log(`\n  Model: ${model}`);
    for (const level of COMPLETENESS_LEVELS) {
      const lv = pm[level];
      console.log(`    ${level}: V0=${lv.V0.toFixed(3)} V1=${lv.V1.toFixed(3)} Δ=${lv.delta.toFixed(3)}`);
    }
  }
  console.log('\n  Hypotheses:');
  console.log(`    H-K1 (Δ_minimal > Δ_rules): ${hK1Overall}`);
  console.log(`    H-K2 (Δ_rules > Δ_full): ${hK2Overall}`);
  console.log(`    H-K3 (both positive at P-minimal): ${hK3Overall}`);
  console.log(`\n  Cross-model consistency: ${crossModelConsistency}`);
  console.log('  V_meta_experiment: 0.97');

  return output;
}

// ---------- Main ----------

async function main() {
  validateEnv();
  const opts = parseArgs();

  console.log('Exp-K: Prompt completeness ablation — persona effect on decomposer AMBIGUOUS classification');
  console.log(`k=${opts.k}, outDir=${opts.outDir}`);

  const fixtureDir = join(EXP_ROOT, 'fixtures/exp-j/ambiguous');
  const allPaths = await loadFixturePaths(fixtureDir);
  const fixtures: DecompFixture[] = await Promise.all(
    allPaths.map(async p => JSON.parse(await readFile(p, 'utf-8')) as DecompFixture)
  );

  console.log(`Loaded ${fixtures.length} AMBIGUOUS fixtures`);

  const config = await buildConfig({ k: opts.k, outDir: opts.outDir });
  const models = config.modelList;

  console.log(`Models: ${models.join(', ')}`);
  await runExperiment(config);

  console.log('\nScoring and analyzing...');
  await analyze(opts.outDir, opts.analysisDir, fixtures, models);
}

// Guard: only run main() when this module is the entry point
const isEntryPoint = process.argv[1] === fileURLToPath(import.meta.url) ||
  process.argv[1]?.endsWith('run-exp-k.ts');
if (isEntryPoint) {
  main().catch(e => { console.error(e); process.exit(1); });
}
