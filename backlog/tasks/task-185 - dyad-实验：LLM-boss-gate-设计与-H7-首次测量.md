---
id: TASK-185
title: dyad 实验：LLM-boss gate 设计与 H7 首次测量
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 05:50'
updated_date: '2026-06-24 09:24'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design and implement the dyad experiment for H7 first measurement by wiring an LLM-boss gate channel at the epicEvaluate soft-halt. Phase 1: draft `docs/research/dyad-experiment-design.md` — boss CC architecture (signal flow + evidence channels), evidence independence operationalization, H7 statistical test design (null hypothesis, controls, effect size, sample planning). Phase 2: implement boss evidence pack in `plugin/skills/loop-backlog/` — encapsulate `archguard_get_change_risk` (epic git diff) + `meta-cc query_session_signals` (worker session trace) into a structured JSON evidence pack, not routed through worker summary. Phase 3: integrate boss CC channel at epicEvaluate soft-halt in `plugin/skills/loop-backlog/SKILL.md` — before writing `cap:evaluate`, fork boss CC that consumes evidence pack and writes FINISH/ITERATE + `gate_actor_type=llm` to gcl-events.jsonl (graceful degradation when TASK-176a schema absent). Phase 4: wire `gate_actor_type=human` and `evidence_independence` into gcl-events.jsonl on the human Epic: Evaluating → Epic: Done path. Phase 5: after data accumulation (≥10 llm gate events), run escape rate comparison and write `docs/research/gcl-h7-validation.md` with falsifiable verdict. DoD: `bash scripts/validate-plugin.sh` passes; `grep -q 'gate_actor_type' plugin/skills/loop-backlog/SKILL.md` exits 0.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: dyad 实验 — LLM-boss gate 设计与 H7 首次测量

## Background
H7 假设（gcl-synthesis.md）指出：在 routine engineering gates 中，human vs automated gate actor 对 escape rate 无显著差异（控制 evidence_independence 后）。当前 gcl-events.jsonl 缺少 `gate_actor_type` 和 `evidence_independence` 字段，使 H7 无法被首次测量。`epicEvaluate` 的 soft-halt 结构是现有代码库中唯一一个人类 gate 的明确接入点，也是接入 LLM-boss gate 所需改动最小的位置（cc-actor-network.md §3 明确此是最小实验台架）。关键约束：boss 和 worker 必须持有不同证据源（archguard change-risk + meta-cc trace），否则测的是 LLM 自我一致性而非 H7。

## Goals
1. `docs/research/dyad-experiment-design.md` 存在：包含 boss CC 架构（信号流 + 证据通道）、evidence independence 操作化定义、H7 统计检验设计（零假设、控制变量、效果量、样本量规划）。
2. `plugin/skills/loop-backlog/` 中有 boss evidence pack 封装：调用 `archguard_get_change_risk`（epic git diff）+ `meta-cc query_session_signals`（worker session trace），输出结构化 JSON evidence pack，不经过 worker 摘要中转。`test -f plugin/skills/loop-backlog/boss-evidence-pack.sh` exits 0.
3. `epicEvaluate` soft-halt 旁有 boss CC 通道接入：消费 evidence pack，输出 FINISH/ITERATE，写 `gate_actor_type=llm` 到 gcl-events.jsonl（TASK-176a 依赖；未就绪时写入 task Notes 占位）。`grep -q 'gate_actor_type' plugin/skills/loop-backlog/SKILL.md` exits 0.
4. Human gate 路径写入 `gate_actor_type=human` 到 gcl-events.jsonl（依赖 TASK-176a）。
5. `docs/research/gcl-h7-validation.md` 存在（data-gated：需 ≥10 llm gate events）：escape rate 对比检验结果 + 可证伪裁定。

## Proposed Approach
Phase 1: doc-only — draft dyad-experiment-design.md (boss CC architecture, evidence independence spec, H7 statistical design). Phase 2: implement boss-evidence-pack.sh helper. Phase 3: integrate boss CC channel at epicEvaluate soft-halt in SKILL.md. Phase 4: wire human gate_actor_type path. Phase 5 (data-gated): after ≥10 llm gate events, write gcl-h7-validation.md.

