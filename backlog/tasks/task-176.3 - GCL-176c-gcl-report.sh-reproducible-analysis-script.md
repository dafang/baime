---
id: TASK-176.3
title: 'GCL-176c: gcl-report.sh reproducible analysis script'
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 06:12'
updated_date: '2026-06-24 06:42'
labels:
  - 'kind:basic'
dependencies: []
parent_task_id: TASK-176
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create scripts/gcl-report.sh that reads gcl-events.jsonl and outputs stratified E/C/H stats, delta_H trend, and GCL-vs-escape-rate table.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: GCL-176c: gcl-report.sh reproducible analysis script

## Background
`gcl-events.jsonl` (created in TASK-176a) accumulates gate events with E/C/H breakdowns, but there is no script to transform the raw JSONL into the statistical summaries needed for drift detection and hypothesis validation. Researchers (and the scheduled alerting in TASK-176h) need a reproducible, zero-dependency script that produces stratified stats, rolling trend, and a GCL-vs-escape-rate table on demand.

## Goals
1. `scripts/gcl-report.sh` exists and exits 0 when run with valid `docs/research/gcl-events.jsonl` present.
2. The script outputs: (a) mean/std of E, C, H stratified by gate_type × task_kind; (b) delta_H column (H − baseline 1.70); (c) rolling 30-day mean GCL trend; (d) GCL-vs-escape-rate pairing table (shows N/A when escape_rate field is absent).
3. The script uses only `python3` (stdlib) — no pip installs required.

## Proposed Approach
Write `scripts/gcl-report.sh` as a thin shell wrapper that invokes an inline Python 3 script (via `python3 -c` or heredoc). The Python script reads `docs/research/gcl-events.jsonl`, groups records, computes statistics with only `statistics` stdlib, and prints formatted tables to stdout. Handle missing `escape_rate` field gracefully.

## Trade-offs and Risks
- Not doing: interactive dashboards or HTML output — plain text tables are sufficient for CLI and log inspection.
- Risk: if gcl-events.jsonl is empty, the script should exit 0 with an empty-table warning, not crash.
- Not doing: scipy/pandas — stdlib only to keep zero-dependency constraint.

---

# Plan: GCL-176c: gcl-report.sh reproducible analysis script

## Phase 1: Design and implement script
### Tests (write first)
- `test -f scripts/gcl-report.sh` — script file exists
- `bash -n scripts/gcl-report.sh` — bash syntax valid

### Implementation
- Create `scripts/gcl-report.sh` with shebang `#!/usr/bin/env bash`, sets `JSONL_FILE="${1:-docs/research/gcl-events.jsonl}"`, invokes inline Python 3 heredoc that reads JSONL, groups by gate_type×task_kind, computes mean/std of E/C/H, prints delta_H (H−1.70), computes rolling 30-day mean GCL, prints GCL-vs-escape_rate table (N/A if field absent). Handles empty file: print "No events found." and exit 0. Uses only Python stdlib.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f scripts/gcl-report.sh`
- [ ] `bash -n scripts/gcl-report.sh`

## Phase 2: Validate with synthetic data
### Tests (write first)
- Run script with one-line synthetic JSONL to confirm exit 0 and valid output.
- Run with empty input to confirm graceful empty handling.

### Implementation
- Run the script against a synthetic one-record JSONL and an empty file.
- Fix any runtime errors found.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash scripts/gcl-report.sh`

## Constraints
- No pip installs; Python stdlib only.
- Script must handle missing `escape_rate` field without error.
- Empty JSONL file must exit 0 (not error).

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash scripts/gcl-report.sh`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
<!-- SECTION:NOTES:BEGIN -->

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: Goals 1/2/3 covered by Phase 1 (script creation, outputs, stdlib) and Phase 2 (exits 0, empty handling) — readable from plan
[E] TDD structure: ### Tests before ### Implementation in both phases — readable from plan
[E] TDD order: first DoD item in each phase is bash scripts/validate-plugin.sh — readable from plan
[E] Acceptance gate: first item is bash scripts/validate-plugin.sh — readable from plan
[E] DoD executability: all items are shell commands — readable from plan
[E] Absence checks: no grep -qv present — readable from plan
[E] Phase ordering: P1 creates script, P2 validates — sequential, readable from plan
[E] Scope discipline: both phases backed by Goals — readable from proposal+plan
[C] File paths: scripts/validate-plugin.sh confirmed present; scripts/gcl-report.sh is the artifact being created
GCL-self-report: E=8 C=1 H=0

claimed: 2026-06-24T06:39:08Z

Agent execution complete (2026-06-24). Created scripts/gcl-report.sh (185 lines, Python stdlib only). Three sections: (1) stratified E/C/H stats with delta_H by gate_type×task_kind, (2) rolling 30-day mean GCL trend anchored to each unique event date, (3) GCL-vs-escape_rate table with graceful N/A when field absent. Empty file exits 0. Tested against real 23-event dataset and synthetic single-event with escape_rate. Both DoDs pass. Commit: de865b3.

Phase 1 ✓ 2026-06-24T06:41:29Z
Created scripts/gcl-report.sh with 3-section report: stratified E/C/H, rolling 30-day GCL, GCL-vs-escape_rate
Phase 2 ✓ 2026-06-24T06:41:29Z
Validated: empty file→'No events found.', synthetic data with escape_rate, real 23-event dataset
DoD #1: PASS — bash scripts/gcl-report.sh
DoD #2: PASS — bash scripts/validate-plugin.sh
## Execution Summary
Result: Done
Commit: de865b3

Completed: 2026-06-24T06:42:55Z
<!-- SECTION:NOTES:END -->

Architect review iteration 1 (2026-06-24): Plan APPROVED. All criteria passed — goal coverage complete, TDD structure correct (Tests before Implementation in both phases), first DoD item in each phase and first Acceptance Gate item are `bash scripts/validate-plugin.sh`, all DoD/gate items are shell commands, no grep -qv anti-pattern, phases are sequential with no circular deps, all phases backed by Goals. GCL self-report: E=3, C=3, H=2 (review was straightforward, no ambiguity in plan, no novel reasoning required).
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/gcl-report.sh
- [ ] #2 bash scripts/validate-plugin.sh
<!-- DOD:END -->
