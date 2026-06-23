# ADR-004: Skill 内部类型名必须带 skill 作用域前缀

**Status**: Accepted
**Date**: 2026-06-23
**Deciders**: Yale Huang
**Related tasks**: TASK-12

## Context

多个 skill 的 SKILL.md 文件中定义了 TypeScript 类型（用于描述参数结构、配置等）。当 Claude Code 同时加载多个 skill 时，相同名称的类型会产生冲突。

典型冲突示例：
- `loop-backlog/SKILL.md` 定义 `Config`
- `backlog-setup/SKILL.md` 也定义 `Config`
- 两者同时在 session 中存在时，行为不确定

## Decision

所有 skill 中定义的 TypeScript 类型名必须以 **PascalCase 的 skill 名** 作为前缀。

命名规则：`{SkillName}{TypeName}`

示例：
- `loop-backlog` → `LoopBacklogConfig`, `LoopBacklogState`
- `backlog-setup` → `BacklogSetupConfig`, `BacklogSetupOptions`
- `epic-to-backlog` → `EpicToBacklogResult`

通用工具类型（如 `Result<T>`）除外，应使用更具体的名称或保留在独立的 stdlib 定义中。

## Consequences

- 跨 skill 的类型名冲突被系统性消除
- 类型名较长，但在 skill 的单文件上下文中可读性仍然良好
- 新增 skill 时，命名规则提供明确的约束，无需逐 skill 检查冲突

## Rejected alternatives

**TypeScript 命名空间/模块**：skill 文件是单文件 prompt（SKILL.md），不是真正的 TypeScript 模块，无法使用 `namespace` 或 `module` 机制。

**不使用类型定义，只用 interface**：同样的冲突问题，命名规范是唯一有效手段。
