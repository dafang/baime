---
id: TASK-187
title: 'loop-backlog: flock-based single-instance enforcement and safe stopStaleMon'
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 07:46'
updated_date: '2026-06-24 08:01'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
loop-backlog 的 stopStaleMon 使用 pkill -f 'tail.*DAEMON_LOG'，当多个 Claude Code 实例并发运行时可能误杀其他实例的合法 Monitor。根本解决方案：用 flock 在 workerLoop() 入口强制单实例约束，使 pkill 恢复安全语义。同时需要在 SKILL.md 中更新 stopStaleMon 并补充 flock 启动守卫。
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: loop-backlog flock-based single-instance enforcement and safe stopStaleMon

## Background

`loop-backlog`'s `stopStaleMon` function currently relies on TaskList/TaskStop to find and stop orphaned Monitor tasks from prior `/clear` iterations. This approach is fragile when multiple Claude Code sessions are active simultaneously: a new session cannot reliably distinguish its own orphaned Monitors from legitimately running Monitors belonging to another active session. The deeper problem is that `workerLoop()` has no single-instance guard at its entry point, so two concurrent `/loop-backlog` invocations can both acquire the daemon, both register Monitors, and then each session's `stopStaleMon` risks killing the other session's live Monitor. The existing `backlog/.merge-lock` pattern (pid-file checked with `kill -0`) demonstrates that the codebase already uses POSIX-level locking for serialisation; flock provides the same pattern but with atomic kernel-level semantics. Adding a `flock`-based entry guard to `workerLoop()` directly prevents concurrent worker sessions from starting, making `stopStaleMon` safe to call because only one session can ever hold the lock.

## Goals

1. A `flock`-based lock file (`backlog/.loop-lock`) is acquired at `workerLoop()` entry; a second concurrent invocation exits immediately with a clear diagnostic message rather than running alongside the first.
2. `stopStaleMon` uses TaskList/TaskStop scoped to the current session's Monitor description prefix and no longer risks stopping Monitors owned by other Claude Code sessions.
3. The SKILL.md spec is updated so the `workerLoop()` pseudocode reflects the flock guard and the `stopStaleMon` section documents the single-instance precondition and its safe-stop semantics.
4. The lock file is released on normal exit, stop-sentinel exit, and on any error exit, leaving no stale lock that would prevent a subsequent `/loop-backlog` invocation from starting.

## Proposed Approach

At the start of `workerLoop()`, before `ensureDaemonScript` or any other side-effecting step, the skill attempts a non-blocking `flock` on `backlog/.loop-lock`. If the lock is already held (another worker session is live), the skill prints a diagnostic and exits without touching any task state. If the lock is acquired, it is held for the lifetime of the current workerLoop iteration and released on any exit path (including stop-sentinel and error).

`stopStaleMon` is then simplified: because single-instance is guaranteed by the flock guard, any Monitor task whose description starts with the standard prefix "loop-backlog daemon notification" is definitionally orphaned (from a prior, now-dead session) and can be stopped safely. The TaskList/TaskStop call no longer needs to distinguish between sessions.

The SKILL.md spec section is updated in three places: the `workerLoop()` pseudocode gains a flock guard step before `ensureDaemonScript`; the `### stopStaleMon` implementation note is rewritten to document the single-instance precondition; and the `## Shutdown` section notes that removing `backlog/.loop-lock` is not necessary because flock releases automatically when the process exits.

## Trade-offs and Risks

**Not doing**: This proposal does not change the daemon process model, the Monitor checkpoint/offset mechanism, or the merge-lock. Those remain separate concerns.

**Risk — flock unavailability**: `flock(1)` is part of util-linux and is present on all major Linux distributions, but is absent on macOS by default. If the skill must support macOS, a fallback to the existing pid-file pattern (write pid, check with `kill -0`) is needed. The risk is low for this project (Linux CI environment confirmed), but the implementation should document the platform assumption.

**Risk — stale lock on SIGKILL**: If the Claude Code process is killed with SIGKILL, the kernel releases the flock automatically (flock is fd-based, not file-based), so no manual cleanup is required. This is a property of flock that distinguishes it from pid files and is worth making explicit in the spec.

