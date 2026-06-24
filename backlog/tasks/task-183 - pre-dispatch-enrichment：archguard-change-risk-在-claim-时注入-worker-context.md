---
id: TASK-183
title: pre-dispatch enrichment：archguard change-risk 在 claim 时注入 worker context
status: 'Epic: Backlog'
assignee: []
created_date: '2026-06-24 05:49'
updated_date: '2026-06-24 05:51'
labels:
  - 'kind:epic'
dependencies: []
ordinal: 121000
---

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: pre-dispatch enrichment — archguard change-risk 在 claim 时注入 worker context

## Background

当前 loop-backlog 的 `claimBatch` 流程：worker 将 task 状态切换为 `Basic: In Progress` 后，执行 agent 拿到的 context 仅限 task description（人类或 LLM 起草的意图描述）。这是接地程度最低的一环：description 不知道涉及文件的实际 cochange 风险，不知道历史中类似任务的执行模式，不知道这类任务过去导致过什么 merge conflict 或 DoD 失败。

GCL 的 C 分量（均值 4.50，占 31%）部分反映了这个缺口：gate 判断者需要跨任务查阅外部文档、手工查找历史 cochange 关系，因为 intake 阶段没有把这些证据内联进来。C 分量代表需要外部知识才能判断的 criteria——减少 C 的核心手段是把外部证据在上下文窗口内就位（"grounding at intake"）。

本项目 `.archguard/query/git-history/file-metrics.json` 已有真实 change-risk 数据（例如 `plugin/skills/loop-backlog/SKILL.md`：6 commits / 2 活跃天、cochange 邻居 `scripts/loop-backlog-daemon.js` strength 0.29）。archguard MCP 的 `archguard_get_change_risk`、`archguard_get_cochange`、`archguard_get_ownership` 都已就绪。改进方向是在 `claimBatch` 后、`spawnAgent` 前，解析 task description 涉及的文件/模块，自动调用 archguard，把 change-risk + cochange 邻居内联进 worker 启动 context。

## Goals

1. **G1 — archguard risk summary 内联于 executePrompt**：claim 一个 `kind:basic` 任务后，`buildExecutePrompt` 输出的 prompt 包含 archguard risk block（涉及文件的 commitCount、activeDays、topCochangeNeighbors strength ≥ 0.2）。可通过查看 executePrompt 输出内容验证。
2. **G2 — 文件解析覆盖率 ≥ 60%**：从 task description 解析出至少一个已知文件路径的比例 ≥ 60%（在 10 个历史任务的 description 上离线评估）。
3. **G3 — C 分量改善趋势**：引入后的 5 个含 archguard context 的 gate events 中，C 分量均值较引入前（4.50）下降 ≥ 0.5（1σ 内有改善迹象）。
4. **G4 — 性能约束**：archguard 查询在 claim 时平均增加 < 3 秒（本地文件缓存路径；MCP 路径可以是异步可选）。
5. **G5 — advisory 降级**：当解析得到 0 个文件路径或 archguard 数据缺失时，静默跳过，不阻塞 claim 流程。

## Decomposition Sketch

候选子任务（按执行依赖顺序）：

1. **文件/模块解析器**：从 task description 提取可能涉及的文件路径列表（regex/LLM 两种模式；优先 regex 覆盖 `plugin/`、`scripts/`、`docs/` 前缀路径）。
2. **archguard risk query 封装**：封装 `archguard_get_change_risk`、`archguard_get_cochange`、`archguard_get_ownership` 为单一函数 `fetchRiskContext(files) → RiskSummary`，优先查本地缓存文件（`.archguard/query/git-history/file-metrics.json`），降级到 MCP 调用。
3. **claimBatch 集成**：在 `buildExecutePrompt` 中新增 `## Archguard Risk Context` block，由 `fetchRiskContext` 注入；当无数据时此 block 为空（advisory）。
4. **C 分量影响测量**：选取 5 个引入后的 gate events，记录 premise-ledger C 分量，与 gcl-corpus 基线（4.50）对比，写入 `docs/research/gcl-predispatch-impact.md`。

