---
id: TASK-97
title: >-
  Instrument loop-backlog daemon to emit a structured JSON event line to
  .daemon.log for every task status transition (task-ready, done, needs-human),
  enabling provenance-stamped trace replay in the evaluator slice
status: Meta-Plan
assignee: []
created_date: '2026-06-20 10:26'
labels: []
dependencies: []
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Instrument loop-backlog daemon to emit a structured JSON event line to .daemon.log for every task status transition (task-ready, done, needs-human), enabling provenance-stamped trace replay in the evaluator slice.

Rationale: Three sub-tasks: (1) add JSON event emission to loop-backlog-daemon.js, (2) update extract-replan-markers.sh to parse new JSON lines, (3) add daemon unit tests for new event format. Well-scoped with shell-testable gates.

This meta-task is part of TASK-93 Exp-K experiment corpus (input MT-03).
Source: plugin/loop-meta/data/task-notes/meta-task-inputs.json
<!-- SECTION:DESCRIPTION:END -->
