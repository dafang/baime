# H8 统计设计：接地受控条件下人机质量差距的假设检验方案

**状态**：H8 评测集设计（Phase 5）
**日期**：2026-06-24
**依赖**：docs/research/h8-scoring-rubric.md（评分体系），h8-evaluation-material-candidates.md（样本池）
**关联**：docs/research/gcl-events-schema.md（gate_actor_type, evidence_independence, grounding_package_id 字段，pending TASK-176）

---

## §1 零假设与备择假设

### 1.1 H8 零假设（H₀）

> 在接地受控条件下（人与机器获得相同内容的等量实世界观测证据包 EGEP），人类输出与机器输出的质量分数分布无显著差异。

形式表述：
```
H₀: median(score_human) = median(score_machine)
    （两侧检验，α = 0.05）
```

**"接地受控"操作定义**：双方使用同一份 EGEP（见 h8-grounding-controlled-operationalization.md §3），且人类评测者的隐性接地外显化程序完成（标注 `grounding_asymmetry: none`）。

### 1.2 备择假设（H₁）

```
H₁: median(score_human) ≠ median(score_machine)
    （两侧，不预设方向）
```

**不预设方向的理由**：
- grounding-infrastructure.md §4.2 指出当前人类在 A 类认知增量中的优势来自 grounding 存量，不是处理机制优势
- 在 EGEP 等量条件下，机器在某些任务类型（如概念推理类）可能高于人类
- H8 首批测量是探索性的，在小样本阶段方向判断不可靠

### 1.3 H8 与 GCL 假设体系的关系

H8 是 grounding-infrastructure.md 中接地基础设施建设的效果测量假设，对应假设体系中的"接地等量条件下质量差距"测量。其上游依赖：
- H6（evidence independence 决定监督质量）：EGEP 设计的理论基础
- H7（gate_actor_type 对 gate 质量的影响）：H8 的操作前身（H7 测量 actor 类型差异，H8 控制 grounding 变量）

---

## §2 检验方法

### 2.1 主检验：置换检验（Permutation Test）

**选择理由**：
- 不假设评分的正态分布（Likert 量表数据非正态）
- 样本量小（首批 N 预计 6-15）时，置换检验比参数检验更可靠
- 可直接对综合分数（0-10 连续量）进行检验，无需离散化

**零分布生成**：
```python
import numpy as np
from itertools import combinations

def permutation_test(human_scores, machine_scores, n_permutations=10000):
    """
    两样本置换检验（两侧）
    检验统计量：两组中位数之差
    """
    observed_diff = np.median(human_scores) - np.median(machine_scores)
    
    combined = np.concatenate([human_scores, machine_scores])
    n_human = len(human_scores)
    
    # 生成零分布
    null_diffs = []
    for _ in range(n_permutations):
        permuted = np.random.permutation(combined)
        diff = np.median(permuted[:n_human]) - np.median(permuted[n_human:])
        null_diffs.append(diff)
    
    # 两侧 p 值
    p_value = np.mean(np.abs(null_diffs) >= np.abs(observed_diff))
    return observed_diff, p_value, null_diffs

# 使用示例
human_scores = [7.2, 6.8, 8.1, 5.9, 7.5, 6.2]   # 示例数据
machine_scores = [6.5, 7.1, 7.8, 6.0, 7.2, 5.8]
diff, p, null_dist = permutation_test(human_scores, machine_scores)
print(f"Observed difference: {diff:.3f}, p = {p:.4f}")
```

**报告要求**：
- 报告观测到的中位数差值（human - machine）
- 报告置换 p 值（n_permutations ≥ 10,000）
- 绘制零分布直方图 + 观测值位置

### 2.2 副检验：Wilcoxon 符号秩检验（Wilcoxon Signed-Rank Test）

**适用条件**：当每个案例有配对设计（同一 EGEP，同一评测任务，人和机器各做一次）时使用。

**选择理由**：
- 配对设计消除案例间差异，提高检验效力
- Wilcoxon 非参数，适合 Likert 衍生的综合分数
- 与置换检验形成互补验证

```python
from scipy import stats

def wilcoxon_test(human_scores, machine_scores):
    """
    Wilcoxon 符号秩检验（配对，两侧）
    假设 human_scores[i] 和 machine_scores[i] 来自同一案例的人机回答
    """
    differences = [h - m for h, m in zip(human_scores, machine_scores)]
    stat, p = stats.wilcoxon(differences, alternative='two-sided')
    return stat, p, differences

stat, p, diffs = wilcoxon_test(human_scores, machine_scores)
print(f"Wilcoxon W = {stat}, p = {p:.4f}")
```

