---
id: TASK-182
title: gate evidence pack：meta-cc session digest 注入 loop-backlog gate 决策点
status: 'Epic: Backlog'
assignee: []
created_date: '2026-06-24 05:48'
updated_date: '2026-06-24 05:50'
labels:
  - 'kind:epic'
dependencies: []
ordinal: 120000
---

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: gate evidence pack — meta-cc session digest 注入 loop-backlog gate 决策点

## Background

loop-backlog 的两个核心 gate 决策点（`verifyDod` 和 `epicEvaluate`）当前依赖的证据来源存在系统性的证据独立性缺口：

1. **agent 自我总结**：worker agent 执行任务后自行写入的 `## Execution Summary` 和 DoD 记录，属于 2×2 观测矩阵左上格（自观测 × 叙述通道），与被监督对象共享同一信源，H6 意义下 evidence independence 为零。
2. **premise-ledger 自报**：reviewLoop 写入 task Notes 的 `GCL-self-report`，属于左下格（自观测 × 结构通道），通过 E/C/H 分类有部分解耦，但仍是叙述层。
3. **缺失进程接地（Process Grounding）**：meta-cc 已有 14 个 MCP 工具，能提供原始 tool-call 序列、实际修改文件轨迹、重试/错误计数、编辑震荡检测——这是与 agent 叙述层失败模式完全解耦的记录-结构通道。

当前 gate 判断不消费这一已就绪的独立证据源，导致 `verifyDod` 和 `epicEvaluate` 在"声明 vs 实际"维度缺乏可测量的核验。

## Goals

1. **G1（可验证）**：`verifyDod` 完成后，task Notes 包含一份 meta-cc digest，列出本次 session 实际修改的文件清单（由 `query_file_activity` 提取），并与 task 声明范围对比标注 `in-scope / out-of-scope`。
2. **G2（可验证）**：`epicEvaluate` 完成后，epic task Notes 包含各子任务的进程证据摘要：重试次数（`analyze_errors`）、编辑震荡文件（`query_edit_sequences`）、以及整体 `evidence_independence: meta-cc-grounded` 标记。
3. **G3（可验证）**：gate 证据包中新增 `data_source: meta-cc-session` 字段，与现有 `data_source: measured` 字段共存，写入 task Notes 及（待 TASK-176a 完成后）`gcl-events.jsonl` 的 `evidence_independence` 字段。
4. **G4（可验证）**：新增 `meta-cc-session-scope` helper，给定一个 TASK-ID，能自动定位该任务的 session（基于时间戳和 task 操作记录），执行三项标准查询并返回结构化 digest。

## Decomposition Sketch

候选子任务（约 4 个 kind:basic 任务）：

1. **meta-cc session scope helper**：封装 per-task session 定位逻辑，给定 TASK-ID + 执行时间窗，调用 `query_file_activity` / `analyze_errors` / `query_edit_sequences`，返回 digest 结构体。实现为 `plugin/skills/loop-backlog/meta-cc-digest.sh` 或等效 bash 函数。
2. **verifyDod gate 集成**：在 `verifyDod` 全部通过后调用 helper，将 digest 以结构化格式 `append-notes` 到 task（声明文件 vs 实际文件 diff，重试计数）。
3. **epicEvaluate gate 集成**：在 `epicEvaluate` 生成 FINISH/ITERATE 推荐前，遍历所有子任务调用 helper 并聚合子任务级进程证据包，附加到 epic Notes。
4. **gcl-events.jsonl evidence_independence 字段写入**：在 helper 调用后，将 `evidence_independence: meta-cc-grounded` 写入 `gcl-events.jsonl`（该任务依赖 TASK-176a schema 就绪；若 TASK-176a 未完成则写入 task Notes 占位标记，接线逻辑先行实现）。

## Trade-offs

- **Scope 限制**：helper 仅 scope 到本任务的 session 时间窗，不做跨任务历史分析，避免查询量膨胀和 token 成本失控。
- **采样策略**：meta-cc 查询在 DoD 通过后单次执行，不在每次 DoD retry 中重复触发；epicEvaluate 按子任务数量线性调用，子任务超过 10 个时采样前 10 个并标注 `digest_truncated: true`。
- **降级处理**：若 meta-cc MCP 调用返回空结果（session 未被记录或时间窗未命中），gate 继续原有流程，Notes 中写入 `meta-cc-digest: unavailable` 而非阻塞 gate。
- **TASK-176a 依赖**：gcl-events.jsonl 写入子任务（#4）在接口上依赖 TASK-176a schema，但接线设计（digest 生成和 Notes 写入）可独立先行实现，TASK-176a 完成后再打通 jsonl 写入路径。
- **SKILL.md 变更范围**：修改限于 `verifyDod` 和 `epicEvaluate` 两个段落的实现节，不改变状态机和 cap:* 幂等标记逻辑。

---

# Plan: gate evidence pack — meta-cc session digest 注入 loop-backlog gate 决策点

## Sub-Task Decomposition

