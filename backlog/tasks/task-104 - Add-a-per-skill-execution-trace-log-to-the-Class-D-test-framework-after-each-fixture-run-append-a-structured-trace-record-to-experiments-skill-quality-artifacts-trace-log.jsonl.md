---
id: TASK-104
title: >-
  Add a per-skill execution-trace log to the Class-D test framework: after each
  fixture run, append a structured trace record to
  experiments/skill-quality/artifacts/trace-log.jsonl
status: Meta-Plan
assignee: []
created_date: '2026-06-20 10:27'
labels: []
dependencies: []
ordinal: 85000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a per-skill execution-trace log to the Class-D test framework: after each fixture run, append a structured trace record to experiments/skill-quality/artifacts/trace-log.jsonl with fields {fixture_id, skill, tool_calls, verdict, timestamp} for use by the evaluator trace_replay slice.

Rationale: Three sub-tasks: (1) extend Class-D runner to write trace-log.jsonl entries, (2) add a trace-log schema validator, (3) update evaluator documentation to reference trace-log.jsonl as the trace_replay data source. All acceptance criteria are file-existence and schema-conformance checks.

This meta-task is part of TASK-93 Exp-K experiment corpus (input MT-10).
Source: plugin/loop-meta/data/task-notes/meta-task-inputs.json
<!-- SECTION:DESCRIPTION:END -->
