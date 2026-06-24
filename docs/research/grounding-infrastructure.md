# 接地基础设施：AI 辅助软件开发的独立观测层

**日期**：2026-06-24
**背景**：meta-cc 和 archguard 已是接地原则的工程实例；本文讨论接地基础设施作为独立设计对象，及其在更广义 AI 辅助开发管线中的应用
**依赖**：docs/research/gcl-complete-observation-mechanism.md（H6/H7/H8, evidence independence）
**关联**：docs/research/cc-actor-network.md（接地是 actor 网络的前置约束）, docs/research/judgment-ux.md（接地是证据通道来源）, docs/research/gcl-synthesis.md（H8）, docs/baime-self-reference-analysis.md（"观测即自观测"，自观测作为最快反馈机制）

---

## 1. 核心命题：接地的独立性是失败模式解耦，不是观察者身份隔离

H6 说监督质量由 evidence independence 决定——监督证据与被监督系统的信息源必须独立。这是框架层的约束。**接地（grounding）是把这个约束落地为工程系统的具体手段。**

一个容易犯的错误（本文初稿犯过）是把"独立"等同于"观察者 ≠ 被观察对象"，即身份隔离。这个等式不成立，理由有两层：

1. **反例存在**：premise-ledger 是 reviewer 对自己刚做的判断分类（观察者 = 被观察对象），但它仍产出有用的独立信号——因为结构化的 E/C/H 分类暴露了自由叙述会掩盖的东西。meta-cc 的 self-trace 同理：同一个 agent 读自己的 session，但读的是原始 tool-call 记录而非自我总结。
2. **本项目的实践反对它**：BAIME 是 **Bootstrapped** 系统，"观测即自观测"是它的核心结构（见 [`baime-self-reference-analysis.md`](../baime-self-reference-analysis.md) §3）。在这个项目的发展中，**对自身的观测一直是最快的反馈机制**——自知的三代演化（手工重建 → meta-cc → GCL/premise-ledger）全部是自观测在加速、在内生化，而不是引入外部观察者。

因此正确的命题是：

> 接地要的是**失败模式解耦**——观察通道不与被观察对象共享同一个出错原因；而不是**身份隔离**——观察者必须是另一个实体。身份隔离是获得失败模式解耦的一种方式（最稳健，但最慢、信息损失最大），不是唯一方式，也不是免费的。

meta-cc 和 archguard 是失败模式解耦的两个工程实例：

| 项目 | 观测对象 | 解耦来源 |
|------|---------|-----------|
| **meta-cc** | Claude Code session（tool call 序列、文件修改轨迹、context 切换） | 读原始 record，不读 agent 自我总结——记录层与叙述层解耦 |
| **archguard** | Codebase 结构（change-risk、cochange、ownership、coverage） | 从历史分析和静态图谱计算，不依赖 developer 的风险判断——方法层与记忆层解耦 |

关键是：archguard 运行在同一个 repo 上，meta-cc 可以被 agent 用来读自己的 session——两者的独立性都不来自"观察者是另一个人/系统"，而来自**观察方法不会和被观察对象一起犯同一个错**。

---

## 2. 观测模式：身份耦合与通道解耦是两个正交的轴

§1 把"独立"从身份隔离修正为失败模式解耦后，观测模式就不是"独立 vs 不独立"的一维量，而是两个正交轴：

- **身份轴**：观察者是否就是被观察对象本身？自观测（self）/ 隔离观测（other）
- **通道轴**：观察读的是被观察对象的自我叙述，还是与其失败模式解耦的记录/结构？叙述通道（narrative）/ 记录-结构通道（record/structural）

H6 真正约束的是**通道轴**，与身份轴无关。把三个项目的实际机制铺到这张 2×2 上：

| | 自观测（observer = observed） | 隔离观测（observer ≠ observed） |
|---|---|---|
| **叙述通道** | agent 自我总结（最差：自指 + 叙述，无任何解耦） | 一个 agent 读另一个 agent 的 summary（换了人，仍叙述耦合） |
| **记录-结构通道** | **premise-ledger**（self，靠 E/C/H 结构解耦）；**meta-cc self-trace**（self，靠原始记录解耦） | **archguard**（other，靠静态+历史分析解耦）；独立模型重跑；escape rate |

