---
id: TASK-185
title: dyad 实验：LLM-boss gate 设计与 H7 首次测量
status: 'Epic: Backlog'
assignee: []
created_date: '2026-06-24 05:50'
updated_date: '2026-06-24 05:53'
labels:
  - 'kind:epic'
dependencies: []
ordinal: 123000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
dyad 实验：LLM-boss gate 设计与 H7 首次测量
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Epic Plan: dyad 实验：LLM-boss gate 设计与 H7 首次测量

## Background

H7 假设（gcl-synthesis.md）指出：在 routine engineering gates 中，human vs automated gate actor 对 escape rate 无显著差异（控制 evidence_independence 后）。但当前 gcl-events.jsonl 缺少 `gate_actor_type` 和 `evidence_independence` 字段，使 H7 无法被首次测量。

`epicEvaluate` 的 soft-halt 结构（loop-backlog SKILL.md §epicEvaluate）是现有代码库中唯一一个人类 gate 的明确接入点，也是接入 LLM-boss gate 所需改动最小的位置。cc-actor-network.md §3 明确指出：dyad 是"测试 H7 的最小实验台架"，只需在 epicEvaluate 软停点旁接一个 boss CC 通道，不需要新机制。

关键约束（cc-actor-network.md §4.1）：boss 和 worker 必须持有不同的证据源（archguard change-risk + meta-cc trace），否则测的是 LLM 自我一致性而非 H7。人类对照样本来自同一 gcl-events.jsonl 的历史记录（gate_actor_type=human）。

依赖 TASK-176a 完成 gcl-events.jsonl schema 扩展（gate_actor_type + evidence_independence 字段），才能写入并联合检验。

## Goals

1. dyad 实验设计文档存在（boss CC 架构、evidence independence 操作化定义、统计检验设计），可通过文件路径检查验证。
2. epicEvaluate 软停点旁有 boss CC 通道接入（代码可通过 grep `boss` / `gate_actor_type` 验证），boss 读取独立证据包（archguard change-risk + meta-cc trace），不依赖 worker 摘要。
3. gcl-events.jsonl 每次 epicEvaluate gate 事件均写入 `gate_actor_type`（值为 `llm` 或 `human`）和 `evidence_independence` 字段（依赖 TASK-176a）。
4. H7 首次统计检验结果文档存在（gcl-h7-validation.md），包含 escape rate 对比和可证伪裁定，可通过文件路径检查验证。

## Sub-Task Decomposition

1. **dyad 实验设计文档**（doc-only）——起草 `docs/research/dyad-experiment-design.md`：boss CC 架构图（信号流 + 证据通道）、evidence independence 操作化定义（包括独立证据包的字段规格和最小集）、H7 统计检验设计（零假设、控制变量、效果量估算、样本量规划）。覆盖 Goal 1。

2. **boss evidence pack 封装**（code-change）——在 `plugin/skills/loop-backlog/` 中封装 boss 的标准化输入结构：调用 `mcp__archguard__get_change_risk`（针对 epic 涉及的 git diff）和 `mcp__plugin_meta-cc_meta-cc__query_session_signals`（针对 worker 的 session trace），输出结构化 evidence pack JSON，不经过 worker 摘要中转。覆盖 Goal 2 的 evidence independence 约束。

3. **epicEvaluate boss 通道接入**（code-change）——修改 loop-backlog SKILL.md 的 `epicEvaluate` bash 实现（行 1432-1446 附近），在 soft-halt 写 `cap:evaluate` 之前，fork 一个 boss CC 通道：boss 消费 evidence pack，输出 FINISH/ITERATE 决定，结果写入 task notes，`gate_actor_type=llm` 写入 gcl-events.jsonl（依赖 TASK-176a schema）。覆盖 Goal 2 + Goal 3（llm 路径）。

4. **human gate_actor_type 写入**（code-change）——依赖 TASK-176a；在 human 确认 Epic: Evaluating → Epic: Done 的路径上，同步写入 `gate_actor_type=human` 和 `evidence_independence` 字段到 gcl-events.jsonl，形成与 llm gate 可配对的对照组。覆盖 Goal 3（human 路径）。

5. **H7 统计分析**（doc-only）——在积累足够 gcl-events.jsonl 数据后（llm gate ≥10 次，human gate 历史记录可用），跑 escape rate 对比检验（Mann-Whitney U 或 Fisher exact test，控制 evidence_independence 分层），写结果到 `docs/research/gcl-h7-validation.md`，含可证伪裁定（H7 confirmed / null / refuted）。覆盖 Goal 4。

## Sequencing

```
TASK-176a（外部依赖，schema 扩展）
  ↓
[可并行]
  子任务 1（dyad 实验设计文档，doc-only，无代码依赖，可最先启动）
  子任务 2（boss evidence pack 封装，仅依赖 archguard + meta-cc MCP 可用）
  ↓
子任务 3（epicEvaluate boss 通道接入，依赖子任务 2 的 evidence pack + TASK-176a schema）
  ↓
子任务 4（human gate_actor_type 写入，依赖 TASK-176a schema，可与子任务 3 并行）
  ↓
[数据积累期：运行若干 epic 让 gcl-events.jsonl 积累 llm gate 样本]
  ↓
子任务 5（H7 统计分析，依赖子任务 3+4 的数据写入完整）
```

子任务 1 可在 TASK-176a 完成前独立启动（doc-only）。
子任务 2 也可独立启动（evidence pack 封装不依赖 schema，只依赖 MCP 可用性）。
子任务 3 和 4 必须在 TASK-176a 完成后才能写入真实 gcl-events.jsonl。
子任务 5 需在 3+4 运行积累足够样本后执行，是最后一步。

## Constraints

- 本 epic 不创建任何子任务，分解由 loop-backlog worker 在 Epic: Decomposing 阶段执行。
- boss CC 必须从 archguard + meta-cc 独立读取证据，不得通过 worker Notes 摘要中转（cc-actor-network.md §4.1 克隆耦合约束）。
- gate_actor_type 字段写入依赖 TASK-176a 的 gcl-events.jsonl schema 扩展，子任务 3+4 在 TASK-176a 完成前无法完成真实路径测试。
- H7 统计分析（子任务 5）须明确控制时间偏差混淆变量，人类对照样本的任务类型分布与 llm gate 运行窗口须在分析报告中说明。
- 验证命令：`bash scripts/validate-plugin.sh`（修改 SKILL.md 后必须通过）。
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
<!-- SECTION:NOTES:END -->
