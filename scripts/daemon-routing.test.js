#!/usr/bin/env node
/**
 * daemon-routing.test.js — Deterministic routing unit tests for the UNIFIED basic-daemon.js.
 *
 * The unified B″ poller emits three channels:
 *   basic-ready  kind:basic AND Basic: Ready
 *   epic-ready   kind:epic  AND Epic: Ready          (ONLY Epic: Ready — not other Epic:* states)
 *   child-done   kind:basic AND Basic: Done AND has parent_task_id
 *                AND the parent epic is still at "Epic: Awaiting Children" (gate)
 *
 * Verifies correct routing, no cross-channel emission, parent_task_id parsing, and that
 * scripts/basic-daemon.js carries daemon-version: v10 and wires all five channels.
 *
 * Exits 0 on all pass, non-zero on fail.
 */
'use strict';
const fs   = require('fs');
const path = require('path');
const os   = require('os');

// ── Routing logic (inlined from the unified daemon for deterministic, process-free tests) ──

const BASIC_READY_STATUS = 'basic: ready';
const EPIC_READY_STATUS  = 'epic: ready';
const BASIC_DONE_STATUS  = 'basic: done';
const EPIC_AWAITING_CHILDREN_STATUS = 'epic: awaiting children';

function parseTaskId(filename) {
  const base = path.basename(filename, path.extname(filename)).toUpperCase();
  const first = base.split(/\s+/)[0];
  const m = first.match(/^([A-Za-z][A-Za-z0-9]*-\d+(?:\.\d+)*)$/);
  return m ? m[1] : null;
}

function findTaskFileById(tasksDir, taskId) {
  let entries;
  try { entries = fs.readdirSync(tasksDir); } catch { return null; }
  for (const entry of entries) {
    if (!entry.endsWith('.md')) continue;
    if (parseTaskId(entry) === taskId) return path.join(tasksDir, entry);
  }
  return null;
}

