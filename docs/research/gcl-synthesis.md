# GCL 综合报告：H2/H4 裁定与方向回灌

**状态**：研究总结（TASK-150 Phase 6 输出）；2026-06-24 增补 H10 及两段制框架
**日期**：2026-06-22（正文）／2026-06-24（H10 节、两段制框架修订、discovery-H 三分类）
**依赖**：docs/research/gcl-definition.md, gcl-corpus.md, gcl-baseline.md, gcl-drivers.md, gcl-intervention.md, gcl-selfReport-analysis.md（附录 A–G）

---

## 核心裁定

| 假设 | 裁定 | ρ / 效果 | p 值 | 置信度 |
|------|------|---------|------|--------|
| **H2**: GCL 与耦合度正相关 | **H2 confirmed** | Spearman ρ=0.87 | p=0.001（单尾） | 高（N=9 任务，可机械复现） |
| **H4**: 隐性项不随 artifact 增加而缩小 | **H4 null** | Scope− 效果稳定（100%），Artifact+ 效果依隐性项类型而异（33%–100%） | N/A（方向性预测） | 中（N=3 事件，[directional-prediction]） |

---

## H2 详细裁定

**H2 confirmed**

耦合代理（跨任务引用数 + git 变更文件数）与跨界 GCL 均值之间存在强正相关（Spearman ρ=0.87，p=0.001，N=9）。在当前 BAIME 语料中，该关系成立。

**工程含义**：
- 降低任务耦合是压缩 C 分量（跨界 GCL）的主要杠杆
- 更自包含的 task 设计（内联关键背景、明确接缝定义）可直接降低 gate 负载
- 父任务的 acceptance gate 应在 child task 创建时就内联，而不是要求 gate 判断者临时查阅父任务

**局限**：N=9，两日窗口，结论方向可信但规模有限。

---

## H4 详细裁定

**H4 null（细化）**

严格 H4 confirmed 条件（Artifact+ ≤10%）未满足：对于可文档化规则类隐性项，Artifact+ 可消除 100% 的 H；对于判断性/结构性隐性项，Artifact+ 效果降至 33%–67%，而 Scope− 在所有类型中均达到 100%。

**工程含义**：
- §7.3 方向（"压缩表面积优于恢复理解"）**不需要整体回退**
- 细化建议：区分隐性项类型
  - **规则类**（可文档化规则、判断标准）：Artifact+ 有效，先外化再 Scope−
  - **判断类/结构类**（整体评估框架、演化中的系统策略）：Artifact+ 效果受限，Scope− 是主要手段
- **H4 的枢轴地位保留**：对于判断类隐性项，"压缩表面积优于恢复理解"的建议仍成立，不回退

**局限**：N=3 事件，所有反事实标注为 [directional-prediction, needs validation]，结论需后续 session trace 数据验证。

---

## GCL 基线关键数据

（来源：gcl-baseline.md，N=20 gate events）

- **GCL 总量均值**：14.55（std=6.51，范围 5–29）
- **E 分量**：均值 8.35（占 57%）——主导分量
- **C 分量**：均值 4.50（占 31%）
- **H 分量**：均值 1.70（占 12%）——最小但最难降低
- **dod-eval gate 的 GCL = 5.0**：验证了 gate 收窄的效果（收窄后 GCL 仅为整体均值的 34%）

---

## 对 proposal-situational-awareness.md 的影响

鉴于 H4 null（非 refuted），§7.3 工程方向不需要回退，但需细化：

1. **situational-awareness 工具的使命设定**需要修正，见下方更新说明
2. **Artifact+ 作为辅助工具**：针对规则类隐性项，增加 artifact（如 `docs/ARCHITECTURE.md` 记录系统不变量和决策准则）有效，应作为 Scope− 的补充
3. **Scope− 是核心杠杆**：收窄 gate 判断范围（更强的 DoD 机械验证、更窄的接受标准）是稳定降低所有类型 GCL 的策略

**已更新**：见 docs/proposals/proposal-situational-awareness.md（§使命更新脚注）

---

## GCL-self-report 首批验证结果（TASK-152）

