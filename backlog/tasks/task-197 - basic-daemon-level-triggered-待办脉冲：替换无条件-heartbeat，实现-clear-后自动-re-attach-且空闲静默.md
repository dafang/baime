---
id: TASK-197
title: >-
  basic-daemon level-triggered 待办脉冲：替换无条件 heartbeat，实现 /clear 后自动 re-attach
  且空闲静默
status: 'Basic: Done'
assignee: []
created_date: '2026-06-25 06:51'
updated_date: '2026-06-25 07:36'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 124000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 问题

loop-backlog 在 /clear 或 compact 后无法自动恢复处理看板：loop 主进程随会话死亡，daemon 是边沿触发（basic-ready 只在任务进入 Ready 时发射一次，加入 notified Set 后不再重发），唯一的周期性信号是每 60s 的无条件 heartbeat。

heartbeat 同时承担两个互相冲突的角色：
- 它是 /clear 后唯一能异步唤醒空闲会话、触发 re-attach 的信号
- 它每 60s 唤醒会话 = 用户抱怨的噪音

TASK-196 后续把 heartbeat 从 Monitor grep filter 排除以消噪，结果切断了 re-attach 路径，导致 Basic: Ready 任务（如 Backlog.md 项目的 BACK-511）卡死无人处理。

## 方案：level-triggered 待办脉冲

将 basic-daemon.js（v8→v9）的无条件 heartbeat 替换为"待办脉冲"：每 60s 重新发射当前仍处于可执行状态的真实事件（basic-ready/epic-ready/child-done/proposal-approved/plan-approved），仅当该状态持续存在时。

- 看板空闲（无可执行任务）→ 0 输出，完全静默（消噪）
- 任务卡在可执行状态没人处理 → 每 60s 重发该事件 → 唤醒空闲会话 → 认领后离开该状态 → 脉冲自动停止（re-attach）
- loop 正在处理（任务已 In Progress）→ 不重发，静默

安全性：所有 handler 幂等（cap:claim / cap:decompose / cap:evaluate 守卫），重发不会重复执行。

脉冲间隔：60s（/clear 后最多 60s 自动恢复）。

## 影响文件

- plugin/scripts/basic-daemon.js（核心逻辑，v8→v9）
- plugin/skills/loop-backlog/SKILL.md（spec/description 更新脉冲语义，Monitor grep filter 保持只放行真实事件）
- 测试：daemon 行为单测（空闲 0 输出、stuck 任务周期重发、离开状态后停止）

"只有一个 Monitor"的保证由现有 flock + stopStaleMon + TaskStop + .monitor-task-id 链覆盖，本任务不改。
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: basic-daemon level-triggered 待办脉冲

## Background

`loop-backlog` 无法在 `/clear` 或上下文压缩后自动恢复。loop 主进程随 session 死亡，而 `basic-daemon.js`（v8）的五个事件通道**边沿触发**：每通道一个 `notified` Set（第 152-169 行），`basic-ready:TASK-N` 在任务进入 Ready 时只发射一次便永不重发；唯一周期性信号是每 60s 无条件的 `heartbeat:TIMESTAMP`（第 172-175 行）。

heartbeat 身兼两个**冲突**角色：(a) 唯一能异步唤醒空闲 session 触发重 attach 的信号；(b) 每 60s 唤醒 = 用户可见噪声。TASK-196 后续把 heartbeat 从 Monitor grep 过滤器剔除以消噪——却切断了重 attach 路径，令 `Basic: Ready` 任务卡死无人认领。

架构约束：Claude Code 中空闲 session 只能由异步外部事件（Monitor）唤醒，hook 无法在空闲 session 创造自主回合——故「heartbeat 即噪声」与「heartbeat 即重 attach」是**同一机制**，无条件 heartbeat 下「空闲静默」与「自动重 attach」不可兼得。

## Goals

