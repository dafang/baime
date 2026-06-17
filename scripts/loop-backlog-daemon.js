#!/usr/bin/env node
// daemon-version: v3
/**
 * loop-backlog-daemon.js — polls backlog tasks dir and emits task-ready events to stdout.
 *
 * Emits one line per Ready transition: "task-ready:TASK-N"
 * Stops on stop-sentinel file or SIGTERM. Does NOT self-terminate on parent PID death
 * (parent is a transient Bash shell; lifecycle is managed by sentinel and nohup/disown).
 *
 * Pure Node.js stdlib — no npm dependencies required.
 */
'use strict';
const fs   = require('fs');
const path = require('path');

function parseArgs(argv) {
  const args = {
    tasksDir: 'backlog/tasks',
    pidFile:  'backlog/.daemon.pid',
    stopFile: 'backlog/.loop-stop',
    interval: 0.5,
  };
  for (let i = 2; i < argv.length; i++) {
    switch (argv[i]) {
      case '--tasks-dir':  args.tasksDir = argv[++i]; break;
      case '--pid-file':   args.pidFile  = argv[++i]; break;
      case '--stop-file':  args.stopFile = argv[++i]; break;
      case '--interval':   args.interval = parseFloat(argv[++i]); break;
      case '--help': case '-h':
        process.stdout.write(
          'Usage: loop-backlog-daemon.js [options]\n' +
          '  --tasks-dir <path>  Directory of task markdown files (default: backlog/tasks)\n' +
          '  --pid-file  <path>  PID file path (default: backlog/.daemon.pid)\n' +
          '  --stop-file <path>  Stop sentinel path (default: backlog/.loop-stop)\n' +
          '  --interval  <secs> Poll interval in seconds (default: 0.5)\n'
        );
        process.exit(0);
    }
  }
  return args;
}

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

const args      = parseArgs(process.argv);
const intervalMs = Math.round(args.interval * 1000);

const pidDir = path.dirname(args.pidFile);
if (pidDir) fs.mkdirSync(pidDir, { recursive: true });
fs.writeFileSync(args.pidFile, String(process.pid));

function removePid() { try { fs.unlinkSync(args.pidFile); } catch { /* gone */ } }
process.on('exit',   removePid);
process.on('SIGTERM', () => process.exit(0));
process.on('SIGINT',  () => process.exit(0));

const notified = new Set();
const timer = setInterval(() => {
  if (fs.existsSync(args.stopFile)) { clearInterval(timer); process.exit(0); }
  const readyIds = scanReadyIds(args.tasksDir);
  for (const id of notified) { if (!readyIds.has(id)) notified.delete(id); }
  for (const id of [...readyIds].filter(id => !notified.has(id)).sort()) {
    process.stdout.write(`task-ready:${id}\n`);
    notified.add(id);
  }
}, intervalMs);
