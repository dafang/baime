---
id: TASK-182
title: gate evidence pack：meta-cc session digest 注入 loop-backlog gate 决策点
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 05:48'
updated_date: '2026-06-24 08:03'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Inject meta-cc session digest into loop-backlog gate decision points to provide process-grounded independent evidence. Phase 1: create `plugin/skills/loop-backlog/meta-cc-digest.sh` — given a TASK-ID, locate the task's execution session, run `query_file_activity` / `analyze_errors` / `query_edit_sequences`, return structured digest. Phase 2: integrate digest into `verifyDod` gate in SKILL.md — after all DoD items pass, append digest (actual vs. declared file scope diff, retry count) to task Notes with `data_source: meta-cc-session`. Phase 3: integrate digest into `epicEvaluate` gate in SKILL.md — before FINISH/ITERATE recommendation, aggregate per-subtask process evidence into epic Notes with `evidence_independence: meta-cc-grounded`. Phase 4: wire `evidence_independence` field into `gcl-events.jsonl` with graceful degradation when TASK-176a schema not yet present. DoD: `bash scripts/validate-plugin.sh` passes; `grep -q 'meta-cc-digest' plugin/skills/loop-backlog/SKILL.md` exits 0.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: gate evidence pack — meta-cc session digest 注入 loop-backlog gate 决策点

## Background
loop-backlog 的两个核心 gate 决策点（`verifyDod` 和 `epicEvaluate`）当前依赖的证据来源存在系统性的证据独立性缺口：agent 执行后自行写入的 Execution Summary 和 premise-ledger 均属于自观测-叙述通道，与被监督对象共享同一信源，H6 意义下 evidence independence 为零。meta-cc 已有 MCP 工具能提供原始 tool-call 序列、实际修改文件轨迹、重试/错误计数、编辑震荡检测——这是与 agent 叙述层失败模式完全解耦的记录-结构通道，当前 gate 判断未消费这一已就绪的独立证据源。

## Goals
1. `plugin/skills/loop-backlog/meta-cc-digest.sh` 存在并可执行：给定 TASK-ID，定位该任务执行期间的 meta-cc session，执行 query_file_activity / analyze_errors / query_edit_sequences，返回结构化 digest 字符串。`bash plugin/skills/loop-backlog/meta-cc-digest.sh --help` exits 0.
2. `verifyDod` gate 在全部 DoD 通过后调用 helper，将 digest（实际修改文件 vs 声明范围 diff、retry count）以 `data_source: meta-cc-session` 格式 append-notes 到 task。`grep -q 'meta-cc-digest' plugin/skills/loop-backlog/SKILL.md` exits 0.
3. `epicEvaluate` gate 在 FINISH/ITERATE 推荐前遍历子任务调用 helper，将聚合进程证据包（retry 计数、震荡文件、file scope diff）附加到 epic Notes，含 `evidence_independence: meta-cc-grounded` 标记。
4. helper 调用后将 `evidence_independence: meta-cc-grounded` 写入 gcl-events.jsonl（若 TASK-176a schema 未就绪则写入 task Notes 占位标记，接线逻辑先行实现）。`bash scripts/validate-plugin.sh` passes throughout.

## Proposed Approach
Phase 1: implement `meta-cc-digest.sh` helper with `--help` flag and TASK-ID positional argument; runs the three meta-cc MCP queries and outputs structured digest. Phase 2: modify `verifyDod` section in SKILL.md to call helper post-DoD and append-notes. Phase 3: modify `epicEvaluate` section in SKILL.md to aggregate per-subtask digests. Phase 4: extend helper / SKILL.md to write `evidence_independence` field to gcl-events.jsonl with conditional check for TASK-176a schema presence.

## Trade-offs and Risks
- Not changing gate state machine: verifyDod/epicEvaluate status transitions, cap:* markers, signal file timing are all unmodified; meta-cc calls are purely additive evidence annotations.
- Graceful degradation: if meta-cc call returns empty or fails, write `meta-cc-digest: unavailable (reason: <msg>)` and continue; gate is never blocked by meta-cc unavailability.
- Sampling cap: epicEvaluate helper calls capped at 10 subtasks; beyond that, mark `digest_truncated: true` and process only the most recent 10.
- TASK-176a dependency isolation: Phase 4 gcl-events.jsonl write must use conditional file-existence + schema-field check to remain independently passable before TASK-176a completes.

---

# Plan: gate evidence pack — meta-cc session digest 注入 loop-backlog gate 决策点

## Phase 1: Implement meta-cc-digest.sh helper
### Tests (write first)
- `! test -f plugin/skills/loop-backlog/meta-cc-digest.sh` — file does not exist yet (must fail before implementation)
- After implementation: `bash plugin/skills/loop-backlog/meta-cc-digest.sh --help` exits 0

