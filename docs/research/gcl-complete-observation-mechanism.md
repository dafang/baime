# GCL 完整观测机制：讨论记录

**日期**：2026-06-23
**背景**：TASK-152 完成首批 GCL self-report 分析后，讨论如何将其升级为长期、可重用的观测机制
**依赖**：docs/research/gcl-definition.md, gcl-synthesis.md, gcl-selfReport-analysis.md

---

## 1. 目标校准：GCL 是"监督是否实质有效"的代理量，不只是研究指标

当前 GCL 研究的动机（gcl-definition.md §概念动机）已指出：随着 loop-backlog 自治深化，人类角色从 throughput 贡献者退为 gate 判断者，瓶颈从"写得多快"变成"判断时需要理解多少"。

外部文献给出了独立的收敛证据，把 GCL 的工程优先级从"研究兴趣"提升到**系统安全属性**：

- **Approval fatigue / YOLO mode**（AI agent 治理文献，2025）：同一个人每天批准成百上千个 agent 动作，human-in-the-loop 控制在认知超载下退化为橡皮图章。GCL 高是 gate 退化的早期信号。
- **EU AI Act（2026 年 8 月截止）**：把"可证明的人类监督"变成法律要求。GCL 是"监督是否实质性"的候选可测指标。
- **Automation bias**（系统性过度信任自动判断，人在矛盾证据下仍 follow AI）：这是 gate 判断者失效的最常见机制。

**含义**：GCL 不只是研究数字——它的工程意义是检测"人类监督是否仍在发挥真实作用"。这一认定应明确写入研究动机，因为它改变后续所有设计的取舍优先级。

---

## 2. 当前机制的四支柱评估

一个完整的观测机制需要：**仪器化 → 持久化（时间序列）→ 可复现分析 → 闭环反馈**。

| 支柱 | 现状（2026-06-23） | 缺口 |
|------|------------------|------|
| **A 仪器化** | premise-ledger 已注入 plan gate，自动写 `GCL-self-report: E=n C=n H=n` | 只覆盖 plan gate；proposal / merge / epic-evaluate / DoD-eval 无仪器；无可靠性采样（单 rater、单次） |
| **B 持久化** | 数据散在各 task 的 Notes 里 | 无结构化事件存储、无 schema、无 append-only 日志；每次分析需全盘 `grep` 重建 |
| **C 分析** | TASK-152 一次性手工任务 | 不可复现；未按任务类型分层；无可靠性统计；无趋势检测 |
| **D 反馈** | 无 | GCL 测量不影响任何 gate 设计；无 GCL 漂移告警；测了等于没测 |

**结论**：仪器化做了一半，后三个支柱基本是空的。TASK-152 是一次性快照，不是可持续机制。

---

## 3. 测量效度问题：LLM self-report 的已知偏差

当前 H 值由做 gate 裁决的**同一个 LLM reviewer 自报**。这是 LLM-as-judge 文献中已命名的缺陷：

- **自不一致性（"Rating Roulette"，EMNLP 2025）**：同一 LLM 评分跨多次运行达不到 inter-rater 0.8 阈值，评分高度易变。当前每个 gate 只采**一次、一个 rater**，无任何方差估计。
- **Self-enhancement bias**：模型倾向于美化自己的输出。映射到 GCL：reviewer 可能**系统性低报 H**——承认自己依赖了未外化的隐性知识，等于承认判断不够扎实。

**对 TASK-152 的影响**：`delta_H = −1.46`（基线系统性高估 H）有两个竞争解释：
1. 新任务规模更小（bug fix 批次，E/C 天然低）——你今天提出的解释，正确但不完整
2. **Self-enhancement bias**（LLM reviewer 系统性低报 H）

当前分析无法区分这两者，因为没有 ground truth、没有第二个 rater。**没有可靠性层的自报数据，方向性结论可信，定量结论不可信。**

---

## 4. 设计张力：GCL 最小化 ≠ 监督质量最大化，且人类不是天然基准

### 4.1 GCL 目标函数的两侧约束

当前 synthesis 的工程结论是"Scope− 是压缩 GCL 的稳定杠杆"，方向上没错。但 cognitive forcing functions 研究（Buçinca et al., Harvard 2021）揭示了反向风险：把每个 gate 都 Scope− 到 H=0，gate 变成纯机械 shell-command 检查，人类完全不需要理解就能批准——这正是 rubber stamp 的定义。

