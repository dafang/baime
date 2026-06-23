# ADR-003: Monitor prompt 必须自包含响应指令

**Status**: Accepted
**Date**: 2026-06-23
**Deciders**: Yale Huang
**Related tasks**: TASK-166

## Context

loop-backlog 的架构依赖 Monitor 工具触发 Claude Code 的响应逻辑。当 Monitor 检测到日志事件时，Claude 需要知道"收到此事件后应该做什么"。

早期实现将响应逻辑依赖会话上下文（session context）中已加载的 skill 指令。这引发了以下问题：
- 用户执行 `/clear` 后，会话上下文被清空
- Monitor 触发时，Claude 没有任何响应上下文，导致无动作或错误响应
- 跨会话场景（如 Claude Code 重启）同样会丢失响应逻辑

## Decision

Monitor 的 `prompt` 参数必须包含**完整的、自包含的**响应指令，不得依赖外部会话状态或已加载的 skill 内容。

具体要求：
- prompt 内嵌任务类型识别逻辑
- prompt 内嵌对应的工作流步骤（basic task 的执行流程、epic 的分解流程）
- prompt 不假设任何 SKILL.md 内容已在会话中加载

## Consequences

- Monitor 具备跨会话自恢复能力：即使在 `/clear` 或重启后，收到事件也能正确响应
- Monitor 的 prompt 较长，但这是必要代价
- prompt 内容与 SKILL.md 存在一定重复，两者必须保持同步（修改 SKILL.md 中的工作流时，同步更新 prompt）

## Rejected alternatives

**依赖会话上下文中的 skill 指令**：`/clear` 或重启后立即失效，用户必须手动重新加载 skill 才能恢复，不可接受。

**在事件触发时动态加载 skill**：Monitor 的响应是单次 Claude 调用，无法在响应过程中加载新 skill 文件。
