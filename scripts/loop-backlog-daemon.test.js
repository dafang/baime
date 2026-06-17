#!/usr/bin/env node
// Unit tests for loop-backlog-daemon.js helper functions.
// Run with: node scripts/loop-backlog-daemon.test.js
'use strict';
const fs   = require('fs');
const path = require('path');
const os   = require('os');

// ── inline copies of the pure helpers (keep in sync with daemon) ──────────────

function parseTaskId(filename) {
  const base = path.basename(filename, path.extname(filename)).toUpperCase();
  for (const part of base.split(/\s+/)) {
    if (/^TASK-\d+$/.test(part)) return part;
  }
  const m = base.match(/\bTASK-(\d+)\b/);
  return m ? `TASK-${m[1]}` : null;
}

function isReady(filepath) {
  try {
    const content = fs.readFileSync(filepath, 'utf8');
    for (const line of content.split('\n')) {
      const s = line.trim().toLowerCase();
      if (s === 'status: ready' || s.startsWith('status: ready')) return true;
    }
  } catch { /* unreadable */ }
  return false;
}

function scanReadyIds(tasksDir) {
  const ready = new Set();
  let entries;
  try { entries = fs.readdirSync(tasksDir); } catch { return ready; }
  for (const entry of entries) {
    if (!entry.endsWith('.md')) continue;
    const id = parseTaskId(entry);
    if (id && isReady(path.join(tasksDir, entry))) ready.add(id);
  }
  return ready;
}

// ── test harness ──────────────────────────────────────────────────────────────

let passed = 0, failed = 0;
function assert(desc, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) { process.stdout.write(`  ✓ ${desc}\n`); passed++; }
  else     { process.stderr.write(`  ✗ ${desc}\n    expected: ${JSON.stringify(expected)}\n    got:      ${JSON.stringify(actual)}\n`); failed++; }
}

// ── parseTaskId ───────────────────────────────────────────────────────────────
process.stdout.write('parseTaskId\n');
assert('simple prefix',      parseTaskId('task-3 - do something.md'),    'TASK-3');
assert('upper already',      parseTaskId('TASK-10 - title.md'),           'TASK-10');
assert('embedded id',        parseTaskId('sprint-TASK-7-notes.md'),       'TASK-7');
assert('no id returns null', parseTaskId('README.md'),                    null);
assert('multi-digit',        parseTaskId('task-42 - long title here.md'), 'TASK-42');

// ── isReady ───────────────────────────────────────────────────────────────────
process.stdout.write('isReady\n');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lbd-test-'));

const readyFile = path.join(tmp, 'ready.md');
fs.writeFileSync(readyFile, '# Task\nStatus: Ready\nSome body\n');
assert('status ready (mixed case)', isReady(readyFile), true);

const doneFile = path.join(tmp, 'done.md');
fs.writeFileSync(doneFile, '# Task\nStatus: Done\n');
assert('status done → false', isReady(doneFile), false);

const emptyFile = path.join(tmp, 'empty.md');
fs.writeFileSync(emptyFile, '');
assert('empty file → false', isReady(emptyFile), false);

assert('missing file → false', isReady(path.join(tmp, 'ghost.md')), false);

// ── scanReadyIds ──────────────────────────────────────────────────────────────
process.stdout.write('scanReadyIds\n');
const dir = path.join(tmp, 'tasks');
fs.mkdirSync(dir);

fs.writeFileSync(path.join(dir, 'task-1 - alpha.md'), 'Status: Ready\n');
fs.writeFileSync(path.join(dir, 'task-2 - beta.md'),  'Status: Done\n');
fs.writeFileSync(path.join(dir, 'task-3 - gamma.md'), 'Status: Ready\n');
fs.writeFileSync(path.join(dir, 'not-a-task.txt'),    'Status: Ready\n');

const ids = scanReadyIds(dir);
assert('finds ready tasks',  [...ids].sort(), ['TASK-1', 'TASK-3']);
assert('skips done tasks',   ids.has('TASK-2'), false);
assert('skips non-md files', ids.size, 2);

assert('missing dir → empty', [...scanReadyIds(path.join(tmp, 'no-such-dir'))].length, 0);

// ── cleanup + result ──────────────────────────────────────────────────────────
fs.rmSync(tmp, { recursive: true });
process.stdout.write(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