### Implementation
- Create `plugin/skills/loop-backlog/meta-cc-digest.sh` with:
  - `--help` flag printing usage (TASK-ID positional arg, optional --session-dir override)
  - Logic to locate meta-cc session directory for a given TASK-ID via session timestamp heuristic
  - Calls to `mcp__plugin_meta-cc_meta-cc__query_file_activity`, `analyze_errors`, `query_edit_sequences`
  - Structured digest output format documented in header comment: `FILE_ACTIVITY:`, `ERROR_COUNT:`, `EDIT_OSCILLATION:` sections
  - Graceful degradation: on empty/error result, print `meta-cc-digest: unavailable (reason: <msg>)` and exit 0

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash plugin/skills/loop-backlog/meta-cc-digest.sh --help`
- [ ] `test -f plugin/skills/loop-backlog/meta-cc-digest.sh`

## Phase 2: Integrate digest into verifyDod gate
### Tests (write first)
- `! grep -q 'meta-cc-digest' plugin/skills/loop-backlog/SKILL.md` — not yet present

### Implementation
- In `plugin/skills/loop-backlog/SKILL.md`, in the `verifyDod` implementation section, after all DoD items pass:
  - Add instruction to call `meta-cc-digest.sh <TASK-ID>` and capture digest
  - Append digest to task Notes with header `## Gate Evidence Pack` and field `data_source: meta-cc-session`
  - Include actual-vs-declared file scope diff (declared = task Implementation Plan file references; actual = FILE_ACTIVITY lines from digest)

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'meta-cc-digest' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'data_source: meta-cc-session' plugin/skills/loop-backlog/SKILL.md`

## Phase 3: Integrate digest into epicEvaluate gate
### Tests (write first)
- `! grep -q 'evidence_independence: meta-cc-grounded' plugin/skills/loop-backlog/SKILL.md` — not yet present

### Implementation
- In `plugin/skills/loop-backlog/SKILL.md`, in the `epicEvaluate` implementation section, before FINISH/ITERATE recommendation:
  - Add instruction to iterate over all child tasks (cap at 10; set `digest_truncated: true` if more)
  - For each child task, call `meta-cc-digest.sh <CHILD-TASK-ID>` and collect digest
  - Append aggregated process evidence pack to epic task Notes with `evidence_independence: meta-cc-grounded`
  - Include per-subtask retry count summary and oscillation flags

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'evidence_independence: meta-cc-grounded' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'epicEvaluate' plugin/skills/loop-backlog/SKILL.md`

## Phase 4: Wire evidence_independence into gcl-events.jsonl
### Tests (write first)
- `! grep -q 'evidence_independence' plugin/skills/loop-backlog/meta-cc-digest.sh` — field wiring not yet present

### Implementation
- In `meta-cc-digest.sh`, after generating the digest, add conditional logic:
  - If `gcl-events.jsonl` exists AND contains `evidence_independence` field in schema: append `evidence_independence: meta-cc-grounded` to the most recent gate event for the given TASK-ID
  - Else: set output line `gcl-evidence-independence: meta-cc-grounded (pending jsonl)` for caller to write to task Notes
- In SKILL.md gate steps, consume the `gcl-evidence-independence` output line and append-notes when jsonl path is not yet active

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'evidence_independence' plugin/skills/loop-backlog/meta-cc-digest.sh`
- [ ] `grep -q 'gcl-evidence-independence\|evidence_independence' plugin/skills/loop-backlog/SKILL.md`

## Constraints
- Do not change gate state machine: verifyDod/epicEvaluate status transitions, cap:* markers, and signal file write order remain unmodified.
- Graceful degradation must not block gate: meta-cc unavailability writes `meta-cc-digest: unavailable` and exits 0.
- epicEvaluate helper calls capped at 10 subtasks; `digest_truncated: true` if exceeded.
- Phase 4 TASK-176a dependency isolation: gcl-events.jsonl write conditional on file + schema field existence check.
- All SKILL.md modifications must preserve existing contracts verified by validate-plugin.sh.
- Digest output format is the interface contract between Phase 1 and Phases 2–4; document in meta-cc-digest.sh header.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash plugin/skills/loop-backlog/meta-cc-digest.sh --help`
- [ ] `grep -q 'meta-cc-digest' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'evidence_independence: meta-cc-grounded' plugin/skills/loop-backlog/SKILL.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Epic proposal self-review: APPROVED
premise-ledger:
[E] background lines: 8 lines in Background section — factual statements about current gate evidence sources and the 2x2 observation matrix position; directly verifiable from SKILL.md and grounding-infrastructure.md
[E] goals verifiable: G1–G4 each specify concrete, shell-checkable outputs (Notes content, field names, file path of helper)
[C] goal coverage vs sketch: sub-tasks 1–4 map 1:1 to G4/G1/G2/G3 respectively — coverage complete
[C] trade-offs identified: scope limit (per-task session only), sampling cap (≤10 subtasks), graceful degradation (unavailable path), TASK-176a dependency isolation — all four are non-trivial design decisions
[H] epic granularity: 4 kind:basic children is appropriate; each child is independently deliverable; no child spans more than one integration point — granularity judged sound
GCL-self-report: E=2 C=2 H=1

Epic proposal approved. Starting epic plan draft.

cap:propose=approved

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: G1→Phase 1 (helper file) / G2→Phase 2 (verifyDod) / G3→Phase 3 (epicEvaluate) / G4→Phase 4 (jsonl wiring) — direct read from plan
[E] TDD structure: all 4 phases have Tests → Implementation → DoD in correct order
[E] first DoD item: bash scripts/validate-plugin.sh confirmed in all 4 phases
[E] acceptance gate: first item is bash scripts/validate-plugin.sh
[E] DoD executability: all items are shell commands (bash / grep -q / test -f)
[C] phase ordering: Phase 1 (helper) must precede Phases 2–4 which depend on meta-cc-digest.sh — verified by reading description dependency statement
[C] file paths: plugin/skills/loop-backlog/SKILL.md verified to exist; meta-cc-digest.sh is new file (correct)
[H] DoD sufficiency: grep -q checks in Phases 2–4 adequately proxy for SKILL.md integration correctness — background knowledge about doc/SKILL.md integration testing norms
GCL-self-report: E=5 C=2 H=1
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 bash plugin/skills/loop-backlog/meta-cc-digest.sh --help
- [ ] #3 grep -q 'meta-cc-digest' plugin/skills/loop-backlog/SKILL.md
- [ ] #4 grep -q 'evidence_independence: meta-cc-grounded' plugin/skills/loop-backlog/SKILL.md
<!-- DOD:END -->
