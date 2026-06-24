---
id: TASK-181
title: grounding-infrastructure.md 补全：缺口再分析、改进方案与过程展望
status: 'Epic: Backlog'
assignee: []
created_date: '2026-06-24 05:48'
updated_date: '2026-06-24 05:53'
labels:
  - 'kind:epic'
dependencies: []
ordinal: 119000
---

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Background

`docs/research/grounding-infrastructure.md` 已覆盖接地的核心概念：失败模式解耦、2×2 观测模式矩阵、三层接地分类（系统/进程/行为）、现有机制全景（meta-cc / archguard / BAIME gate 层），以及 loop-backlog 的接地缺口分析。然而 §9「当前状态与下一步」仅有一张三行状态表和一份简短的优先级列表，未能完成文档应有的三个收尾任务：

1. **缺口再分析**：四个缺口（gcl-events.jsonl、escape rate、pre-dispatch enrichment、gate evidence pack）在文档中被并列列出，但它们在架构上并不对等——gcl-events.jsonl 是所有三层接地的 join key（脊梁），而非普通缺口；其余三个按杠杆高低有明确的优先排序（行为接地 escape rate 最高、系统接地进 intake 次之、进程接地进 gate 次之）。

2. **四个改进方案**：文档提及了方向（§5），但未给出可执行的方案描述——触发点、调用哪些工具、输出什么 artifact、以及四个方案之间的实施次序。

3. **过程展望**：文档结尾缺少「建成后的开发过程是什么样子」的正向描述，即四阶段闭环（intake → execution → gate → outcome）及其三个递进后果和两条操作纪律，读者无法形成对投资价值的完整判断。

这三个缺口使 §9 成为草稿状态，文档整体停在「分析问题」层而未到达「指引行动」层。本 epic 负责补全这三个部分。

## Goals

1. **G1（缺口再分析）**：§9 新增一小节，明确识别 gcl-events.jsonl 为「脊梁」（所有三层接地的 join key），并按杠杆排序排列其余三个缺口，排序可通过阅读文档中的分析逻辑验证。

2. **G2（四个改进方案）**：§9 新增「改进方案」小节，包含方案1~4 的具体描述（触发点 / 调用工具 / 产出物）及实施次序图，可通过核查各方案与 §3~§5 内容的一致性验证。

3. **G3（过程展望）**：§9 新增「过程展望」小节，描述建成后的四阶段闭环（以本项目真实 artifact 走一遍），列出三个递进后果和两条操作纪律，可通过核查描述的内部逻辑自洽性验证。

4. **G4（doc-only 约束）**：所有修改限于 `docs/research/grounding-infrastructure.md`，不触及 `plugin/`、`scripts/`、`backlog/` 或其他运行时文件。

## Decomposition Sketch

- **子任务 A — 缺口再分析节**：分析四个缺口的架构角色，识别 gcl-events.jsonl 作为脊梁的理由（三层接地的唯一 join key），按杠杆排序（escape rate → pre-dispatch enrichment → gate evidence pack）撰写并写入 §9。

- **子任务 B — 四个改进方案节**：将方案1（gate evidence pack）、方案2（pre-dispatch enrichment）、方案3（escape rate linkage，对应 TASK-176d）、方案4（行为接地向生产端延伸）各自展开为触发点 + 调用工具 + 产出物的具体描述，补充实施次序（脊梁 → 方案3+1 → 方案2 → 方案4），写入 §9。

- **子任务 C — 过程展望节**：以四阶段闭环（intake 系统接地 → execution 进程接地 → gate 决策接地 → outcome 行为接地）为骨架，用本项目真实 artifact（loop-backlog SKILL.md、archguard 本地缓存、gcl-events.jsonl）走一遍，推导三个递进后果和两条操作纪律，写入 §9。

## Trade-offs and Risks

- **范围蔓延风险**：「过程展望」若写得过长，会与 §7（可移植设计原则）和 §8（与现有框架关系）形成重叠。缓解：展望专注于「本项目建成后的工作流变化」，设计原则节保持现有的跨项目视角。

- **信息一致性风险**：四个改进方案的工具调用细节须与 §4（现有观测机制全景）保持一致，否则会引入矛盾。缓解：子任务 B 撰写时以 §4 的工具表为参照，逐一核对。

- **doc-only 边界**：本 epic 的所有输出为文档内容，不创建实际可运行代码；如需验证方案可行性，依赖现有已集成工具（archguard / meta-cc MCP）的已知 API，不引入新依赖。

