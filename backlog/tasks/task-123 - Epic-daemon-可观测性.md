---
id: TASK-123
title: 'Epic: daemon 可观测性'
status: 'Epic: Proposal'
assignee: []
created_date: '2026-06-21 09:16'
labels:
  - 'kind:epic'
dependencies: []
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Epic 目标
basic-daemon.js / epic-daemon.js 作为后台进程运行,但缺乏运行态可观测性(存活、最近事件、日志轮转、崩溃恢复)。本 Epic 补齐 daemon 运维能力。

## 拟拆分的 Basic 子任务(decompose 阶段细化)
1. scripts/daemon-status.sh 报告两个 daemon 的 pid/存活/最近事件
2. 两个 daemon 的结构化日志 + 轮转
3. 陈旧/崩溃 daemon 检测与重启提示

## 验收信号
bash scripts/daemon-status.sh (exit 0)
bash scripts/validate-plugin.sh
<!-- SECTION:DESCRIPTION:END -->
