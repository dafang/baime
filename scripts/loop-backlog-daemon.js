#!/usr/bin/env node
/**
 * loop-backlog-daemon.js — polls backlog tasks dir and emits task-ready events to stdout.
 *
 * Emits one line per Ready transition: "task-ready:TASK-N"
 * Stops when parent process dies or stop-sentinel file appears.
 *
 * Pure Node.js stdlib — no npm dependencies required.
 */

import fs from 'fs';
import path from 'path';
import process from 'process';

// ── CLI arg parsing ──────────────────────────────────────────────────────────

function parseArgs(argv) {
  const args = {
    tasksDir: 'backlog/tasks',
    pidFile: 'backlog/.daemon.pid',
    stopFile: 'backlog/.loop-stop',
    interval: 0.5,
  };

  for (let i = 2; i < argv.length; i++) {
    switch (argv[i]) {
      case '--tasks-dir':  args.tasksDir  = argv[++i]; break;
      case '--pid-file':   args.pidFile   = argv[++i]; break;
      case '--stop-file':  args.stopFile  = argv[++i]; break;
      case '--interval':   args.interval  = parseFloat(argv[++i]); break;
      case '--help':
      case '-h':
        process.stdout.write(
          'Usage: loop-backlog-daemon.js [options]\n' +
          '  --tasks-dir <path>   Directory of task markdown files (default: backlog/tasks)\n' +
          '  --pid-file  <path>   PID file path (default: backlog/.daemon.pid)\n' +
          '  --stop-file <path>   Stop sentinel path (default: backlog/.loop-stop)\n' +
          '  --interval  <secs>  Poll interval in seconds (default: 0.5)\n'
        );
        process.exit(0);
    }
  }
  return args;
}

// ── Task ID extraction ───────────────────────────────────────────────────────

function parseTaskId(filename) {
  const base = path.basename(filename, path.extname(filename)).toUpperCase();
  // Split on whitespace only — hyphens are part of "TASK-N"
  for (const part of base.split(/\s+/)) {
    if (/^TASK-\d+$/.test(part)) return part;
  }
  // Fallback: scan for TASK-N anywhere in the filename
  const m = base.match(/\bTASK-(\d+)\b/);
  return m ? `TASK-${m[1]}` : null;
}

// ── Ready status check ───────────────────────────────────────────────────────

function isReady(filepath) {
  try {
    const content = fs.readFileSync(filepath, 'utf8');
    for (const line of content.split('\n')) {
      const stripped = line.trim().toLowerCase();
      if (stripped === 'status: ready' || stripped.startsWith('status: ready')) {
        return true;
      }
    }
  } catch {
    // file unreadable — treat as not ready
  }
  return false;
}

// ── Scan tasks directory ─────────────────────────────────────────────────────

function scanReadyIds(tasksDir) {
  const ready = new Set();
  let entries;
  try {
    entries = fs.readdirSync(tasksDir);
  } catch {
    return ready;
  }
  for (const entry of entries) {
    if (!entry.endsWith('.md')) continue;
    const taskId = parseTaskId(entry);
    if (!taskId) continue;
    if (isReady(path.join(tasksDir, entry))) {
      ready.add(taskId);
    }
  }
  return ready;
}

// ── Parent liveness check ────────────────────────────────────────────────────

function isParentAlive(ppid) {
  try {
    process.kill(ppid, 0);
    return true;
  } catch {
    return false;
  }
}

// ── Main ─────────────────────────────────────────────────────────────────────

const args = parseArgs(process.argv);
const intervalMs = Math.round(args.interval * 1000);
const ppid = process.ppid;

// Write PID file
const pidDir = path.dirname(args.pidFile);
if (pidDir) fs.mkdirSync(pidDir, { recursive: true });
fs.writeFileSync(args.pidFile, String(process.pid));

// Remove PID file on exit
function removePid() {
  try { fs.unlinkSync(args.pidFile); } catch { /* already gone */ }
}
process.on('exit', removePid);
process.on('SIGTERM', () => process.exit(0));
process.on('SIGINT',  () => process.exit(0));

const notified = new Set();

const timer = setInterval(() => {
  // Check stop sentinel
  if (fs.existsSync(args.stopFile)) {
    clearInterval(timer);
    process.exit(0);
  }

  // Check parent liveness
  if (!isParentAlive(ppid)) {
    clearInterval(timer);
    process.exit(0);
  }

  const readyIds = scanReadyIds(args.tasksDir);

  // Purge IDs no longer Ready (allows re-emission on next transition)
  for (const id of notified) {
    if (!readyIds.has(id)) notified.delete(id);
  }

  // Emit newly-ready IDs (sorted for deterministic output)
  const newIds = [...readyIds].filter(id => !notified.has(id)).sort();
  for (const id of newIds) {
    process.stdout.write(`task-ready:${id}\n`);
    notified.add(id);
  }
}, intervalMs);