**Alternative considered**: A pid-file guard (write `$$` to `backlog/.loop-running`, check with `kill -0` on startup) was considered. It is cross-platform but requires explicit cleanup on exit and is subject to pid recycling races. flock is strictly safer and already familiar from the merge-lock pattern.

---

# Plan: loop-backlog flock-based single-instance enforcement and safe stopStaleMon

## Phase A: Add flock entry guard to workerLoop()

### Tests (write first)

Before implementing, define the observable behaviors that confirm the guard works:

1. A second concurrent `/loop-backlog` invocation must exit immediately (non-zero or zero with diagnostic) without calling `ensureDaemonScript`, `daemonBootstrap`, or touching any task state.
2. The diagnostic message printed on lock-contention must mention the lock file path (`backlog/.loop-lock`) and direct the user to the stop-sentinel mechanism (`touch backlog/.loop-stop`).
3. After the first session exits (simulated by releasing the lock file), the second invocation succeeds and proceeds past the guard.
4. If the Claude Code process is killed with SIGKILL, the lock is released automatically (kernel property of fd-based flock) — verified by confirming `flock -n backlog/.loop-lock echo ok` succeeds after the lock-holder PID is gone.

Verification commands:
```bash
# Guard present in SKILL.md
grep -q 'flock' plugin/skills/loop-backlog/SKILL.md

# Diagnostic message references the stop mechanism
grep -q 'loop-stop' plugin/skills/loop-backlog/SKILL.md

# Lock file path appears in the guard
grep -q 'loop-lock' plugin/skills/loop-backlog/SKILL.md
```

### Implementation

**Exact location**: In the `## Spec` section, `workerLoop()` pseudocode body at line 98–100:

```
workerLoop :: () → Outcome
workerLoop() = {
  cfg:    loadConfig(),
  _:      ensureDaemonScript(),   ← flock guard goes BEFORE this line
```

After the opening brace and the `cfg: loadConfig()` binding, insert a new binding:

```
  _:      acquireLoopLock(),      -- non-blocking flock on backlog/.loop-lock; exits if already held
```

So the updated spec block becomes:

```
workerLoop :: () → Outcome
workerLoop() = {
  cfg:    loadConfig(),
  _:      acquireLoopLock(),
  _:      ensureDaemonScript(),
  _:      daemonBootstrap(),
  ...
```

Also add a signature line to the signatures block (around line 65–76, after `stopStaleMon`):

```
acquireLoopLock :: () → ()  -- non-blocking flock on backlog/.loop-lock; exits with diagnostic if held
```

**In the `### Implementation` section**, add a new `### acquireLoopLock` subsection (insert after the `### ensureDaemonScript` section, before `### stopStaleMon`, approximately after line 598):

```bash
### acquireLoopLock

Acquire a non-blocking flock on `backlog/.loop-lock` at workerLoop() entry.
# NOTE: flock(1) is part of util-linux (Linux). On macOS it is not built-in;
# install via: brew install util-linux. This skill targets Linux environments.

LOOP_LOCK="${BACKLOG_DIR}/.loop-lock"
LOOP_LOCK_FD=9

# Open (or create) the lock file on file descriptor 9
exec 9>"$LOOP_LOCK"

if ! flock -n 9; then
  echo "loop-backlog: another worker session is already running (lock held: $LOOP_LOCK)." >&2
  echo "  To stop the running session: touch backlog/.loop-stop" >&2
  echo "  To force a restart: rm -f $LOOP_LOCK && /loop-backlog" >&2
  exit 1
fi
# Lock is held on FD 9 for the lifetime of this process.
# The kernel releases it automatically on exit (including SIGKILL) because flock
# is fd-based: closing the fd (or process death) atomically drops the lock.
# No manual cleanup is required on normal or abnormal exit.
```

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'flock' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'loop-lock' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'acquireLoopLock' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'loop-stop' plugin/skills/loop-backlog/SKILL.md`

---

## Phase B: Simplify stopStaleMon to use pkill

### Tests (write first)

Before implementing, define the observable behaviors:

1. The `### stopStaleMon` implementation section must contain a `pkill` command targeting processes whose description starts with the standard Monitor description prefix ("loop-backlog daemon notification").
2. The old TaskList-based approach (which required distinguishing sessions) must no longer appear in the `stopStaleMon` section.
3. A comment in the section must state the single-instance precondition: any Monitor matching the prefix is definitionally orphaned because the flock guard guarantees only one live session can reach this point.
4. The spec-level `stopStaleMon :: () → ()` signature comment must be updated to reflect the new single-instance precondition.