---

## Background

`docs/research/grounding-infrastructure.md` 已覆盖接地的核心概念：失败模式解耦、2×2 观测模式矩阵、三层接地分类（系统/进程/行为）、现有机制全景（meta-cc / archguard / BAIME gate 层），以及 loop-backlog 的接地缺口分析。然而 §9「当前状态与下一步」仅有一张三行状态表和一份简短的优先级列表，未能完成文档应有的三个收尾任务：缺口再分析（四个缺口的架构角色不对等）、四个可执行改进方案（触发点 / 工具 / 产出物 / 次序）、以及过程展望（建成后的四阶段闭环与后果）。本 epic 通过三个顺序子任务补全这三个部分，全程 doc-only。

## Goals

1. **G1（缺口再分析）**：§9 新增一小节，明确识别 gcl-events.jsonl 为「脊梁」（所有三层接地的 join key），并按杠杆排序排列其余三个缺口，排序可通过阅读文档中的分析逻辑验证。

2. **G2（四个改进方案）**：§9 新增「改进方案」小节，包含方案1~4 的具体描述（触发点 / 调用工具 / 产出物）及实施次序图，可通过核查各方案与 §3~§5 内容的一致性验证。

3. **G3（过程展望）**：§9 新增「过程展望」小节，描述建成后的四阶段闭环（以本项目真实 artifact 走一遍），列出三个递进后果和两条操作纪律，可通过核查描述的内部逻辑自洽性验证。

4. **G4（doc-only 约束）**：所有修改限于 `docs/research/grounding-infrastructure.md`，不触及 `plugin/`、`scripts/`、`backlog/` 或其他运行时文件。

## Sub-Task Decomposition

### TASK-181a — §9.1 缺口再分析节

将 §9 的现有状态表扩充为「缺口再分析」小节。具体内容：
- 识别 gcl-events.jsonl 的特殊角色：它是三层接地的唯一 join key（将进程接地的 session trace、系统接地的 archguard risk、行为接地的 escape rate 连接成可查询的统一日志），是「脊梁」而非普通缺口。
- 对其余三个缺口按杠杆排序，并注明排序依据：
  - 行为接地 escape rate（TASK-176d）— 杠杆最高：是 GCL 从认知负载计量升级为监督质量计量的前提，同时解锁 H5 验证
  - 系统接地进 intake（pre-dispatch enrichment）— 次之：直接降低 C 分量，改善 worker 起点质量
  - 进程接地进 gate（gate evidence pack）— 再次之：提升 evidence independence，改善 gate 决策质量

**产出物**：`docs/research/grounding-infrastructure.md` §9.1 新增约 200 字 + 杠杆排序表

### TASK-181b — §9.2 四个改进方案节

将四个改进方案各自展开为可执行描述并补充实施次序：

- **方案1 gate evidence pack**：
  - 触发点：`verifyDod` / `epicEvaluate` 调用前
  - 工具：`meta-cc query_file_activity`（实际 touched 文件轨迹）+ `analyze_errors`（执行期错误记录）
  - 产出物：「实际 touched 文件 vs 声明范围」差异报告，写入 gate 证据包（task Notes）

- **方案2 pre-dispatch enrichment**：
  - 触发点：`claimBatch` 时（任务分配给 worker 前）
  - 工具：`archguard_get_change_risk`（涉及文件风险评分）+ `archguard_get_cochange`（共变历史）
  - 产出物：内联进 worktree context 的风险摘要（markdown block），使 worker 从「盲目描述」升级为「有实证上下文的描述」

- **方案3 escape rate linkage**（对应 TASK-176d）：
  - 触发点：任务状态变更为 `Needs Human` 或 reaper requeue 时
  - 工具：gcl-events.jsonl append（写入 escape 事件，字段：`task_id / gate_event_id / escape_reason / ts`）
  - 产出物：gate 决策与后续逃逸事件的可查询关联，实现 GCL 的「后置校准」

- **方案4 行为接地向生产端延伸**（长线）：
  - 触发点：外部产品 usage telemetry 可用时
  - 工具：待定（需与生产环境监控系统集成）
  - 产出物：真实外部产品交付指标 → 回链到对应任务的 gate 决策，实现 H8 的前提条件