两个关键结论：

1. **左下格是 BAIME 的主力反馈机制**。premise-ledger 和 meta-cc self-trace 都是自观测，却通过通道解耦获得了有用的独立信号。BAIME 自知的三代演化（手工 → meta-cc → GCL/premise-ledger）整体在左下格里加速，而不是向右移动。
2. **要避免的是左上格**，不是左侧。"agent 说自己做了什么"既不快（还要读一段总结）也不可靠（与被观察对象共享失败模式）。问题从来不是"自观测"，而是"无结构的自叙述"。

### 2.1 速度 / 稳健性的权衡前沿

身份轴不影响 H6 的独立性判定，但它决定**反馈速度**——这正是 BAIME 押注自观测的原因：

| | 自观测 | 隔离观测 |
|---|---|---|
| 反馈延迟 | 低：在环内，无需另起观察系统 | 高：需独立通道/系统 |
| 内部状态访问 | 全：无跨边界信息损失 | 损：只能看到边界外暴露的部分 |
| 失败模式解耦的稳健性 | 依赖结构设计，可能残留相关盲点 | 强：失败模式天然解耦 |
| 适用 | 快速反身迭代、方法论自改进 | 高问责 gate、捕捉相关盲点、周期性校准 |

权衡前沿：**身份隔离用延迟换稳健；自观测内的结构解耦用稳健换速度。** 对方法论开发这种需要最快反身回路的场景，自观测的速度优势压倒一切——你要的是即时反馈，再用结构（premise-ledger）和周期性的隔离校验补足稳健性。`draftAndReview` 把 draft 与 review 合并进同一上下文窗口、省下 25–43% proposal 时间且质量无损（[`baime-self-reference-analysis.md`](../baime-self-reference-analysis.md) §3），就是这条前沿上"自观测换速度"的直接收益。

### 2.2 自观测的系统性偏差需要隔离校准

自观测最快，但有隔离观测天然避免的风险：**相关盲点**——如果 agent 的判断错在某处，而这个错误又同时污染了它对自己的分类，自观测抓不到。

本项目已有这个现象的实证：TASK-152 的 **delta_H = -1.46**（premise-ledger 自报的 H 系统性低于估算基线，且 13 个事件全部为负）。这正是自观测的系统性偏差——只有当它被一个独立通道（gcl-corpus.md 的估算基线）比对时才暴露出来。

结论不是"放弃自观测"，而是：**自观测做主力高频反馈，隔离观测做周期性低频校准。** 自观测负责速度，隔离观测负责检测自观测自身的漂移。两者是分工，不是排序——这也回应了 [`baime-self-reference-analysis.md`](../baime-self-reference-analysis.md) §挑战 里"纯自指有滑向脱离现实的风险，需要外部锚点"：行为接地（§3.3）和隔离校准就是那个锚点。

---

## 3. 三层接地分类

软件开发管线里有三个天然的独立观测层次，分别对应不同类型的真实世界证据：

### 3.1 系统接地（System Grounding）

**观测对象**：codebase 实际处于什么状态

- 文件依赖图、跨模块 cochange 历史
- change-risk（改动涉及多少高耦合区域）
- 所有权分布、测试覆盖率
- 技术债密度、循环依赖

**已有实例**：archguard

**缺失接地的后果**：gate 判断的是"作者认为这次改动波及范围"，而不是系统实际的耦合结构。LLM agent 可以系统性地低估改动风险，且这个低估不会被纠正。

### 3.2 进程接地（Process Grounding）

**观测对象**：开发过程实际发生了什么

- 工具调用序列、回退次数、context 切换频率
- 实际修改了哪些文件（vs. 计划修改哪些）
- 执行时间分布、卡点位置
- 任务声明的完成 vs. DoD 实际验证结果

**已有实例**：meta-cc（session history analysis）