1. **空闲静默**：当看板上没有任何 actionable 任务时，daemon 在连续 3 个脉冲周期（约 180s）内向 stdout 写出 **0 行**输出。可验证：注入仅含非 actionable 状态的任务，断言脉冲输出行数为 0。
2. **卡死任务自愈**：当一个 actionable 任务（如 `Basic: Ready`）无人认领时，daemon 每约 60s **重发**其真实事件行（`basic-ready:TASK-N`），从而唤醒空闲 session 触发重 attach 与认领。可验证：任务停留 Ready 跨 2 个脉冲周期，断言 `basic-ready:TASK-N` 被发射 ≥2 次。
3. **处理中静默**：任务一旦被认领进入 `Basic: In Progress`（离开 actionable 状态），脉冲**不再**重发其事件。可验证：任务从 Ready 转 In Progress 后，后续脉冲周期对该 ID 输出 0 行。
4. **`/clear` 60s 内恢复**：脉冲间隔设为 60s，使 `/clear` 后最迟 60s 内重新 attach 并恢复 worker。
5. **零回归 of 单 Monitor 保证**：本改动不触碰 flock / `stopStaleMon` / `TaskStop` / `.monitor-task-id` 这套「恰好一个 Monitor」机制。

## Proposed Approach

将无条件 heartbeat 替换为**电平触发（level-triggered）的「待办脉冲」**（daemon v8 → v9）。

**改什么（basic-daemon.js）**：
- 删除 `heartbeatTimer`（第 172-175 行）及其 `heartbeat:TIMESTAMP` 输出。
- 新增独立的 `pulseTimer`（`setInterval`，间隔 `pulseInterval` 默认 60s）。每个脉冲周期：遍历五个通道，对每个通道用现有 `scanIds(predicate)` 重新计算当前**仍处于 actionable 状态**的任务 ID 集合，并对集合中**每一个** ID 无条件重发其真实事件行（`${ch.prefix}:${id}`）——即不查 `notified`、不更新 `notified`。
- 保留原有 0.5s 边沿触发 `timer`（第 160-170 行）与 `notified` 语义不变：它负责状态**进入**时的低延迟首次发射（亚秒级），脉冲只是在其之上叠加一层 60s 的电平重发。两者输出同一格式的真实事件行，下游 idempotent，无需区分。

**改什么（SKILL.md Monitor）**：
- grep 过滤器与 description 维持只匹配五个真实事件前缀（`^(basic-ready|epic-ready|child-done|proposal-approved|plan-approved):`）。由于脉冲发射的就是这些真实事件行，它们**天然通过**过滤器并唤醒 session——无需再为 heartbeat 开特例。description 中关于「heartbeat 被过滤」的措辞更新为「事件行可能因任务卡在 actionable 状态而每约 60s 重发，属正常重 attach 信号」。

**保持不变**：五个通道的 predicate、`readTaskMeta`、`scanIds`、PID/stop-file 生命周期、flock 单实例、`stopStaleMon`、worktree 并行执行、cap:* idempotency。

**为什么安全**：所有事件 handler 已是幂等的——`basic-ready` 经 `cap:claim` 守卫（`claimBatch` 检查 `cap:claim=started`），`epic-ready` 经 `cap:decompose` 守卫（`epicDecompose` 检查 `hasCap(id,"decompose")`），`child-done`→`onChildDone` 与 `epicEvaluate` 经 `cap:evaluate` 守卫，`proposal-approved`/`plan-approved` 由 marker 文件 + 状态双重门控。因此重发同一事件**永不二次执行**：要么任务已离开 actionable 状态（脉冲不再发），要么 cap 守卫令重发成为 no-op。

**测试（basic-daemon.test.js 风格）**：沿用现有 `assert()` + 纯函数模式，抽出一个纯函数 `computePulseLines(tasksDir, channels)`（返回本周期应发射的事件行数组），对其单测：(a) 空看板 / 全非 actionable → `[]`；(b) 一个 Ready 任务 → `["basic-ready:TASK-N"]`，连续两次调用均返回该行（证明电平重发不依赖 `notified`）；(c) 同一任务转 In Progress 后 → `[]`。脉冲与边沿 timer 的真实 setInterval 接线不入单测（与现有测试一致，定时器副作用不测）。