**已完成**：TASK-152 收集了 TASK-151 部署后的首批 13 个 premise-ledger 自报事件，与 gcl-corpus.md 基线进行了系统比对。详见 docs/research/gcl-selfReport-analysis.md。

**关键发现**：
- **偏差方向**：所有 13 个事件的 delta_H 均为负值（均值 −1.46），估算基线系统性高估了 H。部分原因是新任务规模更小（E: 6.31 vs 基线 12.3），自然产生更少隐性前提。
- **H4 动态**：H=0 的任务均为"全 DoD 机械可验证"任务，H=1 的任务均包含主观阈值判断——与 H4 细化裁定（规则类 H 可被 artifact 外化，判断类 H 持续存在）一致。
- **H4 局限**：观测期内 artifact 覆盖未变化（恒定 6 个 gcl-research 文件），无法通过 artifact 增量验证 H4。

## 框架修订：GCL 的服务目标重构（2026-06-23）

**Human oversight 不应被当作天然基准；它只是当前治理结构中的一种 gate actor。**

GCL 最终要服务的不是"保护人类监督的地位"，而是衡量：**一个 gate 是否以可持续成本产生了足够独立、可追责、可校准的监督信号。**

在这个框架下，"降低 GCL"和"提升监督质量"是可以解耦的工程变量。最优 gate 设计是在 **evidence independence**（监督证据与被监督系统信息源的独立程度）最大化的前提下，把 GCL 维持在人类可持续参与的区间——而不是无限压低 GCL。

Automation bias 也因此从"人类被 AI 欺骗"的窄问题，扩展为**监督通道和被监督系统的信息源发生耦合**的一般性失效模式。无论 gate actor 是人还是机器，只要证据源不独立，这种失效就会出现。

"人类监督"在工程语境中实际包含性质不同的三类价值，必须分开处理（详见 docs/research/gcl-complete-observation-mechanism.md §4.2）：
- **A. Epistemic contribution**：人提供了系统尚未外化的上下文——这是 **context externalization gap** 的代理量，不是人类洞察力本质优势，随着 decision records / incident log 建设而下降。**且这条不为开放/insight 任务保留例外**：从信息处理视角，人与机器（含大模型）的处理机制无本质差异，当前主要差异在对真实世界的持续观察（grounding），而 grounding 可被工程化弥合，中长期收窄——所以 insight 等开放任务同样可逐步交给充分接地的机器（H8）
- **B. Preference anchoring**：目标函数未完全形式化时，人作为偏好/责任主体提供样本
- **C. Accountability / legitimacy**：当前制度要求人承担后果——纯制度约束，与认知质量无关

**结论**：人类默认不是更强的 reviewer；只有当 A/B/C 有增量价值时才触发人类 gate。除此之外，LLM ensemble + 独立证据通道 + escape-rate 校准可能是更强的监督机制。

见 docs/research/gcl-complete-observation-mechanism.md §4、§5 的完整论述与 H5 / H6 / H7 / H8 表述。

---

## 新增假设

### H5：GCL 存在监督有效性下界

> 当 GCL 被 Scope− 压得过低（H=0、C=0），gate 退化为 rubber stamp，escape rate 上升。

**状态**：待验证。需 gcl-events.jsonl + escape_rate 字段（TASK-176 增量 2）建立后实测。

### H6：监督有效性主要取决于 evidence independence，而非 gate actor 是否为人类

> 一个 gate 的监督质量，由其证据来源与被监督系统的信息独立程度决定。人类 gate 如果只消费 agent summary，可能比具备独立测试、独立模型、独立日志通道的 automated gate 监督质量更低。

**状态**：待验证。需 gcl-events.jsonl 增加 `evidence_independence` 字段后实测。

### H7：在大多数 routine engineering gates 中，human-in-the-loop 降低的不是风险，而是系统吞吐

> Routine engineering gate 的监督质量与 gate actor 是否为人类无关；human presence 的主要效果是增加延迟（成本），而非提高信号准确性（效益）。监督质量的主要预测变量是 evidence_independence，与三变量拆解（A/B/C）一致。

