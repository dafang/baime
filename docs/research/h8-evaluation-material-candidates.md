# H8 评测材料候选集

**状态**：H8 评测集设计（Phase 4）
**日期**：2026-06-24
**依赖**：docs/research/h8-insight-task-taxonomy.md（任务类型），h8-grounding-controlled-operationalization.md（EGEP 格式）
**数据来源**：docs/adr/（已扫描全部 6 个 ADR），docs/proposals/（已扫描 14 个 proposal），docs/research/（已扫描 gcl-synthesis.md, gcl-drivers.md, grounding-infrastructure.md 等）

---

## §0 选择标准

### 必要条件

1. **真实历史案例**：决策已实际发生，有可引用的文档证据（ADR、proposal 审查记录、research 结论）
2. **证据可构造 EGEP**：所需 grounding 证据（文档证据 / 结构证据）可从 `docs/adr/`、`docs/research/`、`docs/proposals/` 中提取
3. **A 类判断**：判断质量可独立于偏好或制度授权被评分（排除 B/C 类 gate）
4. **结果已知**：案例有后续结果（ADR 被接受/拒绝、proposal 被批准/修订）可用于事后效度验证

### 加分项

- 有多个备选方案（适合架构对比类型）
- 在 EGEP 构造时有 2 种以上证据类型（文档 + 结构）
- 有后续逃逸记录（escape_rate > 0）可用于评分体系校准

### 排除标准

- 纯机械决策（只需执行 shell 命令即可判断）
- 偏好性决策（目标函数依赖未编码的组织偏好）
- 制度合规决策（合法性来自制度授权，不是认知质量）

---

## §1 候选案例

### 案例 H8-M-001：daemon 脚本位置决策

**来源文件**：`docs/adr/ADR-001-daemon-script-location.md`
**关联任务**：TASK-168
**决策日期**：2026-06-23

**任务类型**：架构对比（Architecture Comparison，类型一）

**判断内容**：loop-backlog skill 需要部署 basic-daemon.js。两个候选方案：
- 方案 A：skill 执行时动态写入目标项目 `scripts/` 目录
- 方案 B：daemon 脚本保留在 plugin 目录，通过绝对路径调用

**所需接地来源**：
- 文档证据（成熟度 3）：ADR-001 Context 节描述方案 A 的已知问题（目录污染、版本漂移、清理副作用）
- 文档证据（成熟度 3）：plugin 目录结构约定（`plugin/scripts/` 路径语义）
- 结构证据（成熟度 2）：codebase 中 `plugin/scripts/basic-daemon.js` 的实际存在和引用关系

**当前接地可用性**：文档证据完全可用；结构证据需 archguard 查询

**难度估计**：低（两个方案对比清晰，约束来自已明确记录的失败模式）

**实际决策**：方案 B（Accepted，ADR-001）

**评测价值**：适合校准低难度基准；方案 A 的失败模式有详细文档，预期完整性评分较高但需要识别版本漂移这一关键权衡

---

### 案例 H8-M-002：Monitor 生命周期管理策略

**来源文件**：`docs/adr/ADR-002-monitor-lifecycle.md`
**关联任务**：TASK-169
**决策日期**：2026-06-23

**任务类型**：架构对比（Architecture Comparison，类型一）

**判断内容**：当 loop-backlog 重启时，对已存在的 Monitor 进程如何处置。三个候选方案：
- 方案 A：检测到已有 Monitor 则跳过创建（保留旧进程）
- 方案 B：清理旧 Monitor（stopStaleMon()）后再创建新 Monitor
- 方案 C：依赖 Monitor 自然超时退出

**所需接地来源**：
- 文档证据（成熟度 3）：ADR-002 Context 节（旧 Monitor 不自动终止的已知行为）
- 文档证据（成熟度 3）：ADR-002 Rejected alternatives 节（方案 A 和 C 的失败理由）
- 行为证据（成熟度 1，pending）：meta-cc session 记录，多 Monitor 并存时的实际行为轨迹

**当前接地可用性**：文档证据完全可用；行为证据待 behavioral grounding 基础设施

**难度估计**：中（需要识别"僵尸进程"和"重启期望语义"两个非显而易见的约束）

**实际决策**：方案 B（Accepted，ADR-002）

**评测价值**：测试"被拒绝方案的理由能否被独立推导"——方案 A 的僵尸进程问题和方案 C 的 Monitor 无超时机制是否能从文档证据中识别

---

### 案例 H8-M-003：事件驱动 vs 时间轮询架构选择

**来源文件**：`docs/proposals/proposal-loop-backlog-daemon-monitor-event-driven.md`
**关联任务**：TASK-168（proposal 对应实现）
**日期**：2026-06-23（proposal 审查时点）