**缺失接地的后果**：reviewer 只能读 agent summary，而 summary 是 agent 对自己工作的自述——和被监督者共享同一信源，H6 意义下证据独立性为零。

### 3.3 行为接地（Behavioral Grounding）

**观测对象**：产品/系统在真实环境中的实际行为

- 用户路径、错误率、性能基线
- A/B 测试结果、转化漏斗
- Incident 历史、告警记录
- 生产 schema 变更的实际影响

**已有实例**：当前项目缺失此层

**缺失接地的后果**：gate 决策无法与下游结果链接。所有监督都是"前置"判断（改动看起来对不对），没有"后置"校准（它后来导致了什么问题）。escape rate 追踪（TASK-176d）是这一层的最小实现。

---

## 4. 现有观测机制全景

### 4.1 meta-cc — 进程观测（14 个 MCP 工具）

| 工具 | 观测对象 |
|------|---------|
| `query_session_signals` | session 级事件信号 |
| `query_session_content` | session 全文内容搜索 |
| `query_file_activity` | 文件修改活动轨迹 |
| `query_edit_sequences` | 编辑序列模式 |
| `get_session_metadata` | session 元数据（时长、token、工具调用数） |
| `get_session_directory` | session 文件目录 |
| `get_timeline` | 跨 session 时间线 |
| `get_work_patterns` | 工作模式分析 |
| `analyze_bugs` | bug 分析 |
| `analyze_errors` | 错误分析 |
| `get_tech_debt` | 技术债分析 |
| `quality_scan` | 质量扫描 |
| `execute_stage2_query` | 高级自定义查询 |
| `inspect_session_files` | session 原始文件检查 |

### 4.2 archguard — 系统结构观测（21 个 MCP 工具 + 本地文件）

**依赖 / 结构分析**

| 工具 | 观测对象 |
|------|---------|
| `archguard_get_dependencies` / `get_dependents` | 依赖图 |
| `archguard_detect_cycles` | 循环依赖 |
| `archguard_get_atlas_layer` | 分层架构 |
| `archguard_get_package_stats` / `fanin` / `fanout` | 包入度 / 出度 |
| `archguard_detect_god_packages` | 反模式 |

**变更风险**

| 工具 | 观测对象 |
|------|---------|
| `archguard_get_change_risk` | 改动风险评分 |
| `archguard_get_cochange` | 共变历史 |
| `archguard_get_change_context` | 变更上下文 |
| `archguard_analyze_git` | Git 历史分析 |
| `archguard_get_ownership` | 文件所有权 |

**代码实体 / 测试**

| 工具 | 观测对象 |
|------|---------|
| `archguard_find_entity` / `find_callers` / `find_implementers` / `find_subclasses` | 代码导航 |
| `archguard_get_file_entities` | 文件级实体 |
| `archguard_get_entity_coverage` | 测试覆盖率 |
| `archguard_get_test_issues` / `test_metrics` | 测试质量 |
| `archguard_detect_test_patterns` | 测试模式 |
| `archguard_analyze` / `archguard_summary` | 综合分析 |

**本地缓存文件**（`.archguard/query/git-history/`）

| 文件 | 内容 |
|------|------|
| `file-metrics.json` | 每个文件的 commit 数、active days、增删行、所有权比、cochange 邻居 |
| `package-metrics.json` | 包级指标 |

### 4.3 BAIME — 执行 / gate 观测

**Gate 决策观测**

| 机制 | 形式 | 状态 |
|------|------|------|
| **premise-ledger** | reviewLoop 自报 `[E/C/H] criterion` + `GCL-self-report: E=n C=n H=n` → task Notes | ✅ 活跃（TASK-151） |
| **gcl-corpus.md** | 手工回溯标注 20 个 gate events，建立 E/C/H 基线 | ✅ 完成（N=20） |
| **gcl-selfReport-analysis.md** | 首批 13 个自报事件与基线的对比分析 | ✅ 完成（TASK-152） |
| **gcl-events.jsonl** | 结构化 append-only 事件日志，含 `evidence_independence` / `gate_actor_type` 字段 | 🔲 规划中（TASK-176a） |