## Trade-offs and Risks

**我们不做的**：不改「恰好一个 Monitor」保证（已由 flock + `stopStaleMon` + `TaskStop` + `.monitor-task-id` 覆盖，本任务显式不动）；不改任何 predicate 的 actionable 判定语义；不引入新事件通道；不改 SKILL.md 的 dispatch 分支逻辑（第 126-131 行原样）。

**重发-during-decompose 窗口的幂等边界**：`epic-ready` 经 `epicDecompose` 后是 spawn-and-forget——orchestrator 立即返回，背景 agent 才设置 `Epic: Decomposing` 并写 `cap:decompose=started`。在「已 spawn 背景 agent 但 agent 尚未把状态推离 `Epic: Ready` / 尚未落 cap」的窗口内，下一次脉冲会重发 `epic-ready:TASK-N`。这由 `epicDecompose` 入口的 `hasCap(id,"decompose")` 与 `¬isEpicReady(id)` 双重检查兜底：cap 一旦落地即 no-op。残留风险仅限「背景 agent 已 spawn 但 cap 未落」这一亚秒到数秒窗口，此时第二次 `epicDecompose` 可能再 spawn 一个 decompose agent；缓解依赖背景 agent 启动后**尽早**写 `cap:decompose=started`（现有 decomposeAgentPrompt 第 2 步即如此）。此窗口与脉冲无关——v8 的 0.5s 边沿 timer 在状态未变时也会面临同样竞态——脉冲只是把重试周期从「永不」改为「60s」，未新增竞态类别。

**脉冲间隔权衡**：60s 是「`/clear` 恢复延迟」与「卡死任务的重 ping 频率」之间的折中。更短（如 15s）恢复更快但卡死任务若误判为 actionable 会更频繁 ping；更长（如 300s）更安静但 `/clear` 后最长等 5 分钟才恢复。60s 与原 heartbeat 周期一致，行为可预期。间隔经 `--pulse-interval` 暴露（复用现有 `--heartbeat-interval` 解析位，重命名），便于按项目调参。

**罕见「Ready 任务等 worktree slot」的轻度重 ping**：当 `Basic: Ready` 任务数超过 `maxParallel`（默认 2），超额任务持续停留 Ready，脉冲会每 60s 重发其 `basic-ready:TASK-N`。此时 worker 实际在忙（已认领满额），重发会唤醒并触发一次 `workerLoop()` → `claimBatch` 返回空 → 重新 Monitor 阻塞，构成约 60s 一次的轻度无效唤醒。影响：温和的周期性「空转」直到某个 slot 释放，而非噪声风暴；且语义正确（确实有待办工作）。可接受，列为已知行为；若未来需消除，可在 worker 侧对「满额时的 basic-ready」做去抖，但不在本任务范围。

---

# Plan: basic-daemon level-triggered 待办脉冲

Goal: replace the unconditional `heartbeat:TIMESTAMP` timer (daemon v8) with a
level-triggered "待办脉冲" (daemon v9) that re-emits real event lines (~60s) for
tasks that remain in an actionable state, so an idle session after `/clear` re-attaches
and stuck `Basic: Ready` tasks self-heal — while staying silent when nothing is actionable.

## Key facts discovered (load-bearing)
- `plugin/scripts/basic-daemon.js` is canonical (no `scripts/` copy). v8 header at L2.
  `parseArgs` L24-42 (`--heartbeat-interval` at L38, default 60 at L30), channels array
  L152-158, edge timer L160-170, `heartbeatTimer` L172-175, `heartbeatMs` derived at L140.
- `scripts/basic-daemon.test.js` does NOT import basic-daemon.js — it keeps **local copies**
  of helpers (`scanIds`, `readTaskMeta`, predicates) and runs with custom `assert()`.
  The new `computePulseLines` test must add a local copy in the same style (no require).
- `scripts/validate-plugin.sh` L269-291 runs every `scripts/*.test.js` via `node "$file"`,
  so `node scripts/basic-daemon.test.js` is already wired into validate-plugin.