**任务类型**：架构对比（Architecture Comparison，类型一）

**判断内容**：loop-backlog worker 的触发机制。两个架构：
- 当前架构：ScheduleWakeup 每 120 秒轮询，队列为空时仍触发完整 Claude 调用
- 提案架构：daemon + Monitor 事件驱动，仅当任务状态变为 Ready 时触发

**所需接地来源**：
- 文档证据（成熟度 3）：proposal Background 节（当前架构的 token 成本问题，延迟问题）
- 文档证据（成熟度 3）：proposal Goals 节（6 项具体目标）
- 文档证据（成熟度 3）：proposal Trade-offs and Risks 节（daemon 泄漏风险、PID 文件陈旧、Monitor 工具行为依赖）
- 结构证据（成熟度 2）：当前 `plugin/skills/loop-backlog/SKILL.md` 中 ScheduleWakeup 的使用情况

**当前接地可用性**：文档证据完全可用；结构证据需 archguard get_file_entities

**难度估计**：中-高（需要识别多个实现细节风险，特别是 Monitor 最长阻塞时间约束）

**实际决策**：提案被采纳实现（TASK-168 → ADR-001/002 作为实现结果）

**评测价值**：权衡识别（TI 维度）的良好测试案例——proposal 已列出权衡，评测关注是否能独立识别 Monitor 工具行为这一关键假设依赖

---

### 案例 H8-M-004：skill 分层测试框架问题定义审查

**来源文件**：`docs/proposals/proposal-skill-layered-test-framework.md`
**关联任务**：TASK-130
**日期**：2026-06-23

**任务类型**：问题定义审查（Problem Definition Review，类型二）

**判断内容**：proposal 提出了 4 层（Layer 0-3）skill 测试框架。审查该 proposal 的问题定义质量：
- 问题的可测量性：当前缺口是否有量化描述？
- 边界完整性：哪些测试场景 in-scope/out-of-scope？
- 前提可靠性："同一会话中发现 7 个 bug" 这个观察是否有支撑？
- 可操作性：4 层分解是否可直接映射为任务？

**所需接地来源**：
- 文档证据（成熟度 3）：proposal Background 节（问题描述和量化观察）
- 文档证据（成熟度 3）：现有 `validate-plugin.sh` 的已有能力说明（在 Background 中已描述）
- 文档证据（成熟度 3）：proposal Goals 节（各 Layer 的具体目标）
- 结构证据（成熟度 2）：`scripts/validate-plugin.sh` 实际内容（验证 Background 描述的准确性）

**当前接地可用性**：文档证据完全可用；结构证据可提取

**难度估计**：中（需要识别"外部测试脚本随 skill 演进而过时"作为核心问题，而不只是"缺少测试"）

**实际决策**：Proposal 被接受并实现（TASK-130 → validate-plugin.sh 扩展）

**评测价值**：问题定义审查类型的标准案例；测试评测者是否能从 Background 的观察中抽取"stale test"而非"no test"作为核心问题

---

### 案例 H8-M-005：H4 假设裁定（GCL 隐性项与 artifact 增加的关系）

**来源文件**：`docs/research/gcl-synthesis.md`（H4 裁定章节）
**关联任务**：TASK-150 Phase 4/6
**日期**：2026-06-22

**任务类型**：问题定义审查（Problem Definition Review，类型二）

**判断内容**：gcl-synthesis.md 的 H4 裁定结论是"H4 null（细化）"而非"H4 confirmed"或"H4 refuted"。审查这一裁定的可辩护性：
- 裁定逻辑的完整性：三档效果（规则类 100%、判断类 33-67%、结构类低）是否足够支撑"null 而非 refuted"？
- 边界设定："N=3 事件，[directional-prediction]" 这一局限是否被充分标注？
- 工程含义的推导：从 H4 null 到"区分隐性项类型"建议的逻辑链是否完整？

**所需接地来源**：
- 文档证据（成熟度 3）：gcl-synthesis.md §H4 详细裁定节（完整推理链）
- 文档证据（成熟度 3）：gcl-definition.md 中 H 分量定义（理解 H 的三类来源）
- 文档证据（成熟度 3）：gcl-drivers.md 中的 N=9 数据表（用于判断 N=3 的局限性声明是否相称）

**当前接地可用性**：文档证据完全可用（三个文件均在 docs/research/ 中）

**难度估计**：高（需要理解 GCL 理论框架，以及如何在小样本下正确标注方向性预测）

**实际决策**：H4 null（细化）裁定被保留并纳入 synthesis 报告，成为后续干预设计的基础