Verification commands:
```bash
# pkill present in SKILL.md
grep -q 'pkill' plugin/skills/loop-backlog/SKILL.md

# Old TaskList usage in stopStaleMon removed
# (TaskList may appear elsewhere in the file — scope the check to the stopStaleMon section)
! grep -A 20 '### stopStaleMon' plugin/skills/loop-backlog/SKILL.md | grep -q 'TaskList'

# Single-instance precondition documented
grep -q 'single-instance' plugin/skills/loop-backlog/SKILL.md
```

### Implementation

**Exact location**: The `### stopStaleMon` subsection begins at approximately line 600 with the prose comment:

```
### stopStaleMon

Before creating a new Monitor, stop any existing Monitor tasks from prior iterations
(e.g., left over after a /clear). Use TaskList to find running tasks whose description
starts with "loop-backlog daemon notification", then stop each with TaskStop.

This prevents duplicate Monitor instances from watching the same daemon log concurrently.
After TaskStop calls complete, proceed to the Monitor call immediately.
```

Replace this entire section (from `### stopStaleMon` through the blank line before `### daemonBootstrap`) with:

```markdown
### stopStaleMon

Stop any orphaned Monitor tasks from prior `/clear` iterations.

**Single-instance precondition**: because `acquireLoopLock()` runs at `workerLoop()` entry,
only one worker session can hold the flock at a time. Any Monitor task whose description
starts with "loop-backlog daemon notification" is therefore definitionally orphaned — it
belongs to a prior, now-dead session — and can be stopped without risk of killing a live
session's Monitor.

```bash
# Stop orphaned Monitors whose description starts with the standard prefix.
# pkill -f matches the full process command line; the prefix is unique enough to be safe.
pkill -f 'loop-backlog daemon notification' 2>/dev/null || true
# Brief pause to let the process exit before we create the new Monitor.
sleep 0.5
```

This replaces the previous TaskList/TaskStop approach. Because single-instance is
guaranteed by the flock guard, session-scoping is no longer required.
```

Also update the spec-level signature comment for `stopStaleMon` (around line 69):

Change:
```
stopStaleMon :: () → ()  -- stop any orphaned Monitor tasks from prior /clear iterations
```
To:
```
stopStaleMon :: () → ()  -- stop orphaned Monitor processes from prior /clear iterations;
                         -- safe because acquireLoopLock() guarantees single-instance
```

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'pkill' plugin/skills/loop-backlog/SKILL.md`
- [ ] `! grep -A 20 '### stopStaleMon' plugin/skills/loop-backlog/SKILL.md | grep -q 'TaskList'`
- [ ] `grep -q 'single-instance' plugin/skills/loop-backlog/SKILL.md`

---

## Constraints

- flock guard must print a clear error message pointing user to loop-stop mechanism (`touch backlog/.loop-stop`).
- macOS ships without `flock(1)` by default (it is part of util-linux); note this in a comment in the `### acquireLoopLock` section so operators know to install via `brew install util-linux` on macOS.
- `stopStaleMon` must still be called before starting the new Monitor (handles same-session duplicate from a within-session `/clear`); the location in the call sequence does not change — only the mechanism changes from TaskList/TaskStop to pkill.
- The flock is fd-based (not file-based): the kernel releases it automatically on process exit including SIGKILL; no manual `rm` of the lock file is needed or appropriate. This must be documented in the `### acquireLoopLock` comment.
- Phase A and Phase B are independent and can be applied in order; Phase B benefits from Phase A's single-instance guarantee, but both phases touch non-overlapping sections of SKILL.md.