**任务执行观测**

| 机制 | 形式 | 状态 |
|------|------|------|
| **cap:* markers** | `backlog/.caps/TASK-N` 状态机标记（claim / execute / merge） | ✅ 活跃 |
| **task Notes（DoD 记录）** | `DoD #N: PASS/FAIL` + attempt-count 追加到 Implementation Notes | ✅ 活跃 |
| **daemon event log** | `backlog/.basic-daemon.log` — basic-ready / epic-ready / child-done 事件流 | ✅ 活跃 |
| **merge-lock** | `backlog/.merge-lock` — PID + 当前 merge 持有者 | ✅ 活跃 |

**运行时健康观测**

| 脚本 | 观测对象 |
|------|---------|
| `daemon-status.sh` | daemon 存活状态、最后事件、log 新鲜度 |
| `check-l0-observability.sh` | Done 任务中 DoD PASS/FAIL note 覆盖率 |
| `verify-cap-markers.sh` | cap:* 标记覆盖率（advisory） |
| `verify-subtask-dod.sh` | epic 子任务 shell-gate DoD 存在性 |
| `check-roi-gate.sh` | task notes 中 evaluator 结论 + replan 触发事件计数 |

**实验 / 技术质量观测**

| 机制 | 观测对象 |
|------|---------|
| **quantitative experiments**（`experiments/skill-quality/`） | skill 输出质量，oracle FP/FN 标注，fixture-based 自动评分 |
| `verify-experiment-provenance.sh` | 实验 artifact 的 data_source（measured/estimated）+ 预注册时序 |
| `check-provenance.sh` | 单个 artifact 的 data_source 合规 |

---

## 5. loop-backlog 的接地缺口

当前 intake 机制——backlog task description 作为 worker 的主要 context——是接地程度最低的一环。它的证据独立性接近零：

- **描述来源**：人类或 LLM 撰写，反映的是**意图**，不是真实状态
- **系统接地**：无——描述里不包含涉及文件的 cochange 风险
- **进程接地**：无——不知道历史中类似任务的执行模式和逃逸率
- **行为接地**：无——不知道这类任务过去导致过什么生产问题

**GCL 的 C 分量（均值 4.50，占 31%）**部分反映了这个缺口：gate 判断者需要跨任务查阅外部文档，因为 intake 阶段没有把这些证据内联进来。

### 接地原则应用到 intake 的三个方向

**1. Pre-dispatch enrichment（系统接地）**
任务 claim 前自动附加：archguard 对涉及文件的 change-risk 和 cochange 分析；owner 分布（谁最熟悉这块代码）。这把 worker 起点从"盲目描述"升级为"有实证上下文的描述"，直接降低 C 分量。

**2. Execution telemetry（进程接地）**
执行中自动记录实际修改文件、测试结果、diff 统计；这些不依赖 agent 总结，构成 DoD 验证的独立证据通道。meta-cc session trace 是现有的实现路径。

**3. Outcome linkage（行为接地）**
任务完成后，escape rate 信号（是否后来 Needs Human 或被 reaper requeue）自动回链到 gate 决策记录，使历史可校准。这是 TASK-176d 的设计动机，也是三层中目前进展最慢的。

---

## 6. 从 git/session 历史读到的结构性观察

本项目自身是一个样本。TASK-152 的数据（N=13 gate events）和 git 历史提供了几个具体数据点：

**E 分量主导（均值 8.35/14.55，57%）**：gate 判断大量时间在"核对任务文件里已经写了的东西"。这本可机械化（自动验证 E 分量），释放人类 gate 专注于真正需要背景知识判断的 H 分量。

**delta_H = -1.46（全部为负）**：当任务规模收窄（bug fix 批次），H 自然下降——这与 H4 细化裁定一致（scope− 是降低 H 的最稳定手段）。反过来说：任务描述越宽泛，worker 需要靠背景知识填补的空间越大，H 越高，这是 intake 不接地的直接症状。

