---
id: TASK-186
title: H8 insight-task 评测集设计：grounding 受控条件下的人机质量差距测量
status: 'Epic: Backlog'
assignee: []
created_date: '2026-06-24 05:50'
updated_date: '2026-06-24 05:52'
labels:
  - 'kind:epic'
dependencies: []
ordinal: 124000
---

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Epic Proposal: H8 insight-task 评测集设计

## Background

H8 假设（gcl-synthesis.md §新增假设、gcl-complete-observation-mechanism.md §5）主张：在开放/insight 任务（设计取舍、架构判断、产品品味、问题定义）上，人机质量差距的主要解释变量是 grounding 存量，而非处理机制的本质差异。控制 grounding 接入后差距不显著；随接地基础设施建设，残差差距随时间收窄。H7 已在 routine gate 建立"无差异"，H8 把该结论推广到 insight 任务，两者合起来意味着人保留的判断点最终只剩 B（偏好来源）和 C（制度责任）。

当前缺少一套可实施的 insight-task 评测集：没有操作化的"grounding 受控"定义，没有覆盖多类 insight 任务的评分标准，也没有明确的统计检验设计。没有这套评测集，H8 就只是理论命题，无法进入可证伪阶段（gcl-complete §5 H8 可证伪规则明确要求该评测集存在）。本 epic 是评测集的**设计阶段**（doc-only），不包含数据收集。

## Goals

1. 产出一份 insight-task 评测集设计文档，覆盖 ≥3 种 insight 任务类别（如：架构方案对比、问题定义复审、产品 variant 取舍预筛），附带每类的具体任务示例框架。
2. 明确 grounding 受控的操作化定义：同等真实世界观测证据包的构成要素（证据类型、信息截止边界、投喂格式约束）。
3. 制定评分维度与标准：不要求"机器优于人"，只检验"控制 grounding 后差距是否显著"；包含独立评审规程和 escape/rework 代理指标。
4. 识别第一批评测素材（来源：本项目历史决策记录、ADR、research 文档中的真实判断案例）。
5. 写明统计检验设计：可证伪规则对应的 null hypothesis、检验方法、样本量估算、纵向追踪规程。

## Decomposition Sketch

1. **insight 任务类型分类与覆盖设计**（doc-only）：基于 cc-actor-network.md §4.6，梳理 insight 任务的分类框架，确定首批覆盖的 ≥3 类任务，输出任务类型目录和每类的评测场景描述。
2. **grounding 受控操作化定义**（doc-only）：定义"同等真实世界观测证据包"的构成，包括证据来源、截止规则、格式标准；说明如何排除偏差（人的隐性 grounding 如何显式化）。
3. **评分维度与标准设计**（doc-only）：设计多维质量评分量表（如：方案完整性、关键权衡识别、决策可辩护性），制定独立评审规程，确定可机器化的代理指标（escape rate、rework 率）。
4. **第一批评测素材识别**（doc-only）：从本项目 docs/adr/、docs/research/、backlog 历史任务中提取适合作为 insight-task 评测题目的真实判断案例，输出候选素材清单。
5. **统计检验设计**（doc-only）：写明 H8 可证伪规则对应的 null hypothesis（human vs machine 在 grounding 受控下无显著差异）、检验方法（置换检验 / Wilcoxon）、最小样本量估算、纵向重测规程（grounding 存量增长后重跑）。

## Trade-offs

- **范围**：这是设计阶段，不包含实际的数据收集、人类评审执行或 LLM 产出采集。所有交付物均为文档（doc-only）。
- **依赖**：数据收集阶段依赖 grounding 基础设施建设（grounding-infrastructure.md §3.3 行为接地，Epics B、C 及 TASK-176d）的完成进度；设计阶段可以先行，但"grounding 受控"操作化的部分细节可能需要在基础设施明确后补充。
- **评分的主观性**：insight 任务评分本质上包含主观判断；设计时须建立评审者间一致性机制，并区分"主观偏好"（B 类 gate，人保留）和"信息处理质量"（可被度量的目标）。
- **素材来源局限**：第一批素材来自本项目自身历史，领域覆盖有限；设计文档应说明外部扩展路径。