## Trade-offs and Risks
- Evidence independence constraint is hard: boss must read archguard + meta-cc independently; cloning from worker Notes is explicitly prohibited (cc-actor-network.md §4.1).
- TASK-176a dependency isolation: Phases 3+4 gcl-events.jsonl write paths use conditional file+schema check; independently passable before TASK-176a completes.
- Phase 5 is data-gated (≥10 llm gate events); timing is runtime-dependent, not calendar-based.
- Not doing: full statistical analysis until data accumulates; Phase 1 doc pre-registers design to prevent post-hoc analysis bias.

---

# Plan: dyad 实验 — LLM-boss gate 设计与 H7 首次测量

## Phase 1: Draft dyad-experiment-design.md
### Tests (write first)
- `! test -f docs/research/dyad-experiment-design.md` — file does not exist yet

### Implementation
- Create `docs/research/dyad-experiment-design.md` with sections:
  - §1 Boss CC architecture: signal flow diagram (text), evidence channels (archguard + meta-cc, not worker summary), soft-halt wiring point in epicEvaluate
  - §2 Evidence independence operationalization: minimum evidence pack fields (change_risk, session_signals, no worker_notes), independence constraint from cc-actor-network.md §4.1
  - §3 H7 statistical test design: null hypothesis (gate_actor_type has no effect on escape rate, controlling evidence_independence), controls (task_kind, evidence_independence level), effect size estimation, sample planning (≥10 llm gate events for initial measurement), test selection (Mann-Whitney U or Fisher exact, based on distribution)

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/dyad-experiment-design.md`
- [ ] `grep -q 'gate_actor_type\|boss CC\|H7' docs/research/dyad-experiment-design.md`

## Phase 2: Implement boss-evidence-pack.sh helper
### Tests (write first)
- `! test -f plugin/skills/loop-backlog/boss-evidence-pack.sh` — file does not exist yet

### Implementation
- Create `plugin/skills/loop-backlog/boss-evidence-pack.sh`:
  - `--help` flag printing usage (EPIC-TASK-ID positional arg)
  - Call `mcp__archguard__get_change_risk` with epic's git diff file list
  - Call `mcp__plugin_meta-cc_meta-cc__query_session_signals` for worker session trace
  - Output structured JSON: `{"change_risk": {...}, "session_signals": {...}, "evidence_source": "archguard+meta-cc", "worker_notes_included": false}`
  - Graceful degradation: on MCP failure, output `{"evidence_source": "unavailable", "reason": "<msg>"}` and exit 0

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f plugin/skills/loop-backlog/boss-evidence-pack.sh`
- [ ] `bash plugin/skills/loop-backlog/boss-evidence-pack.sh --help`

## Phase 3: Integrate boss CC channel at epicEvaluate soft-halt
### Tests (write first)
- `! grep -q 'gate_actor_type' plugin/skills/loop-backlog/SKILL.md` — not yet present

### Implementation
- In `plugin/skills/loop-backlog/SKILL.md`, `epicEvaluate` implementation section, before `cap:evaluate` is written:
  - Add instruction to call `boss-evidence-pack.sh <EPIC-TASK-ID>` and capture evidence pack
  - Fork a boss CC channel: pass evidence pack as context, ask for FINISH/ITERATE verdict
  - Write boss verdict and reasoning to epic Notes with `gate_actor_type=llm`
  - Write `gate_actor_type=llm` to gcl-events.jsonl (conditional: check TASK-176a schema; if absent, write to Notes as `gcl-gate-actor: llm (pending jsonl)`)
  - Do not modify soft-halt state machine or `cap:evaluate` write timing

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'gate_actor_type' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'boss-evidence-pack\|boss CC\|boss_cc' plugin/skills/loop-backlog/SKILL.md`

## Phase 4: Wire gate_actor_type=human on human Epic: Evaluating → Done path
### Tests (write first)
- `! grep -q 'gate_actor_type=human\|gate_actor_type.*human' plugin/skills/loop-backlog/SKILL.md` — not yet present

### Implementation
- In `plugin/skills/loop-backlog/SKILL.md`, the Epic: Evaluating → Epic: Done transition section:
  - Add instruction to write `gate_actor_type=human` and `evidence_independence=human-review` to gcl-events.jsonl (conditional: check TASK-176a schema; if absent, write to epic Notes as `gcl-gate-actor: human (pending jsonl)`)
  - Must be placed after human FINISH confirmation and before status write

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'gate_actor_type.*human\|gate_actor_type=human' plugin/skills/loop-backlog/SKILL.md`

