/**
 * config-builder.test.ts — Unit tests for lib/config-builder.ts
 *
 * Tests loadFixturePaths and buildExperimentConfig factory function.
 *
 * Run with: npx tsx --test lib/config-builder.test.ts
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadFixturePaths, buildExperimentConfig, type ExperimentConfigSpec } from './config-builder.js';

// ── loadFixturePaths tests ────────────────────────────────────────────────────

test('loadFixturePaths returns sorted .json paths from a directory', async () => {
  const tmpDir = await mkdtemp(join(tmpdir(), 'cfg-builder-test-'));
  try {
    await writeFile(join(tmpDir, 'z-fix.json'), JSON.stringify({ id: 'z-fix', fixtureClass: 'CLEAR' }));
    await writeFile(join(tmpDir, 'a-fix.json'), JSON.stringify({ id: 'a-fix', fixtureClass: 'CLEAR' }));
    await writeFile(join(tmpDir, 'm-fix.json'), JSON.stringify({ id: 'm-fix', fixtureClass: 'CLEAR' }));
    // Non-JSON file should be excluded
    await writeFile(join(tmpDir, 'notes.txt'), 'not json');

    const paths = await loadFixturePaths(tmpDir);

    assert.equal(paths.length, 3, 'should return 3 .json files');
    // Sorted order
    assert.ok(paths[0]!.endsWith('a-fix.json'), `first should be a-fix.json, got ${paths[0]}`);
    assert.ok(paths[1]!.endsWith('m-fix.json'), `second should be m-fix.json, got ${paths[1]}`);
    assert.ok(paths[2]!.endsWith('z-fix.json'), `third should be z-fix.json, got ${paths[2]}`);
  } finally {
    await rm(tmpDir, { recursive: true });
  }
});

test('loadFixturePaths filters to CLEAR fixtures only when filterClear=true', async () => {
  const tmpDir = await mkdtemp(join(tmpdir(), 'cfg-builder-test-'));
  try {
    await writeFile(join(tmpDir, 'clear-1.json'), JSON.stringify({ id: 'clear-1', fixtureClass: 'CLEAR' }));
    await writeFile(join(tmpDir, 'ambig-1.json'), JSON.stringify({ id: 'ambig-1', fixtureClass: 'AMBIGUOUS' }));
    await writeFile(join(tmpDir, 'clear-2.json'), JSON.stringify({ id: 'clear-2', fixtureClass: 'CLEAR' }));
    await writeFile(join(tmpDir, 'error-1.json'), JSON.stringify({ id: 'error-1', fixtureClass: 'ERROR' }));

    const paths = await loadFixturePaths(tmpDir, { filterClear: true });

    assert.equal(paths.length, 2, 'should return only CLEAR fixtures');
    assert.ok(paths.every(p => p.includes('clear-')), 'all returned paths should be CLEAR fixtures');
  } finally {
    await rm(tmpDir, { recursive: true });
  }
});

test('loadFixturePaths returns all fixtures when filterClear not set', async () => {
  const tmpDir = await mkdtemp(join(tmpdir(), 'cfg-builder-test-'));
  try {
    await writeFile(join(tmpDir, 'clear-1.json'), JSON.stringify({ id: 'clear-1', fixtureClass: 'CLEAR' }));
    await writeFile(join(tmpDir, 'ambig-1.json'), JSON.stringify({ id: 'ambig-1', fixtureClass: 'AMBIGUOUS' }));

    const paths = await loadFixturePaths(tmpDir);

    assert.equal(paths.length, 2, 'should return all 2 fixtures when filterClear not set');
  } finally {
    await rm(tmpDir, { recursive: true });
  }
});

// ── buildExperimentConfig tests ───────────────────────────────────────────────

function makeSpec(overrides: Partial<ExperimentConfigSpec> = {}): ExperimentConfigSpec {
  return {
    variants: {
      'v-a': ['/tmp/fix-1.json', '/tmp/fix-2.json'],
      'v-b': ['/tmp/fix-3.json'],
    },
    buildPrompt: (_fixture, _variant) => 'test prompt',
    scoreResponse: (_response, _fixture) => 1,
    ...overrides,
  };
}

test('buildExperimentConfig assembles an ExperimentConfig with correct shape', () => {
  const spec = makeSpec();
  const config = buildExperimentConfig(spec, { k: 3, outDir: '/tmp/out' });

  assert.ok(config !== null && typeof config === 'object', 'config must be an object');
  assert.ok(typeof config.variants === 'object', 'config.variants must be an object');
  assert.ok(Array.isArray(config.modelList), 'config.modelList must be an array');
  assert.ok(typeof config.k === 'number', 'config.k must be a number');
  assert.ok(typeof config.outDir === 'string', 'config.outDir must be a string');
  assert.ok(typeof config.buildPrompt === 'function', 'config.buildPrompt must be a function');
  assert.ok(typeof config.scoreResponse === 'function', 'config.scoreResponse must be a function');

  // variants pass-through
  assert.deepEqual(config.variants, spec.variants, 'variants should be passed through');
});

test('buildExperimentConfig passes through k and outDir from opts', () => {
  const spec = makeSpec();
  const config = buildExperimentConfig(spec, { k: 7, outDir: '/custom/out/dir' });

  assert.equal(config.k, 7, 'k should be 7');
  assert.equal(config.outDir, '/custom/out/dir', 'outDir should be /custom/out/dir');
});

test('buildExperimentConfig passes through sanityDir from spec when provided', () => {
  const spec = makeSpec({ sanityDir: '/tmp/sanity-fixtures' });
  const config = buildExperimentConfig(spec, { k: 1, outDir: '/tmp/out' });

  assert.equal(config.sanityDir, '/tmp/sanity-fixtures', 'sanityDir should be /tmp/sanity-fixtures');
});

test('buildExperimentConfig omits sanityDir when spec does not include it', () => {
  const spec = makeSpec();
  // Ensure sanityDir is not in spec
  assert.ok(!('sanityDir' in spec), 'spec should not have sanityDir');

  const config = buildExperimentConfig(spec, { k: 1, outDir: '/tmp/out' });

  assert.equal(config.sanityDir, undefined, 'sanityDir should be undefined');
});

test('buildExperimentConfig uses spec.modelList when provided', () => {
  const spec = makeSpec({ modelList: ['custom-model-a', 'custom-model-b'] });
  const config = buildExperimentConfig(spec, { k: 1, outDir: '/tmp/out' });

  assert.deepEqual(config.modelList, ['custom-model-a', 'custom-model-b'], 'should use spec.modelList');
});