## Trade-offs

- **advisory 性质**：archguard 文件路径预测基于 description 文本解析，可能漏报（description 未明确提及文件）或误报（提及文件但最终未实际修改）。因此 risk context 仅作为 advisory 提示，不阻塞执行流程。
- **预测准确率 vs 覆盖率**：regex 解析高精度但低召回（只抓显式路径）；LLM 解析高召回但低精度（可能虚构路径）。初版优先 regex，LLM 作为可选扩展。
- **成本控制**：本地 `.archguard/query/git-history/file-metrics.json` 缓存覆盖现有文件，无 MCP 网络开销；MCP 路径为未知文件的降级备选，需控制每次 claim 的 MCP 调用数（上限 3 个文件）。
- **方案 B（反向校正）**：gate evidence pack 中实际 touched 文件是真实文件集合。可在 merge 后用实际 touched 文件重新查 archguard，对比 claim 时的预测，作为解析准确率的后验反馈（不在本 epic 范围内，作为后续任务）。

---

# Plan: pre-dispatch enrichment — archguard change-risk 在 claim 时注入 worker context

## Sub-Task Decomposition

### Child 1 — task description 文件/模块解析器
**Title**: feat: task description file-path parser for pre-dispatch enrichment
**Kind**: basic (CODE-CHANGE — 新增 `scripts/lib/parse-task-files.js`)
**Goal**: 实现 `parseTaskFiles(description: string) → string[]`，返回 description 中出现的已知文件路径列表。
**Approach**:
- Phase 1: 用 regex 提取形如 `plugin/`、`scripts/`、`docs/`、`.archguard/`、`.claude/` 前缀的路径 token
- Phase 2: 对每个候选路径用 `fs.existsSync(path.join(repoRoot, candidate))` 验证存在性，过滤不存在的路径
- Phase 3: 写单元测试覆盖至少 5 个历史任务 description 样本，验证覆盖率 ≥ 60%
**DoD**:
- `node scripts/lib/parse-task-files.js --self-test` 退出码为 0（内置测试通过）
- 覆盖率断言：10 个历史任务 description 中 ≥ 6 个返回非空路径列表

### Child 2 — archguard risk query 封装
**Title**: feat: fetchRiskContext — archguard change-risk/cochange/ownership wrapper
**Kind**: basic (CODE-CHANGE — 新增 `scripts/lib/fetch-risk-context.js`)
**Goal**: 实现 `fetchRiskContext(files: string[], repoRoot: string) → RiskSummary`。
**Approach**:
- Phase 1: 读取 `.archguard/query/git-history/file-metrics.json`，构建 `filePath → metrics` 索引
- Phase 2: 对 `files` 中每个路径查索引，提取 `commitCount`、`activeDays`、`topCochangeNeighbors`（strength ≥ 0.2）
- Phase 3: 格式化为 `## Archguard Risk Context` Markdown block；若无数据则返回空字符串
- Phase 4: 降级路径：若本地文件缺失，尝试调用 `archguard_get_change_risk` MCP（最多 3 个文件）
**DoD**:
- `node scripts/lib/fetch-risk-context.js --self-test` 退出码为 0
- 对 `plugin/skills/loop-backlog/SKILL.md` 返回包含 `commitCount: 6`、`activeDays: 2` 的 summary
- 对空文件列表返回空字符串（advisory 降级验证）

