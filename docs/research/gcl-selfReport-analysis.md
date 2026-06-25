# GCL Self-Report Analysis：首批自报数据与基线比对

**状态**：TASK-152 输出（Phase 1–4）；2026-06-24 增补附录（观测者相对性、系统性低估、"下限"再解读）
**日期**：2026-06-23（正文）／2026-06-24（附录 A–G）
**数据来源**：backlog/tasks/*.md（GCL-self-report 行）、docs/research/gcl-corpus.md（估算基线）、docs/research/gcl-baseline.md（分层统计）、docs/research/gcl-events.jsonl（N=33，附录用）

---

## 收集说明

TASK-151 于 2026-06-22 将 premise-ledger 自报指令注入 feature-to-backlog 和 epic-to-backlog 的 reviewLoop reviewer prompt（合并提交 b11cb45）。每次 plan/proposal review gate 事件现在向 task Notes 写入 `GCL-self-report: E=n C=n H=n`。

扫描命令：`grep -rl 'GCL-self-report' backlog/tasks/`

找到含 GCL-self-report 的任务文件：13 个（满足 DoD #1 ≥3 的条件）。

---

## Phase 1 数据：GCL-self-report Gate 事件

所有 13 条自报事件汇总如下（按 git 提交时间排序）：

| # | TASK-ID | Gate 类型 | 迭代 | 日期 | E | C | H | GCL | 备注 |
|---|---------|-----------|------|------|---|---|---|-----|------|
| 1 | TASK-153-A | plan | iter1 | 2026-06-22 14:12 | 6 | 0 | 1 | 7 | cap-experiment facet 定义 |
| 2 | TASK-154-B | plan | iter1 | 2026-06-22 14:12 | 5 | 1 | 1 | 7 | experiments-lib/runner.ts |
| 3 | TASK-155-C | plan | iter1 | 2026-06-22 14:12 | 5 | 1 | 1 | 7 | run-exp-h.ts 移植 |
| 4 | TASK-156-D | plan | iter1 | 2026-06-22 14:12 | 5 | 1 | 1 | 7 | timing.ts 提取器 |
| 5 | TASK-157-E | plan | iter1 | 2026-06-22 14:12 | 5 | 1 | 1 | 7 | provenance gate 构建 |
| 6 | TASK-158-F | plan | iter1 | 2026-06-22 14:12 | 5 | 1 | 1 | 7 | SKILL 重构为薄层 |
| 7 | TASK-159 | plan | iter1 | 2026-06-23 06:16 | 2 | 1 | 1 | 4 | ESM/CJS 守护进程修复 |
| 8 | TASK-165 | plan | iter1 | 2026-06-23 03:53 | 8 | 1 | 0 | 9 | kind:basic 标签修复（第1次审查）|
| 9 | TASK-165 | plan | iter2 | 2026-06-23 03:53 | 9 | 0 | 0 | 9 | kind:basic 标签修复（第2次审查）|
| 10 | TASK-166 | plan | iter1 | 2026-06-23 07:27 | 8 | 1 | 1 | 10 | Monitor prompt 跨会话自恢复（第1次）|
| 11 | TASK-166 | plan | iter2 | 2026-06-23 07:27 | 7 | 1 | 0 | 8 | Monitor prompt 跨会话自恢复（第2次）|
| 12 | TASK-167 | plan | iter1 | 2026-06-23 08:22 | 9 | 0 | 0 | 9 | backlog-setup L0 Config 初始化 |
| 13 | TASK-170 | plan | iter1 | 2026-06-23 15:42 | 8 | 1 | 0 | 9 | Monitor checkpoint 无状态 worker |

**所有事件均为 `plan` gate 类型**（feature-to-backlog/epic-to-backlog reviewLoop 目前只在 plan 阶段触发 premise-ledger）。

---

## 比对结果

### 基线参考（来自 gcl-corpus.md + gcl-baseline.md）

`plan` gate 基线（N=7，TASK-125/136/137/138/146/147/149）：

| 分量 | 基线均值 | 基线范围 |
|------|---------|---------|
| E | 12.3 | 6–21 |
| C | 4.7 | 1–9 |
| H | **2.0** | 1–3 |
| GCL | 19.0 | 15–29 |

### 自报数据统计（N=13 事件）

| 分量 | 自报均值 | 自报范围 | 自报标准差 |
|------|---------|---------|-----------|
| E | 6.31 | 2–9 | 1.89 |
| C | 0.69 | 0–1 | 0.48 |
| H | **0.54** | 0–1 | 0.52 |
| GCL | 7.54 | 4–10 | 1.81 |

### delta_H 分析（偏差方向）

**delta_H = self_reported_H − estimated_H_baseline**

基线 plan gate 的 H 均值 = 2.0

| # | TASK-ID | 自报 H | 基线 H（plan 均值） | delta_H |
|---|---------|--------|-------------------|---------|
| 1 | TASK-153-A | 1 | 2.0 | −1.0 |
| 2 | TASK-154-B | 1 | 2.0 | −1.0 |
| 3 | TASK-155-C | 1 | 2.0 | −1.0 |
| 4 | TASK-156-D | 1 | 2.0 | −1.0 |
| 5 | TASK-157-E | 1 | 2.0 | −1.0 |
| 6 | TASK-158-F | 1 | 2.0 | −1.0 |
| 7 | TASK-159 | 1 | 2.0 | −1.0 |
| 8 | TASK-165-iter1 | 0 | 2.0 | −2.0 |
| 9 | TASK-165-iter2 | 0 | 2.0 | −2.0 |
| 10 | TASK-166-iter1 | 1 | 2.0 | −1.0 |
| 11 | TASK-166-iter2 | 0 | 2.0 | −2.0 |
| 12 | TASK-167 | 0 | 2.0 | −2.0 |
| 13 | TASK-170 | 0 | 2.0 | −2.0 |

**汇总**：
- 均值 delta_H = −1.46（自报 H 均值 0.54，基线 H 均值 2.0）
- 偏差方向：**一致负向**（所有 13 个事件的 delta_H ≤ −1.0）
- 偏差含义：原始估算的 H=2.0 相对于自报结果**系统性高估**了约 1.5 单元

### E、C 分量的同步偏差

E 和 C 也呈现出同向的负偏差：
- 自报 E 均值（6.31）vs 基线 E 均值（12.3）：delta_E = −6.0（高估约 2x）
- 自报 C 均值（0.69）vs 基线 C 均值（4.7）：delta_C = −4.0（高估约 7x）

这表明新一批任务（TASK-153+）本质上比基线语料中的任务（TASK-125–149）规模更小、耦合度更低，不能单纯归因于估算偏差。自报 H 偏差方向与 E、C 偏差方向一致，支持"任务类型改变"的解释（而非纯粹的测量偏差）。

---

## H4 动态验证

### H4 假设（动态版本）

H4 的动态版本预测：随着 artifact 覆盖率增加，H 值应下降（隐性前提被外化）。

### Artifact 覆盖代理

以 `docs/research/*.md` 文件数量作为 artifact 覆盖代理：
- 2026-06-22 10:13（b14e1ca）：6 个 gcl-research 文件创建
- 2026-06-22 10:45（582cc7a）：gcl-synthesis.md 和 gcl-definition.md 更新（共 6 个文件）
- 所有 13 个自报 gate 事件均发生在 6 个 research artifact 存在之后

由于所有事件均发生在相同的 artifact 覆盖水平下（6 个 gcl-research 文件），无法用时序手段验证 H4 的动态版本（artifact 覆盖在观测期间未变化）。

### 时序 H 值趋势分析

| 日期区间 | 事件 | H 值 | artifact 数 |
|---------|------|------|------------|
| 2026-06-22 14:12 | #1–#6（TASK-141 子任务） | 全部 H=1 | 6 |
| 2026-06-23 03:53 | #7–#9（TASK-159、TASK-165） | H=1, H=0, H=0 | 6 |
| 2026-06-23 07:27–08:22 | #10–#12（TASK-166、TASK-167） | H=1, H=0, H=0 | 6 |
| 2026-06-23 15:42 | #13（TASK-170） | H=0 | 6 |

**时序观察**：H 值在两天内从 1（最大值）趋向 0（最小值）。前 6 个事件（2026-06-22）全部为 H=1，后 7 个事件（2026-06-23）中有 5 个为 H=0、2 个为 H=1。这与 H4 动态版本的预测方向**一致**。

然而，artifact 覆盖在此期间保持不变，因此此趋势更可能反映的是：
1. 任务特征的变化（TASK-141 子任务包含 H=1 的"DoD 充分性"判断，而后期任务 DoD 全部为机械可验证命令）
2. reviewer 对 E/H 分类标准理解的变化（后期倾向于将更多前提标记为 E 而非 H）

### 规则类 vs 判断类隐性项比较

从 premise-ledger 内容分析：
- **H=1 的事件**（#1–7, #10）：隐性项通常是"DoD sufficiency: wc -l < 609 as LOC gate is a reasonable proxy but does not prove quality"（TASK-155）或"Absence DoD feasibility"（TASK-166-iter1）——属于**判断类**隐性项
- **H=0 的事件**（#8, #9, #11, #12, #13）：reviewer 认为所有前提已被 E 类或 C 类 artifact 覆盖，无需额外判断——属于**规则类** DoD 的任务

这与 gcl-intervention.md 的 H4 细化裁定一致：规则类隐性项（可通过 artifact 外化的判断标准）在 artifact 增加后确实会消失（H=0），而判断类隐性项（整体质量评估、代理有效性判断）仍然保持 H=1。

---

## 结论

### 偏差方向裁定

**估算 H 系统性高估**：相对于 premise-ledger 自报的 H 值，gcl-corpus.md 中的估算 H 偏高约 1.5 单元（均值 delta_H = −1.46，N=13）。偏差方向一致（所有事件均为负向）。

**解释**：这不完全是估算方法的失败——新一批任务的整体规模（E）和耦合度（C）也比基线语料低得多（E: 6.31 vs 12.3，C: 0.69 vs 4.7）。更小、更自包含的任务自然产生更少的隐性前提。建议：在跨任务规模差异较大的情况下，应按任务规模分层比较 H 值，而非直接用整体均值。

### H4 动态裁定

**H4 部分支持**：观测期内 artifact 覆盖未变化（恒定 6 个 gcl-research 文件），无法通过 artifact 增量验证 H4。然而时序上存在 H=1→0 的趋势（前期高、后期低），与 H4 方向一致。

细化发现（与 gcl-synthesis.md H4 null 裁定一致）：
- **规则类隐性项**（机械可验证的 DoD、明确的文件路径检查）：H=0（已被 artifact 完全外化）
- **判断类隐性项**（DoD 充分性代理合理性、质量判断框架）：H=1（仍需判断者记忆/推断）

### 方法论含义

1. **premise-ledger 自报的 H 值普遍低于估算基线**（0–1 vs 2–3），支持"reviewer 倾向于将更多前提归入 E 类"的观察
2. **H=0 的任务均具备：全 DoD 为 shell 命令、无主观阈值判断**——与 Scope− 策略（收窄 gate 判断面积）的方向一致
3. **样本局限**：所有 13 个事件均为 `plan` gate，均由同一 reviewer 框架（feature-to-backlog/epic-to-backlog）产生，泛化到其他 gate 类型需要更多数据

---

## 数据来源

- 自报数据：`grep -rn 'GCL-self-report' backlog/tasks/` 提取（N=13 行，13 个 gate 事件）
- 基线数据：docs/research/gcl-corpus.md（#2,#5,#8,#10,#13,#16,#19 七个 plan gate 事件）
- 分层统计：docs/research/gcl-baseline.md（plan gate: N=7, H均值=2.0）
- H4 背景：docs/research/gcl-intervention.md, docs/research/gcl-synthesis.md

---

## 附录（2026-06-24）：自报指标的观测者相对性、系统性低估，及"下限"再解读

本节补上原分析缺失的一环：在**承认偏差**的前提下，如何正确使用自报 GCL。原文已给出"估算 H 系统性高估"的裁定，但未追问一个更根本的问题——**自报 GCL 本身在测谁的负载？** 这决定了它能不能当任务复杂度的近似来用。

### A. 核心问题：E/C/H 边界是观测者相对的

分类规则 `H = 不在任何 artifact、靠背景知识或记忆推断`，定义的不是 gate 的属性，而是**判断者知识与 artifact 之间的落差**。同一个 gate，对每个判断者有不同的 E/C/H 切分。当前 `gcl-events.jsonl` 中 `gate_actor_type` 为 `llm` 的事件占 32/33——这意味着已记录的"理解负载"几乎全部以 **Sonnet 训练语料 + 当前 context window** 为隐含基准。

把这把尺子套到人类身上在两处失真：

1. **语料内容不同**：LLM 视为免费背景的东西（框架惯用法、库 API、"TDD 即测试先行"），人类可能要查（对人是 `C` 或 `H`，且成本高）；反之，对 LLM 是 `H` 的项（"上周为何选 A 弃 B"、"上次拆 daemon 死锁过"），亲历该决策的人类作为廉价情景记忆持有（≈0 成本）。H 账本不跨观测者可移植，而 Sonnet 的边界是其中最不像人类的一种。

2. **数 units 而非 cost**：GCL 动机（gcl-definition.md：人为可靠判断需理解多少）关乎**人类可持续成本**，但公式等权数认知单元数。LLM 在 context 内 `C` 近乎免费，等权尚可；人类的 `C` 是分钟级、`H` 可能不可得（无法回忆未亲历的决策）。单位成本的不对称恰好集中在 C/H 项——也正是 LLM 自报最不像人类之处。

### B. 系统性低估的方向是单一的（结构性偏差，非噪声）

**LLM 无法为它不持有的前提报告负载。** 人类架构师从 grounding 调取前提——生产事故、客户现实、"这个接口有六个下游消费者"——多数按定义是 `H`。LLM 不是低估这些前提，而是**根本不调取**，于是它们连 H 都不出现。Gate 因此显得"便宜"——不是因为它便宜，而是判断者对使其昂贵的前提失明。

这与 gcl-synthesis.md §94 的"人机信息处理无本质差异、grounding 可工程弥合"假设构成**循环**：自报机制建立在该假设之上（用 LLM 内省作理解负载代理），synthesis 又据低 H 反推人类非必需。**处理等价性假设被装进了量具，于是量具确认了它自己。** TASK-181 路径放置漏检即经验印证：GCL 低、gate 通过、结论错——低 GCL 与漏掉的前提同时出现，而 premise-ledger 只记被调取的前提，从不记**应调取而未调取**的前提。

### C. "下限"再解读：它是「可枚举结构负载」的下限，不是「任务难度」的下限

承认低估后，自报 GCL 仍有价值——但须精确到它是**哪个量**的下限。按分量分层看可信度：

| 分量 | 是否 observer-invariant | 作为下限的可信度 |
|------|------------------------|-----------------|
| **E** | 是（DoD/Phase 机械可数） | 硬下限。人类至少也要读这些。 |
| **C** | 计数是（artifact 内引用客观存在） | 计数为下限；人类单位成本只会更高。 |
| **H** | 否（依赖判断者知识边界） | 仅"被报告的那些"是 true-H 子集（reported-H ⊆ true-H）。 |

不等式 `LLM-GCL ≤ 真实可枚举负载` 对**被枚举出的结构性认知单元**成立。但"复杂度"一旦从"可枚举单元数"滑到"任务难度/后果"，下限即断——断点正是 LLM 从不调取的 grounding 前提。一个 schema migration 可以 `E+C+H` 很低而 blast radius 极大。**它能 lower-bound 枚举量，不能 lower-bound 后果。**

### D. 让"下限"既成立又安全的三个条件

1. **单向使用：触发升级，不触发放行。** 高 LLM-GCL → 任务确定复杂（连低估的判官都喊累），可靠的 triage 信号。低 LLM-GCL → 信息量近乎为零（简单 / 专家压缩 / 判官失明，三者不可分）。把低 GCL 当绿灯正好踩中 H5 的 rubber-stamp / escape-rate 失效。下限只配做 escalation 触发器。

2. **信 GCL 总量，不信 H/GCL 比值。** LLM 会把判断性 H 前提（"什么算好 DoD"）当成"读了 DoD 这件显然的事"，把 true-H 误记为 E。此误分类下总和 `E+C+H` 仍可能是下限（同一前提换桶计一次），但 `H/GCL` 比值被**定向压低**——而 synthesis 的 H4/H5 大量依赖 H 占比。**总量当下限稳，比值当结论险。**

3. **只在同任务类型内比序。** 低估幅度非常数：grounding-heavy / open 任务低估多，机械任务低估少（参见 MEMORY「bug fix 批次自然产生更低 H」）。这是个**异方差下限**，压扁高端。故 gcl-synthesis.md 中 ρ=0.87 一类跨任务相关，若混合任务类型则序关系可能失真；同质类型内才稳。

### E. 本文 delta_H 数据反过来支持"下限"解读

原文 §delta_H：13 个自报事件相对负空间估算基线**全为负（均值 −1.46）**——self-report 系统性低于 forensic 重建值，方向与"自报是下限"一致。（严格说，低于"负空间估算"不等于低于真实负载，因估算自身可能高计；但方向互证，足以支撑下限解读。）即：本文 B 节的"系统性低估"与 C 节的"下限"是同一现象的两面——低估使它失去"测准"资格，却恰好赋予它"单向下限"资格。

### F. 给下限配一个它给不了的维度：risk-orthogonal 路由

既然 LLM-GCL 结构上盲于后果，不应由它独自承担路由决策。配一个同样 observer-invariant、但测**后果而非理解**的信号：blast radius / 不可逆性——archguard change-risk、改动文件数、可回退性。这些不依赖判官知识边界，恰补下限盲区。TASK-183 的 pre-dispatch enrichment 已引入 archguard 通道，可将二者并成二维路由：

| | 低 risk | 高 risk |
|---|---|---|
| **低 GCL** | 可自动放行 | **GCL 单独漏掉的危险格** → 强制人类 / 独立证据 |
| **高 GCL** | 升级 | 升级 |

如此"系统性低估"从缺陷转为**已知偏向、且被第二维兜住**的工程量：下限做它擅长的（廉价、客观、单向 triage），risk 维度补它结构上做不到的（后果）。

### G. 两条当前数据卫生问题（须独立修复，否则上述解读无数据支撑）

1. **可靠性二次采样从未触发**：`gcl-events.jsonl` 中 `sample_run_id` 非空 = 0/33。skill 里 `md5(TASK-ID) % 10 == 0` 的 10% 二次自报通道从未产出事件，故当前 H 既无 validity 也无 test-retest reliability 证据。需核查该分支是否真正执行。
2. **evidence_independence 普遍偏低**：33 事件中 `unknown`×23、`low`×9，从无更高值。即 H6 警示的"监督通道与被监督系统信息源耦合"正在数据中实时发生——reviewer 消费的是同一 skill 刚起草的 plan。在引入独立证据通道前，E/C/H 切分本身是在耦合条件下产生的。

**一句话**：自报 GCL 测的是 *LLM 的* 理解落差并悄悄贴上 *人类的* 标签；因 LLM 最盲于人类赖以判断的 grounding / 反事实前提，量具在 synthesis 想要的方向上系统性低读 gate 的真实人类负载。正确用法不是更好的 prompt，而是：(1) 把它降格为「可枚举结构负载的单向下限」，(2) 配 risk 维度兜住后果盲区，(3) 用配对的人类 baseline（dyad / H8，TASK-185/186）实测低读幅度。
