---
id: TASK-94
title: >-
  Add a contracts-density soft-warning to validate-plugin.sh: emit a warning
  when any SKILL.md has fewer than 1 contract per 50 lines of spec
status: Meta-Plan
assignee: []
created_date: '2026-06-20 10:25'
labels: []
dependencies: []
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a contracts-density soft-warning to validate-plugin.sh: emit a warning when any SKILL.md has fewer than 1 contract per 50 lines of spec, helping catch under-specified skills early in CI.

Rationale: validate-plugin.sh already has a contracts-count path; this extends it with a density check. Two sub-tasks: (1) implement density check in shell, (2) add a regression test in validate-plugin test suite. Clear, measurable acceptance criteria make replan unlikely.

This meta-task is part of TASK-93 Exp-K experiment corpus (input MT-01).
Source: plugin/loop-meta/data/task-notes/meta-task-inputs.json
<!-- SECTION:DESCRIPTION:END -->
