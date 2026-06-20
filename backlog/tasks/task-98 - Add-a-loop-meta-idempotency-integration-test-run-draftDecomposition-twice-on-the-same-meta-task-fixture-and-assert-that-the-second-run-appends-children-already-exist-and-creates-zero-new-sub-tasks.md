---
id: TASK-98
title: >-
  Add a loop-meta idempotency integration test: run draftDecomposition twice on
  the same meta-task fixture and assert that the second run appends 'children
  already exist' and creates zero new sub-tasks
status: Meta-Plan
assignee: []
created_date: '2026-06-20 10:26'
labels: []
dependencies: []
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a loop-meta idempotency integration test: run draftDecomposition twice on the same meta-task fixture and assert that the second run appends 'children already exist' and creates zero new sub-tasks.

Rationale: Two sub-tasks: (1) write shell integration test fixture and driver, (2) wire it into the CI job in .github/workflows. The idempotency guard code already exists; this is purely testing and CI plumbing.

This meta-task is part of TASK-93 Exp-K experiment corpus (input MT-04).
Source: plugin/loop-meta/data/task-notes/meta-task-inputs.json
<!-- SECTION:DESCRIPTION:END -->
