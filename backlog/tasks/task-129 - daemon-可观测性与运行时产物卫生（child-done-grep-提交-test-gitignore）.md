---
id: TASK-129
title: daemon 可观测性与运行时产物卫生（child-done grep / 提交 test / gitignore）
status: 'Basic: Proposal'
assignee: []
created_date: '2026-06-21 12:06'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 88000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
两项独立小修，归为单个 Basic Task。

**Phase A — daemon-status.sh 补全 child-done 事件模式**
scripts/daemon-status.sh 的 last-event grep 为 (basic|epic)-ready:|epic_task:|child_task:|terminal: ，缺 child-done: 。结果：daemon 正在发 child-done 时 daemon-status 仍显示 "(no log)"（本会话 bootstrap 后即如此）。修复：grep 模式加入 child-done: ，并清理已退役的 epic_task:|child_task: 旧模式。

**Phase B — 运行时产物卫生**
loop-backlog 运行时生成 scripts/basic-daemon.test.js（由 ensureDaemonTest 写出）但未入库 —— fresh clone / CI 无法运行该自测。方案：将 basic-daemon.test.js 提交入库（与已入库的 scripts/daemon-routing.test.js 对齐），ensureDaemonTest 退化为"缺失才写 + 始终运行"。同时把运行时产物 backlog/.basic-daemon.log、backlog/.basic-daemon.pid、backlog/.caps/ 加入 .gitignore（本会话这些文件以 untracked 形式污染 git status）。

DoD 应包含：daemon-status.sh 在有 child-done 事件时正确显示 last-event；node scripts/basic-daemon.test.js 通过；git status 不再出现上述运行时产物；validate-plugin.sh 通过。
<!-- SECTION:DESCRIPTION:END -->