**可证伪规则**：在控制 evidence_independence 的情况下，human vs automated gate actor 对 escape rate 无显著差异（routine gate 子集）。需将 `gate_actor_type`（human/llm/hybrid/tool）加入 gcl-events.jsonl schema，配合 H6 的 `evidence_independence` 字段联合检验。

**状态**：待验证。需 gcl-events.jsonl 增加 `gate_actor_type` 字段后实测（TASK-176）。

### H8：开放/insight 任务上的人机差距由 grounding 解释，而非处理机制本质差异

> 在开放性 / insight 任务（设计取舍、架构判断、产品品味、问题定义）上，人与机器信息处理机制的质量差距，主要由对真实世界的持续观察（grounding）存量解释，而非处理机制本质差异。控制 grounding 接入后差距不显著；随接地基础设施建设，残差差距随时间收窄。

H7 在 routine gate 上确立"无差异"，H8 在 grounding 受控的前提下把它推广到开放任务。两者合起来：为人保留的判断点最终只剩 B（偏好来源）和 C（制度责任），而非任何"人在信息处理上更强"的类别。

**状态**：待验证。需带 grounding 接入标注的 insight-task 评测集；是 cc-actor-network.md §6 "接地开发加速层"实验的延伸。

### H10：低成本可回退 regime 下，监督价值主要由后验发现循环效率决定，而非先验 gate 理解负载

> 当执行廉价且可回退时，系统的监督质量主要由**后验发现循环**（MTTD、MTTR、discovery-H recall、每循环成本）决定，而非先验 gate 的 GCL 高低。先验 gate 唯一不可替代的职责是识别"回退本身成本高昂"的子集（不可逆 / 高 blast-radius），其余监督资源应投入后验循环的可观测性建设。

**动机**：观察到的开发者行为（见 gcl-selfReport-analysis.md 附录 A–G）揭示了现有 GCL 框架的测量位置错误：

1. **先验判断在 task 创建前已完成**。开发者在 chat 阶段已完成 goal/cost/benefit/risk 的高认知负载判断，并经过筛选；到 proposal/plan gate 触发时，评的是已被上游预批准的决定。先验 GCL 低因此可能反映的是"硬判断已完成"而非"任务简单"或"LLM 低估"。

2. **低成本可回退 regime 下，薄先验 gate 是理性设计**。执行把 H 前提转化为 E 前提（H9 机制），在回退廉价时，烧认知在先验 gate 的高-H 推理上是负收益的。

3. **设计阶段不可预见的不完善（discovery-H）无法被先验 gate 拦截**。按定义，discovery-H 只在执行后才变成 E——运行任务、读 git diff、读测试结果，是把 discovery-H 外化为可观测信号的唯一路径。先验 gate 不管 GCL 多高，都无法发现尚未执行的行为。

**H4 的三分类修订**：原 H4 把 H 分为 rule-H 和 judgment-H 两类，这是先验 gate 视角的分类。加入执行维度后需增加第三类：

| H 类型 | 来源 | 唯一有效干预 | 先验 gate 可拦截？ |
|--------|------|------------|-----------------|
| **rule-H** | 系统不变量、可文档化规则 | Artifact+ | 是 |
| **judgment-H** | 质量基准、阈值判断 | 人类 / ensemble 判官 | 是（成本高） |
| **discovery-H** | 执行才揭示的不完善（设计阶段不可预见） | 后验循环 + 可观测性 | **否** |

discovery-H 解释了为何 H4 严格版（Artifact+ ≤10%）从未满足：被试图用 artifact 外化的 H 里混着结构上无法外化的 discovery-H，Artifact+ 和 Scope− 对它都无效。

**Escape 重定义**：当前 `escape_rate=0`（全部 33 事件）在此模型下几乎无意义——先验 gate 不是安全的主要承载者。Escape 应重定义为：**漏过先验 gate 且后验循环在产生显著成本前未能捕获**。一个被先验 gate 漏过、但被后验循环一轮廉价捕获的缺陷，是系统设计的**成功**，不是 escape。重定义将 escape 从 gate 属性变成**整个循环的属性**，escape rate 的主要预测变量从 GCL 变为后验循环的 MTTD × 修复成本。

