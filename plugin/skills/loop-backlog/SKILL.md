---
name: loop-backlog
description: "Autonomous L0 Worker for the backlog.md task queue. Each task runs in an isolated git worktree, then merges back to master on success. Starts an event-driven daemon that emits task-ready events; uses Monitor to react instantly. Invoke /loop-backlog once to start the worker loop; it keeps running until the backlog/.loop-stop sentinel is written."
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Monitor
---

λ() → workerLoop()

## Spec

Config :: {
  symlinks : [Path]   -- dirs to symlink into worktree ([] = none)
}

loadConfig :: () → Config
loadConfig() =
  | fromClaudeMd()   -- explicit: "## L0 Config" section in CLAUDE.md
  | autoDetect()     -- implicit: probe package.json, go.mod, Cargo.toml, etc.

autoDetect :: () → Config
autoDetect() = case detectLang() of
  | Node    → { symlinks: ["node_modules"] }
  | _       → { symlinks: [] }

detectLang :: () → Lang
detectLang() =
  | exists("package.json") → Node
  | exists("go.mod")       → Go
  | exists("Cargo.toml")   → Rust
  | exists("pyproject.toml") ∨ exists("setup.py") → Python
  | otherwise              → Unknown

data Outcome = Done CommitHash | NeedsHuman Reason | Idle | Stopped

workerLoop :: () → Outcome
workerLoop() = {
  cfg:    loadConfig(),
  _:      ensureDaemonScript(),
  _:      daemonBootstrap(),
  _:      reap(inProgressTasks()),
  task:   claim(),

  if (stopSentinel()):
    return: Stopped,

  if (empty(task)):
    -- No task yet; block persistently until daemon emits a task-ready line
    -- Monitor(persistent=true) never times out — daemon runs until .loop-stop written
    event: Monitor(persistent=true),
    if (event matches "task-ready:TASK-*"):
      return: workerLoop(),      -- re-enter to claim the announced task
    if (stopSentinel()):
      return: Stopped,

  result: withWorktree(task, cfg, execute),
  return: result
}

reap :: [Task] → ()
reap(tasks) = ∀t ∈ tasks
  where claimAge(t) > 30min ∨ ¬hasClaimed(t): {
    reset(t, "Ready"),
    appendNote(t, "Requeued by reaper: in-progress timeout."),
    removeWorktree(t)
  }

claim :: () → Maybe Task
claim() = {
  t: head(readyTasks()),
  if (empty(t)): return Nothing,
  atomically: {
    setStatus(t, "In Progress"),
    appendNote(t, "claimed: " + now())
  },
  return: Just(t)
}

withWorktree :: Task → Config → (Task → a) → a
withWorktree(T, cfg, f) = {
  wt:  createWorktree(T),
  _:   ∀s ∈ cfg.symlinks: symlink(repoRoot + "/" + s, wt + "/" + s),
  cd:  wt,
  return: f(T)
}

-- execute is task-type-agnostic: T.description is the sole authority on what to do
execute :: Task → Outcome
execute(T) = {
  _:      followDescription(T.description),
  _:      ∀(n, cmd) ∈ enumerate(T.dodCommands): verifyDod(T, n, cmd),
  hash:   conditionalCommit(T),
  return: merge(T, hash)
} | cannotProceed(reason) → escalate(T, reason)

-- escalate: only exit when the worker cannot continue without human input.
-- Never ask the user a question while a task is In Progress; call escalate() instead.
escalate :: (Task, Reason) → Outcome
escalate(T, r) = {
  setStatus(T, "Needs Human"),
  appendNote(T, "Escalated: " + r),
  return: NeedsHuman(r)
}

verifyDod :: (Task, Int, ShellCmd) → ()
verifyDod(T, n, cmd) =
  | eval(cmd).exitCode == 0 → checkDod(T, n)
  | attempts(n) < 3         → fix(); verifyDod(T, n, cmd)
  | otherwise               → raise Stuck(n, cmd)

conditionalCommit :: Task → Maybe CommitHash
conditionalCommit(T) =
  | hasChanges() → git add -A; commit(T); return Just(HEAD)
  | otherwise    → return Nothing

merge :: (Task, Maybe CommitHash) → Outcome
merge(T, hash) =
  | mergeNoFF(T.branch) succeeds → markDone(T, hash); removeWorktree(T); Done(hash)
  | otherwise                    → markNeedsHuman(T, "merge conflict"); NeedsHuman("merge conflict")

