---
id: TASK-125.7
title: '端到端冒烟:统一双泳道全生命周期'
status: 'Basic: Backlog'
assignee: []
created_date: '2026-06-21 10:23'
labels:
  - 'kind:basic'
dependencies: []
parent_task_id: TASK-125
ordinal: 84000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
epic-to-backlog→促 Epic: Ready→自动 decompose→促子任务 Ready→执行→自动 evaluate+建议→确认 Done。
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 grep -q "terminal:" logs/unified-loop-smoke.log
- [ ] #2 bash scripts/validate-plugin.sh
<!-- DOD:END -->