**两段制路由框架**：

| | 先验 gate（廉价 triage） | 后验循环（主要监督） |
|---|---|---|
| **职责** | 识别"回退成本高"的子集并阻截 | 捕获 discovery-H，驱动快速改进 |
| **关键量** | blast-radius / 不可逆性（GCL 仅作辅助下限） | MTTD、MTTR、discovery-H recall、每循环成本 |
| **低 GCL 含义** | 可自动放行（若 risk 也低） | N/A |
| **低 GCL × 高 risk** | **拦截**——这是 GCL 单独漏掉的危险格 | — |
| **失效模式** | Rubber stamp（H5）；LLM 低估 blast-radius | 可观测性不足 → discovery-H 无信号 → 循环沉默 |

先验 gate 不可消去的职责：仅拦截「low GCL × high blast-radius」格（schema migration、共享状态、外部副作用、已发布产物）。这个子集的识别**与 GCL 高低无关**，一行代码的 migration 可以 GCL 极低而不可逆。因此 risk 维度（archguard change-risk、TASK-183 pre-dispatch enrichment）是先验 gate 真正需要的第二输入，而非 GCL 的精度提升。

**后验循环的当前状态（2026-06-24）**：仓库里已有雏形——`extract-replan-markers.sh`、`declared-vs-actual-report.sh`（TASK-190）、`gcl-events.jsonl`——但这些信号目前**彼此独立，未关联回任务**。尚无人统计"通过了薄先验 gate 的任务里，有多少后来触发了 replan / 返工、多快被发现、修复成本是多少"。这个关联分析才是此 regime 下 value function 的实测。

**边界条件（H10 不是无条件成立）**：
1. 后验只在回退真便宜、blast radius 受控时成立。对易检测但难撤销的缺陷，后验救不了。
2. 后验 recall 依赖可观测性。沉默的 discovery-H（不挂测试、不抛异常）不产生信号。
3. H10 与 H9 关系：H9 是证据质量的先/后验比较（单 gate 视角）；H10 是系统级路由（整个循环视角）。H9 成立是 H10 的条件之一，但 H10 更强——它主张先验 gate 的认知投入不应随任务数线性增长，应趋近固定开销。

**可证伪**：
- 在回退廉价的任务子集中，低先验 GCL 与 escape rate（重定义版）无显著相关（而高 blast-radius 预测 escape）。
- 后验循环效率（MTTD、MTTR）与系统实际质量（累计 escape count）之间的相关，强于先验 GCL 与系统质量之间的相关。
- 需字段：`gate_timing`（先/后验）、`replan_marker_count`、`days_to_detection`、`rollback_cost`。

**状态**：框架成立，待后验循环插桩验证。当前最紧迫前置工作：把 replan marker / declared-vs-actual / escape（重定义）关联回任务，建立后验循环的基线指标。

### H9：低执行成本下，后验 gate 在每单位成本的证据质量上优于先验 gate

> 当执行+回退成本低时，后验 gate（执行后评估，gate-temporal-portfolio.md 形态 R）在"每单位成本的证据质量"上优于先验 gate（形态 P），因为执行把 H 前提转化为 E 前提——运行一次任务，就是把"如果执行会怎样"的假设性推理，转化为"实际产生了这个 git diff、这些测试结果"的可读证据。

**可证伪**：对比形态 P 与形态 R 任务的 H 占比（H/GCL）和 escape rate。预测：形态 R 的 H 占比显著更低，escape rate 不高于形态 P，总成本（认知 + 执行 + 回退）更低。
**前置条件**：gcl-events.jsonl 需有 `gate_timing` 字段才能分层（TASK-176d 扩展）。

**对 H5 的影响**：H5「GCL 存在监督有效性下界」中的"gate quality"必须按 gate 形态分层重新解读——后验 gate（高 E）与先验 gate（高 H）的 GCL 结构根本不同，不能混在一个分布里比较。完整论证见 docs/research/gate-temporal-portfolio.md。