function parseLabels(fm) {
  let labels = [];
  const inlineLabels = fm.match(/^labels:\s*\[([^\]]*)\]/m);
  if (inlineLabels) {
    labels = inlineLabels[1].split(',').map(s => s.trim().replace(/['"]/g, '')).filter(Boolean);
  } else {
    const blockMatch = fm.match(/^labels:\s*\n((?:  - .+\n?)*)/m);
    if (blockMatch) {
      labels = blockMatch[1].split('\n')
        .map(l => l.replace(/^\s+-\s+/, '').trim().replace(/['"]/g, ''))
        .filter(Boolean);
    }
  }
  return labels;
}

function readTaskMeta(filepath) {
  try {
    const content = fs.readFileSync(filepath, 'utf8');
    const m = content.match(/^---\n([\s\S]*?)^---/m);
    if (!m) return null;
    const fm = m[1];
    const statusMatch = fm.match(/^status:\s*(.+)$/m);
    const status = statusMatch ? statusMatch[1].trim().replace(/['"]/g, '').toLowerCase() : null;
    const parentMatch = content.match(/^parent_task_id:\s*(.+)$/m);
    const parent_task_id = parentMatch ? parentMatch[1].trim().toUpperCase() : null;
    const labels = parseLabels(fm);
    return {
      status,
      hasKindBasic: labels.includes('kind:basic'),
      hasKindEpic:  labels.includes('kind:epic'),
      parent_task_id,
    };
  } catch { /* unreadable */ }
  return null;
}

function isBasicReady(filepath) {
  const meta = readTaskMeta(filepath);
  if (!meta) return false;
  return meta.hasKindBasic && !meta.hasKindEpic && meta.status === BASIC_READY_STATUS;
}

function isEpicReady(filepath) {
  const meta = readTaskMeta(filepath);
  if (!meta) return false;
  return meta.hasKindEpic && !meta.hasKindBasic && meta.status === EPIC_READY_STATUS;
}

function isChildDone(filepath, tasksDir = path.dirname(filepath)) {
  const meta = readTaskMeta(filepath);
  if (!meta) return false;
  if (!(meta.hasKindBasic && !meta.hasKindEpic
        && meta.status === BASIC_DONE_STATUS && !!meta.parent_task_id)) return false;
  const parentPath = findTaskFileById(tasksDir, meta.parent_task_id);
  const pmeta = parentPath ? readTaskMeta(parentPath) : null;
  return !!pmeta && pmeta.hasKindEpic && pmeta.status === EPIC_AWAITING_CHILDREN_STATUS;
}

// ── Test helpers ──

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) { console.log(`  PASS: ${message}`); passed++; }
  else           { console.log(`  FAIL: ${message}`); failed++; }
}

function makeTaskFile(dir, id, status, labels, parentId = null) {
  const labelsYaml = labels.length === 0
    ? 'labels: []'
    : `labels:\n${labels.map(l => `  - ${l}`).join('\n')}`;
  const parentLine = parentId ? `parent_task_id: ${parentId}\n` : '';
  const content = `---\nid: ${id}\ntitle: Test task ${id}\nstatus: ${status}\nassignee: []\ncreated_date: '2026-06-21'\nupdated_date: '2026-06-21'\n${labelsYaml}\ndependencies: []\n${parentLine}ordinal: 1000\n---\n\n## Description\n\nTest task.\n`;
  const filename = `${id.toLowerCase()} - Test-task-${id}.md`;
  fs.writeFileSync(path.join(dir, filename), content);
  return path.join(dir, filename);
}

// ── Tests ──

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'daemon-routing-test-'));

try {
  console.log('\n=== daemon-routing.test.js (unified daemon) ===\n');

  // Test 1: kind:basic + Basic: Ready → basic-ready only
  {
    const f = makeTaskFile(tmpDir, 'TASK-1', 'Basic: Ready', ['kind:basic'], 'TASK-99');
    assert(isBasicReady(f) === true,  'Test 1a: kind:basic + Basic: Ready → basic-ready');
    assert(isEpicReady(f)  === false, 'Test 1b: kind:basic + Basic: Ready → no epic-ready');
    assert(isChildDone(f)  === false, 'Test 1c: Basic: Ready (not Done) → no child-done');
  }

  // Test 2: kind:epic + Epic: Ready → epic-ready only
  {
    const f = makeTaskFile(tmpDir, 'TASK-2', 'Epic: Ready', ['kind:epic']);
    assert(isEpicReady(f)  === true,  'Test 2a: kind:epic + Epic: Ready → epic-ready');
    assert(isBasicReady(f) === false, 'Test 2b: kind:epic + Epic: Ready → no basic-ready');
  }

  // Test 3: kind:epic + non-Ready Epic:* statuses do NOT emit epic-ready
  //         (handled by epic-to-backlog interactively, or by worker via child-done)
  {
    const nonReady = ['Epic: Proposal', 'Epic: Plan', 'Epic: Backlog',
                      'Epic: Decomposing', 'Epic: Awaiting Children', 'Epic: Evaluating'];
    for (const status of nonReady) {
      const id = `TASK-3-${status.replace(/[^A-Za-z]/g, '')}`;
      const f = makeTaskFile(tmpDir, id, status, ['kind:epic']);
      assert(isEpicReady(f) === false, `Test 3: kind:epic + "${status}" → no epic-ready (only Epic: Ready emits)`);
    }
  }

  // Test 4: kind:epic terminal statuses do NOT emit
  {
    for (const status of ['Epic: Done', 'Epic: Needs Human']) {
      const id = `TASK-4-${status.replace(/[^A-Za-z]/g, '')}`;
      const f = makeTaskFile(tmpDir, id, status, ['kind:epic']);
      assert(isEpicReady(f) === false, `Test 4: kind:epic + "${status}" → terminal, no epic-ready`);
    }
  }

  // Test 5: child-done channel — kind:basic + Basic: Done + parent_task_id, GATED on the
  //         parent epic still being at "Epic: Awaiting Children" (the only actionable state).
  {
    // Parent epic awaiting children → child-done emits.
    makeTaskFile(tmpDir, 'TASK-50', 'Epic: Awaiting Children', ['kind:epic']);
    const withParent = makeTaskFile(tmpDir, 'TASK-5', 'Basic: Done', ['kind:basic'], 'TASK-50');
    assert(isChildDone(withParent) === true,  'Test 5a: Basic: Done + parent at Awaiting Children → child-done');
    assert(isBasicReady(withParent) === false, 'Test 5b: Basic: Done → no basic-ready');

    const noParent = makeTaskFile(tmpDir, 'TASK-5N', 'Basic: Done', ['kind:basic']);
    assert(isChildDone(noParent) === false, 'Test 5c: Basic: Done WITHOUT parent → no child-done');

    const epicDone = makeTaskFile(tmpDir, 'TASK-5E', 'Epic: Done', ['kind:epic'], 'TASK-50');
    assert(isChildDone(epicDone) === false, 'Test 5d: kind:epic Done → no child-done (basic channel only)');

    // Parent epic already Done → child-done SUPPRESSED (regression: stops the 60s pulse from
    // re-emitting forever once the epic is reconciled). Parent TASK-51 is Epic: Done.
    makeTaskFile(tmpDir, 'TASK-51', 'Epic: Done', ['kind:epic']);
    const doneParent = makeTaskFile(tmpDir, 'TASK-5D', 'Basic: Done', ['kind:basic'], 'TASK-51');
    assert(isChildDone(doneParent) === false, 'Test 5e: parent epic Done → child-done suppressed (gate)');

    // Parent epic missing entirely → suppressed (no actionable reconciliation target).
    const orphan = makeTaskFile(tmpDir, 'TASK-5O', 'Basic: Done', ['kind:basic'], 'TASK-999');
    assert(isChildDone(orphan) === false, 'Test 5f: parent epic missing → child-done suppressed');
  }

  // Test 6: kind:basic non-Ready/non-Done statuses → no emission on any channel
  {
    for (const status of ['Basic: Backlog', 'Basic: Proposal', 'Basic: In Progress']) {
      const id = `TASK-6-${status.replace(/[^A-Za-z]/g, '')}`;
      const f = makeTaskFile(tmpDir, id, status, ['kind:basic'], 'TASK-60');
      assert(isBasicReady(f) === false, `Test 6: kind:basic + "${status}" → no basic-ready`);
      assert(isChildDone(f)  === false, `Test 6: kind:basic + "${status}" → no child-done`);
    }
  }

  // Test 7: XOR violation (both kind labels) and missing kind → neither channel
  {
    const both = makeTaskFile(tmpDir, 'TASK-7', 'Basic: Ready', ['kind:basic', 'kind:epic']);
    assert(isBasicReady(both) === false, 'Test 7a: both kind labels → no basic-ready');
    assert(isEpicReady(both)  === false, 'Test 7b: both kind labels → no epic-ready');
    const none = makeTaskFile(tmpDir, 'TASK-7N', 'Basic: Ready', []);
    assert(isBasicReady(none) === false, 'Test 7c: no kind label → no basic-ready');
  }

  // Test 8: parent_task_id is parseable from frontmatter
  {
    const f = makeTaskFile(tmpDir, 'TASK-8', 'Basic: Ready', ['kind:basic'], 'TASK-42');
    const meta = readTaskMeta(f);
    assert(meta !== null, 'Test 8a: readTaskMeta succeeds');
    assert(meta.parent_task_id === 'TASK-42', 'Test 8b: parent_task_id reads correctly');
  }

  // Test 9: unified daemon file carries daemon-version: v9 and wires all five channels
  {
    const daemon = path.join(__dirname, '..', 'plugin', 'scripts', 'basic-daemon.js');
    assert(fs.existsSync(daemon), 'Test 9a: plugin/scripts/basic-daemon.js exists');
    if (fs.existsSync(daemon)) {
      const content = fs.readFileSync(daemon, 'utf8');
      assert(content.slice(0, 300).includes('daemon-version: v10'), 'Test 9b: basic-daemon.js has daemon-version: v10');
      assert(content.includes('basic-ready'),       'Test 9c: emits basic-ready');
      assert(content.includes('epic-ready'),        'Test 9d: emits epic-ready');
      assert(content.includes('child-done'),        'Test 9e: emits child-done');
      assert(content.includes('parent_task_id'),    'Test 9f: reads parent_task_id');
      assert(content.includes('proposal-approved'), 'Test 9g: emits proposal-approved');
      assert(content.includes('plan-approved'),     'Test 9h: emits plan-approved');
    }
  }

  console.log(`\n=== Summary: ${passed} passed, ${failed} failed ===\n`);
  if (failed > 0) process.exit(1);

} finally {
  try {
    for (const f of fs.readdirSync(tmpDir)) fs.unlinkSync(path.join(tmpDir, f));
    fs.rmdirSync(tmpDir);
  } catch { /* ignore */ }
}

process.exit(0);