### Child 3 — claimBatch 集成：将 archguard summary 写入 executePrompt
**Title**: feat: inject archguard risk block into buildExecutePrompt (SKILL.md claimBatch integration)
**Kind**: basic (CODE-CHANGE — 修改 `plugin/skills/loop-backlog/SKILL.md` 的 `buildExecutePrompt` 章节)
**Goal**: 在 `buildExecutePrompt` 中调用 `parseTaskFiles` + `fetchRiskContext`，将结果注入 prompt 的 `## Archguard Risk Context` block。
**Approach**:
- Phase 1: 在 `buildExecutePrompt` bash 实现中，紧接 `TASK_DESC` 赋值后，调用 `node scripts/lib/parse-task-files.js "$TASK_DESC"` 获取文件列表
- Phase 2: 调用 `node scripts/lib/fetch-risk-context.js "${FILES[@]}"` 获取 risk summary
- Phase 3: 将 risk summary 内联进 `cat <<PROMPT_EOF` heredoc，新增 `## Archguard Risk Context` 节
- Phase 4: 当 risk summary 为空时，block 整体省略（不输出空节标题）
**DoD**:
- `bash scripts/validate-plugin.sh` 通过（所有 contract grep 仍满足）
- 手工 claim 一个含 `plugin/skills/loop-backlog/SKILL.md` 引用的测试任务，验证生成的 prompt 包含 `## Archguard Risk Context` 节且含 commitCount/cochange 数据

### Child 4 — C 分量影响测量
**Title**: research: measure GCL C-component delta after pre-dispatch enrichment goes live
**Kind**: basic (DOC-ONLY — 写入 `docs/research/gcl-predispatch-impact.md`)
**Goal**: 收集引入后 5 个 gate events 的 premise-ledger C 分量，与基线（4.50）对比，产出量化报告。
**Approach**:
- Phase 1: 等待 child 1–3 合并并运行至少 5 个任务 claim 周期
- Phase 2: 从 task Notes 提取 `GCL-self-report: E=N C=N H=N` 记录，计算 C 均值
- Phase 3: 对比基线 4.50，计算 delta 和方向（↓/↑/=），写入分析文档
- Phase 4: 若 C 均值下降 ≥ 0.5 → CONFIRM（G3 达成）；否则记录偏差原因
**DoD**:
- `docs/research/gcl-predispatch-impact.md` 存在且包含 N≥5 的 C 分量观测表
- 文档包含 `baseline: 4.50`、`post_mean: X.XX`、`delta: ±Y.YY` 字段

## Implementation Sequencing

```
Child 1 (parse-task-files) ──┐
                              ├──→ Child 3 (claimBatch integration) ──→ Child 4 (measurement)
Child 2 (fetch-risk-context) ─┘
```

Child 1 和 Child 2 可并行执行。Child 3 依赖 Child 1 和 Child 2 均完成。Child 4 依赖 Child 3 合并后运行足够多任务。

## Definition of Done (Epic Level)

- [ ] `bash scripts/validate-plugin.sh` 通过
- [ ] `buildExecutePrompt` 产出的 prompt 包含 `## Archguard Risk Context` block（有数据时）
- [ ] `parseTaskFiles` 覆盖率 ≥ 60%（10 个历史任务样本）
- [ ] `gcl-predispatch-impact.md` 存在且记录 N≥5 gate events 的 C 分量 delta

## Risk Register

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| description 中无显式路径（regex 覆盖率 < 60%） | 中 | 中 | 记录覆盖率；不影响系统运行（advisory）；后续迭代可加 LLM 解析 |
| archguard MCP 调用超时 | 低 | 低 | 降级为本地缓存；MCP 路径设 2 秒超时 |
| SKILL.md 修改破坏现有 contract grep | 中 | 高 | DoD 明确包含 `validate-plugin.sh` 验证 |
| C 分量未下降（G3 miss） | 中 | 低 | G3 仅要求"改善趋势"而非强制达成；miss 需记录原因，触发后续迭代 |
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Epic proposal self-review: APPROVED
premise-ledger:
[E] background lines: 6 lines (within 3-8 limit)
[E] concrete data: file-metrics.json 6 commits/2 days, cochange strength 0.29 cited
[E] C-分量 claim grounded in observed GCL mean 4.50 from gcl-corpus
[C] goal coverage: G1→sub-task 3, G2→sub-task 1, G3→sub-task 4, G4→sub-tasks 1+2, G5→sub-task 2
[C] all goals verifiable (shell-checkable or measurable vs gcl-corpus baseline)
[H] epic granularity: 4 sub-tasks, each independently deliverable, right-sized
GCL-self-report: E=1 C=2 H=1

Epic proposal approved. Starting epic plan draft.

cap:propose=approved
<!-- SECTION:NOTES:END -->