- Smoke test `plugin/skills/loop-backlog/smoke/test-monitor-lifecycle.sh` L43-48 asserts the
  Monitor grep filter EXCLUDES heartbeat (stays true) — Phase C must not reintroduce
  `heartbeat` into any `grep --line-buffered` line.
- SKILL.md "heartbeat" mentions to update: Monitor description (3 copies: L123, L788, L1834),
  GCL-drift section (L1847-1848), and L1751 ("on the next child-done or heartbeat event").

## Phase A: 抽出 computePulseLines 纯函数 + 单测（TDD core）

### Tests (write first)
Add a `computePulseLines` test block to `scripts/basic-daemon.test.js` using the existing
`assert()` style and a **local copy** of `computePulseLines(tasksDir, channels)` (mirroring
how the file already locally copies `scanIds`/predicates). The pulse function takes the
channel list with `{prefix, predicate}` (NOT `notified`) and returns a sorted array of
`${prefix}:${id}` lines for all currently-actionable tasks. Cases:
- empty board / dir with only non-actionable tasks (e.g. `Basic: In Progress`, `Basic: Done`
  without parent) → `[]`
- one `Basic: Ready` kind:basic task → `["basic-ready:TASK-N"]`, AND a **second** call on the
  unchanged board returns the SAME array (proves level-trigger — no `notified` dependence)
- that same task rewritten to `Basic: In Progress` → `[]` (leaves actionable set)
- mixed board: one `Basic: Ready` (kind:basic) + one `Epic: Ready` (kind:epic) →
  `["basic-ready:TASK-A","epic-ready:TASK-B"]` (sorted, both channels)

