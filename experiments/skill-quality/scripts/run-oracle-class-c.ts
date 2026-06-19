/**
 * run-oracle-class-c.ts — Layer 2.5 Oracle: verifyDod branch-selection
 *
 * Runs the 6 Class C fixtures (checkDod / fix_retry / raise_Stuck) through
 * Haiku and reports accuracy. Exit 0 if accuracy ≥ threshold, exit 1 if not.
 *
 * Usage:
 *   npx tsx scripts/run-oracle-class-c.ts [--threshold 0.80] [--k 3]
 *
 * Returns exit code 0 (pass) or 1 (fail) — safe to use as a CI gate.
 */

import { readFile, readdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createLlmClient } from '../lib/llm-client.js';
import { extractAnswer, scoreResponse } from '../lib/score.js';
import { validateEnv, getModelPrimary } from '../lib/env.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const EXP_ROOT = join(__dirname, '..');
const FIXTURES_DIR = join(EXP_ROOT, 'fixtures', 'exp-b', 'class-c');

function getArg(flag: string, def: string): string {
  const i = process.argv.indexOf(flag);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1]! : def;
}
const THRESHOLD = parseFloat(getArg('--threshold', '0.80'));
const K = parseInt(getArg('--k', '3'), 10);

interface Fixture {
  id: string;
  taskClass: string;
  taskType: string;
  specSection: string;
  state: { exitCode: number; attempts_so_far: number };
  answer: string;
  answerType: 'exact' | 'set' | 'partial';
}

function buildPrompt(fixture: Fixture): string {
  return [
    'You are evaluating a verifyDod branch-selection decision.',
    '',
    'Spec:',
    fixture.specSection,
    '',
    `Current state:`,
    `  exitCode: ${fixture.state.exitCode}`,
    `  attempts_so_far: ${fixture.state.attempts_so_far}`,
    '',
    'Based on the spec, which branch applies?',
    'Output ONLY valid JSON: {"answer": "checkDod"} or {"answer": "fix_retry"} or {"answer": "raise_Stuck"}',
  ].join('\n');
}

async function main() {
  validateEnv();
  const model = getModelPrimary();
  const client = createLlmClient();

  const files = (await readdir(FIXTURES_DIR)).filter(f => f.endsWith('.json')).sort();
  const fixtures: Fixture[] = await Promise.all(
    files.map(async f => JSON.parse(await readFile(join(FIXTURES_DIR, f), 'utf-8'))),
  );

  console.log(`Layer 2.5 Oracle — Class C (verifyDod branch-selection)`);
  console.log(`Model: ${model}  |  Fixtures: ${fixtures.length}  |  k=${K}  |  Threshold: ${threshold}`);
  console.log('');

  const results: Array<{ id: string; scores: number[]; mean: number }> = [];

  for (const fixture of fixtures) {
    const prompt = buildPrompt(fixture);
    const scores: number[] = [];

    for (let i = 0; i < K; i++) {
      try {
        const resp = await client.chat({
          model,
          messages: [{ role: 'user', content: prompt }],
        });
        const extracted = extractAnswer(resp.content);
        scores.push(scoreResponse(extracted, fixture.answer, fixture.answerType));
      } catch (err) {
        console.error(`  ERROR ${fixture.id} run ${i}:`, (err as Error).message);
        scores.push(0);
      }
    }

    const mean = scores.reduce((a, b) => a + b, 0) / scores.length;
    results.push({ id: fixture.id, scores, mean });

    const status = mean >= threshold ? '✓' : '✗';
    console.log(`  ${status} ${fixture.id}: ${mean.toFixed(2)} (expected: ${fixture.answer})`);
  }

  const overallMean = results.reduce((a, r) => a + r.mean, 0) / results.length;
  const pass = overallMean >= threshold;

  console.log('');
  console.log(`Overall accuracy: ${overallMean.toFixed(3)} (threshold: ${threshold})`);
  console.log(pass ? '✅ PASS — Class C oracle verified' : '❌ FAIL — accuracy below threshold');

  process.exit(pass ? 0 : 1);
}

// hoist threshold for use inside main
const threshold = THRESHOLD;
main().catch(e => { console.error(e); process.exit(1); });
