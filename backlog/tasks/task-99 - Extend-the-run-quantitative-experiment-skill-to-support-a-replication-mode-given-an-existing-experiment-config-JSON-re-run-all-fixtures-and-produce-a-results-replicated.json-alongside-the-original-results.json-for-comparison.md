---
id: TASK-99
title: >-
  Extend the run-quantitative-experiment skill to support a 'replication' mode:
  given an existing experiment config JSON, re-run all fixtures and produce a
  results-replicated.json alongside the original results.json for comparison
status: Meta-Plan
assignee: []
created_date: '2026-06-20 10:26'
labels: []
dependencies: []
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extend the run-quantitative-experiment skill to support a 'replication' mode: given an existing experiment config JSON, re-run all fixtures and produce a results-replicated.json alongside the original results.json for comparison.

Rationale: Three sub-tasks: (1) add --replicate flag and mode logic to run-quantitative-experiment SKILL.md, (2) implement results comparison report generator, (3) validate with a regression fixture. Replan is expected because the current run-quantitative-experiment skill has an ambiguous output-format contract — the decomposer may produce subtasks that overlap or conflict once implementation reveals format assumptions, triggering a replanner root-cause classification of 'sub-plan'.

This meta-task is part of TASK-93 Exp-K experiment corpus (input MT-05).
Source: plugin/loop-meta/data/task-notes/meta-task-inputs.json
<!-- SECTION:DESCRIPTION:END -->
