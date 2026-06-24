# H8 接地受控操作化：等量实世界观测证据包定义

**状态**：H8 评测集设计（Phase 2）
**日期**：2026-06-24
**依赖**：docs/research/grounding-infrastructure.md §3, gcl-complete-observation-mechanism.md §4.2
**关联**：h8-insight-task-taxonomy.md, h8-scoring-rubric.md, h8-statistical-design.md

---

## §0 操作化目标

H8 的核心控制变量是**接地等量性**：人与机器必须在相同的实世界观测证据边界内工作，否则质量差距无法归因到处理能力差异。

本文定义"等量实世界观测证据包"（Equal Grounding Evidence Pack，EGEP）的组成、截止规则、格式规范，以及人类隐性接地外显化程序。

grounding-infrastructure.md §4.2 指出人类在 A 类认知增量中的暂时优势来自 grounding 存量而非处理机制差异。EGEP 的设计目标正是让每次评测实例的 grounding 边界变为**可描述、可复现、可控制**的工程量。

---

## §1 EGEP 组成分类

### 1.1 文档证据（Documentary Evidence）

**来源**：ADR、research 文档、backlog task 历史、proposal 文档

**当前可用性**：高（已存在于 `docs/adr/`、`docs/research/`、`backlog/tasks/`）

**内容范围**：
- 已做决策及其理由（ADR）
- 已完成分析的研究摘要（research/*.md 中结构化章节）
- 相关任务的 Notes 字段（backlog task view --plain 可提取）

**截止操作**：提取特定 `--plain` 快照或 git commit hash 时间点的文件版本，确保人机获得同一版本。

**格式示例**：
```yaml
evidence_type: documentary
source_path: docs/adr/ADR-001-daemon-script-location.md
cutoff_date: 2026-06-23
git_commit: abc1234  # 用于精确复现
content_sections:
  - Context
  - Decision
  - Consequences
```

### 1.2 行为证据（Behavioral Evidence）

**来源**：meta-cc session 信号、工具调用序列、edit 振荡记录

**当前可用性**：低-中（meta-cc MCP 工具可查询，但尚无标准化摘要格式）

**内容范围**：
- 工具调用频率和类型分布（process grounding 的观测层）
- 错误分布、回退次数（失败模式信号）
- 文件修改轨迹（实际修改 vs 计划修改）

**成熟度注释**：`pending behavioral grounding infrastructure`。当前 EGEP 可包含 meta-cc 查询结果的文本摘要，但标准化摘要格式尚未定义（见 grounding-infrastructure.md §3.2 进程接地缺口分析）。

**格式示例（待成熟后扩展）**：
```yaml
evidence_type: behavioral
source: meta-cc:query_session_signals
session_id: <session-id>
cutoff_date: 2026-06-23
maturity: pending_behavioral_grounding_infra
summary_fields:
  - tool_call_count
  - error_rate
  - edit_oscillation_count
```

### 1.3 结构证据（Structural Evidence）

**来源**：archguard change-risk、cochange 分析、依赖图快照

**当前可用性**：中（archguard MCP 可在线查询，但历史快照 replay 尚未标准化）

**内容范围**：
- change-risk 评分（文件维度，来自 git 历史）
- cochange 频率矩阵（哪些文件总是一起变更）
- 依赖图（模块间依赖关系）
- 测试覆盖率（函数/行级别）

**格式示例**：
```yaml
evidence_type: structural
source: archguard:get_change_risk
target_path: plugin/scripts/basic-daemon.js
cutoff_date: 2026-06-23
snapshot_method: archguard_mcp_query_at_commit_hash
git_commit: abc1234
```

---

## §2 信息截止规则

### 2.1 截止原则

人与机器必须在**相同的信息截止点**工作。截止点之后产生的任何信息（包括该 task 的最终结果、后续 ADR、后续 research 文档更新）均不得进入 EGEP。

### 2.2 截止点确定方法

**首选**：git commit hash 截止。每个 EGEP 指定一个 commit hash，所有文档证据以该 commit 时点的文件版本为准。

```bash
# 提取截止 commit 时的文件内容
git show <commit-hash>:docs/adr/ADR-001-daemon-script-location.md
```

**次选**：ISO 8601 日期截止（用于无法精确到 commit 的场景，如 backlog 快照）。日期截止时，取该日期 23:59:59 UTC 前最后一个 commit。

**禁止**：使用"当前"内容（即评测人可能比机器多看到新信息）。

### 2.3 EGEP 内容封装规则

每个评测实例的 EGEP 是一个 Markdown 文件，包含：

1. **frontmatter**（YAML 块）：证据元数据，所有字段见 §3 格式规范
2. **正文**：各证据的摘要或全文（根据来源决定摘录比例）
3. **信息截止声明**：明确声明截止点，提醒评测者不得使用截止点后的知识

**人机共用同一 EGEP 文件**：人类评测者和机器均读同一个 Markdown 包，不存在两份不同内容的输入。

---

## §3 EGEP 格式规范

### 3.1 Frontmatter 字段

```yaml
---
egep_id: EGEP-<task_type>-<case_id>          # 唯一标识，如 EGEP-arch-compare-001
cutoff_date: "2026-06-23T23:59:59Z"           # 信息截止时间点（ISO 8601 UTC）
cutoff_commit: "abc1234"                       # 截止 git commit hash（优先）
task_type: architecture_comparison             # 来自 h8-insight-task-taxonomy.md 的任务类型
evidence_types:                               # 本 pack 包含哪些证据类型
  - documentary
  - structural                                # behavioral 项留空时注明 maturity: pending
behavioral_evidence_maturity: pending_behavioral_grounding_infra
source_paths:                                 # 所有文档来源的相对路径
  - docs/adr/ADR-001-daemon-script-location.md
  - docs/proposals/proposal-loop-backlog-daemon-monitor-event-driven.md
difficulty_estimate: medium                   # 来自 h8-evaluation-material-candidates.md
human_implicit_grounding_externalized: true   # 是否完成了隐性接地外显化程序（见 §4）
---
```

### 3.2 正文结构模板

```markdown
## 信息截止声明

本 EGEP 的信息截止点为 **<cutoff_date>**（commit: <cutoff_commit>）。
请评测者**不使用截止点之后**获得的任何信息（包括该决策的最终结果、后续文档更新等）。

## 任务描述

[来自 h8-insight-task-taxonomy.md 对应类型的任务模板，填入具体场景]

## 证据包

### 文档证据

[逐份摘录相关文档的关键章节，注明来源路径和版本]

### 结构证据（如有）

[archguard 查询结果，注明查询时间和参数]

### 行为证据（如有，当前标注为 pending）

[meta-cc 查询摘要，注明 maturity: pending_behavioral_grounding_infra]

## 评测约束

- 仅使用本 EGEP 内的信息
- 如有 pending 证据，说明在没有该证据时如何处理
```

---

## §4 人类隐性接地外显化程序

### 4.1 问题

人类评测者拥有比 EGEP 更多的背景知识（曾参与该项目、读过相关文档、有行业经验），这部分"隐性 grounding"不在 EGEP 中但会影响判断。

gcl-definition.md 中的 H（隐性项）分量正是捕获这种背景知识的度量。但在 H8 评测中，我们需要更系统的外显化程序，而不只是事后的 H 计数。

### 4.2 外显化程序

评测者在开始评测前，完成以下"隐性知识声明"步骤：

**步骤 1：直接参与声明**
```
问：你是否曾直接参与本 EGEP 所描述的决策过程？
选项：是 / 否 / 不记得
如果是：简要描述你的参与内容（≤50字）
```

**步骤 2：背景文档访问记录**
```
问：EGEP 发出后截止点前，你是否读过与本案例直接相关的背景文档（EGEP 中未包含的）？
选项：是 / 否
如果是：列出文档名称（用于标注 grounding 不等量的案例）
```

**步骤 3：隐性假设外显化**
```
问：在开始评测前，你对本案例的直觉判断是什么？（一句话）
你的判断主要依赖哪一条不在 EGEP 中的知识？
```

**步骤 4：不对称接地标记**
如果步骤 1-3 中存在"是"或重要隐性假设，该评测实例标记为 `grounding_asymmetry: partial`。分析时此类实例单独分层，不与 `grounding_asymmetry: none` 的实例混合计算 H8 主效应。

### 4.3 机器侧等价处理

机器（LLM）的 prompt 中加入明确的接地边界声明：

```
你只能使用以下证据包中的信息做出判断。
证据包截止于 <cutoff_date>。
请不要使用你的预训练知识中可能包含的、关于本项目截止日期之后的发展信息。
如果你认为做出判断还需要截止日期之后才出现的信息，请明确指出缺口。
```

---

## §5 成熟度注释框架

每个 EGEP 的每类证据标注成熟度级别：

| 级别 | 标签 | 含义 |
|------|------|------|
| 0 | `not_available` | 该类证据当前无法获取 |
| 1 | `pending_infra` | 对应接地基础设施尚未建立（如 behavioral evidence 需要进程接地基础设施） |
| 2 | `available_unstandardized` | 证据可获取但格式未标准化，需手工处理 |
| 3 | `available_standardized` | 证据可按本文 §3 格式规范机械生成 |

**当前各类型成熟度**（2026-06-24）：

| 证据类型 | 成熟度 | 备注 |
|---------|--------|------|
| 文档证据 | 3 | docs/adr/ 和 docs/research/ 已有 git 版本控制 |
| 结构证据 | 2 | archguard MCP 可查询，但历史快照 replay 尚未标准化 |
| 行为证据 | 1 | 依赖进程接地基础设施（见 grounding-infrastructure.md §3.2） |

**behavioral evidence 标注**：所有当前 EGEP 中的 behavioral evidence 字段标注 `maturity: pending_behavioral_grounding_infra`，表示在 grounding-infrastructure.md 中定义的进程接地基础设施建立后才可填充。这不阻断 H8 评测的启动——可先用文档证据 + 结构证据的子集进行首批评测，behavioral evidence 在后续轮次填入。
