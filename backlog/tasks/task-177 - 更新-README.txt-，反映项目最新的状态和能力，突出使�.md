---
id: TASK-177
title: 更新 README.md ，反映项目最新的状态和能力，突出使�
status: 'Basic: Done'
assignee: []
created_date: '2026-06-23 22:18'
updated_date: '2026-06-23 23:22'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 115000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
更新 README.txt ，反映项目最新的状态和能力，突出使用 BAIME 方法创建 skills 和使用 loop-backlog 等驱动开发。
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Plan: 更新 README.md ，反映项目最新的状态和能力，突出使用 BAIME 方法创建 skills 和使用 loop-backlog 等驱动开发。

## Context
项目的主要文档文件是 README.md 。当前 README 已有一定覆盖，但缺少：
1. 「用 BAIME 方法自己创建 skills」的完整示例
2. 「用 loop-backlog 驱动自主开发」的端到端流程说明
3. **Epic / Basic 两种任务颗粒度**的工作流说明（Epic 自动分解为 Basic 子任务，Basic 自动执行并合并）
4. **前置依赖安装说明**：使用 loop-backlog 工作流前需要先安装第三方工具 `backlog.md`（`npm install -g backlog.md`），并用 `/backlog-setup` 初始化项目 backlog 目录
5. **过程测量与自指/自知/自举方法论**：README 缺少对 BAIME 如何度量自身开发过程、如何用自身工具演化自身的说明——包括 GCL（Gate Comprehension Load）人类监督负担度量、Skill 质量实验七层验收体系、meta-cc 会话历史自分析，以及 BAIME 用自身 OCA 方法论驱动自身演化的自举闭环

## Phase 1: 审查现状与差距分析
读取 README.md 全文（`cat README.md`），同时查看最近 git log（`git log --oneline -20`）了解近期变化。确认以下内容缺失：
- 是否有专门章节说明「如何用 BAIME 方法创建新 skill」？
- loop-backlog 工作流是否有 Epic/Basic 双颗粒度说明？
- skills/agents 数量是否与 validate-plugin.sh 输出一致？

### DoD
- `grep -q '## Backlog + Loop Workflow' README.md`
- `grep -q '## Quick Start' README.md`

## Phase 2: 更新 README.md
在 README.md 中进行以下具体修改（使用 Edit 工具，不重写整个文件）：

1. **技能数量核实**：运行 `bash scripts/validate-plugin.sh 2>&1 | grep -E 'agents|skills'`，如实际数量与 README 不符则更新 "What's Included" 节的描述。

2. **在 `## Installation` 节末尾补充前置依赖说明**：
   loop-backlog 工作流依赖 `backlog.md` CLI（第三方 npm 包）。在 baime 安装步骤之后、安装完成提示之前，插入：
   ```
   ### Prerequisites for loop-backlog workflow
   npm install -g backlog.md
   ```
   并说明：安装后需在项目根目录运行 `/backlog-setup` 完成 backlog 目录初始化（详见 Backlog + Loop Workflow 节）。

3. **新增「用 BAIME 创建 Skill」章节**（插入在 "Quick Start" 之后、"Backlog + Loop Workflow" 之前）：
   - 标题：`## Creating Skills with BAIME`
   - 内容：用 `/methodology-bootstrapping` 观察、编码、自动化一个新方法论；用 `/task-to-backlog` 将创建 skill 的任务入队；用 loop-backlog 自动执行。给出 Observe → Codify → Automate 三步示例。

3. **强化 loop-backlog 章节，增加 Epic/Basic 双颗粒度说明**：
   在 "Backlog + Loop Workflow" 的步骤 2（Create Tasks）中补充：
   - `kind:basic` 任务：直接进入执行队列，loop-backlog 在隔离 worktree 中执行并合并
   - `kind:epic` 任务：loop-backlog 调用 `/epic-to-backlog` 自动分解为 Basic 子任务，子任务全部完成后 Epic 自动标记 Done
   - 示意流程：`Epic: Ready → Decomposing → [Basic children: Ready → In Progress → Done] → Epic: Done`
   - 对应命令示例：`/epic-to-backlog "重构认证模块"` 和 `/feature-to-backlog "Add OAuth2 login"`

4. **在 "Backlog + Loop Workflow" 的步骤 1（Initialize）中强化 `/backlog-setup` 说明**：
   明确说明该步骤前提是已安装 `backlog.md`（`npm install -g backlog.md`），并描述 `/backlog-setup` 会创建 `backlog/` 目录、`backlog/tasks/` 子目录及必要的状态列（Basic: Backlog / Basic: Ready / Basic: In Progress / Basic: Done / Needs Human）。

5. **在 "Backlog + Loop Workflow" 的步骤 3（Run the Autonomous Worker）中补充**：
   说明 `kind:epic` 任务被 loop-backlog daemon 自动拾取并拆解（不需要人工干预），并补充 `kind:epic` 任务自动拆解为子任务的行为描述。

