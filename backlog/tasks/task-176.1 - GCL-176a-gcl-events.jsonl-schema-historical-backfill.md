---
id: TASK-176.1
title: 'GCL-176a: gcl-events.jsonl schema + historical backfill'
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 06:11'
updated_date: '2026-06-24 06:31'
labels:
  - 'kind:basic'
dependencies: []
parent_task_id: TASK-176
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create `docs/research/gcl-events.jsonl` with defined schema and backfill 13 historical gate events.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: GCL-176a: gcl-events.jsonl schema + historical backfill

## Background
GCL (Gate Confidence Level) self-reports exist in premise-ledger notes of individual tasks, but are scattered and not queryable. To enable statistical analysis of gate reliability (H5/H6/H7 hypotheses), we need a single structured JSONL file that captures every gate event with its E/C/H breakdown, gate type, task kind, and metadata. Without this, drift analysis, escape-rate correlation, and hypothesis testing (176f) cannot run.

## Goals
1. `docs/research/gcl-events.jsonl` exists and is valid JSONL (all lines parse with `json.loads`).
2. `docs/research/gcl-events-schema.md` documents all required fields: task_id, gate_type, task_kind, timestamp, E, C, H, GCL, reviewer_model, sample_run_id, evidence_independence, gate_actor_type, premise_lines.
3. At least 13 historical gate events are present (backfilled from TASK-151 onward).

## Proposed Approach
Define a fixed JSONL schema (one JSON object per line). Write schema documentation first. Then parse existing premise-ledger notes from task files (backlog/tasks/) to extract E/C/H values and populate the file. Set `evidence_independence=unknown` and `gate_actor_type=llm` for all historical records since these were not captured originally.

## Trade-offs and Risks
- Not doing: real-time streaming; the file is append-only and written manually/via hooks (176b).
- Risk: some historical tasks may lack complete E/C/H data — those records will have null values.
- Not doing: database or SQLite; JSONL is simpler and git-friendly for this scale.

---

# Plan: GCL-176a: gcl-events.jsonl schema + historical backfill

## Phase 1: Define schema and write documentation
### Tests (write first)
- `test -f docs/research/gcl-events-schema.md` — schema doc exists
- `grep -q "evidence_independence" docs/research/gcl-events-schema.md` — key field documented

### Implementation
- Create `docs/research/gcl-events-schema.md` with field table covering: task_id, gate_type, task_kind, timestamp, E, C, H, GCL, reviewer_model, sample_run_id, evidence_independence, gate_actor_type, premise_lines.
- Field table format: name | type | description | allowed values.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/gcl-events-schema.md`
- [ ] `grep -q "evidence_independence" docs/research/gcl-events-schema.md`

## Phase 2: Historical backfill
### Tests (write first)
- `python3 -c "import json; [json.loads(l) for l in open('docs/research/gcl-events.jsonl')]"` — valid JSONL
- `test $(wc -l < docs/research/gcl-events.jsonl) -ge 13` — 13+ records

### Implementation
- Parse `backlog/tasks/task-*.md` files for premise-ledger entries containing `GCL-self-report: E=N C=N H=N`.
- For each match: extract task_id, E, C, H from the note; set gate_type from context (plan/proposal); task_kind=basic; timestamp from task updated_date; GCL=E+C+H; reviewer_model=claude-sonnet-4-6; sample_run_id=null; evidence_independence=unknown; gate_actor_type=llm; premise_lines=null.
- Append one JSON line per event to `docs/research/gcl-events.jsonl`.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 -c "import json; [json.loads(l) for l in open('docs/research/gcl-events.jsonl')]"`
- [ ] `test $(wc -l < docs/research/gcl-events.jsonl) -ge 13`

## Phase 3: Validate
### Tests (write first)
- Full DoD assertion: `python3 -c "import json; lines=list(open('docs/research/gcl-events.jsonl')); assert len(lines)>=13, f'Only {len(lines)} lines'; [json.loads(l) for l in lines]; print('PASS')"`

### Implementation
- Run validation command and confirm output is PASS.
- Fix any malformed JSON lines found.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 -c "import json; lines=list(open('docs/research/gcl-events.jsonl')); assert len(lines)>=13, f'Only {len(lines)} lines'; [json.loads(l) for l in lines]; print('PASS')"`

## Constraints
- Do not modify existing task files when extracting historical data.
- JSONL file must be append-only; no in-place editing of existing lines.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 -c "import json; lines=list(open('docs/research/gcl-events.jsonl')); assert len(lines)>=13, f'Only {len(lines)} lines'; [json.loads(l) for l in lines]; print('PASS')"`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
<!-- SECTION:NOTES:BEGIN -->

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: 3 goals mapped to Phase 1/2/3 and Acceptance Gate — readable directly from task file
[E] TDD structure: ### Tests before ### Implementation in each phase — readable from plan
[E] TDD order: first DoD item in each phase is bash scripts/validate-plugin.sh — readable from plan
[E] Acceptance gate: first item is bash scripts/validate-plugin.sh — readable from plan
[E] DoD executability: all items are shell commands, no natural-language entries — readable from plan
[H] Absence check pattern: no grep -qv present; pattern correctness judged from background knowledge
[E] Phase ordering: P1 creates schema, P2 backfills, P3 validates — logical sequence readable from plan
[E] Scope discipline: all phases trace to Goals 1-3 — readable from proposal+plan
[C] File paths: docs/research/ not yet created (new files); scripts/validate-plugin.sh and backlog/tasks/ confirmed present in repo
GCL-self-report: E=7 C=1 H=1

claimed: 2026-06-24T06:25:20Z

DoD: PASS. gcl-events.jsonl created with 23 records (TASK-153 through TASK-186). Schema documented in gcl-events-schema.md with 13 fields including evidence_independence (H6) and gate_actor_type (H7). validate-plugin.sh: ALL CHECKS PASSED.
<!-- SECTION:NOTES:END -->

Plan review iteration 1: APPROVED
premise-ledger:
[E] Goal coverage: All 3 Goals addressed by Phase 1 (schema doc), Phase 2 (backfill), Phase 3 (validation)
[E] TDD structure: Every Phase has ### Tests then ### Implementation in correct order
[E] TDD order: First DoD item in each Phase is bash scripts/validate-plugin.sh
[E] Acceptance gate: First Acceptance Gate item is bash scripts/validate-plugin.sh
[C] DoD executability: All DoD and Acceptance Gate items are shell commands; no natural-language items present
[C] Absence checks: No grep -qv patterns; only presence checks used
[C] Phase ordering: Schema doc (P1) → backfill (P2) → validate (P3); no circular deps
[H] Scope discipline: All phases trace directly to proposal Goals; no out-of-scope work
[H] File paths: New files (docs/research/*) are being created by task; backlog/tasks/ and scripts/validate-plugin.sh exist
GCL-self-report: E=3 C=3 H=3
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 python3 -c "import json; lines=list(open('docs/research/gcl-events.jsonl')); assert len(lines)>=13, f'Only {len(lines)} lines'; [json.loads(l) for l in lines]; print('PASS')"
- [ ] #2 bash scripts/validate-plugin.sh
<!-- DOD:END -->