### Implementation
Add a pure exported function to `plugin/scripts/basic-daemon.js`:
```js
function computePulseLines(tasksDir, channels) {
  const lines = [];
  for (const ch of channels) {
    for (const id of [...scanIds(tasksDir, ch.predicate)].sort()) {
      lines.push(`${ch.prefix}:${id}`);
    }
  }
  return lines;
}
```
- Reuses `scanIds` + each channel's `predicate`. Does NOT read or mutate `ch.notified`.
- The local copy added to the test file mirrors this exactly (test stays self-contained,
  consistent with the file's existing no-require convention).

### DoD
- [ ] `node scripts/basic-daemon.test.js`
- [ ] `bash scripts/validate-plugin.sh`

## Phase B: 接线 pulseTimer，删除 heartbeatTimer

### Tests (write first)
Verification commands (red→green via grep on `plugin/scripts/basic-daemon.js`):
- `! grep -q "heartbeat:" plugin/scripts/basic-daemon.js` (no more `heartbeat:TIMESTAMP` output)
- `! grep -q "heartbeatTimer" plugin/scripts/basic-daemon.js`
- `grep -q "pulseTimer" plugin/scripts/basic-daemon.js`
- `grep -q "computePulseLines" plugin/scripts/basic-daemon.js`
- `grep -q -- "--pulse-interval" plugin/scripts/basic-daemon.js`
- `grep -q "daemon-version: v9" plugin/scripts/basic-daemon.js`

### Implementation
In `plugin/scripts/basic-daemon.js`:
- Bump header L2 `// daemon-version: v8` → `// daemon-version: v9`.
- In `parseArgs` (L24-42): rename default key `heartbeatInterval` → `pulseInterval`; parse
  `--pulse-interval` (and keep `--heartbeat-interval` as a back-compat alias writing the same
  field — cheap one-line case). Default stays 60.
- Replace derived `heartbeatMs` (L140) with `pulseMs = Math.round(args.pulseInterval * 1000)`.
- Delete the `heartbeatTimer` block (L172-175). Add in its place:
  ```js
  const pulseTimer = setInterval(() => {
    if (fs.existsSync(args.stopFile)) { clearInterval(pulseTimer); process.exit(0); }
    for (const line of computePulseLines(args.tasksDir, channels)) {
      process.stdout.write(`${line}\n`);
    }
  }, pulseMs);
  ```
- Keep the edge timer (L160-170) and per-channel `notified` Set semantics UNCHANGED —
  sub-second first emission still flows through it; the pulse just adds a 60s level re-emit
  of the same real event lines (downstream idempotent).

### DoD
- [ ] `node scripts/basic-daemon.test.js`
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `! grep -q "heartbeat:" plugin/scripts/basic-daemon.js`
- [ ] `grep -q "daemon-version: v9" plugin/scripts/basic-daemon.js`
- [ ] `grep -q "computePulseLines" plugin/scripts/basic-daemon.js`
- [ ] `grep -q "pulseTimer" plugin/scripts/basic-daemon.js`

## Phase C: SKILL.md 脉冲语义文档更新

### Tests (write first)
grep checks on `plugin/skills/loop-backlog/SKILL.md`. Each is RED on the current
tree and GREEN only after the Phase C edits (verified against current wording):
- `! grep -q "event the worker already calls" plugin/skills/loop-backlog/SKILL.md`
  (the no-op-heartbeat GCL sentence at L1847-1848 must be rewritten away — RED now since it matches once)
- `! grep -q "Heartbeat lines are suppressed by the grep filter" plugin/skills/loop-backlog/SKILL.md`
  (ALL five copies — three live `description=` at L123/788/1834 plus the two commented
  template copies at L1209/1218 — must be reworded; RED now since all five match)
- `grep -q "basic-daemon.js v9" plugin/skills/loop-backlog/SKILL.md`
  (daemon version reference bumped at L118 — RED now, only v8 present)
- `! grep -qP "grep.*--line-buffered.*heartbeat" plugin/skills/loop-backlog/SKILL.md`
  (smoke-test invariant — filter must still NOT contain heartbeat; already GREEN, regression guard)

### Implementation
Edit `plugin/skills/loop-backlog/SKILL.md`:
- ALL FIVE occurrences of "Heartbeat lines are suppressed by the grep filter" — the three
  live Monitor `description=` strings (L123, L788, L1834) AND the two commented template
  copies (L1209 `description=` comment, L1218 standalone comment): replace with language
  stating that event lines may re-emit roughly every 60s while a task stays actionable, and
  that this re-emit is the normal re-attach signal for an idle session (e.g. after `/clear`);
  non-event lines are filtered out. Keep the grep filter pattern itself unchanged (five real
  prefixes only). After this, `! grep -q "Heartbeat lines are suppressed by the grep filter"`
  passes (no copy of the old phrase remains).
- Update daemon version reference L118 (`basic-daemon.js v8` → `v9`).
- L1751: change "on the next `child-done` or `heartbeat` event" → "on the next `child-done`
  event or the next pulse re-emit".
- GCL Drift section L1847-1848: rewrite "On each `heartbeat:*` event the worker already calls
  `workerLoop()` as a no-op" → reference the ~60s pulse re-emit of an actionable event (or a
  re-entered `workerLoop()`) as the periodic hook for the daily GCL health check.
