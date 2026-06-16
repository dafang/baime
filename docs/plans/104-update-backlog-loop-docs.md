# Plan: 使用 meta-cc 检查本项目历史，更新 backlog+loop 使用文档

## Context

本项目（baime）提供了 backlog-setup、feature-to-backlog、task-to-backlog、loop-backlog 四个技能，但 README.md 中缺乏系统性的 backlog+loop 使用流程引导。通过 meta-cc 分析本项目近期的 Claude Code 会话历史，可以从真实使用记录中提炼完整工作流，并以此更新文档，使新用户能够从零完整初始化并自主运行 backlog+loop 机制。

## Phase 1: 用 meta-cc 查询本项目近期会话历史

按以下步骤调用 meta-cc MCP 工具，将结果追加写入 `/tmp/meta-cc-summary.txt`：

1. 调用 `mcp__plugin_meta-cc_meta-cc__query_summaries`，参数 `query="backlog loop worktree"`，将返回文本追加写入文件，前缀标记 `=== query_summaries ===`。
2. 调用 `mcp__plugin_meta-cc_meta-cc__query_tool_blocks`，参数 `query="backlog-setup feature-to-backlog task-to-backlog loop-backlog"`，将返回文本追加写入文件，前缀标记 `=== query_tool_blocks ===`。

重点从结果中提取：
- 哪些技能被调用、按什么顺序
- 初始化步骤（backlog-setup）有哪些子步骤
- 创建任务（task-to-backlog / feature-to-backlog）的典型交互模式
- loop-backlog 的启动条件和轮询行为

### DoD
- [ ] `grep -q "=== query_summaries ===" /tmp/meta-cc-summary.txt`
- [ ] `grep -q "=== query_tool_blocks ===" /tmp/meta-cc-summary.txt`
- [ ] `grep -q "backlog" /tmp/meta-cc-summary.txt`

## Phase 2: 整理 backlog+loop 完整工作流摘要

基于 Phase 1 的查询结果，在 `/tmp/backlog-loop-workflow.md` 中写出完整工作流描述，涵盖：
1. 前置条件（安装 baime、meta-cc 可选）
2. 初始化：`/backlog-setup`
3. 创建任务：`/feature-to-backlog` 或 `/task-to-backlog`
4. 启动自治执行：`/loop-backlog`
5. 查看结果：`backlog task list`

每步须包含典型提示词示例和预期输出说明。

### DoD
- [ ] `grep -q "backlog-setup" /tmp/backlog-loop-workflow.md`
- [ ] `grep -q "loop-backlog" /tmp/backlog-loop-workflow.md`
- [ ] `grep -q "task-to-backlog" /tmp/backlog-loop-workflow.md`
- [ ] `grep -q "feature-to-backlog" /tmp/backlog-loop-workflow.md`
- [ ] `grep -q "backlog task list" /tmp/backlog-loop-workflow.md`

## Phase 3: 更新 README.md — 新增 Backlog + Loop Workflow 章节

在 `/home/yale/work/baime/README.md` 的 `## Quick Start` 章节之后，新增 `## Backlog + Loop Workflow` 章节，内容基于 Phase 2 的摘要，结构为：

```
## Backlog + Loop Workflow

### 1. Initialize
### 2. Create Tasks
### 3. Run the Autonomous Worker
### 4. Monitor Progress
```

每个子节须含可复制的命令示例或提示词示例。同时更新 `## What's Included` 中 backlog-setup / feature-to-backlog / task-to-backlog / loop-backlog 的 Purpose 描述，确保与新章节保持一致。

### DoD
- [ ] `grep -q "## Backlog + Loop Workflow" /home/yale/work/baime/README.md`
- [ ] `grep -q "### 1. Initialize" /home/yale/work/baime/README.md`
- [ ] `grep -q "### 2. Create Tasks" /home/yale/work/baime/README.md`
- [ ] `grep -q "### 3. Run the Autonomous Worker" /home/yale/work/baime/README.md`
- [ ] `grep -q "### 4. Monitor Progress" /home/yale/work/baime/README.md`
- [ ] `grep -q "## Quick Start" /home/yale/work/baime/README.md`
- [ ] `grep -q "loop-backlog" /home/yale/work/baime/README.md`
- [ ] `grep -q "task-to-backlog" /home/yale/work/baime/README.md`
- [ ] `bash /home/yale/work/baime/scripts/validate-plugin.sh`

## Constraints

- README.md 中新增章节须使用英文，与现有文档语言风格一致
- 不得删除或破坏 README.md 中已有的任何章节（包括 ## Quick Start、## What's Included 等）
- meta-cc 查询仅读取历史，不产生任何副作用
- 工作流描述须基于 meta-cc 查询到的真实会话记录，而非纯粹推断

## Acceptance Gate
- [ ] `grep -q "## Backlog + Loop Workflow" /home/yale/work/baime/README.md`
- [ ] `grep -q "### 1. Initialize" /home/yale/work/baime/README.md`
- [ ] `grep -q "### 2. Create Tasks" /home/yale/work/baime/README.md`
- [ ] `grep -q "### 3. Run the Autonomous Worker" /home/yale/work/baime/README.md`
- [ ] `grep -q "### 4. Monitor Progress" /home/yale/work/baime/README.md`
- [ ] `grep -q "## Quick Start" /home/yale/work/baime/README.md`
- [ ] `bash /home/yale/work/baime/scripts/validate-plugin.sh`