**配对设计要求**：
- 同一案例的人类评测者和机器使用**完全相同的 EGEP**
- 评测顺序随机化（部分人先做，部分机器先做，避免序列效应）
- 评测结果在双方完成后才揭盲（机器输出不影响人类评测）

### 2.3 检验方法选择规则

| 设计类型 | 首选检验 | 辅助检验 |
|---------|---------|---------|
| 配对设计（同案例人机各做一次） | Wilcoxon 符号秩（主） | 置换检验（两独立样本版） |
| 非配对设计（不同案例集） | 置换检验（主） | Mann-Whitney U（辅） |

首批评测推荐配对设计（见 §4 纵向重测）。

---

## §3 最小样本量估计

### 3.1 参数设定

| 参数 | 值 | 来源 |
|------|-----|------|
| 效应量 Cohen's d | 0.5（中等） | 首批保守估计；GCL 研究（H2: ρ=0.87）暗示 grounding 效应可能较大，但 H8 是首次测量 |
| 统计功效（1-β） | 0.8 | 标准功效要求 |
| 显著性水平 α | 0.05（两侧） | H₀ 中定义 |
| 检验类型 | Wilcoxon 符号秩（配对） | §2.2 |

### 3.2 样本量计算

对于 Wilcoxon 符号秩检验，近似等价于 t 检验的配对设计样本量：

```python
from scipy import stats
import numpy as np

def sample_size_paired_wilcoxon(d=0.5, power=0.8, alpha=0.05):
    """
    配对 Wilcoxon 检验的近似样本量估计
    使用正态近似，Wilcoxon 相对效率约为 0.955 × t 检验
    """
    # 先计算配对 t 检验的样本量
    beta = 1 - power
    z_alpha = stats.norm.ppf(1 - alpha/2)  # 两侧
    z_beta = stats.norm.ppf(power)
    
    n_t = ((z_alpha + z_beta) / d) ** 2
    
    # Wilcoxon 的 Pitman 相对效率修正
    # ARE(Wilcoxon vs t) ≈ 0.955 for normal distributions
    # 对非正态更高；保守取 1/0.95 的修正因子
    n_wilcoxon = n_t / 0.95
    
    return int(np.ceil(n_wilcoxon))

n_required = sample_size_paired_wilcoxon(d=0.5, power=0.8, alpha=0.05)
print(f"最小样本量: {n_required} 个配对观测")
# 预期输出: ~34 个配对观测
```

**计算结果**：
- 配对 t 检验（等价基础）：N ≈ 34
- Wilcoxon 修正后：N ≈ 36 个配对观测（即 36 个案例，每个案例人机各做一次）

### 3.3 样本量对首批评测的含义

当前候选集（h8-evaluation-material-candidates.md）有 6 个案例，距目标 36 个有较大缺口。

**分阶段策略**：
- **第 0 批（可行性验证，N=6）**：使用当前 6 个候选案例，验证 EGEP 构造流程、评分体系操作性和评测者间一致性（kappa 目标），不做显著性检验（功效不足）
- **第 1 批（探索性，N=12-15）**：扩展候选集至 15 个，进行探索性分析，报告效应量估计和 90% 置信区间（不报 p 值决策）
- **第 2 批（确认性，N=36）**：达到最小样本量后，执行预注册的 Wilcoxon + 置换检验，报告 H8 主效应

**注意**：预设样本量是最低要求，实际案例数应尽量更多（目标 50+）以提供亚组分析（按任务类型、grounding 成熟度分层）的功效。

---

## §4 纵向重测设计

### 4.1 重测触发条件

H8 的核心预测是：随 grounding 基础设施完善，接地受控条件下的人机质量差距会收窄。因此 H8 不是一次性测量，而是追踪 grounding 基础设施里程碑的纵向实验。

**grounding 里程碑触发器**：

| 里程碑 | 描述 | 预计触发重测时间 |
|--------|------|----------------|
| M1：行为证据格式标准化 | meta-cc 查询结果有标准化 EGEP 格式（behavioral evidence 从 maturity=1 升至 maturity=3） | behavioral grounding infra 完成后 |
| M2：结构证据快照 replay | archguard 历史快照 replay 标准化（structural evidence 从 maturity=2 升至 maturity=3） | archguard snapshot 工程完成后 |
| M3：gcl-events.jsonl schema 扩展 | `grounding_package_id` 字段可用（见 §5，pending TASK-176），实现 EGEP 与 gate 事件的关联 | TASK-176 完成后 |
| M4：评测案例集扩展 | 候选案例达到 36 个（最小样本量） | 语料积累后 |

### 4.2 重测标准

每次重测使用**相同的案例集**和**更新版 EGEP**（包含新类型证据），比较不同 grounding 成熟度下的人机差距。