- Do NOT change the dispatch branch logic (L125-131) or any predicate/actionable semantics.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash plugin/skills/loop-backlog/smoke/test-monitor-lifecycle.sh`
- [ ] `! grep -q "event the worker already calls" plugin/skills/loop-backlog/SKILL.md`
- [ ] `! grep -q "Heartbeat lines are suppressed by the grep filter" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "basic-daemon.js v9" plugin/skills/loop-backlog/SKILL.md`

## Constraints (non-executable)
- Do NOT touch flock single-instance, `stopStaleMon`, `TaskStop`, `.monitor-task-id`,
  PID/stop-file lifecycle, worktree parallel execution, or `cap:*` idempotency guards.
- Keep the 0.5s edge timer (L160-170) and per-channel `notified` Sets intact and unchanged.
- All event handlers must remain idempotent (they already are: `cap:claim`, `cap:decompose`,
  `cap:evaluate`, marker-file gates) — the pulse relies on this, do not weaken it.
- Pulse interval default = 60s. Each phase ≤ 200 lines change.
- Pulse must emit ONLY real event lines (the five prefixes); never reintroduce a `heartbeat:`
  line or add a sixth channel.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `node scripts/basic-daemon.test.js`
- [ ] `bash plugin/skills/loop-backlog/smoke/test-monitor-lifecycle.sh`
- [ ] `grep -q "daemon-version: v9" plugin/scripts/basic-daemon.js`
- [ ] `grep -q "computePulseLines" plugin/scripts/basic-daemon.js`
- [ ] `! grep -q "heartbeat:" plugin/scripts/basic-daemon.js`

---

## Plan 细化（TASK-197 refinement）：三机制覆盖回归断言

### 背景

worker 在“认领任务后继续处理后续任务”靠三个互补机制：
1. **re-claim 全量扫描**（处理期间新变 Ready 的任务）——位于 SKILL.md 的 claimBatch，不在 daemon。
2. **边沿触发**（空闲时新任务进 Ready → 0.5s 内首发）——daemon edge timer + notified Set。
3. **脉冲**（卡死 Ready 任务每 60s 重发）——本任务新增。

本次 daemon 改动只能直接断言机制 2 和 3（它们在 daemon 内）；机制 1 在 worker 侧，不在 basic-daemon.test.js 单测范围。关键回归风险：脉冲（level-trigger）不能污染 edge timer 赖以去重的 notified 语义——否则 claim→process→re-claim 主循环的去重会被破坏。

### Phase A 追加断言（写在 scripts/basic-daemon.test.js）

在现有 assert() 风格下新增两条“两层解耦”断言，测试描述字符串须可被 grep 定位：
- `assert('edge-dedup preserved: notified suppresses re-emit', ...)` —— 模拟 edge timer 逻辑：同一 ID 已在 notified Set 时，边沿发射不重发（证明脉冲未污染 notified 去重）。
- `assert('pulse independent of notified: re-emits regardless', ...)` —— computePulseLines 对一个已在 notified 的 Ready 任务仍返回其事件行（证明脉冲的 level-trigger 与 edge 的 once-only 互不干扰）。

两条合起来锁住：脉冲层与边沿层解耦——edge timer 保留 once-only 去重（主循环 re-claim 不被脉冲事件洪泛），脉冲只叠加 level-trigger 重发。

### Constraints 追加

- **三机制覆盖不变**：claim→process→re-claim 主循环（机制 1，claimBatch 全量扫描）与边沿触发首发（机制 2，edge timer + notified）是现有行为，本任务不得修改。脉冲（机制 3）仅叠加于空闲相位的唤醒信号，不得改变 edge timer 的 once-only 去重语义（notified Set 不被 computePulseLines 读或写）。上述解耦由 Phase A 两条断言回归锁住。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Proposal self-review: APPROVED
premise-ledger:
[E] Motivation grounded in code: premise = read basic-daemon.js fully; cited notified Set (L152-169), heartbeat (L172-175), edge timer (L160-170), channels array, cap:* guards verbatim from SKILL.md.
[E] Feasibility verified against structure: premise = proposed pulseTimer mirrors existing setInterval; computePulseLines extraction matches basic-daemon.test.js pure-function/assert() style; --pulse-interval reuses existing --heartbeat-interval parse slot.
[C] Internal consistency: premise = edge timer PRESERVED + pulse ADDED ⇒ idle board still 0 lines (edge emits nothing without new notified entry; pulse emits nothing without actionable task); 'delete heartbeatTimer' does not contradict 'keep timer'.
[C] Goals↔Approach alignment: premise = each of 5 goals maps to a concrete approach element and a verifiable assertion (line-count / emit-count / state-transition).
[H] Honest about gaps: premise = explicitly flagged residual decompose-window race (agent spawned, cap not yet landed), worktree-slot empty-wake at ~60s, and that pulse changes retry period 'never'→'60s' WITHOUT adding a new race class (not claimed race-free).
[H] Scope discipline: premise = 'exactly one Monitor' guarantee declared out-of-scope (flock/stopStaleMon/TaskStop/.monitor-task-id untouched); no test actually executed ⇒ evidence_independence=low acknowledged.
Reliability sample: md5(TASK-197)%10 != 0 ⇒ single pass (no r2).
GCL-self-report: E=4 C=5 H=4

Proposal approved. Starting plan draft.

Plan review iteration 1: APPROVED
premise-ledger:
[E] Goal coverage: all 5 proposal Goals map to Phase A tests (idle-silence/self-heal/in-progress-silence), Phase B pulseTimer 60s (/clear recovery), Constraints+smoke (single-Monitor zero-regression).
[E] TDD structure: every phase has ### Tests before ### Implementation; Phase A/B first DoD = node basic-daemon.test.js, Phase C first DoD = validate-plugin.
[E] Acceptance gate first item = bash scripts/validate-plugin.sh.
[C] DoD executability: all DoD/acceptance items are shell commands; natural-language scope moved to Constraints.
[E] Absence checks use ! grep -q (no grep -qv).
[C] Phase C grep gates hardened: original 'no-op/re-emit/pulse' checks were VACUOUS (passed pre-edit due to L225/L1741 're-emit', L1847 wording mismatch). Replaced with binding RED-now checks: ! grep -q 'event the worker already calls' (1 match, L1848), ! grep -q 'Heartbeat lines are suppressed by the grep filter' (5 matches incl 2 comment copies — impl scope extended to all five), grep -q 'basic-daemon.js v9' (absent now). All verified RED on current tree.
[E] Phase ordering A(pure fn+test)->B(wire timer)->C(docs); no circular deps; flock/stopStaleMon/TaskStop/.monitor-task-id NOT touched.
[E] File paths verified exist; node scripts/basic-daemon.test.js -> 26 passed; bash scripts/validate-plugin.sh -> exit 0 (Errors 0).
[E] Source facts verified: v8 header L2, parseArgs L24-42, heartbeatInterval default 60 L30, channels L152-158, edge timer L160-170, heartbeatTimer L172-175, heartbeatMs L140; test file uses no-require local-copy convention; validate runs *.test.js.
GCL-self-report: E=7 C=3 H=2

claimed: 2026-06-25T07:21:21Z

Phase A ✓ 2026-06-25T07:30:03Z: computePulseLines pure function added to basic-daemon.js; 7 unit tests added to basic-daemon.test.js including level-trigger and edge-dedup decoupling assertions — all 33 tests pass

Phase B ✓ 2026-06-25T07:30:08Z: heartbeatTimer replaced with pulseTimer in basic-daemon.js v9; --heartbeat-interval back-compat alias kept; daemon emits only real event lines on pulse interval

Phase C ✓ 2026-06-25T07:30:13Z: SKILL.md updated — 5 description occurrences replaced, v8→v9, L1751 child-done/heartbeat→pulse re-emit, GCL Drift section updated; smoke test 8/8 PASS; validate-plugin.sh ALL CHECKS PASSED

## Execution Summary
Result: Done
Commit: 2a451a1

Completed: 2026-06-25T07:36:47Z
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 node scripts/basic-daemon.test.js
- [ ] #2 bash scripts/validate-plugin.sh
- [ ] #3 ! grep -q "heartbeat:" plugin/scripts/basic-daemon.js
- [ ] #4 grep -q "daemon-version: v9" plugin/scripts/basic-daemon.js
- [ ] #5 grep -q "computePulseLines" plugin/scripts/basic-daemon.js
- [ ] #6 grep -q "pulseTimer" plugin/scripts/basic-daemon.js
- [ ] #7 bash plugin/skills/loop-backlog/smoke/test-monitor-lifecycle.sh
- [ ] #8 ! grep -q "event the worker already calls" plugin/skills/loop-backlog/SKILL.md
- [ ] #9 ! grep -q "Heartbeat lines are suppressed by the grep filter" plugin/skills/loop-backlog/SKILL.md
- [ ] #10 grep -q "basic-daemon.js v9" plugin/skills/loop-backlog/SKILL.md
- [ ] #11 grep -q "edge-dedup preserved" scripts/basic-daemon.test.js
- [ ] #12 grep -q "pulse independent of notified" scripts/basic-daemon.test.js
<!-- DOD:END -->
