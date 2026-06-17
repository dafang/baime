# Proposal: loop-backlog: daemon + Monitor 替代 ScheduleWakeup 实现事件驱动触发

## Background

The current loop-backlog worker relies on ScheduleWakeup to reschedule itself every 120 seconds after each iteration, regardless of whether any work was done. When the task queue is empty — which is the common state between bursts of task activity — every wakeup consumes a full Claude invocation just to call `backlog task list`, find nothing, and reschedule again. Because ScheduleWakeup enforces a minimum 60-second interval, the worker cannot react faster even when a task is enqueued immediately after a poll. Over hours of idle time this pattern burns tokens on pure overhead: no decision is made, no code is written, yet each cycle incurs model invocation cost. The fundamental mismatch is that ScheduleWakeup is a time-driven mechanism being used to solve an event-driven problem — "is there a new Ready task?" — whose answer changes only when a human or process edits a task file.

## Goals

1. Token cost per idle hour drops to zero: when no Ready tasks exist, no Claude invocations are triggered until a task file changes.
2. Latency from task becoming Ready to worker picking it up is ≤ 2 seconds under normal filesystem load (currently up to 120 seconds).
3. The daemon starts and stops without any dependency outside Python stdlib; `python3 --version` is the only prerequisite.
4. Exactly one daemon process runs per repository at any time; duplicate invocations of `/loop-backlog` do not spawn duplicate daemons.
5. The worker can be halted cleanly by a human without killing Claude: placing `.backlog/.loop-stop` causes both the daemon and the loop to exit within one poll cycle.
6. A task that is set Ready, picked up, then reset to Ready (e.g. by the reaper) is re-notified correctly; tasks that remain Ready but have already been claimed are not re-notified spuriously.

## Proposed Approach

A small Python daemon script (stdlib only) is written to the repository under `.backlog/task-watcher.py`. It polls the backlog tasks directory at a 500 ms interval using `os.walk` and `os.stat` to detect files whose content contains `status: Ready`. When a qualifying task is found whose ID is not already in an in-memory "notified" set, the daemon writes `task-ready:TASK-X` to stdout and adds the ID to the set. When a task ID disappears from Ready status it is removed from the notified set, so future Ready transitions for that task trigger a fresh notification. The daemon also polls for the sentinel file `.backlog/.loop-stop`; when it appears, the daemon exits cleanly.

The loop-backlog skill is updated to replace the ScheduleWakeup model with the following lifecycle:

1. **Daemon bootstrap** — on entry, loop-backlog checks whether a PID recorded in `.backlog/.daemon.pid` corresponds to a live process. If not, it spawns the daemon as a background subprocess, writes its PID to `.backlog/.daemon.pid`, and waits briefly for the process to confirm it is running.
2. **Event-driven wait** — instead of ScheduleWakeup, the skill calls the Monitor tool, subscribing to the daemon's stdout stream. Monitor blocks until a `task-ready:TASK-X` line arrives, then returns the task ID to the skill.
3. **Claim and execute** — the existing claim/withWorktree/execute/merge logic runs unchanged on the signalled task ID.
4. **Loop continuation** — after merging (or escalating), the skill calls Monitor again for the next event, eliminating the ScheduleWakeup call entirely. The only remaining scheduled wakeup is a watchdog: if Monitor receives no event within 10 minutes, loop-backlog re-checks that the daemon is still alive and restarts it if necessary, then re-enters Monitor.
5. **Graceful shutdown** — when the skill detects `.backlog/.loop-stop`, or when the daemon process is no longer alive, it exits without rescheduling.

The daemon script itself is idempotent to create: loop-backlog writes it from an embedded template if it does not already exist, so no separate installation step is needed.

The loop-backlog SKILL.md `allowed-tools` header must also be updated: `ScheduleWakeup` is removed and `Monitor` is added. Without this change the skill cannot call Monitor and the event-driven design will not function. This is a one-line edit to the skill definition file.

## Trade-offs and Risks

**What we are not doing.** We are not using OS-native filesystem event APIs (inotify, FSEvents, ReadDirectoryChangesW) or third-party libraries such as watchdog. The 500 ms polling interval means the daemon is not zero-CPU, but at that frequency the cost is negligible compared to Claude invocation overhead.

**Daemon process leak risk.** If Claude crashes mid-session without writing `.loop-stop`, the daemon continues running indefinitely. Mitigation: the daemon checks at each poll whether its parent PID (recorded at startup) is still alive; if the parent has exited, the daemon self-terminates.

**PID file staleness.** A stale `.daemon.pid` from a previous crashed session could cause loop-backlog to believe a daemon is running when it is not. Mitigation: loop-backlog validates liveness with `os.kill(pid, 0)` before trusting the PID file, and re-spawns on failure.

**Monitor tool availability.** This design assumes the Monitor tool can subscribe to a long-lived subprocess stdout stream. If Monitor imposes a maximum blocking duration shorter than the 10-minute watchdog window, the skill must re-enter Monitor in a tight loop, which partially re-introduces polling at the Claude layer. This constraint should be verified before implementation.

**Windows compatibility.** Python `os.kill(pid, 0)` works on Windows for liveness checks. Subprocess stdout streaming via Monitor may behave differently under Windows PTY handling. Basic functionality should work, but CI verification on Windows is out of scope for this change.

**Alternatives considered.** Using a named pipe or Unix socket instead of stdout was rejected as more complex to implement cross-platform. Using ScheduleWakeup with a shorter interval (e.g. 10 s) was rejected because it lowers latency but does not eliminate idle token cost. A pure Claude-side file-watch loop was rejected because it would require the model to remain "awake" continuously, which is not how ScheduleWakeup works.