---

# Epic Plan: H8 insight-task 评测集设计

## Objective

设计一套可实施的 insight-task 评测集（doc-only），使 H8 假设（「控制 grounding 接入后，人机质量差距不显著」）进入可证伪阶段。所有交付物为设计文档；数据收集在后续依赖 grounding 基础设施建成后执行。

## Sub-Task Decomposition

### TASK-186a：insight 任务类型分类与覆盖设计（doc-only）

**目标**：建立 insight 任务的分类框架，确定首批评测覆盖 ≥3 类，并为每类输出评测场景描述模板。

**交付物**：`docs/research/h8-insight-task-taxonomy.md`，包含：
- 分类框架（基于 cc-actor-network.md §4.6）：架构方案对比、问题定义复审、产品 variant 取舍预筛，以及扩展类别（如：技术债优先级判断、实验设计评审）
- 每类的定义、边界条件、典型输入/输出描述
- 与 B/C 类 gate（偏好来源、制度责任）的边界划分，说明评测仅针对可度量的信息处理质量

**验收**：分类框架覆盖 ≥3 种 insight 类别；每类有明确定义和示例场景描述。

**依赖**：无。
**Labels**: `kind:basic`, `area:research`

---

### TASK-186b：grounding 受控操作化定义（doc-only）

**目标**：定义"同等真实世界观测证据包"的构成，建立标准化的 grounding 包制备规程。

**交付物**：`docs/research/h8-grounding-controlled-operationalization.md`，包含：
- 证据包构成要素：文档证据（ADR、incident log、research 文档摘录）、行为证据（运行指标、用户路径，依赖接地基础设施）、结构证据（代码库快照、架构图）
- 信息截止边界规则：如何确保人和机器接收到"同等"且"信息截止相同"的观测证据
- 格式标准：证据包的结构化格式（Markdown 包、frontmatter 字段）
- 人的隐性 grounding 显式化方案：如何通过访谈/问卷把人类评审者的隐性背景知识识别并纳入证据包
- 接地成熟度标注：标记当前"可操作"（文档证据）vs "依赖基础设施"（行为接地）的部分

**验收**：有明确的证据包构成要素定义；有格式规范；有隐性 grounding 处理方案。

**依赖**：TASK-186a 完成后并行可开始；与 grounding-infrastructure Epic 有逻辑依赖（行为接地部分标注为"待填充"）。
**Labels**: `kind:basic`, `area:research`

---

### TASK-186c：评分维度与标准设计（doc-only）

**目标**：制定可操作的多维质量评分量表、独立评审规程，以及可机器化的代理指标。

**交付物**：`docs/research/h8-scoring-rubric.md`，包含：
- 多维质量评分量表（Likert 5 分或 0/1/2 分制）：
  - 方案完整性：关键维度是否覆盖（可参考 baime-and-quantitative-experiments.md 的 oracle 标注方法）
  - 关键权衡识别：是否识别并权衡了主要 trade-off
  - 决策可辩护性：结论是否有证据支撑，推理链是否可追踪
  - 信息利用率：是否充分利用了提供的 grounding 证据包（不依赖证据包外的隐性知识）
- 评审者间一致性规程：Cohen's kappa 目标（≥0.6）、分歧解决机制
- 代理指标：escape rate（下游是否触发返工/改正）、rework rate
- 评分不含 B/C 类 gate（偏好来源和制度责任不打分，仅记录）

**验收**：评分量表有 ≥3 个维度；有评审者间一致性目标；有代理指标定义。

**依赖**：TASK-186a、TASK-186b 完成后开始。
**Labels**: `kind:basic`, `area:research`

---

### TASK-186d：第一批评测素材识别（doc-only）

**目标**：从本项目历史决策记录中提取适合作为 H8 评测题目的真实 insight 判断案例，输出候选素材清单。

