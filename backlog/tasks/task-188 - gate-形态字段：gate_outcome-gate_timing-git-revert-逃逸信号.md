---
id: TASK-188
title: gate 形态字段：gate_outcome / gate_timing + git-revert 逃逸信号
status: 'Basic: Proposal'
assignee: []
created_date: '2026-06-24 09:35'
labels:
  - 'kind:basic'
  - 'area:research'
dependencies:
  - TASK-176.1
  - TASK-176.4
references:
  - docs/research/gate-temporal-portfolio.md
  - docs/research/gcl-events-schema.md
  - docs/research/gcl-synthesis.md
ordinal: 119000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extend gcl-events.jsonl instrumentation to capture gate *form* (gate-temporal-portfolio.md), making H9 measurable. TASK-176.4 already added escape_rate (Needs Human / reaper only). This follow-on adds the two form fields and a third escape signal.

Background: the current schema models gates as synchronous prior decisions. Actual development uses a temporal portfolio of gate forms — defer (搁置), optimistic-execute + posterior git-revert, and batch retrospective cleanup — driven by low execution/reversal cost. The schema doc (gcl-events-schema.md) and H9 (gcl-synthesis.md) already define the concepts; this task wires them into the data + extraction logic.

Phase 1: backfill `gate_outcome` (approved | deferred | iterate | abandoned) and `gate_timing` (prior | posterior | batch) onto all existing gcl-events.jsonl records, defaulting historical records to gate_outcome=approved / gate_timing=prior (they were all prior-synchronous reviewLoop gates). Phase 2: extend the escape extraction procedure to detect git-revert / branch-abandon of a gate-approved change as escape_rate=1 (in addition to Needs Human / reaper), and document the git-log-based detection query in gcl-events-schema.md. Phase 3: handle deferred records — gate_outcome=deferred events have escape_rate=null until final disposition (revived=0, batch-archived=excluded as "无效搁置"). Phase 4: extend gcl-report.sh (TASK-176.3) to stratify GCL and escape_rate by gate_timing, so H9 (posterior vs prior H-fraction + escape) becomes a queryable report.

DoD: all gcl-events.jsonl records have gate_outcome and gate_timing fields; gcl-events-schema.md documents the git-revert escape query; gcl-report.sh prints a gate_timing-stratified table; bash scripts/validate-plugin.sh passes.
<!-- SECTION:DESCRIPTION:END -->