## Implementation

### loadConfig

Read `CLAUDE.md` for an `## L0 Config` section. If not found, auto-detect from project files.

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)

# --- fromClaudeMd ---
L0_SECTION=$(awk '/^## L0 Config/{found=1; next} found && /^## /{exit} found{print}' \
  "${REPO_ROOT}/CLAUDE.md" 2>/dev/null)

parse_cfg() { echo "$L0_SECTION" | grep -oP "(?<=^$1:\s)\S.*" | head -1 | xargs; }

CFG_SYMLINKS=$(parse_cfg "worktree-symlinks")

# --- autoDetect fallback ---
if [ -z "$L0_SECTION" ]; then
  if   [ -f "${REPO_ROOT}/package.json" ]; then CFG_SYMLINKS="${CFG_SYMLINKS:-node_modules}"
  else                                          CFG_SYMLINKS="${CFG_SYMLINKS:-}"
  fi
  echo "L0 auto-detected config: symlinks=${CFG_SYMLINKS:-none}"
else
  echo "L0 config loaded from CLAUDE.md: symlinks=${CFG_SYMLINKS:-none}"
fi

# Normalise "none" → empty
[ "$CFG_SYMLINKS" = "none" ] && CFG_SYMLINKS=""
```

### ensureDaemonScript

Write the daemon script to `scripts/loop-backlog-daemon.js` if it does not already exist.
Node.js is guaranteed available on every Claude Code install; no runtime dependency needed.

```bash
DAEMON_SCRIPT="${REPO_ROOT}/scripts/loop-backlog-daemon.js"

if [ ! -f "$DAEMON_SCRIPT" ]; then
  mkdir -p "${REPO_ROOT}/scripts"
  cat > "$DAEMON_SCRIPT" << 'DAEMON_EOF'
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

function isParentAlive(ppid) {
  try { process.kill(ppid, 0); return true; } catch { return false; }
}

const args = parseArgs(process.argv);
const intervalMs = Math.round(args.interval * 1000);
const ppid = process.ppid;

const pidDir = path.dirname(args.pidFile);
if (pidDir) fs.mkdirSync(pidDir, { recursive: true });
fs.writeFileSync(args.pidFile, String(process.pid));

function removePid() { try { fs.unlinkSync(args.pidFile); } catch { /* gone */ } }
process.on('exit', removePid);
process.on('SIGTERM', () => process.exit(0));
process.on('SIGINT',  () => process.exit(0));

const notified = new Set();
const timer = setInterval(() => {
  if (fs.existsSync(args.stopFile)) { clearInterval(timer); process.exit(0); }
  if (!isParentAlive(ppid))         { clearInterval(timer); process.exit(0); }
  const readyIds = scanReadyIds(args.tasksDir);
  for (const id of notified) { if (!readyIds.has(id)) notified.delete(id); }
  for (const id of [...readyIds].filter(id => !notified.has(id)).sort()) {
    process.stdout.write(`task-ready:${id}\n`);
    notified.add(id);
  }
}, intervalMs);
DAEMON_EOF
  echo "ensureDaemonScript: wrote $DAEMON_SCRIPT"
fi
```

### daemonBootstrap

Start the task-watcher daemon if not already running. The daemon polls `backlog/tasks/`
and writes `task-ready:TASK-N` lines to stdout, which Monitor picks up as events.

```bash
BACKLOG_DIR="${REPO_ROOT}/backlog"
PID_FILE="${BACKLOG_DIR}/.daemon.pid"
STOP_FILE="${BACKLOG_DIR}/.loop-stop"
TASKS_DIR="${BACKLOG_DIR}/tasks"

# Remove stale stop sentinel from a previous run
rm -f "$STOP_FILE"

# Start daemon only if not already running
DAEMON_RUNNING=false
if [ -f "$PID_FILE" ]; then
  DPID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "$DPID" ] && kill -0 "$DPID" 2>/dev/null; then
    DAEMON_RUNNING=true
    echo "daemonBootstrap: daemon already running (pid $DPID)"
  fi
fi