**评测价值**：测试"在数据局限条件下，合理化 null 裁定"的质量——预期高评分应识别到 N=3 局限性标注合理、但 directional-prediction 标签的作用未在正文中解释这一细节

---

### 案例 H8-M-006：接地独立性定义修订（身份隔离 vs 失败模式解耦）

**来源文件**：`docs/research/grounding-infrastructure.md`（§1 核心命题）
**关联任务**：TASK-181 research 阶段
**日期**：2026-06-24

**任务类型**：问题定义审查（Problem Definition Review，类型二）

**判断内容**：grounding-infrastructure.md §1 将"接地独立性"从"观察者身份隔离"修订为"失败模式解耦"。审查这一修订的可辩护性：
- 核心命题是否清晰：两个反例（premise-ledger、meta-cc self-trace）是否充分支撑命题？
- 边界完整性：新定义的"失败模式解耦"是否比"身份隔离"有更清晰的操作边界？
- 工程含义的连贯性：从命题到 §2 的 2×2 矩阵分析，推导是否完整？

**所需接地来源**：
- 文档证据（成熟度 3）：grounding-infrastructure.md §1-2（含 2×2 矩阵）
- 文档证据（成熟度 3）：gcl-complete-observation-mechanism.md §3（测量效度问题，理解为何需要此修订）

**当前接地可用性**：文档证据完全可用

**难度估计**：高（哲学/概念性判断，需要识别"反例支撑命题"的逻辑质量）

**实际决策**：修订被接受并成为 grounding-infrastructure.md 的核心框架

**评测价值**：测试高度概念性判断的质量；预期 LLM 在此类型上具有比较优势（不需要实世界观测积累，纯分析框架）

---

## §2 案例元数据汇总表

| 案例 ID | 任务类型 | 文档来源 | 接地类型 | 当前可用性 | 难度 |
|---------|---------|---------|---------|-----------|------|
| H8-M-001 | 架构对比 | ADR-001 | 文档 + 结构 | 高（结构待 archguard） | 低 |
| H8-M-002 | 架构对比 | ADR-002 | 文档 + 行为 | 中（行为 pending） | 中 |
| H8-M-003 | 架构对比 | proposal-daemon-monitor | 文档 + 结构 | 高（结构待 archguard） | 中-高 |
| H8-M-004 | 问题定义审查 | proposal-skill-test | 文档 + 结构 | 高（结构可提取） | 中 |
| H8-M-005 | 问题定义审查 | gcl-synthesis.md | 文档 | 高 | 高 |
| H8-M-006 | 问题定义审查 | grounding-infrastructure.md | 文档 | 高 | 高 |

**首批评测推荐优先级**（按接地可用性和难度排序）：
1. H8-M-001（低难度，证据完整，适合作为基准校准）
2. H8-M-004（中难度，证据完整，问题定义审查类型的标准案例）
3. H8-M-005（高难度，证据完整，测试理论推理质量）
4. H8-M-003（中-高难度，补充结构证据后）
5. H8-M-002（需行为证据，待 grounding 基础设施后）
6. H8-M-006（高难度，纯文档即可，但概念性强）

---

## §3 未来扩展路径

### 3.1 产品变体预筛类型案例（当前不足）

当前候选集中缺少任务类型三（产品变体预筛）的案例。以下候选在语料中识别但尚未完整构造：

- `proposal-plugin-distribution.md` 中插件分发机制的候选方案筛选（自托管 marketplace vs 直接 git 安装 vs npm 包）
- `proposal-epic-capability-model.md` vs `proposal-epic-split-board.md`（B 档 vs B″ 档的预筛决策，但最终变为设计演化，不完全是预筛）

这些案例在 TASK-176 的 grounding 基础设施完善后，可结合 gcl-events.jsonl 中的 escape_rate 数据补充。

### 3.2 风险判断类型案例（需 archguard 数据积累）

archguard change-risk 数据积累后，可从高 risk 文件的历史变更记录中构造"预测变更风险"类型的评测案例，用于测试机器在结构证据充分时的风险判断能力。

### 3.3 跨类型对照组

未来扩展时建议为每个任务类型至少构造 3 个案例（目前架构对比有 3 个，问题定义审查有 3 个，预筛类型 0 个），形成每类型均衡的评测集。

### 3.4 难度分层策略

当前候选集包含：低 ×1、中 ×2、中-高 ×1、高 ×2。
目标分布：低（2）/ 中（3）/ 高（2）每个难度层均有代表，以便检测 H8 效应是否存在难度交互（grounding 控制对高难度案例的效应是否与低难度不同）。