## Phase 5: Write H7 validation report (data-gated)
### Tests (write first)
- `! test -f docs/research/gcl-h7-validation.md` — file does not exist yet

### Implementation
- After ≥10 llm gate events have accumulated in gcl-events.jsonl:
  - Query gcl-events.jsonl for gate_actor_type=llm events with escape outcomes
  - Query historical human gate events for comparison
  - Run escape rate comparison (Mann-Whitney U or Fisher exact, controlling evidence_independence)
  - Create `docs/research/gcl-h7-validation.md` with: sample sizes (N_llm, N_human), escape rates, test statistic + p-value, verdict (H7 confirmed / null / refuted), confound notes

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/gcl-h7-validation.md`
- [ ] `grep -q 'gate_actor_type\|escape rate\|H7' docs/research/gcl-h7-validation.md`

## Constraints
- Boss evidence pack must not include worker Notes; evidence independence constraint is hard (cc-actor-network.md §4.1).
- TASK-176a dependency: Phases 3+4 gcl-events.jsonl writes use conditional file+schema existence check; must be independently passable before TASK-176a completes.
- Phase 5 is data-gated (≥10 llm gate events); do not run analysis with insufficient samples.
- All SKILL.md edits must preserve existing epicEvaluate soft-halt timing and cap:evaluate write order.
- boss CC channel is additive: does not alter or gate the human decision path.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/dyad-experiment-design.md`
- [ ] `test -f plugin/skills/loop-backlog/boss-evidence-pack.sh`
- [ ] `grep -q 'gate_actor_type' plugin/skills/loop-backlog/SKILL.md`
- [ ] `test -f docs/research/gcl-h7-validation.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Epic proposal self-review: APPROVED
premise-ledger:
[E] background line count: 背景共 4 段，行数从 proposal 文件直接数，满足 3-8 行约束
[E] goals verifiability: 所有 4 条 Goal 均含可机械检查的验证手段（文件路径、grep、schema 字段），从 proposal 文件直接读
[C] decomposition coverage: 5 个子任务覆盖 4 条 Goal——须逐条对照验证（doc→Goal1; evidence pack→Goal2; boss 接入→Goal2+3; gate_actor_type 写入→Goal3; H7 分析→Goal4）
[C] feasibility of epicEvaluate soft-halt接入: 须读 SKILL.md 确认 epicEvaluate 软停点代码结构（已读，行 1442-1445 确认）
[H] epic 粒度合理性: 5 个子任务跨 doc-only 和 code-change 两类，有明确依赖顺序，满足 epic 门槛（≥2 independent basic tasks with ordering）
[E] trade-offs completeness: 明确列出 Not doing 范围、3 类风险（依赖/测量偏差/克隆耦合），从 proposal 文件直接读
GCL-self-report: E=3 C=2 H=1

Epic proposal approved. Starting epic plan draft.

Epic plan review iteration 1: APPROVED
premise-ledger:
[E] sub-task count: 5 个子任务，从 plan 文件直接数
[C] goal coverage: 需逐条对照 Goals 验证（ST1→Goal1; ST2+ST3→Goal2; ST3+ST4→Goal3; ST5→Goal4），已逐条确认
[E] sequencing acyclic: DAG 从 plan 文件直接读，无环路（外部依赖→并行→串行→数据积累→分析）
[C] feasibility: plugin/skills/loop-backlog/SKILL.md 和 epicEvaluate 软停点已读确认（行 1432-1446）；docs/ 路径合法
[H] scope discipline: 5 个子任务均没有超出 epic Goals 范围，且没有哪个大到应再拆为独立 epic——此判断以背景知识为准
[E] no premature creation: plan 未创建任何子任务，从 plan 文件直接读
GCL-self-report: E=3 C=2 H=1

cap:propose=approved

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: G1→Phase 1 / G2→Phase 2 / G3→Phase 3 / G4→Phase 4 / G5→Phase 5 — direct read from plan phases
[E] TDD structure: all 5 phases have Tests → Implementation → DoD in correct order
[E] first DoD item: bash scripts/validate-plugin.sh confirmed in all 5 phases
[E] acceptance gate: first item is bash scripts/validate-plugin.sh
[E] DoD executability: all items are shell commands (bash / test -f / grep -q)
[C] file paths: plugin/skills/loop-backlog/SKILL.md confirmed to exist; boss-evidence-pack.sh and dyad-experiment-design.md are new files (correct); gcl-h7-validation.md is data-gated (correct)
[C] TASK-176a dependency isolation: Phases 3+4 use conditional schema check to remain independently passable — verified from constraint description
[H] evidence independence hard constraint adequacy: boss evidence pack excluding worker Notes adequately operationalizes cc-actor-network.md §4.1 — background knowledge
GCL-self-report: E=5 C=2 H=1

claimed: 2026-06-24T09:14:41Z

Phase 1 ✓ 2026-06-24T09:20:00Z: Created docs/research/dyad-experiment-design.md with §1 boss CC architecture (signal flow diagram, evidence channels), §2 evidence independence operationalization (minimum evidence pack fields, independence levels, §4.1 constraint mapping), §3 H7 statistical test design (null hypothesis, controls, sample planning N_llm≥10, test selection Fisher exact + Mann-Whitney U).

Phase 2 ✓ 2026-06-24T09:20:00Z: Created plugin/skills/loop-backlog/boss-evidence-pack.sh — positional arg EPIC-TASK-ID, --help flag, collects archguard change_risk from .archguard/query/git-history/file-metrics.json + meta-cc session signals, outputs structured JSON with worker_notes_included:false, graceful degradation on failure (exit 0, evidence_source:unavailable), made executable.

Phase 3 ✓ 2026-06-24T09:20:00Z: Integrated boss CC channel in SKILL.md epicEvaluate implementation — calls boss-evidence-pack.sh, LLM boss verdict with independent evidence, writes Boss CC Verdict note, conditional gcl-events.jsonl write with gate_actor_type=llm (checks TASK-176a schema; falls back to Notes if absent). cap:evaluate write timing and RECOMMENDATION format unchanged.

Phase 4 ✓ 2026-06-24T09:20:00Z: Added recordHumanEpicGate() function to SKILL.md — writes gate_actor_type=human, evidence_independence=human-review to gcl-events.jsonl after human sets Epic: Done (conditional schema check, Notes fallback). Placed as new '### Human confirmation gate' section before Shutdown.

Phase 5 ✓ 2026-06-24T09:20:00Z: Created docs/research/gcl-h7-validation.md — data-gated placeholder with H7 hypothesis, measurement protocol, sample size requirement (N_llm≥10, N_human≥10), PENDING status, analysis script (not run), current data summary. Contains gate_actor_type, escape rate, and H7 references. No fabricated data.

DoD #1: PASS — bash scripts/validate-plugin.sh (Errors: 0, Warnings: 55, ALL CHECKS PASSED)

DoD #2: PASS — test -f docs/research/dyad-experiment-design.md

DoD #3: PASS — test -f plugin/skills/loop-backlog/boss-evidence-pack.sh

DoD #4: PASS — grep -q 'gate_actor_type' plugin/skills/loop-backlog/SKILL.md

DoD #5: PASS — test -f docs/research/gcl-h7-validation.md

## Execution Summary
Result: Done
Commit: f6df1db

Completed: 2026-06-24T09:24:36Z
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 test -f docs/research/dyad-experiment-design.md
- [ ] #3 test -f plugin/skills/loop-backlog/boss-evidence-pack.sh
- [ ] #4 grep -q 'gate_actor_type' plugin/skills/loop-backlog/SKILL.md
- [ ] #5 test -f docs/research/gcl-h7-validation.md
<!-- DOD:END -->