**比较维度**：
- 效应量 d 的绝对值：随里程碑是否缩小（H8 的核心预测）
- 各评分维度的变化：哪个维度（SC/TI/DJ/EUR）对 grounding 改善最敏感
- 任务类型分层：架构对比类 vs 问题定义审查类的差距变化是否不同

### 4.3 "差距收窄"判断标准

**差距收窄**（grounding 基础设施有效的证据）：
```
在连续两个 grounding 里程碑之间，效应量 |d| 的 90% CI 上界 < 前次测量的 90% CI 下界
```

这是保守标准（需要置信区间不重叠），避免在小样本下误判趋势。

**差距不收窄**（grounding 基础设施效果不显著）：
```
连续两个里程碑后，|d| 的点估计变化 < 0.1
```

当不收窄时，需要区分两种解释：
1. grounding 基础设施设计有效但质量差距本来不大（H8 effect 不存在）
2. grounding 基础设施设计有效但当前 EGEP 未成功控制人类隐性 grounding（测量问题）

区分方法：检查 `grounding_asymmetry: partial` 的案例与 `grounding_asymmetry: none` 的案例是否有系统性差异。

---

## §5 gcl-events.jsonl Schema 依赖（pending TASK-176）

### 5.1 需要的新字段

H8 统计分析依赖 gcl-events.jsonl 中尚未定义的字段（当前 schema 见 gcl-events-schema.md）：

| 字段名 | 类型 | 含义 | 需要 TASK-176 的哪个子任务 |
|--------|------|------|--------------------------|
| `grounding_package_id` | string \| null | EGEP 文件的唯一标识，将 gate 事件与 EGEP 关联 | TASK-176 schema 扩展 |
| `h8_quality_score` | float \| null | H8 评分体系下该 gate 输出的综合质量分（0-10） | TASK-176 schema 扩展 + h8-scoring-rubric.md |
| `h8_sc` | int \| null | Solution Completeness 分（1-5） | TASK-176 schema 扩展 |
| `h8_ti` | int \| null | Trade-off Identification 分（1-5） | TASK-176 schema 扩展 |
| `h8_dj` | int \| null | Decision Justifiability 分（1-5） | TASK-176 schema 扩展 |
| `h8_eur` | int \| null | Evidence Utilization Rate 分（0-2） | TASK-176 schema 扩展 |
| `inter_rater_kappa` | float \| null | 该评测实例的评测者间 kappa | TASK-176 schema 扩展 |

**当前状态**：以上字段均标注为 `pending TASK-176`。H8 统计分析的启动不依赖这些字段（可以独立维护 h8-results.jsonl），但在 TASK-176 完成后应合并进统一的 gcl-events.jsonl。

### 5.2 现有字段的 H8 用途

当前 gcl-events.jsonl 中已有的字段可直接用于 H8 分析：

| 字段 | H8 用途 |
|------|---------|
| `gate_actor_type` | 分组变量（human vs llm） |
| `evidence_independence` | 筛选 grounding 等量案例（只分析 evidence_independence="high" 的 gate） |
| `escape_rate` | 外部效度验证：h8_quality_score 与 escape_rate 应负相关 |
| `task_id` | 关联 backlog task 历史，提取后续返工率 |

---

## §6 分析报告模板

每次 H8 测量周期结束后，生成以下报告结构：

```markdown
# H8 测量报告 — [测量周期标识]

**测量日期**: YYYY-MM-DD
**grounding 里程碑**: M0（无行为证据）/ M1（行为证据标准化）/ ...
**样本量**: N = <案例数>，人机各 <N> 个配对观测

## 汇总结果

| 指标 | 人类 | 机器 | 差值 (H-M) |
|------|------|------|-----------|
| 综合分中位数 | | | |
| SC 中位数 | | | |
| TI 中位数 | | | |
| DJ 中位数 | | | |
| EUR 中位数 | | | |

## 显著性检验

- 置换检验（两侧）：observed diff = ?, p = ?
- Wilcoxon 符号秩：W = ?, p = ?
- 结论：H₀ 拒绝 / 未拒绝（α=0.05）

## 效应量

- Cohen's d = ?（基于综合分）
- 90% CI = [?, ?]（Bootstrap，B=1000）

## 评测者间一致性

- 整体 kappa = ?（目标 ≥ 0.6）
- 各维度 kappa: SC=?, TI=?, DJ=?, EUR=?

## 与前次测量比较（纵向）

- 前次效应量: d = ?
- 本次效应量: d = ?
- 差距收窄判断: 是 / 否 / 不可判断（样本量不足）

## 异常记录

- grounding_asymmetry: partial 案例数及其平均分差
- inter_rater kappa < 0.6 的案例及处置
```
