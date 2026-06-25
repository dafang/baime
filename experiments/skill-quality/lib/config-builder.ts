/**
 * config-builder.ts — Shared factory for ExperimentConfig assembly.
 *
 * Eliminates the repeated buildConfig boilerplate found in exp-h/i/j/k.
 * Each experiment provides the variant-specific parts (paths, prompt builder,
 * scorer) via ExperimentConfigSpec; this module handles the common assembly.
 */

import { readFile } from 'node:fs/promises';
import { readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { getModelPrimary } from './env.js';
import type { ExperimentConfig, FixtureRecord } from './runner.js';

// ── ExperimentConfigSpec ──────────────────────────────────────────────────────

/**
 * Experiment-specific parts provided by each experiment's buildConfig.
 * The factory buildExperimentConfig assembles these into a full ExperimentConfig.
 */
export interface ExperimentConfigSpec {
  /** variant name → list of fixture file paths (already resolved) */
  variants: Record<string, string[]>;
  /**
   * Model list override. When omitted, defaults to [getModelPrimary()].
   * Supply an explicit list to include secondary models.
   */
  modelList?: string[];
  /** Optional sanity (negative-control) fixture directory */
  sanityDir?: string;
  /** Build the prompt for a given fixture and variant */
  buildPrompt: ExperimentConfig['buildPrompt'];
  /** Score a single LLM response against the fixture ground truth */
  scoreResponse: ExperimentConfig['scoreResponse'];
}

// ── loadFixturePaths ──────────────────────────────────────────────────────────

/**
 * Return sorted absolute paths to all .json files in `dir`.
 *
 * @param dir         Directory to scan.
 * @param opts.filterClear  When true, only paths whose fixture has
 *                          `fixtureClass === 'CLEAR'` are returned.
 */
export async function loadFixturePaths(
  dir: string,
  opts?: { filterClear?: boolean },
): Promise<string[]> {
  const files = (await readdir(dir)).filter(f => f.endsWith('.json')).sort();
  const paths = files.map(f => join(dir, f));

  if (!opts?.filterClear) {
    return paths;
  }

  const cleared: string[] = [];
  for (const p of paths) {
    const fx = JSON.parse(await readFile(p, 'utf-8')) as { fixtureClass?: string };
    if (fx.fixtureClass === 'CLEAR') cleared.push(p);
  }
  return cleared;
}

// ── buildExperimentConfig ────────────────────────────────────────────────────

/**
 * Assemble a full ExperimentConfig from an ExperimentConfigSpec and run options.
 *
 * This is a synchronous factory — all path resolution and file I/O must happen
 * before calling this function (e.g., in the experiment's async buildConfig).
 */
export function buildExperimentConfig(
  spec: ExperimentConfigSpec,
  opts: { k: number; outDir: string },
): ExperimentConfig {
  const config: ExperimentConfig = {
    variants: spec.variants,
    modelList: spec.modelList ?? [getModelPrimary()],
    k: opts.k,
    outDir: opts.outDir,
    buildPrompt: spec.buildPrompt,
    scoreResponse: spec.scoreResponse,
  };

  if (spec.sanityDir !== undefined) {
    config.sanityDir = spec.sanityDir;
  }

  return config;
}