**正确目标函数不是 `minimize(GCL)`，而是维持 GCL 在两侧有界的区间。** 配对信号是 **gate escape rate**（gate 通过后任务是否需要 Needs Human / reaper requeue），已存在于 backlog，可机械提取，不需要新仪器。

### 4.2 人类在 gate 中的价值：三变量拆解

"人类监督"在工程语境中被过度统一化了。实际上它混入了性质不同的三类来源，必须分开处理：

#### A. Epistemic contribution（认知增量）：人是否提供了系统没有的信息？

这只在以下情况成立：
- 人拥有**尚未外化**的上下文（客户关系、近期事故、模块债务）
- 人能识别 evidence channel 的缺失（"这个 log 不可信"）
- 人能提供真实偏好样本

关键：这不是人类本质优势，而是**当前信息架构不完备**的结果。随着 CRM、incident log、decision records、architecture registry 的建立，这部分价值会持续下降。长期正确方向是把私有上下文外化进 evidence channels，而不是永久依赖人脑。

**对 GCL 的含义**：高 H 往往不是"人很有价值"，而是"系统没有把必要上下文外化"。H 是 context externalization gap 的代理量，不是人类洞察力的代理量。

**进一步：A 不为开放/insight 任务保留例外。** 容易把 A 退守到"事实判断可以交给机器，但开放性洞察、品味、判断仍然需要人"。这条退守线也站不住。**从信息处理的视角，人与机器（含大模型）的处理机制没有本质差异**——同样是在表征上做模式识别、压缩、外推、组合。当前可观察的主要差异不在"机制"，而在**对真实世界的持续观察**（grounding）：人长期、连续、多模态地接触产品、用户、事故、市场，积累了尚未进入任何 evidence channel 的观察。这正是 A 的真实内容。而 grounding 是可以被工程化弥合的（持续观测管线、遥测、回放、外部数据接入——见 cc-actor-network.md §4.4 的三类接地锚点），中长期这一差异也会收窄。

因此 insight 等开放任务同样可以、且应当逐步交给充分接地的机器信息处理机制。人在开放任务上的暂时优势，是 grounding 存量的优势，不是处理机制的优势；它随接地基础设施建设而递减，而非永久保留。这把"为人保留的 gate"进一步收窄到 **B（偏好来源）和 C（制度责任）**——这两者本就不是信息处理优劣问题。

#### B. Preference anchoring（偏好锚定）：人是否代表目标函数来源？

"是否值得为了速度接受 regression 风险"可以拆成两部分：
```
事实判断：风险多大、概率多少、恢复成本多少  →  LLM + telemetry + incident history 可能更强
偏好判断：这个风险是否值得接受            →  偏好本身来自组织、人、法律责任主体
```

人在这里的价值不是"更能算清 trade-off"，而是：**当目标函数没有完全形式化时，人作为偏好/责任主体提供目标函数样本。** 一旦组织偏好已充分编码成 policy、risk budget、SLO、contract terms，LLM 就可以执行，未必需要每次问人。

这类 gate 应命名为 **preference source / risk budget authority**，不应被伪装成"人类判断更准"。

#### C. Accountability / legitimacy（问责与合法性）：当前制度是否要求人承担后果？

这完全不是认知价值，是**制度约束**。它回答的是：谁有权批准、谁对后果负责、谁能被追问、谁能修改政策。LLM 可能在 epistemic quality 上更强，但在当前制度下不能独立成为责任主体——不是因为技术做不到，而是因为制度尚未把责任主体资格赋予它。

这影响的是"哪些 gate 必须有人签字"，不应被混入"监督质量"指标。

### 4.3 人类默认不是更强的 reviewer

> **人类监督默认不是优势，而是成本、瓶颈和噪声源。只有当人提供未外化上下文（A）、偏好样本（B）或制度授权（C）时，人才有增量价值。除此之外，LLM ensemble + 独立证据通道 + escape-rate 校准，可能是更强的监督机制。**

这对"系统设计层面的 meta-reviewer"尤其成立：当 LLM 能访问全量历史 gate 事件、escape/rework 数据、多版本机制变更记录、外部研究，让一个疲劳的人类定期"反思监督系统是否退化"，未必比 LLM ensemble 更可靠。人的可能作用只是最后选择采用哪个制度设计，因为这涉及 B 和 C，而不是因为人更会设计。

### 4.4 四层 gate 架构（机制设计方向）

基于上述拆解，gate 设计的长期方向是按性质分层：

