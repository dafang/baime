---
id: TASK-176.4
title: 'GCL-176d: gate escape rate tracking'
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 06:12'
updated_date: '2026-06-24 06:44'
labels:
  - 'kind:basic'
dependencies:
  - TASK-176.1
parent_task_id: TASK-176
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Document escape rate extraction procedure and add escape_rate field post-hoc to gcl-events.jsonl records.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: GCL-176d: gate escape rate tracking

## Background
The H5 hypothesis predicts that lower GCL scores correlate with higher task escape rates (tasks that pass a gate but later reach "Basic: Needs Human" or get reaper-requeued). Without an `escape_rate` field in `gcl-events.jsonl`, the GCL-vs-escape-rate table in `gcl-report.sh` (176c) shows only N/A and H5 cannot be tested statistically (176f). This task backfills escape_rate for all existing records and documents how to derive it from backlog state.

## Goals
1. All records in `docs/research/gcl-events.jsonl` have an `escape_rate` field (integer 0 or 1).
2. The escape rate definition and extraction query are documented in `docs/research/gcl-events-schema.md`.
3. The DoD assertion `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert all('escape_rate' in r for r in recs); print('PASS')"` exits 0.

## Proposed Approach
Define escape: a task reached "Basic: Needs Human" after gate approval, or was reaper-requeued. Query `backlog task list --plain` and cross-reference task history. For each task_id in gcl-events.jsonl, check if it ever reached "Needs Human" post-gate. Rewrite gcl-events.jsonl with escape_rate field added per record. Document definition in schema file.

## Trade-offs and Risks
- Not doing: real-time escape tracking — this is a one-time historical annotation.
- Risk: tasks with ambiguous history (no notes) get escape_rate=0 conservatively.
- Not doing: multi-escape tracking per task — single 0/1 flag per gate event is sufficient for H5.

---

# Plan: GCL-176d: gate escape rate tracking

## Phase 1: Document escape rate definition
### Tests (write first)
- `grep -q "escape_rate" docs/research/gcl-events-schema.md` — field documented in schema
- `grep -q "Basic: Needs Human" docs/research/gcl-events-schema.md` — escape definition present

### Implementation
- Append to `docs/research/gcl-events-schema.md`: define `escape_rate` field (int 0|1); define escape as: task_id reached "Basic: Needs Human" after its gate event OR was reaper-requeued; document extraction query: `backlog task list --plain | grep -A2 "Needs Human"`.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "escape_rate" docs/research/gcl-events-schema.md`
- [ ] `grep -q "Basic: Needs Human" docs/research/gcl-events-schema.md`

## Phase 2: Extract escape rates and annotate records
### Tests (write first)
- `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert all('escape_rate' in r for r in recs); print('PASS')"` exits 0

### Implementation
- For each record in `docs/research/gcl-events.jsonl`, look up whether the task_id is currently or was previously in "Basic: Needs Human" by inspecting backlog task list and task notes for reaper entries.
- Rewrite `docs/research/gcl-events.jsonl` with `escape_rate` field (0 or 1) added to each JSON object (preserve all other fields).
- Tasks with no evidence of escape: escape_rate=0.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert all('escape_rate' in r for r in recs); print('PASS')"`

## Phase 3: Validate
### Tests (write first)
- Full assertion: `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert all('escape_rate' in r for r in recs), 'missing escape_rate'; print(f'PASS: {len(recs)} records all have escape_rate')"`

### Implementation
- Run validation and fix any records missing the field.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert all('escape_rate' in r for r in recs), 'missing escape_rate'; print(f'PASS: {len(recs)} records all have escape_rate')"`

## Constraints
- escape_rate is 0 (no escape) or 1 (escaped); no other values.
- Do not remove existing fields from gcl-events.jsonl records.
- Depends on TASK-176.1 having created docs/research/gcl-events.jsonl.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert all('escape_rate' in r for r in recs); print('PASS')"`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
<!-- SECTION:NOTES:BEGIN -->

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: Goals 1/2/3 mapped to Phases 1/2/3 — readable from plan
[E] TDD structure: ### Tests before ### Implementation in all 3 phases — readable from plan
[E] TDD order: first DoD item in each phase is bash scripts/validate-plugin.sh — readable from plan
[E] Acceptance gate: first item is bash scripts/validate-plugin.sh — readable from plan
[E] DoD executability: all items are shell commands (bash/grep/python3) — readable from plan
[E] Absence checks: no grep -qv present — readable from plan
[E] Phase ordering: 1→2→3 strictly linear, no circular deps
[E] Scope discipline: all phases backed by Goals in proposal
[C] File paths: scripts/validate-plugin.sh confirmed; gcl-events.jsonl and schema produced by TASK-176.1 dependency
GCL-self-report: E=8 C=1 H=0

claimed: 2026-06-24T06:39:53Z

Phase 1 DONE: Appended escape_rate field definition to docs/research/gcl-events-schema.md — defines escape (0|1), extraction procedure via backlog task view + keyword search for 'Needs Human' and 'Requeued by reaper'.

Phase 2 DONE: Annotated all 23 records in docs/research/gcl-events.jsonl with escape_rate=0. Checked all 18 unique task IDs (TASK-153 through TASK-186) against backlog task history — none showed evidence of escape (all Basic: Done or Epic: Awaiting Children/Backlog, no Needs Human status, no reaper requeue notes).

Phase 3 DONE: DoD #1 PASS (python3 all() check). DoD #2 PASS (validate-plugin.sh: 0 errors, 55 warnings).

Phase 1 ✓ 2026-06-24T06:41:22Z
Appended escape_rate field definition to gcl-events-schema.md with extraction query
Phase 2 ✓ 2026-06-24T06:42:18Z
Added escape_rate=0 to all 23 gcl-events.jsonl records; all tasks verified as non-escaped (Basic: Done, no Needs Human or reaper requeue)
Phase 3 ✓ 2026-06-24T06:42:18Z
DoD #1 PASS: all 23 records have escape_rate field; DoD #2 PASS: validate-plugin.sh 0 errors

Completed: 2026-06-24T06:44:18Z
<!-- SECTION:NOTES:END -->

Architect review — Iteration 1 — 2026-06-24

Premise ledger:
- scripts/validate-plugin.sh: confirmed present on disk
- docs/research/gcl-events.jsonl + gcl-events-schema.md: created by TASK-176.1 (declared dependency, valid)

Criteria checked:
[PASS] Goal coverage: all 3 Goals addressed across phases
[PASS] TDD structure: Tests before Implementation in all 3 phases
[PASS] TDD order: first DoD item is `bash scripts/validate-plugin.sh` in all phases
[PASS] Acceptance Gate: first item is `bash scripts/validate-plugin.sh`
[PASS] DoD executability: all items are shell commands
[PASS] No grep -qv anti-pattern
[PASS] Phase ordering: linear Phase 1 → 2 → 3, no circular deps
[PASS] Scope discipline: all phases backed by Goals
[PASS] File paths: all valid or covered by declared dependency

GCL self-report: E=1, C=1, H=1 (review task; single-pass structural check, no ambiguity)

Verdict: APPROVED
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert all('escape_rate' in r for r in recs); print('PASS')"
- [ ] #2 bash scripts/validate-plugin.sh
<!-- DOD:END -->