if [ "$DAEMON_RUNNING" = "false" ]; then
  node "${REPO_ROOT}/scripts/loop-backlog-daemon.js" \
    --tasks-dir "$TASKS_DIR" \
    --pid-file  "$PID_FILE"  \
    --stop-file "$STOP_FILE" \
    --interval  0.5 &
  sleep 0.6
  DPID=$(cat "$PID_FILE" 2>/dev/null || true)
  echo "daemonBootstrap: started daemon (pid ${DPID:-unknown})"
fi
```

### reap

```bash
backlog task list --status "In Progress" --plain \
  | grep -oP 'TASK-\d+' \
  | while read TASK_ID; do
    VIEW=$(backlog task view "$TASK_ID" --plain)
    CLAIMED=$(echo "$VIEW" | grep -oP '(?<=claimed: )\S+' | tail -1)
    AGE=9999
    if [ -n "$CLAIMED" ]; then
      AGE=$(( $(date -u +%s) - $(date -u -d "$CLAIMED" +%s 2>/dev/null || echo 0) ))
    fi
    if [ $AGE -gt 1800 ]; then
      backlog task edit "$TASK_ID" --status "Ready" \
        --append-notes "Requeued by reaper: in-progress timeout exceeded 30 minutes."
      PROJECT_NAME=$(basename "$REPO_ROOT")
      WORKTREE="${REPO_ROOT}/../${PROJECT_NAME}-${TASK_ID}"
      [ -d "$WORKTREE" ] && git worktree remove "$WORKTREE" --force 2>/dev/null || true
      git branch -D "task/${TASK_ID}" 2>/dev/null || true
    fi
  done
```

### claim

```bash
TASK_ID=$(backlog task list --status "Ready" --plain | grep -oP 'TASK-\d+' | head -1)
```

If empty and no stop sentinel: use Monitor (persistent) to wait for the next `task-ready` event.

```bash
backlog task edit "$TASK_ID" --status "In Progress" \
  --append-notes "claimed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

### withWorktree

```bash
BRANCH="task/${TASK_ID}"
PROJECT_NAME=$(basename "$REPO_ROOT")
WORKTREE="${REPO_ROOT}/../${PROJECT_NAME}-${TASK_ID}"
git worktree add "$WORKTREE" -b "$BRANCH"

# Symlink configured dirs (e.g. node_modules) to avoid reinstall
for SYM in $CFG_SYMLINKS; do
  [ -e "${REPO_ROOT}/${SYM}" ] && \
    ln -sf "${REPO_ROOT}/${SYM}" "${WORKTREE}/${SYM}"
done

cd "$WORKTREE"
```

### execute → followDescription

```bash
TASK_VIEW=$(backlog task view "$TASK_ID" --plain)
TITLE=$(echo "$TASK_VIEW" | grep -oP '(?<=Task TASK-\d+ - ).+' | head -1)

# Accumulator for final-summary
EXECUTION_LOG=""
log_exec() { EXECUTION_LOG="${EXECUTION_LOG}$1\n"; }
```

Read the task Description in full. The Description is the sole authority on what to
do — it may call for code changes, documentation, experiments, or analysis. Follow its
`## Phase` sections in order. After each phase completes, append a structured checkpoint
that includes the key outputs or decisions from that phase:

```bash
PHASE_NOTE="Phase <X> ✓ $(date -u +%Y-%m-%dT%H:%M:%SZ)
<one-line summary of what was done or found>"
backlog task edit "$TASK_ID" --append-notes "$PHASE_NOTE"
log_exec "$PHASE_NOTE"
```

If a phase produced notable command output (e.g. test results, validation output, key
tool responses), include the relevant excerpt (truncated to ~20 lines) in the note.

Do not invent steps beyond what the Description specifies. Do not assume a task type.

### verifyDod

```bash
DOD_COUNT=$(echo "$TASK_VIEW" | grep -cP '^\- \[.\] #\d+')

for N in $(seq 0 $((DOD_COUNT - 1))); do
  CMD=$(echo "$TASK_VIEW" | grep -P "^\- \[.\] #${N} " | sed "s/^- \[.\] #${N} //")
  ATTEMPTS=0
  while true; do
    if eval "$CMD"; then
      backlog task edit "$TASK_ID" --check-dod $N
      log_exec "DoD #${N} ✓: ${CMD}"
      break
    fi
    ATTEMPTS=$((ATTEMPTS + 1))
    LAST_ERROR="$(eval "$CMD" 2>&1 || true)"
    if [ $ATTEMPTS -ge 3 ]; then
      STUCK_INDEX=$N
      STUCK_CMD="$CMD"
      log_exec "DoD #${N} ✗ STUCK after 3 attempts: ${CMD}
Last error:
${LAST_ERROR}"
      break 2   # → Failure path
    fi
    # Log the failure and what fix is being attempted
    FIX_NOTE="DoD #${N} ✗ attempt ${ATTEMPTS}: ${CMD}
Error: $(echo "$LAST_ERROR" | head -5)
→ applying fix..."
    backlog task edit "$TASK_ID" --append-notes "$FIX_NOTE"
    log_exec "$FIX_NOTE"
    # Fix the issue causing the failure, then retry
  done
done
```

