# Plan: loop-backlog: daemon + Monitor 替代 ScheduleWakeup 实现事件驱动触发

Proposal: docs/proposals/proposal-loop-backlog-daemon-monitor-event-driven.md

## Phase A: Create the daemon script (scripts/loop-backlog-daemon.py)

### Tests (write first)

File: `scripts/test-loop-backlog-daemon.sh`

Test cases to add (each must fail before implementation):
- `test_daemon_writes_pid_file` — spawn daemon, check `.backlog/.daemon.pid` contains a numeric PID
- `test_daemon_emits_task_ready_line` — create a fake task file with `status: Ready`, start daemon, capture stdout line matching `task-ready:TASK-`
- `test_daemon_debounces_repeated_ready` — assert daemon does NOT emit duplicate `task-ready` for same task ID without a Ready→non-Ready transition
- `test_daemon_re_emits_after_status_reset` — mark task non-Ready then Ready again, assert a second `task-ready` line is emitted
- `test_daemon_stops_on_sentinel` — write `.backlog/.loop-stop`, assert daemon process exits within 2 seconds
- `test_daemon_removes_pid_on_exit` — after daemon exits, assert `.backlog/.daemon.pid` has been removed

### Implementation

File to create: `scripts/loop-backlog-daemon.py`

Key logic:
- Parse args: `--tasks-dir` (default `.backlog/tasks`), `--pid-file` (default `.backlog/.daemon.pid`), `--stop-file` (default `.backlog/.loop-stop`), `--interval` (default `0.5`)
- On startup: write `os.getpid()` to pid-file; record `parent_pid = os.getppid()`
- Poll loop (500 ms): scan tasks dir for files containing `status: Ready`; emit `task-ready:TASK-X\n` (flushed) for any ID not in `notified` set; purge IDs from `notified` when no longer Ready
- Check stop sentinel and parent-PID liveness each cycle; exit cleanly on either
- On exit: remove pid-file via `atexit`

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 scripts/loop-backlog-daemon.py --help 2>&1 | grep -q "tasks-dir"`
- [ ] `python3 -c "import ast; ast.parse(open('scripts/loop-backlog-daemon.py').read())" && echo "syntax ok"`

---

## Phase B: Daemon bootstrap in loop-backlog skill (SKILL.md — daemon startup section)

### Tests (write first)

File: `scripts/test-loop-backlog-skill-bootstrap.sh`

Test cases (must fail before implementation):
- `test_skill_md_has_daemon_bootstrap_section` — grep SKILL.md for `daemonBootstrap`; assert present
- `test_skill_md_has_monitor_in_allowed_tools` — grep SKILL.md front-matter for `Monitor`; assert present
- `test_skill_md_no_schedulewakeup_in_allowed_tools` — assert `! grep -q "ScheduleWakeup" .claude/skills/loop-backlog/SKILL.md`
- `test_skill_md_references_daemon_script` — grep SKILL.md for `loop-backlog-daemon.py`; assert present
- `test_skill_md_references_pid_file` — grep SKILL.md for `.daemon.pid`; assert present

### Implementation

File to modify: `.claude/skills/loop-backlog/SKILL.md`

Changes:
1. Front-matter `allowed-tools` line: replace `ScheduleWakeup` with `Monitor`
2. New `### daemonBootstrap` section added to `## Implementation`, before the existing `### reap` section:

```
daemonBootstrap :: () → ()
daemonBootstrap() = {
  pidFile: REPO_ROOT + "/.backlog/.daemon.pid",
  pid:     readPidFile(pidFile),
  alive:   pid != null && processAlive(pid),
  if (!alive): {
    Bash(run_in_background=true,
         command="python3 scripts/loop-backlog-daemon.py
           --tasks-dir .backlog/tasks
           --pid-file .backlog/.daemon.pid
           --stop-file .backlog/.loop-stop"),
    sleep(1),   -- brief settle
  }
}
```

Implementation bash prose:

