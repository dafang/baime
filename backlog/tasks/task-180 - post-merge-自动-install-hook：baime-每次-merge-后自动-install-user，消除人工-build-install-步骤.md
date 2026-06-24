---
id: TASK-180
title: >-
  post-merge 自动 install hook：baime 每次 merge 后自动 install --user，消除人工
  build/install 步骤
status: 'Basic: Proposal'
assignee: []
created_date: '2026-06-24 00:40'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 118000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
当前每次 micro-fix 后需人工执行 'bash scripts/install/install.sh --user && bash scripts/validate-plugin.sh'，在昨天的跨项目验证中至少出现 3 次，是纯机械开销。在 loop-backlog 的 post-merge 路径加一个 hook，在 worktree merge 回 main 后自动触发 install。需考虑：(1) 仅对 baime 自身 repo 生效（不影响外部项目的 loop-backlog）；(2) install 失败要阻断并报告，不静默；(3) 与现有 validate-plugin.sh gate 的顺序关系。
<!-- SECTION:DESCRIPTION:END -->
