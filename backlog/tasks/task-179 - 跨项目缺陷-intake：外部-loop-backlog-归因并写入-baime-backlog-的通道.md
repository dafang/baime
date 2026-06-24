---
id: TASK-179
title: 跨项目缺陷 intake：外部 loop-backlog 归因并写入 baime backlog 的通道
status: 'Basic: Proposal'
assignee: []
created_date: '2026-06-24 00:40'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 117000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
当外部项目（如 archguard、meta-cc）运行 loop-backlog 时，若任务失败可归因于 baime 自身缺陷（skill 崩溃、CLI flag 被拒等，而非目标项目测试逻辑失败），应自动在 baime 的 backlog/tasks/ 写入一个 kind:basic 修复任务，触发 baime daemon 拾取执行。核心挑战：归因判定（区分 baime 缺陷 vs 目标项目问题）+ 跨目录/跨 repo 写入通道设计。
<!-- SECTION:DESCRIPTION:END -->
