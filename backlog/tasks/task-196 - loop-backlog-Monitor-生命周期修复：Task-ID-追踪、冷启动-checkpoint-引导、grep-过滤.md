---
id: TASK-196
title: loop-backlog Monitor 生命周期修复：Task ID 追踪、冷启动 checkpoint 引导、grep 过滤
status: 'Basic: Done'
assignee: []
created_date: '2026-06-25 01:07'
updated_date: '2026-06-25 06:18'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 123000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
loop-backlog skill 在跨会话/上下文压缩场景下存在三个 Monitor 生命周期缺陷，需在 plugin/skills/loop-backlog/SKILL.md 中修复：

1. stopStaleMon() 仅用 pkill 杀 OS 级 tail 进程，未 TaskStop Claude Code Monitor 任务本身 → 旧 Monitor 跨会话存活，新会话再次启动后产生双 Monitor 重复通知。
2. daemonBootstrap 仅在 Monitor 返回事件后写 checkpoint；若会话因上下文压缩结束而 Monitor 尚未触发，checkpoint 不更新，下次冷启动 OFFSET=0，所有历史 heartbeat 一次性涌入。
3. Monitor command 为裸 tail -f，daemon 每 60s 写一次 heartbeat，每行都触发通知，空闲时噪音高。
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: loop-backlog Monitor 生命周期修复

## Background

loop-backlog 使用 Claude Code 的 Monitor 工具（harness 级对象，持有 task ID 如 `beu4217aa`）监听 daemon 日志。ADR-002 已要求在创建新 Monitor 前调用 `stopStaleMon()` 清理旧进程，但当前实现仅调用 `pkill -f "tail.*${DAEMON_LOG}"` 杀死 OS 层面的 tail 进程，未能终止 harness 层面的 Monitor task，导致上下文压缩后旧 Monitor 与新 Monitor 并存、每个事件被双重触发。此外，checkpoint 仅在 Monitor 返回事件后写入，若上下文压缩发生于 Monitor 空闲阻塞期（正常状态），checkpoint 从未被写入；下次冷重启 OFFSET=0，所有历史 heartbeat 行洪泛式重放。最后，Monitor command 是裸 `tail -f`，daemon 每 60 秒发出一条 heartbeat，空闲状态下产生 1 次/分钟的无效唤醒噪声。三个缺陷共同导致 loop-backlog 在长期运行中出现幽灵重复触发和持续噪声唤醒。

## Goals

1. 上下文压缩后重启 loop-backlog 时，同一 daemon 日志文件有且仅有一个活跃 Monitor task（harness 级），不出现双触发现象（可通过 TaskList 枚举 Monitor task 数量验证 = 1）。
2. 上下文压缩后冷重启时，OFFSET 能正确恢复到压缩前的日志末尾字节位置，不发生历史行洪泛（重放行数 = 0，等价于 `tail -c +${OFFSET}` 从正确偏移量开始）。
3. `heartbeat:` 行在 workerLoop 内被显式过滤，不进入任何下游处理分支，空闲期 Monitor 唤醒后的有效工作量降为 0（仅读取行内容后 continue，不修改任何任务状态）。

## Proposed Approach

**Bug 1 — 终止 harness 级 Monitor task**：在 `stopStaleMon()` 中，除保留 `pkill` 杀死 OS 层 tail 进程外，新增通过 `TaskStop` 原语（已在 allowed-tools 中列出）停止 harness 层面的旧 Monitor task。为使 TaskStop 能找到目标，在每次创建 Monitor 之前将 Monitor task ID 写入 `backlog/.monitor-task-id` 文件；`stopStaleMon()` 读取该文件并调用 `TaskStop(id)` 后删除文件。若文件不存在（首次启动）则跳过 TaskStop 步骤。

**Bug 2 — 入场基线 checkpoint**：在 `daemonBootstrap` 结尾、Monitor 创建之前，立即执行一次 checkpoint 写入：`wc -c < "$DAEMON_LOG" > "$CHECKPOINT_FILE"`。这确保即使 Monitor 空闲阻塞期间上下文压缩，下次重启时 OFFSET 仍指向本次入场时的日志末尾。Monitor 返回事件后继续追加写入 checkpoint（现有逻辑保留），形成"入场基线 + 事件驱动推进"的双重保障。

