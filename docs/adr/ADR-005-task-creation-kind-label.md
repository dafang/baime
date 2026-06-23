# ADR-005: 任务创建调用必须包含 kind 标签

**Status**: Accepted
**Date**: 2026-06-23
**Deciders**: Yale Huang
**Related tasks**: TASK-165

## Context

loop-backlog 的 Monitor 通过检测 backlog 日志中的事件来路由任务。事件路由依赖 `kind:basic` 或 `kind:epic` 标签来区分任务类型。

TASK-165 发现有 3 个 skill（feature-to-backlog、task-to-backlog、epic-to-backlog）在调用 `mcp__backlog__task_create` 时遗漏了 `kind` 标签。结果是这些 skill 创建的任务不会被 Monitor 识别，loop-backlog 自动化流程对其无效。

## Decision

所有调用 `mcp__backlog__task_create` 的 skill，**必须**在 `labels` 字段中包含以下之一：
- `kind:basic` — 直接可执行的叶子任务
- `kind:epic` — 需要分解的史诗任务

缺少 `kind` 标签的任务创建调用视为 bug。

## Consequences

- Monitor 能正确识别所有由 baime skill 创建的任务
- 新 skill 的 code review 和 validate-plugin.sh 应检查此约束
- 手动创建任务（不通过 skill）时，用户需自行添加 `kind` 标签（或接受该任务不进入自动化流程）

## Rejected alternatives

**Monitor 忽略 kind 标签，处理所有任务**：会导致非 baime 管理的任务被意外处理，破坏目标项目的自主性。

**在 Monitor 侧补全缺失的 kind 标签**：事后修复数据不如事前约束创建端。