**逃逸率信号空缺**：所有 GCL 测量目前无法对接"这个 gate 决策后来正确了没有"。在 TASK-176d 完成之前，GCL 只是认知负载的计量，不是监督质量的计量——因为缺少行为接地这一校准锚。

---

## 7. 可移植的接地基础设施设计原则

这个框架不绑定本项目，对任何 AI 辅助软件开发管线都适用。四条设计原则：

**原则 1：每个 gate 决策应附带独立证据，而非 agent 总结**

gate 的监督证据必须来自独立于被监督 agent 的通道。"agent 说自己做了什么"不构成独立证据；"系统状态分析 + 进程 trace + DoD 执行结果"构成独立证据。这是 H6 在工程层的翻译。

**原则 2：escape rate 是校准锚**

把 gate 决策和后续结果链接起来是整个框架的收敛条件。没有这个链接，监督质量无法测量，gate threshold 无法优化。"看起来通过"和"后来没问题"之间的差距就是逃逸率。

**原则 3：接地层次应匹配任务性质**

- Execution task：系统接地 + 进程接地已充分
- Insight task（架构判断、产品取舍）：还需要行为接地——产品空间观测、竞品参考、用户反馈、运行指标
- H8 的前提正是"充分接地"，不是泛泛的"接地"

**原则 4：B/C gate 是稳定需求，A gate 是衰减的过渡**

随着接地基础设施建设，"因为系统信息没有外化所以需要人判断"（A 类）的场景持续减少；"因为需要偏好/责任锚定所以需要人"（B/C 类）的场景不会消失。接地投资的方向：把 A 类场景工程化压缩，把 B/C 类场景的信息质量最大化。

---

## 8. 与现有框架的关系

**接地基础设施 → evidence independence（H6）**：三层接地是 evidence independence 的工程实现路径。没有这三层，"证据独立"只是框架约束，无法操作化。

**接地基础设施 → H8（insight task）**：H8 的可证伪条件是"grounding 受控"——接地基础设施的建设进度直接决定 H8 何时可以测试。behavioral grounding（产品空间、运行指标）是 insight task 接地的关键缺失层。

**接地基础设施 → actor 网络（cc-actor-network.md §4.4）**：boss actor 的证据独立性来源正是这三层接地。一个只读 worker 自述的 boss 不是接地的 boss——它与 worker 共享同一信源，H6 意义下监督质量接近零。

**接地基础设施 → judgment console（judgment-ux.md §2）**：三个后端项目（meta-cc / archguard / baime/loop-backlog）分别覆盖进程接地、系统接地、gate 结构，缺失的是行为接地通道。judgment console 的"构造性证据独立"原则（§3）依赖接地基础设施已经建好这三层通道。

**接地基础设施 → 自指性分析（baime-self-reference-analysis.md）**：该文确立"观测即自观测"是 BAIME 的核心结构，自知三代演化全在自观测内加速。本文 §2 把它接进 H6 框架：自观测之所以能既快又（部分）独立，是因为身份耦合与通道解耦正交——premise-ledger 和 meta-cc self-trace 在身份上是自观测，在通道上已解耦。该文 §挑战 提出的"纯自指脱离现实"风险，对应本文的"自观测需隔离校准 + 行为接地锚点"（§2.2、§3.3）。

---

## 9. 当前状态与下一步

| 接地层 | 已有实现 | 缺口 |
|--------|---------|------|
| 系统接地 | archguard MCP（完整） | 未集成到 loop-backlog intake |
| 进程接地 | meta-cc MCP（完整） | 未系统化地用于 gate 证据包 |
| 行为接地 | 无 | TASK-176d（escape rate linkage）是最小步 |

优先级建议：
1. **escape rate linkage（TASK-176d）**：行为接地的最小可行实现，同时解锁 H5 验证
2. **pre-dispatch enrichment**：将 archguard risk 自动附加到 worker context，降低 C 分量
3. **gate evidence pack**：将 meta-cc session trace 系统化地注入 gate 决策点，提升 evidence independence

behavioral grounding 的完整建设（用户行为、生产信号）是中长期目标，先有 escape rate 这个最接近的行为信号，再逐步向生产端延伸。