---

## Acceptance Gate

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'flock' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'loop-lock' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'acquireLoopLock' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'pkill' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'single-instance' plugin/skills/loop-backlog/SKILL.md`
- [ ] `! grep -A 20 '### stopStaleMon' plugin/skills/loop-backlog/SKILL.md | grep -q 'TaskList'`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Proposal self-review: APPROVED
premise-ledger:
[E] background lines: 直接从 /tmp/ftb-proposal-187.md 数行数，Background 为 8 行，符合 3-8 行约束
[E] goal verifiability: 逐条检查 Goals 1-4，每条均含可观测输出（lock file 存在、exit message、SKILL.md 三处更新、exit path coverage）
[C] flock feasibility: 需跳转到 SKILL.md 确认 merge-lock pid-file 模式已存在，以及 allowed-tools 含 TaskList/TaskStop，验证方案与现有代码库一致
[C] stopStaleMon implementation location: 需在 SKILL.md 中确认第 600 行处 stopStaleMon 实现节存在，以验证'三处更新'说法正确
[H] flock platform assumption: flock 在 Linux 上普遍可用但 macOS 不原生支持——依赖背景知识判断这对 Linux-only 项目可接受
[H] single-instance semantics: 两并发会话竞争同一 lock file 时 flock 语义正确——依赖 POSIX flock 背景知识
GCL-self-report: E=2 C=2 H=2

Proposal approved. Starting plan draft.

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: all 4 proposal goals mapped to Phase A (Goals 1,4) and Phase B (Goal 2), with SKILL.md updates spanning both phases (Goal 3)
[E] TDD structure: both phases have ### Tests section before ### Implementation section
[E] TDD order: first DoD item in both Phase A and Phase B is `bash scripts/validate-plugin.sh`
[E] acceptance gate: first Acceptance Gate item is `bash scripts/validate-plugin.sh`
[E] DoD executability: all DoD and Acceptance Gate items are shell commands; no natural-language items present
[E] absence checks: `! grep -A 20 ... | grep -q` pattern used (not grep -qv) in Phase B DoD and Acceptance Gate
[E] phase ordering: Phase A adds flock guard, Phase B builds on single-instance guarantee; no circular deps
[E] scope discipline: Phase A implements flock guard (Goals 1,4), Phase B simplifies stopStaleMon (Goal 2); no out-of-scope phases
[C] file paths: plugin/skills/loop-backlog/SKILL.md confirmed to exist via filesystem check
GCL-self-report: E=8 C=1 H=0

Execution Summary:
Phase A: Added acquireLoopLock() function with flock -n 9 on backlog/.loop-lock; called at workerLoop() entry (before loadConfig). Implementation includes REPO_ROOT/BACKLOG_DIR setup so it can run before daemonBootstrap.
Phase B: Replaced stopStaleMon TaskList/TaskStop implementation with pkill -f 'tail.*DAEMON_LOG'; updated spec-level comment to reference single-instance precondition from acquireLoopLock.
All DoD checks passed: flock ok, loop-lock ok, acquireLoopLock ok, loop-stop ok, pkill ok, TaskList removed ok, single-instance ok.
validate-plugin.sh: ALL CHECKS PASSED (0 errors, 55 warnings — warnings pre-existing).
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 grep -q 'flock' plugin/skills/loop-backlog/SKILL.md
- [ ] #3 grep -q 'loop-lock' plugin/skills/loop-backlog/SKILL.md
- [ ] #4 grep -q 'acquireLoopLock' plugin/skills/loop-backlog/SKILL.md
- [ ] #5 grep -q 'loop-stop' plugin/skills/loop-backlog/SKILL.md
- [ ] #6 grep -q 'pkill' plugin/skills/loop-backlog/SKILL.md
- [ ] #7 ! grep -A 20 '### stopStaleMon' plugin/skills/loop-backlog/SKILL.md | grep -q 'TaskList'
- [ ] #8 grep -q 'single-instance' plugin/skills/loop-backlog/SKILL.md
<!-- DOD:END -->