实施次序：脊梁（TASK-176a，gcl-events.jsonl schema）→ 方案3 + 方案1（便宜且让假设可检验）→ 方案2（打 C 分量，降低 intake 盲目性）→ 方案4（H8 前提，中长期）

**产出物**：`docs/research/grounding-infrastructure.md` §9.2 新增约 400 字 + 方案表 + 次序图（文字描述）

### TASK-181c — §9.3 过程展望节

以四阶段闭环为骨架，用本项目真实 artifact 走一遍，推导后果和纪律：

**四阶段闭环**：
1. **Intake — 系统接地**：`claimBatch` 自动附加 archguard change-risk + cochange 摘要（方案2）。真实场景：loop-backlog SKILL.md 涉及文件变更时，worker 得到的 context 包含「高 cochange 节点风险评分」而非仅任务描述。
2. **Execution — 进程接地**：meta-cc session trace 实时记录实际 touched 文件、回退次数、卡点。`query_file_activity` 可对比「声明修改 SKILL.md」vs 实际还修改了哪些文件。
3. **Gate — 决策接地**：`verifyDod` 前自动跑方案1，把「touched 文件差异 + 错误记录」写入证据包。gate actor 读的是独立证据，而非 worker 自述。
4. **Outcome — 行为接地**：任务完成后若出现 escape，方案3 把 escape 事件 append 到 gcl-events.jsonl，回链到原始 gate 决策，实现「后置校准」。

**三个递进后果**：
1. meta-cc + archguard 从「个别调用的工具」升级为可移植的三层接地基础设施
2. GCL 假设（H4/H5/H6）从「看起来对」升级为「数据可查、逻辑可反驳」
3. escape rate 回链建立后，哪类任务逃逸率高、哪个 gate 决策点是瓶颈，变成可回答的问题

**两条操作纪律**：
1. **观测成本热力学约束**：接地层次应匹配任务性质；doc-only 任务的 pre-dispatch enrichment 应有豁免逻辑，否则观测本身成为摩擦。
2. **D 支柱风险**：escape rate 在方案4 建成前是行为接地的代理指标；所有「监督质量已充分」的结论须注明「行为接地仍为代理指标」，防止 Goodhart 定律。

**产出物**：`docs/research/grounding-infrastructure.md` §9.3 新增约 500 字

## Sequencing

```
TASK-181a（缺口再分析）
    ↓ 建立架构角色共识，为后续方案提供参照
TASK-181b（四个改进方案）
    ↓ 方案详情依赖缺口排序中的杠杆判断
TASK-181c（过程展望）
    依赖方案2/3/4 的具体描述，才能走「真实 artifact」闭环
```

三个子任务严格顺序执行；无并行化空间（C 依赖 B 的方案细节，B 依赖 A 的杠杆排序）。

## Constraints

- **doc-only**：仅修改 `docs/research/grounding-infrastructure.md`，不修改 `plugin/`、`scripts/`、`backlog/` 或任何运行时文件。
- **不预先创建子任务**：三个子任务在 epic 进入 Epic: Ready 并开始 Decomposing 时才由 loop-backlog 创建，本 plan 仅描述子任务内容。
- **与现有 §1~§8 不冲突**：§9 的补全只在现有状态表之后追加内容，不修改已有段落；若发现逻辑矛盾，以 §5（接地缺口）和 §7（设计原则）为准。
- **依赖已有工具**：方案描述依赖已集成的 archguard MCP 和 meta-cc MCP，不引入新工具或新依赖。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Epic proposal self-review: APPROVED
premise-ledger:
[E] background lines: 6 lines in Background section (直接计数)
[C] goal coverage: G1~G4 逐条对照 Decomposition Sketch A/B/C 验证覆盖（A→G1，B→G2，C→G3，doc-only→G4）
[H] epic 粒度: 三个子任务规模均匀，§9 补全不需要跨越 plugin/ 边界，粒度合理靠背景知识判断
GCL-self-report: E=1 C=2 H=1

Epic plan review iteration 1: APPROVED
premise-ledger:
[E] sub-task count: 3 子任务（181a / 181b / 181c），直接计数
[C] goal coverage: G1→1bc，G2→181b，G3→181c，G4→Constraints — 逆向验证每个 Goal 均有子任务对应
[H] sequencing 合理性: A→B→C 的依赖理由（杠杆识别先于方案详情，方案详情先于过程展望）靠背景知识判断
GCL-self-report: E=1 C=2 H=1

cap:propose=approved
<!-- SECTION:NOTES:END -->
