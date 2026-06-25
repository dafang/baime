# Gate 作为时间上的实物期权组合（Temporal Portfolio）

**状态**：研究文档（gate 形态再分析）
**日期**：2026-06-24
**关联**：docs/research/gcl-definition.md（GCL 压缩论题）, gcl-synthesis.md（H5/H9）, grounding-infrastructure.md（执行即 grounding）, cc-actor-network.md（后验 gate 的 actor 配置）

---

## 1. 问题：现有文档把 gate 当作同步先验决策

GCL 框架（gcl-definition.md）的隐含假设是：gate 是一个**同步的先验决策点**——actor 在某个时刻读证据，付出认知负载 GCL = E + C + H，输出 APPROVED / ITERATE / NEEDS_HUMAN，然后流程继续。GCL 最小化 = 在这个时点压缩理解表面积（grounding 把 C、H 压成 E）。

这个模型描述的是 `feature-to-backlog` 的 reviewLoop 和 `loop-backlog` 的 verifyDod / epicEvaluate。但它漏掉了一整根轴：**何时 gate**。实际开发中，gate 不是一次性的点决策，而是在时间上展开的一组选择——可以推迟、可以后置、可以批处理。选择哪一种，不由证据质量决定，由**执行与回退的成本结构**决定。

本文把 gate 重新建模为**时间上的实物期权组合**，并论证一个被现有文档忽略的核心机制：**执行本身是最强的 grounding 操作——它把 H 前提转化为 E 前提**。

---

## 2. 三种 gate 形态

### 形态 P（Prior gate，先验同步）
当前文档描述的形态。在执行前读证据、下判断。适用于收益和风险都清晰、执行成本相对回退收益不可忽略的任务。GCL 结构中 H 占比可能较高——因为"执行会怎样"只能靠假设性推理。

### 形态 D（Defer，搁置）
对**收益不明显、风险相对大**的任务，理性选择不是否决，而是**根本不付 gate 成本**，让任务挂起，直到被迫处理或被清理。

搁置是实物期权里的**等待价值**：再多收集证据的预期收益 < 收集成本时，最优解是等待——保留"将来信息更充分时再决定"的权利。搁置在 GCL 意义下携带信息：它说"当前证据不足以支撑决策，且收益不足以支付更多证据"。

**关键问题**：搁置是一个**非事件**。当前 gcl-events.jsonl 只记录已发生的 gate 决策，看不到搁置。而搁置的**最终去向**（被复活 vs. 被批量归档）才是它是否为正确"等待"的判据——被复活说明等待期权行权正确，被归档说明这任务从一开始就不值得 gate。两者目前都不可观测。

### 形态 R（posterioR gate via Revert，乐观执行 + 后验回退）
对**可能收益和风险都大**的任务，当 git revert / 重开 branch 的成本足够低时，最优策略是**先推进执行**，若干个 commit 之后再判断——有问题就 git 回退、重开 branch 往前走。

这是实物期权里的**放弃期权（abandonment option）**：先建仓，保留低成本平仓的权利。它在结构上是**最高证据质量的 gate**——gate actor 读的是真实 git diff 和运行结果，而非 worker 自述，evidence independence 天然极高（见 §4）。

### 形态 B（Batch retrospective，批量清理）
数天之后集中检查积压任务并清理。这是延迟的先验 gate，但有两个特性：
- **固定成本摊销**：context-loading 的固定成本被一批任务分摊。
- **证据更丰富**：到批量审时，git 历史已积累，证据比执行时点更完整。

代价是单个 gate 决策的独立性下降——一批任务在一次会话里被处理，GCL 难以精确归因到单个任务，且存在批内锚定效应。

---

## 3. 驱动量：执行/回退成本不对称

四种形态的最优选择，由一个成本比决定：

```
执行成本 + 回退成本
─────────────────────
先验 gate 把 H 压成 E 的认知成本
```

- **当这个比值 < 1**（执行+回退很便宜）：形态 R 占优。与其在先验 gate 上付高 H 的认知负载去猜"执行会怎样"，不如用一次廉价执行把 H 直接变成 E。
- **当任务收益不明、比值难估**：形态 D 占优。不付任何 gate 成本，保留等待期权。
- **当固定 context 成本高、任务可积压**：形态 B 占优。摊销固定成本。
- **当执行或回退昂贵、收益风险清晰**：形态 P 占优（传统先验 gate）。

