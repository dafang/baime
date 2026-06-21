---
id: TASK-125.6
title: 删除 loop-meta(技能 26→25)
status: 'Basic: Backlog'
assignee: []
created_date: '2026-06-21 10:23'
labels:
  - 'kind:basic'
dependencies: []
parent_task_id: TASK-125
ordinal: 83000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
移除 skill+symlink;EXPECTED_SKILLS 26→25;清理契约/文档引用。
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 ! test -d plugin/skills/loop-meta
- [ ] #2 bash scripts/validate-plugin.sh
<!-- DOD:END -->
