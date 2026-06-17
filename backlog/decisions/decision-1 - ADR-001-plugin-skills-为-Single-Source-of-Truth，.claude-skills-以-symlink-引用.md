---
id: decision-1
title: 'ADR-001: plugin/skills/ 为 Single Source of Truth，.claude/skills/ 以 symlink 引用'
date: '2026-06-17 09:15'
status: Accepted
---
## Context

本项目同时存在两个 skills 目录，均被 git 跟踪：

| 路径 | 用途 |
|---|---|
| `plugin/skills/<skill>/` | 插件发布源；由 `scripts/install/install.sh` 打包安装到用户环境 |
| `.claude/skills/<skill>/` | Claude Code 运行时加载路径；当前 session 所用的 skill 内容 |

两个目录均为真实目录（非 symlink），内容独立演化，导致：

- **静默分叉风险**：在 `.claude/skills/` 调试好的版本不会自动同步到 `plugin/skills/`，发布出去的仍是旧版。
- **双重维护负担**：同一 skill 的改动需在两处同步执行。
- **验证盲区**：`validate-plugin.sh` 只校验 `plugin/`，`.claude/skills/` 的内容不受 CI 保护。

实际案例：TASK-7（loop-backlog daemon 从 Python 改写为 Node.js）更新了 `.claude/skills/loop-backlog/SKILL.md`（+246 行），但 `plugin/skills/loop-backlog/SKILL.md` 未同步，两版本分叉直到 2026-06-17 被发现。

## Decision

**`plugin/skills/` 是唯一可信来源（Single Source of Truth）。**

`.claude/skills/` 下每个与 plugin 共享的 skill 目录，改为指向对应 `plugin/skills/` 子目录的相对 symlink：

```
.claude/skills/<skill>  →  ../../plugin/skills/<skill>
```

**规则：**

1. 所有 skill 内容的修改均在 `plugin/skills/` 下进行，`.claude/skills/` 不直接包含任何 SKILL.md 文件。
2. 新增对外发布的 skill 时：在 `plugin/skills/` 建目录，在 `.claude/skills/` 建对应 symlink，在 `plugin/.claude-plugin/plugin.json` 的 `commands` 列表中注册。
3. 项目专属（不发布）的 skill 可在 `.claude/skills/` 下建真实目录，须放置 `PRIVATE` 文件标识，且不得在 `plugin.json` 中注册。
4. `validate-plugin.sh` 增加 symlink 一致性检查，对 `plugin.json` 中注册的每个 skill 验证 `.claude/skills/<skill>` 为指向正确目标的 symlink。

**执行（2026-06-17）：**

- 将 `.claude/skills/loop-backlog/SKILL.md`（新版）覆盖至 `plugin/skills/loop-backlog/SKILL.md`，消除已有分叉。
- 删除 `.claude/skills/` 下四个真实目录，替换为 symlink（顺带为全部 22 个 plugin skills 建立 symlink）。
- 新增 `scripts/install/setup-skill-symlinks.sh`，供 clone 后验证或修复使用。
- 在 `validate-plugin.sh` 中加入 symlink 一致性检查。

## Consequences

**正面：**
- 零分叉风险：本地调试即是对发布内容的调试，两者物理上是同一文件。
- git 历史清晰：skill 内容的变更只出现在 `plugin/skills/` 的 diff 中。
- `install.sh` 无需改动：`rsync -a` 跟随 symlink 目标内容，打包时自动复制真实文件。
- CI 覆盖完整：`validate-plugin.sh` 对 `plugin/skills/` 的校验即覆盖运行时实际使用的内容。

**约束：**
- symlink 在 Windows 路径上有限制（本项目仅在 Linux/macOS 开发，可接受）。
- 若意外执行 `cp -r` 等操作破坏 symlink，需运行 `scripts/install/setup-skill-symlinks.sh` 修复。