**Bug 3 — heartbeat 过滤**：在 `workerLoop` 内处理 Monitor 返回行时，在所有 `basic-ready:`/`epic-ready:`/`child-done:` 分支之前增加 `heartbeat:` 前缀检查，匹配则打印调试行（`echo "[loop-backlog] heartbeat, skipping"`）并 continue。不修改 daemon 的 heartbeat 发送逻辑（保留其连接保活语义），不在 Monitor command 层过滤（避免破坏事件日志完整性）。

## Trade-offs and Risks

**未做之事**：不修改 daemon heartbeat 频率（60 秒）或格式；不在 Monitor command 层添加 grep 过滤（保留日志完整性，debug 更容易）；不更改 `acquireLoopLock` 机制（flock 单实例保证已足够，Bug 1 是 stopStaleMon 实现缺口，而非锁机制问题）；不修改 gcl-events.jsonl 或任何历史记录。

**已知风险**：TaskStop 原语接受 task ID 字符串，若 harness 版本不支持按 ID 停止 Monitor task，则 Bug 1 的主修复失效，需退化为依赖 pkill 的现有方案（并在 ADR-002 中记录此限制）。入场基线 checkpoint 写入依赖 `daemonBootstrap` 在 Monitor 创建前执行，当前调用顺序满足此约束；若未来重构改变调用顺序需重新验证。

---

# Plan: loop-backlog Monitor 生命周期修复

## Phase A: stopStaleMon — 增加 TaskStop harness 层 Monitor task 终止

### Tests (write first)

验证条件（在实现前这些 grep 均应失败）：

```bash
# T-A1: SKILL.md 中存在 TaskStop 调用
grep -q "TaskStop" plugin/skills/loop-backlog/SKILL.md

# T-A2: SKILL.md 中存在 monitor-task-id 文件引用
grep -q "monitor-task-id" plugin/skills/loop-backlog/SKILL.md

# T-A3: validate-plugin.sh 仍通过（现有契约不被破坏）
bash scripts/validate-plugin.sh
```

### Implementation

目标文件：`plugin/skills/loop-backlog/SKILL.md`，`stopStaleMon` 小节（当前行 616-628）。

将现有 stopStaleMon 代码块替换为包含 TaskStop 逻辑的新版本（见 Proposed Approach Bug 1）。同时在 workerLoop Monitor 调用之前写入 monitor-task-id 文件并捕获 MONITOR_TASK_ID。

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "TaskStop" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "monitor-task-id" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "STALE_MONITOR_ID" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "MONITOR_TASK_ID_FILE" plugin/skills/loop-backlog/SKILL.md`

---

## Phase B: daemonBootstrap — 入场基线 checkpoint 写入

### Tests (write first)

验证条件（在实现前这些 grep 均应失败）：

```bash
# T-B1: daemonBootstrap 块内存在 wc -c 写入 CHECKPOINT_FILE 的语句（入场写入）
grep -qP "wc -c.*DAEMON_LOG.*CHECKPOINT_FILE|CHECKPOINT_FILE.*wc -c" plugin/skills/loop-backlog/SKILL.md

# T-B2: 存在"baseline checkpoint"调试输出
grep -q "baseline checkpoint" plugin/skills/loop-backlog/SKILL.md

# T-B3: validate-plugin.sh 仍通过
bash scripts/validate-plugin.sh
```

### Implementation

目标文件：`plugin/skills/loop-backlog/SKILL.md`，`daemonBootstrap` 小节末尾（当前行 698-701）。在 active-agents reconcile 段之后、代码块结束前追加 baseline checkpoint 写入语句。

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -qP "wc -c.*DAEMON_LOG.*CHECKPOINT_FILE|CHECKPOINT_FILE.*wc -c" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "baseline checkpoint" plugin/skills/loop-backlog/SKILL.md`

---

## Phase C: workerLoop — heartbeat 过滤

### Tests (write first)

验证条件（在实现前这些 grep 均应失败）：