**低开发成本把最优点系统性地推向 R 和 D。** 这正是当前 BAIME 开发的实际形态——本仓库的 git revert 成本极低、任务可廉价搁置，所以同步先验 gate（verifyDod / epicEvaluate）实际上**不是主要 gate**，它们是中间检查点；真正的最终关卡是"是否 revert"和"搁置任务的最终去向"。

---

## 4. 核心论题：执行即 grounding（H→E 转化）

GCL 压缩论题（gcl-definition.md）说：grounding 在执行**前**压缩理解表面积——archguard 把系统结构变成可读证据，premise-ledger 把判据结构化。本文补一个极端形态：

> **执行是终极的 grounding 操作。运行一次任务，就是把"如果执行会怎样"的 H 前提，转化为"实际执行产生了这个 diff、这些测试结果"的 E 前提。**

先验 gate 对高方差任务的 GCL 里，H 占比高——actor 在对没有 artifact 支撑的假设做推理。执行若干 commit 后，后验 gate 读真实 git diff 和运行结果——GCL 几乎全是 E。**执行不是 gate 的下游，执行是 gate 的证据生产手段。**

这把 grounding-infrastructure.md §9.3 的线性四阶段（intake → execution → gate → outcome）**折叠**了：当执行+回退便宜，execution 不再是 gate 的前置阶段，而是 gate 用来把 H 变 E 的工具。gate 与 execution 的边界消失。

这也连接了 H6（evidence independence）：后验 gate 读的是 git diff——一个完全不经过 worker 叙述层的独立证据通道。**形态 R 是 evidence independence 最高的 gate 配置**，因为它的证据是被审对象的实际产物，不是它对自己的描述。

---

## 5. 对 GCL 测量的影响

| 现有假设 | 受影响处 | 修正方向 |
|---|---|---|
| GCL 在单一时点测量 | 后验 gate（高 E）与先验 gate（高 H）的 GCL 结构根本不同 | gcl-events.jsonl 加 `gate_timing` 字段（prior / posterior / batch） |
| gate_outcome 只有隐含的"通过" | 缺 deferred、abandoned(revert) | 加 `gate_outcome` 字段（approved / deferred / iterate / abandoned） |
| escape 只由 Needs Human / reaper 触发 | git revert / 弃 branch 是更直接的逃逸信号 | escape_rate 定义扩展 |
| H5「gate quality → escape rate」无差别 | gate quality 必须按形态分层 | H5 加形态分层；新增 H9（见下） |

### H9（新增假设）
> 当执行+回退成本低时，后验 gate（形态 R）在"每单位成本的证据质量"上优于先验 gate（形态 P），因为执行把 H 前提转化为 E 前提。

**可证伪**：对比形态 P 与形态 R 任务的 H 占比（H/GCL）和 escape rate。
**预测**：形态 R 的 H 占比显著更低；escape rate 不高于形态 P；总成本（认知 + 执行 + 回退）更低。
**前置条件**：gcl-events.jsonl 需有 `gate_timing` 字段才能分层（依赖 TASK-176d 扩展）。

---

## 6. 与其他文档的关系

- **gcl-definition.md（GCL 压缩论题）**：本文是压缩论题的时间维延伸——压缩不仅发生在 grounding 把 C/H 压成 E，也发生在执行把 H 压成 E。
- **grounding-infrastructure.md（§9.3 四阶段回路）**：本文论证当执行便宜时四阶段会折叠；四阶段回路是形态 P 假设下的理想模型，形态 R 是它的退化/优化形态。
- **cc-actor-network.md（§4.1 克隆耦合）**：形态 R 的后验 gate 读 git diff，是天然解耦的独立证据通道——一种不需要第二个 actor 就能达到高 evidence independence 的配置。
- **gcl-synthesis.md（H5/H9）**：H9 在此首次形式化；H5 的 gate quality 须按本文三形态分层重新解读。