### ST-1: meta-cc session scope helper
**Title**: implement meta-cc-digest helper: per-task session scope + query executor
**Kind**: basic (code-change — creates `plugin/skills/loop-backlog/meta-cc-digest.sh`)
**One-line**: 给定 TASK-ID，定位该任务执行期间的 meta-cc session，执行 `query_file_activity` / `analyze_errors` / `query_edit_sequences`，返回结构化 digest 字符串。
**DoD (shell-gate)**:
- `bash plugin/skills/loop-backlog/meta-cc-digest.sh --help` exits 0 and prints usage
- `bash scripts/validate-plugin.sh` passes

### ST-2: verifyDod gate 集成
**Title**: integrate meta-cc digest into verifyDod gate output in SKILL.md
**Kind**: basic (code-change — modifies `plugin/skills/loop-backlog/SKILL.md` verifyDod implementation section)
**One-line**: 在 `verifyDod` 全部 DoD 通过后，调用 ST-1 helper 并将 digest（实际修改文件 vs 声明范围）以结构化格式 `append-notes` 到 task。
**DoD (shell-gate)**:
- `grep -q 'meta-cc-digest' plugin/skills/loop-backlog/SKILL.md` exits 0
- `grep -q 'data_source: meta-cc-session' plugin/skills/loop-backlog/SKILL.md` exits 0
- `bash scripts/validate-plugin.sh` passes

### ST-3: epicEvaluate gate 集成
**Title**: integrate meta-cc digest into epicEvaluate in SKILL.md
**Kind**: basic (code-change — modifies `plugin/skills/loop-backlog/SKILL.md` epicEvaluate section)
**One-line**: 在 `epicEvaluate` 生成 FINISH/ITERATE 推荐前，遍历子任务调用 helper 并将聚合进程证据包（retry 计数、震荡文件、file scope diff）附加到 epic Notes。
**DoD (shell-gate)**:
- `grep -q 'epicEvaluate.*meta-cc\|meta-cc.*epicEvaluate' plugin/skills/loop-backlog/SKILL.md` exits 0
- `grep -q 'evidence_independence: meta-cc-grounded' plugin/skills/loop-backlog/SKILL.md` exits 0
- `bash scripts/validate-plugin.sh` passes

### ST-4: gcl-events.jsonl evidence_independence 字段写入
**Title**: wire meta-cc evidence_independence field into gcl-events.jsonl (pending TASK-176a schema)
**Kind**: basic (code-change — modifies helper and/or SKILL.md to write `evidence_independence` field; adds graceful degradation when TASK-176a schema not yet present)
**One-line**: 在 helper 调用后将 `evidence_independence: meta-cc-grounded` 写入 `gcl-events.jsonl`；若 schema 未就绪则写入 task Notes 占位标记 `gcl-evidence-independence: meta-cc-grounded (pending jsonl)`。
**DoD (shell-gate)**:
- `grep -q 'evidence_independence' plugin/skills/loop-backlog/meta-cc-digest.sh` exits 0
- `grep -q 'gcl-evidence-independence\|evidence_independence' plugin/skills/loop-backlog/SKILL.md` exits 0
- `bash scripts/validate-plugin.sh` passes

## Sequencing

```
ST-1  ──────────────────────────────►  ST-2
        │                               │
        └──────────────────────────►  ST-3
                                        │
                                        └──►  ST-4
```

- **ST-1 先行**：ST-2、ST-3、ST-4 全部依赖 helper，必须 ST-1 完成后才能开始。
- **ST-2 和 ST-3 并行**：两者修改 SKILL.md 的不同段落（`verifyDod` vs `epicEvaluate`），可并行执行，合并时若冲突为同文件冲突需人工解决。
- **ST-4 最后**：依赖 ST-2/ST-3 中 `evidence_independence` 字段的具体写入位置确定后，才能接入 jsonl 写入逻辑。

## Constraints

1. **不改变 gate 状态机**：verifyDod 和 epicEvaluate 的状态转换逻辑、cap:* 幂等标记、信号文件写入时序均不变；meta-cc 调用是纯追加的证据注释，不阻塞也不改变任何 gate 决策路径。
2. **降级不阻塞**：meta-cc MCP 调用失败或返回空结果时，写入 `meta-cc-digest: unavailable (reason: <msg>)` 并继续；gate 不因 meta-cc 不可用而被阻塞。
3. **采样上限**：epicEvaluate 中 helper 调用数量上限为 10 个子任务；超出时标注 `digest_truncated: true` 并仅处理最近 10 个。
4. **TASK-176a 依赖隔离**：ST-4 实现 `gcl-events.jsonl` 写入时，必须用条件检查（文件是否存在 + schema 字段是否存在）实现向前兼容，确保 TASK-176a 未完成时 ST-4 仍能独立通过自己的 DoD。
5. **validate-plugin.sh 必须通过**：所有 SKILL.md 修改必须满足现有 contracts（特别是 `grep: "DoD #.*: PASS"` 等合约不被破坏）；helper 脚本加入后若 validate 脚本不覆盖可无需新增合约，但不能破坏已有合约。
6. **helper 输出格式稳定**：ST-1 的 digest 输出格式需在 header 注释中明确记录，作为 ST-2/ST-3/ST-4 集成的接口契约；格式变更视为破坏性变更，需同步更新所有集成点。
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
<!-- SECTION:NOTES:END -->