```bash
PID_FILE="${REPO_ROOT}/.backlog/.daemon.pid"
DAEMON_ALIVE=false
if [ -f "$PID_FILE" ]; then
  DPID=$(cat "$PID_FILE")
  kill -0 "$DPID" 2>/dev/null && DAEMON_ALIVE=true
fi
if [ "$DAEMON_ALIVE" = "false" ]; then
  # Spawn daemon via Bash(run_in_background=true)
  python3 "${REPO_ROOT}/scripts/loop-backlog-daemon.py" \
    --tasks-dir "${REPO_ROOT}/.backlog/tasks" \
    --pid-file  "${REPO_ROOT}/.backlog/.daemon.pid" \
    --stop-file "${REPO_ROOT}/.backlog/.loop-stop"
  sleep 1
fi
```

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "Monitor" .claude/skills/loop-backlog/SKILL.md`
- [ ] `! grep -q "ScheduleWakeup" .claude/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "daemonBootstrap" .claude/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "loop-backlog-daemon" .claude/skills/loop-backlog/SKILL.md`

---

## Phase C: Replace ScheduleWakeup with Monitor in workerLoop (SKILL.md — scheduling section)

### Tests (write first)

File: `scripts/test-loop-backlog-skill-monitor.sh`

Test cases (must fail before implementation):
- `test_workerloop_spec_uses_monitor` — grep SKILL.md for `Monitor(` in workerLoop spec; assert present
- `test_workerloop_spec_no_schedule_call` — assert `! grep -q "schedule(" .claude/skills/loop-backlog/SKILL.md`
- `test_skill_md_references_loop_stop_sentinel` — grep SKILL.md for `loop-stop`; assert present
- `test_skill_md_has_shutdown_section` — grep SKILL.md for `## Shutdown`; assert present

### Implementation

File to modify: `.claude/skills/loop-backlog/SKILL.md`

Changes:

1. Update `workerLoop` spec — replace `schedule(...)` calls with Monitor-based event loop:

```
workerLoop :: () → Outcome
workerLoop() = {
  cfg:    loadConfig(),
  _:      daemonBootstrap(),
  _:      reap(inProgressTasks()),
  event:  Monitor(timeout=600),   -- 10-minute watchdog

  if (stopSentinelPresent()):
    return: Idle,                 -- exit without rescheduling

  if (event == timeout):
    daemonBootstrap(),            -- watchdog: restart daemon if dead
    return: workerLoop(),

  taskId: parseTaskReady(event),
  task:   claimById(taskId),
  if (empty(task)): return: workerLoop(),   -- already claimed by another

  result: withWorktree(task, cfg, execute),
  return: workerLoop()            -- tail-recursive loop via Monitor
}
```

2. Replace `## Scheduling` section with `## Shutdown` section:

```markdown
## Shutdown

The worker exits (without rescheduling) when:
- `.backlog/.loop-stop` sentinel file is present, OR
- Monitor receives a daemon-exit signal with no further events

To stop a running loop: `touch .backlog/.loop-stop`
```

3. Remove `delayFor` function and scheduling table entirely.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "Monitor(timeout=600)" .claude/skills/loop-backlog/SKILL.md`
- [ ] `! grep -q "ScheduleWakeup" .claude/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "loop-stop" .claude/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "## Shutdown" .claude/skills/loop-backlog/SKILL.md`

---

## Phase D: Wire ensureDaemonScript into skill (write daemon from embedded template if missing)

### Tests (write first)

File: `scripts/test-loop-backlog-skill-template.sh`

Test cases (must fail before implementation):
- `test_skill_md_has_ensure_daemon_script_section` — grep SKILL.md for `ensureDaemonScript`; assert present
- `test_daemon_script_exists_in_repo` — assert `test -f scripts/loop-backlog-daemon.py`
- `test_daemon_script_is_valid_python` — `python3 -c "import ast; ast.parse(open('scripts/loop-backlog-daemon.py').read())"`

### Implementation

File to modify: `.claude/skills/loop-backlog/SKILL.md`

New `### ensureDaemonScript` section added to `## Implementation` (before `### daemonBootstrap`):

```bash
DAEMON_SCRIPT="${REPO_ROOT}/scripts/loop-backlog-daemon.py"
if [ ! -f "$DAEMON_SCRIPT" ]; then
  # Write daemon script from embedded template
  python3 - <<'PYEOF'
import sys, textwrap, os
# ... embedded full source of loop-backlog-daemon.py ...
PYEOF
  chmod +x "$DAEMON_SCRIPT"
fi
```

The embedded template content is the full source of `scripts/loop-backlog-daemon.py` from Phase A.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "ensureDaemonScript" .claude/skills/loop-backlog/SKILL.md`
- [ ] `test -f scripts/loop-backlog-daemon.py`
- [ ] `python3 -c "import ast; ast.parse(open('scripts/loop-backlog-daemon.py').read())" && echo "syntax ok"`

---

## Constraints

- The daemon must use Python stdlib only (no pip dependencies).
- The daemon must run on Python 3.6+ (`f-strings` allowed, walrus operator not required).
- The daemon PID file path is `.backlog/.daemon.pid` (relative to repo root).
- The stop sentinel path is `.backlog/.loop-stop` (relative to repo root).
- The daemon emits exactly one `task-ready:TASK-X` line per Ready transition (debounced via an in-memory set).
- The daemon self-terminates when its parent PID is no longer alive (orphan protection).
- The Monitor timeout window is 600 seconds (10 minutes); on timeout, the skill re-checks daemon liveness and re-enters Monitor — it does not exit unless the stop sentinel is present.
- Windows PTY compatibility is out of scope.
- No external test framework is required; test scripts use plain bash with `set -e` and inline assertions.
- Each phase must leave `bash scripts/validate-plugin.sh` passing before the next phase starts.

## Acceptance Gate

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "Monitor" .claude/skills/loop-backlog/SKILL.md`
- [ ] `! grep -q "ScheduleWakeup" .claude/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "loop-backlog-daemon" .claude/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "loop-stop" .claude/skills/loop-backlog/SKILL.md`
- [ ] `python3 -c "import ast; ast.parse(open('scripts/loop-backlog-daemon.py').read())" && echo "syntax ok"`
- [ ] `test -f scripts/loop-backlog-daemon.py`
