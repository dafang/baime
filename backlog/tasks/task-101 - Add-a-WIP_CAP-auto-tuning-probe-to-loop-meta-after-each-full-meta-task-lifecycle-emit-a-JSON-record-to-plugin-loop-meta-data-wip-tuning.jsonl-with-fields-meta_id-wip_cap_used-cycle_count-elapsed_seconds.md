---
id: TASK-101
title: >-
  Add a WIP_CAP auto-tuning probe to loop-meta: after each full meta-task
  lifecycle, emit a JSON record to plugin/loop-meta/data/wip-tuning.jsonl with
  fields {meta_id, wip_cap_used, cycle_count, elapsed_seconds}
status: Meta-Plan
assignee: []
created_date: '2026-06-20 10:26'
labels: []
dependencies: []
ordinal: 82000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a WIP_CAP auto-tuning probe to loop-meta: after each full meta-task lifecycle, emit a JSON record to plugin/loop-meta/data/wip-tuning.jsonl with fields {meta_id, wip_cap_used, cycle_count, elapsed_seconds} to accumulate throughput data for future WIP_CAP calibration.

Rationale: Three sub-tasks: (1) instrument idempotentReconcile to write JSONL record on meta-task completion, (2) add a wip-tuning schema validator script, (3) document the probe in loop-meta data README. All gates are shell-testable.

This meta-task is part of TASK-93 Exp-K experiment corpus (input MT-07).
Source: plugin/loop-meta/data/task-notes/meta-task-inputs.json
<!-- SECTION:DESCRIPTION:END -->