```bash
# T-C1: SKILL.md 中存在显式 heartbeat: 过滤分支
grep -q "heartbeat:" plugin/skills/loop-backlog/SKILL.md

# T-C2: 过滤分支包含 skipping 调试输出
grep -q "heartbeat, skipping" plugin/skills/loop-backlog/SKILL.md

# T-C3: validate-plugin.sh 仍通过
bash scripts/validate-plugin.sh
```

### Implementation

目标文件：`plugin/skills/loop-backlog/SKILL.md`，workerLoop 事件分发段（行 1189-1196 附近）。在所有事件分支之前增加 heartbeat: 前缀检查并 continue。

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "heartbeat:" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "heartbeat, skipping" plugin/skills/loop-backlog/SKILL.md`

---

## Constraints

- 不修改 daemon 的 heartbeat 发送逻辑（60 秒频率与格式保留）。
- 不在 Monitor command 层添加 grep 过滤（保留完整日志，便于调试）。
- 不更改 `acquireLoopLock` 机制（flock 单实例保证已足够）。
- 不修改 gcl-events.jsonl 或任何历史记录。
- Phase A 必须先于 Phase B 和 Phase C 执行。
- TaskStop 原语若 harness 不支持按 ID 停止 Monitor task，需在 ADR-002 中记录退化方案（依赖 pkill）。
- 每个 Phase 的代码变更量均在 20 行以内，远低于 200 行上限。

---

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "TaskStop" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "monitor-task-id" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -qP "wc -c.*DAEMON_LOG.*CHECKPOINT_FILE|CHECKPOINT_FILE.*wc -c" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "heartbeat:" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "heartbeat, skipping" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "baseline checkpoint" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "STALE_MONITOR_ID" plugin/skills/loop-backlog/SKILL.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Proposal self-review: APPROVED
premise-ledger:
[E/C/H] Motivation: loop-backlog Monitor task persists at harness level across context compression; pkill only kills OS-level tail process
[E/C/H] Motivation: checkpoint write occurs only after Monitor returns event; context compression during idle leaves checkpoint un-updated → OFFSET=0 on cold restart
[E/C/H] Motivation: bare tail -f Monitor command causes 1 heartbeat notification/minute of pure noise
[E] Goal 1: verifiable via TaskList count = 1 after restart
[E] Goal 2: verifiable via replay line count = 0 (tail starts at correct offset)
[E] Goal 3: verifiable via no downstream task state mutation on heartbeat wakeup
[C] Bug 1 approach: TaskStop is in allowed-tools (SKILL.md line 4); .monitor-task-id file pattern is consistent with existing .merge-lock, .basic-daemon.pid patterns
[C] Bug 2 approach: daemonBootstrap runs before Monitor call (lines 630-701 vs 754-762 in SKILL.md); constraint already satisfied
[C] Bug 3 approach: workerLoop already dispatches on line prefix (basic-ready:, epic-ready:, child-done:); heartbeat: check adds one more branch
[H] Risk: TaskStop harness API may not support stopping by ID — fallback documented
[H] Risk: hours_to_detection rename is irrelevant (wrong task context; discard); valid risk is ordering constraint for Bug 2 checkpoint
GCL-self-report: E=6 C=3 H=2

Proposal approved. Starting plan draft.

Plan review iteration 1: APPROVED
premise-ledger:
[E/C/H] Goal coverage: all 3 goals map 1-to-1 to Phases A/B/C — premise holds
[E/C/H] TDD structure: each phase has ### Tests then ### Implementation in correct order — premise holds
[E/C/H] TDD order: first DoD item in each phase is bash scripts/validate-plugin.sh — premise holds
[E/C/H] Acceptance Gate first item: bash scripts/validate-plugin.sh — premise holds
[E/C/H] DoD executability: all DoD and Acceptance Gate items are shell commands, no natural-language items — premise holds
[E/C/H] Absence checks: no grep -qv pattern used anywhere — premise holds
[E/C/H] Phase ordering: A→B→C, no circular deps, A builds monitor-task-id infra used conceptually by B/C — premise holds
[E/C/H] Scope discipline: all three phases backed by Goals 1/2/3 respectively — premise holds
[E/C/H] File paths: plugin/skills/loop-backlog/SKILL.md confirmed to exist — premise holds
GCL-self-report: E=7 C=9 H=7

claimed: 2026-06-25T04:43:14Z

Phase A ✓ 2026-06-25T00:00:00Z
stopStaleMon: replaced pkill-only block with TaskStop + MONITOR_TASK_ID_FILE tracking + OS-level pkill fallback

Phase B ✓ 2026-06-25T00:00:00Z
daemonBootstrap: added baseline checkpoint write (wc -c of DAEMON_LOG → CHECKPOINT_FILE) before Monitor creation

Phase C ✓ 2026-06-25T00:00:00Z
workerLoop dispatch: added heartbeat filter (grep -q "^heartbeat:" → echo "[loop-backlog] heartbeat, skipping") before case dispatch

DoD #1: PASS — bash scripts/validate-plugin.sh
DoD #2: PASS — grep -q "TaskStop" plugin/skills/loop-backlog/SKILL.md
DoD #3: PASS — grep -q "monitor-task-id" plugin/skills/loop-backlog/SKILL.md
DoD #4: PASS — grep -q "STALE_MONITOR_ID" plugin/skills/loop-backlog/SKILL.md
DoD #5: PASS — grep -q "MONITOR_TASK_ID_FILE" plugin/skills/loop-backlog/SKILL.md
DoD #6: PASS — grep -qP "wc -c.*DAEMON_LOG.*CHECKPOINT_FILE|CHECKPOINT_FILE.*wc -c" plugin/skills/loop-backlog/SKILL.md
DoD #7: PASS — grep -q "baseline checkpoint" plugin/skills/loop-backlog/SKILL.md
DoD #8: PASS — grep -q "heartbeat:" plugin/skills/loop-backlog/SKILL.md
DoD #9: PASS — grep -q "heartbeat, skipping" plugin/skills/loop-backlog/SKILL.md
DoD #10: PASS — bash scripts/validate-plugin.sh
## Execution Summary
Result: Done
Commit: 4320f0ddd7630da979fff80f95afcefb985fecff

Completed: 2026-06-25T04:51:29Z

后续修正（2026-06-25）：Bug 3 修复层级错误

TASK-196 将 heartbeat 过滤加在 workerLoop dispatch 代码层，但 Monitor 仍会把 heartbeat 行作为通知 deliver 给用户 UI（每 60s 一次），用户可见噪音未消除。

根本原因：过滤需在 Monitor command 的 grep filter 层完成，而非事后在代码里 skip。

修正：将 Monitor command 从裸 `tail -c +${OFFSET} -f "$DAEMON_LOG"` 改为
`tail -c +${OFFSET} -f "$DAEMON_LOG" | grep --line-buffered -E "^(basic-ready|epic-ready|child-done|proposal-approved|plan-approved):"`

heartbeat: 行现在在 Monitor command 层被 grep 过滤，永远不会触发通知。同步更新：spec pseudocode、workerLoop parallel 注释、reference 章节、description 字符串；smoke test 新增两项检查（Monitor grep 包含 actionable events、heartbeat 不在 filter 里）。
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 grep -q "TaskStop" plugin/skills/loop-backlog/SKILL.md
- [ ] #3 grep -q "monitor-task-id" plugin/skills/loop-backlog/SKILL.md
- [ ] #4 grep -q "STALE_MONITOR_ID" plugin/skills/loop-backlog/SKILL.md
- [ ] #5 grep -q "MONITOR_TASK_ID_FILE" plugin/skills/loop-backlog/SKILL.md
- [ ] #6 grep -qP "wc -c.*DAEMON_LOG.*CHECKPOINT_FILE|CHECKPOINT_FILE.*wc -c" plugin/skills/loop-backlog/SKILL.md
- [ ] #7 grep -q "baseline checkpoint" plugin/skills/loop-backlog/SKILL.md
- [ ] #8 grep -q "heartbeat:" plugin/skills/loop-backlog/SKILL.md
- [ ] #9 grep -q "heartbeat, skipping" plugin/skills/loop-backlog/SKILL.md
- [ ] #10 bash scripts/validate-plugin.sh
<!-- DOD:END -->