| Gate 类型 | 判断主体 | 何时触发人 |
|-----------|---------|-----------|
| **Routine gates** | Tools + tests + LLM ensemble + historical calibration | 不触发；human 不在 critical path |
| **Ambiguous preference gates** | LLM 准备选项 + 人提供偏好/risk budget | 目标函数未完全形式化，需采样偏好（B） |
| **High-accountability gates** | Automated evidence pack + 人授权签字 | 制度/法律要求责任主体签字（C） |
| **Meta-governance** | LLM/ensemble 提议机制变更，人/组织批准目标函数修改 | 系统演化方向涉及 B + C |

---

## 5. 研究假设更新

### H5：GCL 存在监督有效性下界

> **H5**：当 GCL 被 Scope− 压得过低（特别是 H=0、C=0 的纯机械 gate），gate 退化为 rubber stamp，gate escape rate 上升。

**可证伪规则**：GCL 均值低于某阈值 θ 的 gate 批次，其 escape rate 显著高于 GCL 在 [θ, 2θ] 区间的批次。待 gcl-events.jsonl + escape_rate 字段（TASK-176 增量 2）建立后实测。

### H6：监督有效性主要取决于 evidence independence，而非 gate actor 是否为人类

> **H6**：一个 gate 的监督质量，由其证据来源与被监督系统的信息独立程度决定——而非由 gate actor 是否为人类决定。

在这个框架下，**automation bias** 不再是"人类被 AI 欺骗"的窄问题，而是**监督通道和被监督系统的信息源发生耦合**的一般性失效模式——无论 gate actor 是人还是机器，只要信息源不独立，bias 就会出现。

| gate 设计 | evidence independence | 预期监督质量 |
|-----------|----------------------|------------|
| 人类读 agent summary，无独立验证 | 低（信息源耦合） | 低 |
| 人类运行独立测试，读 raw log | 高 | 高 |
| Automated gate，独立模型验证，独立 log channel | 高 | 高 |
| Automated gate，同模型自报，无独立验证 | 低 | 低 |

**可证伪规则**：在控制 GCL 总量的情况下，evidence_independence 分类（高/低）对 escape rate 有显著预测力。需在 gcl-events.jsonl schema 中增加 `evidence_independence` 字段。

### H7：在大多数 routine engineering gates 中，human-in-the-loop 降低的不是风险，而是系统吞吐；监督质量主要来自 evidence independence，而不是 human presence

> **H7**：Routine engineering gate 的监督质量与 gate actor 是否为人类无关；human presence 的主要效果是增加延迟（成本），而非提高信号准确性（效益）。监督质量的主要预测变量是 evidence_independence，与 §4.2 的三变量拆解一致。

**可证伪规则**：在控制 evidence_independence 的情况下，human vs automated gate actor 对 escape rate 无显著差异（routine gate 子集）。需要将 `gate_actor_type`（human/llm/hybrid/tool）加入 gcl-events.jsonl schema，配合 H6 的 `evidence_independence` 字段联合检验。

### H8：开放/insight 任务上的人机差距由 grounding 解释，而非处理机制本质差异

> **H8**：在开放性 / insight 任务（设计取舍、架构判断、产品品味、问题定义）上，人与机器信息处理机制的质量差距，主要由对真实世界的持续观察（grounding）存量解释，而非由处理机制的本质差异解释。控制 grounding 接入后，差距不显著；且随接地基础设施建设，残差差距随时间收窄。

**含义**：H7 把"无差异"结论建立在 routine gate 上；H8 把它推广到开放任务——条件是 grounding 被显式控制/补齐。两者合起来意味着：为人保留的判断点最终只剩 B（偏好来源）和 C（制度责任），而非任何"人在信息处理上更强"的类别。

**可证伪规则**：在控制 grounding 接入（同等真实世界观测证据包）的前提下，human vs machine 在 insight 任务上的产出质量（由独立评审 + 下游 escape/rework 度量）无显著差异；并且在两个时间点之间，随 grounding 管线扩展，machine 侧的残差差距显著缩小。需要一个带 grounding 接入标注的 insight-task 评测集；这是 cc-actor-network.md §6 "接地开发加速层"实验的自然延伸。

### 对 GCL 框架定义的修订

当前 gcl-definition.md 隐含"human understanding is the scarce gold-standard resource"。应改为：

> **gate actor 的有效裁决需要多少未外化上下文恢复成本。**

其中 gate actor 可以是：LLM、LLM ensemble、tooling、human、hybrid。分三组独立记录：