6. **新增「过程测量与自举方法论」章节**（插入在 "Backlog + Loop Workflow" 之后、"Related Projects" 之前），标题 `## Measurement & Self-Improvement`，内容包括四个方面：

   **自指（Self-Reference）**：BAIME 的研究对象是 BAIME 本身——用 OCA 方法论开发 OCA 方法论，用 loop-backlog 驱动 loop-backlog 自身的演化。这不是比喻，而是实际的开发模式（可在 git log 中验证）。

   **自知（Self-Knowledge）**：
   - **GCL（Gate Comprehension Load）**：度量人类在 gate 判断时刻的认知密度（E=Efficiency / C=Complexity / H=Human value），作为"人类监督是否仍实质有效"的代理指标。随自动化深化，总时间下降但单位时间认知密度上升（Amdahl 定律的认知版本）。
   - **meta-cc 会话分析**：通过 meta-cc MCP server 查询 Claude Code 会话历史，可分析工具使用频率、上下文切换、token 消耗趋势，作为开发效率的自观测工具。
   - 使用示例：`@workflow-coach` agent 可结合 meta-cc 数据做工作流诊断。

   **过程测量（Process Measurement）**：
   - **Skill 质量实验**（Exp-A 至 Exp-K）：fixture-based oracle 框架，用量化实验验证 skill 设计选择（如 `## Implementation` 节对准确率的贡献）。
   - **七层验收清单**（来自 `docs/llm-capability-measurement-methodology.md`）：指标三元组 / 统计有效性 / 难度分层 / Ground truth / 部署保真度 / 元验证 / Provenance——所有层通过，实验结论才被视为可信。

   **自举（Bootstrapping）**：loop-backlog 当前以 Basic/Epic 双轨处理 BAIME 自身的 backlog，包括 skill 开发、实验执行、文档更新。项目是自己工具链的第一个用户，每个新 skill 落地即进入下一轮 OCA 循环。

### DoD
- `grep -q '## Creating Skills with BAIME' README.md`
- `grep -q 'Observe' README.md`
- `grep -q 'kind:epic' README.md`
- `grep -q 'kind:basic' README.md`
- `grep -q 'epic-to-backlog' README.md`
- `grep -q 'backlog.md' README.md`
- `grep -q 'npm install' README.md`
- `grep -q 'backlog-setup' README.md`
- `grep -q '## Measurement' README.md`
- `grep -q 'GCL' README.md`
- `grep -q 'meta-cc' README.md`
- `grep -q 'Self-Reference\|self-reference\|自指' README.md`

## Phase 3: 验证与收尾
运行插件验证确认无破坏性变更，并检查 README.md 结构完整性。

### DoD
- `bash scripts/validate-plugin.sh`
- `grep -q '## License' README.md`
- `grep -q '## Installation' README.md`

## Constraints
- `test -f README.md` （文件必须已存在，不创建）
- 不创建 README.txt 文件（实际文件是 README.md）
- 不修改 plugin/ 目录下任何 skill 内容
- 不重写整个 README，只做针对性增补
- 不创建分支、不 push、不开 PR

## Acceptance Gate
- `grep -q '## Creating Skills with BAIME' README.md`
- `grep -q 'kind:epic' README.md`
- `grep -q 'kind:basic' README.md`
- `grep -q 'epic-to-backlog' README.md`
- `grep -q 'backlog.md' README.md`
- `grep -q 'npm install' README.md`
- `grep -q 'backlog-setup' README.md`
- `grep -q '## Measurement' README.md`
- `grep -q 'GCL' README.md`
- `grep -q 'meta-cc' README.md`
- `bash scripts/validate-plugin.sh`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan review iteration 2: APPROVED

cap:propose=approved

claimed: 2026-06-23T15:30:00Z

## Execution Summary
Result: Done
Commit: 9101d5f (merged)
All 16 DoD checks passed. Added Prerequisites/backlog-setup to Installation, new ## Creating Skills with BAIME section (OCA), Epic/Basic dual granularity to loop-backlog section, new ## Measurement & Self-Improvement section (GCL, meta-cc, skill experiments, bootstrapping).
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 grep -q '## Backlog + Loop Workflow' README.md
- [ ] #2 grep -q '## Quick Start' README.md
- [ ] #3 grep -q '## Creating Skills with BAIME' README.md
- [ ] #4 grep -q 'Observe' README.md
- [ ] #5 grep -q 'kind:epic' README.md
- [ ] #6 grep -q 'kind:basic' README.md
- [ ] #7 grep -q 'epic-to-backlog' README.md
- [ ] #8 grep -q 'backlog.md' README.md
- [ ] #9 grep -q 'npm install' README.md
- [ ] #10 grep -q 'backlog-setup' README.md
- [ ] #11 grep -q '## Measurement' README.md
- [ ] #12 grep -q 'GCL' README.md
- [ ] #13 grep -q 'meta-cc' README.md
- [ ] #14 bash scripts/validate-plugin.sh
- [ ] #15 grep -q '## License' README.md
- [ ] #16 grep -q '## Installation' README.md
<!-- DOD:END -->