**状态**：待验证。依赖 TASK-176d 的 `gate_timing` / `gate_outcome` schema 扩展。

---

## 下一步

1. **首次 premise-ledger 对比验证**（TASK-151 已完成仪器建设，TASK-152 已执行首批分析）：✓ 已验证，见 docs/research/gcl-selfReport-analysis.md。后续需积累更多样本，扩展到 proposal gate 和 epic-evaluate gate 类型。

2. **完整观测机制建设**（TASK-176，Epic: Backlog）：结构化事件日志 + 可复现分析脚本 + 可靠性采样 + escape rate 配对 + H5/H6/H7 验证实验 + 闭环告警。schema 需包含 `evidence_independence` 和 `gate_actor_type` 字段以支持 H6/H7 联合检验。详见 docs/research/gcl-complete-observation-mechanism.md。

3. **收窄 gate 实验**：设计对照实验——对比"全 proposal 评审"（当前）与"仅 DoD 机械验证"（Scope−）的 gate 可靠性，同时控制 evidence independence，实证验证 H5 边界。

4. **规则类隐性项外化**：对 H 均值贡献最大的隐性项（系统不变量、judge 标准）建立 `docs/ARCHITECTURE.md`，作为 Artifact+ 的实施路径，同时提升 evidence independence。

5. **后验循环插桩（H10 前置）**：把 replan marker（`extract-replan-markers.sh`）、declared-vs-actual diff（`declared-vs-actual-report.sh`）、escape（重定义版）关联回任务 ID，建立后验循环基线指标（MTTD、MTTR、每循环成本）。这是验证 H10 的最小前置工作，也是在低成本可回退 regime 下实测 value function 的唯一路径。当前三个数据源彼此独立、未关联任务——把它们拼起来的分析脚本尚未存在。

6. **可靠性二次采样修复**：`gcl-events.jsonl` 中 `sample_run_id` 非空 = 0/33，skill 里 10% 二次自报通道未产出任何事件（gcl-selfReport-analysis.md §G）。需核查并修复该分支，否则 H 的 test-retest reliability 无数据支撑。

---

## 研究追踪

| Phase | 文件 | 状态 |
|-------|------|------|
| 1. GCL 定义 | docs/research/gcl-definition.md | ✓ 完成 |
| 2. 语料构建 | docs/research/gcl-corpus.md | ✓ 完成（N=20） |
| 3. 基线统计 | docs/research/gcl-baseline.md | ✓ 完成 |
| 4. H2 验证 | docs/research/gcl-drivers.md | ✓ H2 confirmed |
| 5. H4 验证 | docs/research/gcl-intervention.md | ✓ H4 null（细化）|
| 6. 综合与回灌 | docs/research/gcl-synthesis.md（本文）| ✓ 完成；2026-06-24 增补 H10 + 两段制框架 |
| 7. 首批自报分析 | docs/research/gcl-selfReport-analysis.md | ✓ 完成（N=13，TASK-152）；2026-06-24 增补附录（观测者相对性、下限解读）|
| 8. 完整观测机制 | docs/research/gcl-complete-observation-mechanism.md | 进行中（TASK-176）|
| 9. Judgment 用户 UX | docs/research/judgment-ux.md | ✓ 完成（2026-06-23，evidence-independence 轴·人介入方向）|
| 10. CC Actor 网络 | docs/research/cc-actor-network.md | ✓ 完成（2026-06-23，evidence-independence 轴·非人 actor 方向，含接地开发加速层框架）|
| 11. 接地基础设施 | docs/research/grounding-infrastructure.md | ✓ 完成（2026-06-24，三层接地分类、intake 缺口分析、可移植设计原则）|
| 12. 后验循环基线 | （待创建）| 待开始：replan marker + declared-vs-actual + escape（重定义）关联分析，验证 H10 |

参考文档：
- docs/baime-software-engineering-capability-analysis.md §7.3（研究动机）
- docs/proposals/proposal-situational-awareness.md（受影响的使命设定）
- docs/research/gcl-intervention.md（H4 反事实分析，含 situational-awareness 影响）