```
1. epistemic independence（判断是否更准）
   - evidence source diversity
   - judge diversity / inter-rater agreement
   - calibration quality（escape rate predictive power）

2. preference authority（目标函数来源）
   - policy encoded? risk budget encoded?
   - preference sample needed?
   - exception approval needed?

3. accountability requirement（制度约束）
   - no human signoff needed
   - owner signoff needed
   - compliance/legal/product signoff needed
```

---

## 6. 落地增量规划

按价值/成本排序的三个增量：

### 增量 1 — 结构化日志 + 可复现分析（最高性价比）
- 建立 `docs/research/gcl-events.jsonl` + `scripts/gcl-report.sh`
- 把 premise-ledger 自报写入 jsonl（可从现有 Notes 回填历史 13 条）
- 立刻解决"分层问题"和"不可复现问题"
- 无需改动任何 gate 流程

### 增量 2 — 可靠性采样 + escape rate 配对
- 10% gate 的多次/多模型采样，建立 H 的误差棒
- 把 escape rate 加入 gcl-events.jsonl（post-hoc，从 task 状态历史提取）
- 把数据从"方向可信"升级到"定量可信"
- 引入 H5 验证实验

### 增量 3 — 闭环告警 + 全 gate 类型覆盖
- 扩展 premise-ledger 到 proposal / epic-evaluate gate
- 定期分析 + GCL 漂移告警
- GCL-vs-escape-rate 前沿监控
- 真正意义上的"长期观测机制"

---

## 7. 外部文献引用

| 来源 | 核心贡献 | 关联 |
|------|---------|------|
| Buçinca et al., Harvard 2021 — [Cognitive Forcing Functions Can Reduce Overreliance on AI](https://arxiv.org/abs/2102.09692) | 增加认知摩擦反而降低 overreliance；Scope− 过度会变橡皮图章 | §4 设计张力 |
| [Human oversight fails first in AI agent governance](https://nhimg.org/articles/human-oversight-fails-first-in-ai-agent-governance/) | Approval fatigue / YOLO mode 的量化证据 | §1 目标校准 |
| [EDPS TechDispatch #2/2025 — EU AI Act 人类监督](https://www.edps.europa.eu/data-protection/our-work/publications/techdispatch/2025-09-23-techdispatch-22025-human-oversight-automated-making_en) | 可证明人类监督的法律要求（2026-08） | §1 目标校准 |
| [Automation bias in human–AI collaboration (AI & SOCIETY, 2025)](https://link.springer.com/article/10.1007/s00146-025-02422-7) | Automation bias 机制与缓解方式 | §4 设计张力 |
| Rating Roulette — [Self-Inconsistency in LLM-As-A-Judge](https://arxiv.org/pdf/2510.27106) | 同一 LLM 跨运行一致性达不到 0.8 | §3 效度问题 |
| [LLM-as-a-judge survey (ScienceDirect 2025)](https://www.sciencedirect.com/science/article/pii/S2666675825004564) | Position/verbosity/self-enhancement bias | §3 效度问题 |
| [Measuring Cognitive Load of Software Developers (ICPC 2019)](https://kleinnerfarias.github.io/pdf/articles/icpc-2019.pdf) | 软件工程认知负载测量综述 | 方法论背景 |
| [MIT Sloan: AI Explainability — How to Avoid Rubber-Stamping Recommendations](https://sloanreview.mit.edu/article/ai-explainability-how-to-avoid-rubber-stamping-recommendations/) | 管理实践层面命名 rubber stamp 风险；450 名临床医生实验：AI 辅助下诊断准确率从 73% 降至 61.7%（Dietz et al. 2025）；是 H5 下界"gate 退化"的最新实证 | §3 效度问题 / §4 设计张力 |
| [International AI Safety Report 2026](https://arxiv.org/pdf/2602.21012) | 将 rubber stamp / approval fatigue 列为 AI 安全报告级别的系统性风险；确认 GCL 观测的优先级从"研究兴趣"提升到"系统安全属性" | §1 目标校准 |
| [Automated Self-Testing as a Quality Gate (arxiv 2603.15676)](https://arxiv.org/html/2603.15676v1) | evidence coverage 是最重要的严重回归判别器；PROMOTE/HOLD/ROLLBACK 决策架构与 verifyDod 结构同构；LLM 应用发布层面的 evidence-driven gate 先例 | §6 落地增量规划 |
| [Beyond Final Code: Process-Oriented Error Analysis of Software Development Agents (arxiv 2503.12374)](https://arxiv.org/pdf/2503.12374) | 分析 agent **实际执行过程**（而非最终产出），识别过程层错误模式；meta-cc session digest 方案的直接学术对应物 | §2 四支柱评估 / §6 落地增量 |