### conditionalCommit

```bash
git add -A
if ! git diff --cached --quiet; then
  git commit -m "${TITLE} (${TASK_ID})"
  COMMIT_HASH=$(git rev-parse HEAD)
else
  COMMIT_HASH="(no file changes)"
fi
```

### merge

```bash
cd "$REPO_ROOT"
if git merge --no-ff "$BRANCH" -m "merge: ${TITLE} (${TASK_ID})"; then
  FINAL_SUMMARY="## Execution Summary

**Result:** Done  
**Commit:** ${COMMIT_HASH}

### Execution Log
$(echo -e "$EXECUTION_LOG")"
  backlog task edit "$TASK_ID" \
    --status "Done" \
    --append-notes "Completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --final-summary "$FINAL_SUMMARY"
  git worktree remove "$WORKTREE"
  git branch -d "$BRANCH"
  WORK_DONE=true
else
  FINAL_SUMMARY="## Execution Summary

**Result:** Needs Human — merge conflict  
**Branch:** ${BRANCH}  
**Worktree:** ${WORKTREE}

### Execution Log
$(echo -e "$EXECUTION_LOG")

### Resolution Steps
\`\`\`
cd ${REPO_ROOT}
git mergetool
git commit
git worktree remove ${WORKTREE}
git branch -d ${BRANCH}
\`\`\`"
  backlog task edit "$TASK_ID" \
    --status "Needs Human" \
    --append-notes "Merge conflict: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --final-summary "$FINAL_SUMMARY"
  echo "⚠️  Merge conflict: $TASK_ID — worktree preserved at $WORKTREE"
  WORK_DONE=false
fi
```

### Failure path (Stuck)

```bash
cd "$REPO_ROOT"
FINAL_SUMMARY="## Execution Summary

**Result:** Needs Human — stuck on DoD #${STUCK_INDEX}  
**Branch:** ${BRANCH}  
**Worktree:** ${WORKTREE}

### Failing Command
\`\`\`
${STUCK_CMD}
\`\`\`

### Last Error
\`\`\`
${LAST_ERROR}
\`\`\`

### Execution Log
$(echo -e "$EXECUTION_LOG")

### Cleanup
\`\`\`
git worktree remove ${WORKTREE} --force
git branch -D ${BRANCH}
\`\`\`"
backlog task edit "$TASK_ID" \
  --status "Needs Human" \
  --append-notes "Stuck on DoD #${STUCK_INDEX}: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --final-summary "$FINAL_SUMMARY"
echo "❌ Stuck: $TASK_ID (DoD #$STUCK_INDEX)"
echo "Task moved to Needs Human. Worktree preserved at $WORKTREE"
WORK_DONE=false
```

## Shutdown

To stop the worker loop, write the stop sentinel:

```bash
touch "${REPO_ROOT}/backlog/.loop-stop"
```

The daemon (`loop-backlog-daemon.js`) detects `backlog/.loop-stop` and exits.
The skill also checks for this file at the top of each iteration and returns `Stopped`
without re-entering Monitor.

To restart after a shutdown:

```bash
rm -f "${REPO_ROOT}/backlog/.loop-stop"
# then invoke /loop-backlog
```

The `daemonBootstrap` section will restart the daemon automatically on the next
`/loop-backlog` invocation. The PID file (`backlog/.daemon.pid`) is managed
by the daemon itself and removed on exit.

Use `Monitor(persistent=true)` to wait for task-ready events. The Monitor runs for the
lifetime of the session — no re-arming on timeout needed. The daemon subprocess exits
only when `backlog/.loop-stop` is written (or the parent process dies).

To stop the Monitor from outside the skill, call `TaskStop <monitor-task-id>`.
