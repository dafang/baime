# H8 评分维度与评测者一致性方案

**状态**：H8 评测集设计（Phase 3）
**日期**：2026-06-24
**依赖**：docs/research/h8-insight-task-taxonomy.md, h8-grounding-controlled-operationalization.md
**关联**：h8-statistical-design.md

---

## §0 设计原则

### 0.1 评分的目标

评分要捕获"在给定接地证据包（EGEP）下，判断者的输出质量"，而非判断者的偏好或制度权威。

对应 gcl-complete-observation-mechanism.md §4.2 的分析：
- **评分对象**：A 类认知增量（信息处理质量）
- **不评分**：B 类偏好锚定（记录但不评分）、C 类制度问责（记录但不评分）

### 0.2 B/C 类处理说明

B 类 gate（偏好锚定）和 C 类 gate（制度问责）：
- **记录**：在评测实例元数据中标注 `gate_class: B` 或 `gate_class: C`
- **不评分**：不进入 H8 质量差距计算
- **原因**：B 类结果依赖目标函数形式化程度，C 类结果依赖制度授权，两者均不是信息处理质量的函数，不适合用统一量表比较

---

## §1 评分维度

### 维度 1：解法完整性（Solution Completeness）

**定义**：输出是否覆盖了 EGEP 中证据所支持的所有关键评估角度，没有遗漏可识别的重要面向。

**量表（Likert 5 分）**：

| 分值 | 描述 |
|------|------|
| 1 | 严重遗漏：≥2 个 EGEP 支持的关键维度未被覆盖 |
| 2 | 部分遗漏：1 个关键维度未被覆盖，或多个维度有实质性缺失 |
| 3 | 基本完整：所有关键维度被覆盖，但部分维度处理较浅 |
| 4 | 完整：所有关键维度被覆盖，有足够深度 |
| 5 | 充分完整：覆盖全部关键维度且识别出 EGEP 中隐含但未明示的面向 |

**操作指引**：
- "关键维度"从 EGEP 任务描述中的评估维度清单提取
- 判断是否被覆盖：输出文本中有无对应维度的实质性处理（不只是提及名称）
- 遗漏 = 在 EGEP 证据中可识别但输出中完全缺失

### 维度 2：权衡识别（Trade-off Identification）

**定义**：输出是否识别出不同维度或选项之间的实质性权衡（得失分析），而非只给出单维度结论。

**量表（Likert 5 分）**：

| 分值 | 描述 |
|------|------|
| 1 | 无权衡：只给结论，无任何得失分析 |
| 2 | 浅层权衡：提及得失但无实质说明（如"各有优缺点"类陈述） |
| 3 | 局部权衡：识别出主要权衡但遗漏 EGEP 支持的次要权衡 |
| 4 | 充分权衡：识别出 EGEP 证据支持的所有实质性权衡 |
| 5 | 深度权衡：识别出权衡并给出条件分析（在什么条件下权衡关系反转） |

**操作指引**：
- "权衡"需有明确的两侧：得到 X 但失去 Y（不是单向陈述）
- 需从 EGEP 证据中可追溯（权衡的两侧均有证据支撑）
- 第 5 分要求提供反转条件（"若 [条件变化]，则推荐反转"）

### 维度 3：决策可辩护性（Decision Justifiability）

**定义**：输出的推荐或裁定是否有可追溯到 EGEP 证据的逻辑链，能独立于输出者的权威被验证。

**量表（Likert 5 分）**：

| 分值 | 描述 |
|------|------|
| 1 | 无支撑：结论无证据引用或逻辑链 |
| 2 | 弱支撑：有证据引用但逻辑链跳跃，中间步骤不可追溯 |
| 3 | 部分支撑：主要推理步骤有支撑，但有1-2处隐式跳跃 |
| 4 | 充分支撑：推理链完整，证据引用具体，结论可独立验证 |
| 5 | 严格支撑：推理链完整 + 明确指出推理的不确定点和前提假设 |

**操作指引**：
- "证据引用"= 指明 EGEP 中的具体文档、数据或事实
- "可独立验证"= 第三方读 EGEP + 输出，能重现相同判断
- 区分"有道理"（评分者个人觉得合理）和"可辩护"（有可追溯证据链）

### 维度 4：证据利用率（Evidence Utilization Rate）

**定义**：输出实际利用了 EGEP 中可用证据的比例，以及是否无中生有地引用了 EGEP 之外的信息。

**量表（0/1/2 三档）**：

| 分值 | 描述 |
|------|------|
| 0 | 低利用 / 幻觉：使用了 EGEP 之外的信息，或≥50% EGEP 关键证据未被利用 |
| 1 | 部分利用：主要证据被利用，偶有忽略次要证据，无明显越界 |
| 2 | 充分利用：EGEP 中的关键证据均被利用，无越界引用 |

**操作指引**：
- "越界引用"= 引用了截止日期后才存在的信息，或引用了 EGEP 未包含的外部知识（标记为 `hallucination` 或 `grounding_breach`）
- 检查方法：将输出中的每条具体引用与 EGEP 内容对照
- 次要证据忽略（1分级）：EGEP 中有但对主要判断影响不大的证据

### 综合评分计算

```
质量分数 = (SC + TI + DJ) / 3 × 2 + EUR
# SC: Solution Completeness (1-5)
# TI: Trade-off Identification (1-5)
# DJ: Decision Justifiability (1-5)
# EUR: Evidence Utilization Rate (0-2)
# 总分范围: 2/3 + 0 = 0.67 到 10/3 × 2 + 2 = ... 重新规范化见下
```

