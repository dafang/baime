---
id: TASK-125.5
title: loop-backlog worker 增 epic 分发(自动 decompose + child-done evaluate)
status: 'Basic: Backlog'
assignee: []
created_date: '2026-06-21 10:23'
labels:
  - 'kind:basic'
dependencies: []
parent_task_id: TASK-125
ordinal: 82000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
epic-ready→自动 decompose;child-done→reconcile→Evaluating→写 recommendation;吸收 decomposer/createSubTask/evaluator。
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 grep -qE "epic-ready|child-done" plugin/skills/loop-backlog/SKILL.md
- [ ] #2 bash scripts/validate-plugin.sh
<!-- DOD:END -->
