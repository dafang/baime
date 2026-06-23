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

## 4. 最关键的设计张力：GCL 最小化 ≠ 监督质量最大化

这是当前研究框架中缺失的一块。

当前 gcl-synthesis.md 的工程结论是"Scope−（收窄 gate 判断范围）是压缩 GCL 的稳定杠杆"，方向上没错。但 **cognitive forcing functions** 研究（Buçinca et al., Harvard 2021）揭示了反向风险：

> 减少 overreliance 最有效的 gate 设计，恰恰是那些**增加**而非减少认知摩擦的设计（checklist、diagnostic time-out、强制排除备选）。

**对 BAIME 的直接映射**：如果把每个 gate 都 Scope− 到 H=0，gate 变成纯机械 shell-command 检查——人类完全不需要理解就能批准，这正是 automation bias / 橡皮图章的定义。GCL 低到极致，监督质量可能崩溃。

**正确目标函数不是 `minimize(GCL)`，而是**：

> GCL 低到人类可持续承受，但高到仍强迫人类对真正重要的决策保持分析性参与。

### 配对指标：Gate Escape Rate

GCL 必须与一个**监督质量信号**配对，否则无法区分"GCL 下降是好事还是坏事"。最现成的配对信号：

**Gate escape rate**：一个 gate 通过的任务，后续是否需要返工 / 升级 Needs Human / 被 reaper 回收？

- GCL 下降 + escape rate 不变或下降 → gate 设计改进（任务更自包含）
- GCL 下降 + escape rate 上升 → 监督退化（gate 收窄过度，变橡皮图章）

这个信号已存在于 backlog（Basic: Needs Human / reaper 记录），可以机械提取，不需要新仪器。

### 新假设 H5

> **H5（待验证）**：存在 GCL 的监督有效性下界。当 gate 的 GCL 降到某阈值以下（特别是 H=0 + C=0），gate escape rate 会上升，表明人类监督实质性已退化。

---

## 5. 完整机制架构

### 支柱 A — 仪器化扩展

- 把 premise-ledger 自报扩展到所有 gate 类型（proposal / merge / epic-evaluate），不止 plan gate
- 引入**可靠性采样**：对一小比例 gate（约 10%），让 reviewer 跑多次或换模型跑一次，记录 H 的 intra-rater / inter-rater 方差
- 在 self-report 格式中增加 `task_kind` 标注（bug-fix / feature / epic-decomp / doc-only）

### 支柱 B — 结构化事件日志

取代数据散在 Notes 里的现状，每个 gate 事件 append 一行到 `docs/research/gcl-events.jsonl`：

```json
{
  "task_id": "TASK-170",
  "gate_type": "plan",
  "task_kind": "bug-fix",
  "timestamp": "2026-06-23T15:42:00Z",
  "E": 8, "C": 1, "H": 0,
  "GCL": 9,
  "reviewer_model": "claude-sonnet-4-6",
  "sample_run_id": null,
  "premise_lines": ["[E] validate-plugin.sh DoD: ...", "[C] refs SKILL.md: ..."]
}
```

`task_kind` 字段使分层分析变为一次 `group by`，无需事后追溯。

### 支柱 C — 可复现分析脚本

`scripts/gcl-report.sh`：随时运行，输出当前截面：

- 按 gate_type × task_kind 的分层统计（E/C/H 均值、delta_H）
- 可靠性方差（如果有多次采样）
- 时序趋势（滚动窗口 30 天 vs 全量）
- GCL vs escape rate 对照表

### 支柱 D — 闭环反馈

- 定期（通过 `/schedule` 或 loop-backlog heartbeat）自动跑 `gcl-report.sh`
- GCL 漂移超阈值时触发告警（写入 backlog 日志或 PushNotification）
- 高 H gate 类型自动成为"Scope− 或 Artifact+ 候选"的输入

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
