---
adr: "001"
title: "Daemon 脚本归属 plugin，不写入目标项目"
status: Accepted
date: 2026-06-23
applies-to: ["plugin/skills/loop-backlog/SKILL.md", "plugin/skills/loop-backlog/**/*.sh"]
enforcement: static
stage: [check]
lint: |
  ! grep -rE '\$\{?REPO_ROOT\}?/scripts/basic-daemon' plugin/skills/loop-backlog/SKILL.md 2>/dev/null
---

# ADR-001: Daemon 脚本归属 plugin，不写入目标项目

**Status**: Accepted
**Date**: 2026-06-23
**Deciders**: Yale Huang
**Related tasks**: TASK-168

## Context

loop-backlog skill 需要一个后台 Node.js 进程（basic-daemon.js）来监听 backlog 事件并路由任务。早期实现在 skill 执行时将该脚本动态写入目标项目的 `scripts/` 目录，再通过相对路径调用。

这导致了以下问题：
- 目标项目 `scripts/` 被 baime 内部文件污染
- daemon 版本与 plugin 版本可能漂移（目标项目可能保留旧版本）
- 需要在目标项目做清理，增加了部署的副作用

## Decision

`plugin/scripts/basic-daemon.js` 是 daemon 脚本的唯一规范位置。

skill 执行时通过 `$(npm root -g)/baime/plugin/scripts/basic-daemon.js` 或等效绝对路径调用，**不得**将脚本复制或写入目标项目目录。

## Consequences

- 目标项目不产生任何 baime 内部文件的污染
- daemon 版本与 plugin 安装版本严格一致
- plugin 升级时，所有目标项目自动使用新版 daemon
- 目标项目的 `scripts/` 目录出现 `basic-daemon.js` 是违规信号

## Rejected alternatives

**写入目标项目 scripts/**：造成版本漂移、目录污染，且 skill 需要在执行后负责清理，增加复杂度。

**在目标项目 package.json 中声明依赖**：过重，目标项目不应感知 baime 内部实现。