**交付物**：`docs/research/h8-evaluation-material-candidates.md`，包含：
- 从 `docs/adr/`、`docs/research/`、`backlog/` 历史任务中识别的候选案例列表
- 每个候选案例的元数据：任务类型（对应 TASK-186a 分类）、所需 grounding 来源、当前 grounding 可用性（文档可用 / 依赖基础设施）、难度估计
- 筛选标准：有真实的决策记录（不是虚构题目）、有可识别的"正确"判断（有后验验证或专家共识）、grounding 证据包可以重建
- 第一批目标：≥5 个候选案例，覆盖 ≥2 种 insight 任务类型
- 外部扩展路径说明（局限性：首批素材领域覆盖有限）

**验收**：候选清单有 ≥5 条；每条有完整元数据；有筛选标准说明。

**依赖**：TASK-186a 完成后开始（需要任务类型分类）。
**Labels**: `kind:basic`, `area:research`

---

### TASK-186e：统计检验设计（doc-only）

**目标**：将 H8 可证伪规则转化为可操作的统计检验方案，包括 null hypothesis、检验方法、样本量估算和纵向重测规程。

**交付物**：`docs/research/h8-statistical-design.md`，包含：
- Null hypothesis 精确表述：「在 grounding 受控（同等证据包）条件下，human vs machine 产出的质量评分（TASK-186c 量表）分布无显著差异」（双侧检验，α=0.05）
- 检验方法：置换检验（primary）+ Wilcoxon 符号秩检验（secondary），理由：非正态小样本，对应 gcl-complete §5 H8 可证伪规则
- 最小样本量估算：基于 Cohen's d=0.5（中等效应）、power=0.8、α=0.05，估算所需任务×评审者数量
- 纵向重测规程：定义 grounding 存量增长的里程碑（接地基础设施扩展节点），制定重测触发条件，说明「残差差距收窄」的判断标准（时间序列，对比两个时间点）
- 与 gcl-events.jsonl schema 的关联：需要 `gate_actor_type`、`evidence_independence`、`grounding_package_id` 字段（依赖 TASK-176 增量）

**验收**：null hypothesis 明确；检验方法有理由；有样本量估算；有纵向重测规程。

**依赖**：TASK-186c 完成后开始（需要评分量表）；与 TASK-176 有 schema 依赖（标注为待填充）。
**Labels**: `kind:basic`, `area:research`

---

## Execution Order

```
TASK-186a（分类）
    ├── TASK-186b（grounding 操作化）─┐
    ├── TASK-186d（素材识别）          ├── TASK-186c（评分标准）── TASK-186e（统计设计）
    └──────────────────────────────────┘
```

TASK-186a 先行；TASK-186b 和 TASK-186d 并行；TASK-186c 依赖 a+b；TASK-186e 依赖 c。

## Definition of Done（Epic 级别）

- [ ] 5 个子任务文档全部产出（docs/research/h8-*.md）
- [ ] insight 任务类型覆盖 ≥3 种
- [ ] grounding 受控定义有明确的证据包构成
- [ ] 评分量表有 ≥3 个维度，有评审者一致性目标
- [ ] 候选素材清单 ≥5 条
- [ ] 统计检验方案包含 null hypothesis + 检验方法 + 样本量估算 + 纵向规程
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Epic proposal self-review: APPROVED
premise-ledger:
[E] background lines: 8 行，涵盖 H8 来源、当前缺口、与 H7 的关系——直接可数
[C] goal coverage: Goals 1-5 对照 gcl-complete §5 H8 可证伪规则：「grounding 受控评测集存在」→ Goal 1+2；「独立评审+下游指标」→ Goal 3；「素材识别」→ Goal 4；「统计检验+纵向追踪」→ Goal 5；覆盖完整，需推断「Wilcoxon/置换检验」与 H8 统计要求的匹配，信心适中
[H] epic 粒度: 5 个 doc-only 子任务均为设计文档，无实现或数据收集，粒度一致；与背景知识判断相符
GCL-self-report: E=1 C=3 H=1

Epic proposal approved. Starting epic plan draft.

cap:propose=approved
<!-- SECTION:NOTES:END -->