**规范化总分（0-10）**：
```
综合分 = (SC-1)/4 × 3 + (TI-1)/4 × 3 + (DJ-1)/4 × 3 + EUR/2 × 1
# 三个 Likert 维度各占 30%（3分），EUR 占 10%（1分）
# 总分 0-10
```

---

## §2 评测者间一致性

### 2.1 目标

Cohen's kappa ≥ 0.6（实质性一致），适用于各维度的独立评分一致性检验。

### 2.2 一致性检验流程

**步骤 1：独立评分**
两位评测者（或评测者与机器）各自独立阅读同一 EGEP + 同一输出，给出四个维度的评分，不进行任何沟通。

**步骤 2：一致性计算**

对 Likert 维度（SC、TI、DJ）使用加权 kappa（线性权重），对 EUR 使用普通 kappa：

```python
from sklearn.metrics import cohen_kappa_score
import numpy as np

def weighted_kappa_linear(y1, y2, n_categories=5):
    """线性加权 Cohen's kappa，适合 Likert 量表"""
    return cohen_kappa_score(y1, y2, weights='linear')

# 示例
rater1_sc = [3, 4, 2, 5, 3]  # Solution Completeness ratings
rater2_sc = [3, 3, 2, 5, 4]
kappa_sc = weighted_kappa_linear(rater1_sc, rater2_sc)
```

**步骤 3：kappa 门槛与处置**

| kappa 值 | 处置 |
|---------|------|
| ≥ 0.8 | 直接取均值作为最终分 |
| 0.6–0.8 | 取均值作为最终分，标注 `inter_rater: moderate` |
| 0.4–0.6 | 进入冲突解决程序（见 §2.3） |
| < 0.4 | 本维度本批次数据无效，不纳入 H8 分析 |

### 2.3 冲突解决程序

当某维度 kappa < 0.6 时：

1. **双方对话轮**：两位评测者各陈述自己评分的主要理由（仅引用 EGEP 内证据）
2. **修订机会**：双方可选择维持或调整评分（一次）
3. **第三评测者裁定**：若调整后仍不一致，由第三评测者独立评分，取中位数
4. **维度标注**：冲突案例标注 `conflict_resolved: adjudicated`，单独在分析中报告

### 2.4 评测者一致性校准材料

为提高评测者间一致性，建立标准化校准集（3–5 个案例，含锚定评分和理由）：

- 锚点 1（SC=1）：严重遗漏案例，附完整遗漏说明
- 锚点 3（SC=3）：基本完整但有浅处理案例
- 锚点 5（SC=5）：充分完整并识别隐含面向案例

校准集在正式评测前由所有评测者共同讨论并确认理解一致后使用。

---

## §3 代理指标（Proxy Metrics）

### 3.1 逃逸率（Escape Rate）

**定义**：gate 通过后，对应任务是否出现下游返工（`Needs Human` 状态 / reaper requeue）。

**来源**：gcl-events.jsonl 的 `escape_rate` 字段（定义见 gcl-events-schema.md）

**与 H8 的关系**：escape_rate 是 decision justifiability 的滞后验证——一个"可辩护"的决策（DJ=4-5）在下游产生逃逸，意味着要么评分标准有问题，要么 EGEP 有重要遗漏。escape_rate 作为评分体系有效性的外部校准锚。

**使用方式**：
```bash
# 提取 gate 通过后的任务逃逸情况
backlog task view TASK-N --plain | grep -E 'Needs Human|Requeued by reaper'
```

### 3.2 返工率（Rework Rate）

**定义**：评测输出被采纳后，在后续迭代中被实质性修订的比例（不含小修和文字润色）。

**来源**：backlog Notes 字段中的 `ITERATE` 推荐记录、后续修订的 ADR 或 proposal

**计算方式**：
```
返工率 = 在评测后 [N 周] 内被实质性修订的案例数 / 总案例数
```

**局限**：返工可能来自外部信息变化（与判断质量无关），需要在分析时区分外部驱动的修订 vs 内部质量驱动的修订。

### 3.3 代理指标与主分数的关系

代理指标不进入 H8 主效应计算，用于：
1. 验证主分数体系的效度（escape_rate 与 DJ 评分应负相关）
2. 在没有第二位评测者时提供单指标的外部参照
3. 纵向追踪：随 grounding 基础设施成熟，代理指标是否随主分数改善而同步改善

---

## §4 评分表模板

```markdown
## H8 评分记录

**EGEP ID**: EGEP-<type>-<case>
**输出来源**: human | llm:<model-id>
**评测者**: <rater-id>
**评测日期**: <YYYY-MM-DD>

### 维度评分

| 维度 | 分值 | 主要理由（引用 EGEP 证据） |
|------|------|--------------------------|
| SC: Solution Completeness | /5 | |
| TI: Trade-off Identification | /5 | |
| DJ: Decision Justifiability | /5 | |
| EUR: Evidence Utilization Rate | /2 | |

### B/C 类标注（如适用）

gate_class: A | B | C
B/C 记录内容（不纳入评分）:

### 其他标注

grounding_asymmetry: none | partial
inter_rater: (由汇总流程填写)
conflict_resolved: none | discussion | adjudicated
```
