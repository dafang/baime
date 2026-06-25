---
id: TASK-176.7
title: 'GCL-176g: premise-ledger extension to proposal and epic-evaluate gates'
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 06:12'
updated_date: '2026-06-24 06:54'
labels:
  - 'kind:basic'
dependencies:
  - TASK-176.2
parent_task_id: TASK-176
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extend premise-ledger injection in SKILL.md files to fire at proposal gate and epic-evaluate gate with gate_type tagging.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: GCL-176g: premise-ledger extension to proposal and epic-evaluate gates

## Background
TASK-176b added GCL-self-report hooks only to the plan gate in `feature-to-backlog` and `epic-to-backlog`. However, proposal gates and epic-evaluate gates are equally important measurement points: proposal-gate GCL captures early-stage judgment quality, and epic-evaluate-gate GCL captures the final reconciliation judgment. Without these additional gate types, the `gcl-events.jsonl` dataset is incomplete and the gate_type stratification in `gcl-report.sh` will show only "plan" records.

## Goals
1. `plugin/skills/feature-to-backlog/SKILL.md` has GCL-self-report + JSONL append at the proposal gate approval point (gate_type=proposal).
2. `plugin/skills/epic-to-backlog/SKILL.md` has GCL-self-report + JSONL append at the proposal gate approval point (gate_type=proposal).
3. `plugin/skills/loop-backlog/SKILL.md` has GCL-self-report + JSONL append at the epic-evaluate RECOMMENDATION: FINISH/ITERATE note (gate_type=epic-evaluate).
4. `bash scripts/validate-plugin.sh` exits 0 after all changes.

## Proposed Approach
Read each SKILL.md to find the proposal gate approval point (where "APPROVED" is written for proposals) and the epic-evaluate soft-halt (RECOMMENDATION: FINISH/ITERATE in loop-backlog). Insert GCL-self-report premise-ledger note and JSONL append instruction at each location with appropriate gate_type tagging.

## Trade-offs and Risks
- Not doing: extending to loop-backlog basic execution gates — those are not architect-review gates.
- Risk: loop-backlog/SKILL.md may not have an obvious single insertion point; requires careful reading.
- Not doing: retroactive backfill of proposal-gate or epic-evaluate events — historical data is incomplete and noted as such.

---

# Plan: GCL-176g: premise-ledger extension to proposal and epic-evaluate gates

## Phase 1: Identify proposal gate locations in feature-to-backlog/SKILL.md
### Tests (write first)
- `grep -qn "APPROVED" plugin/skills/feature-to-backlog/SKILL.md` — APPROVED marker exists (proposal gate)

### Implementation
- Read `plugin/skills/feature-to-backlog/SKILL.md` and find the section where "APPROVED" is written for the proposal review (distinct from plan review).
- Record the line/section reference for the proposal gate approval point.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "APPROVED" plugin/skills/feature-to-backlog/SKILL.md`

## Phase 2: Add proposal gate GCL hook to feature-to-backlog/SKILL.md and epic-to-backlog/SKILL.md
### Tests (write first)
- `grep -q "gate_type=proposal" plugin/skills/feature-to-backlog/SKILL.md` — proposal gate hook present
- `grep -q "gate_type=proposal" plugin/skills/epic-to-backlog/SKILL.md` — proposal gate hook present

### Implementation
- In `plugin/skills/feature-to-backlog/SKILL.md`, at the proposal gate APPROVED write point, insert GCL-self-report premise-ledger instruction and JSONL append instruction with gate_type=proposal, task_kind=basic.
- In `plugin/skills/epic-to-backlog/SKILL.md`, at the proposal gate APPROVED write point, insert the same with gate_type=proposal, task_kind=epic.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "gate_type=proposal" plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `grep -q "gate_type=proposal" plugin/skills/epic-to-backlog/SKILL.md`

## Phase 3: Identify and extend epic-evaluate gate in loop-backlog/SKILL.md
### Tests (write first)
- `grep -q "FINISH\|ITERATE" plugin/skills/loop-backlog/SKILL.md` — FINISH/ITERATE recommendation point exists

### Implementation
- Read `plugin/skills/loop-backlog/SKILL.md` and find the epicEvaluate soft-halt where RECOMMENDATION: FINISH or ITERATE is written.
- Insert GCL-self-report premise-ledger instruction and JSONL append instruction with gate_type=epic-evaluate, task_kind=epic at that point.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "epic-evaluate" plugin/skills/loop-backlog/SKILL.md`

## Phase 4: Validate plugin
### Tests (write first)
- `bash scripts/validate-plugin.sh` exits 0

### Implementation
- Run `bash scripts/validate-plugin.sh` and fix any contract violations.

### DoD
- [ ] `bash scripts/validate-plugin.sh`

## Constraints
- Do not remove existing plan-gate hooks added by TASK-176b.
- gate_type values must be exactly: proposal, plan, epic-evaluate.
- Depends on TASK-176b for the JSONL format spec.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "gate_type=proposal" plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `grep -q "gate_type=proposal" plugin/skills/epic-to-backlog/SKILL.md`
- [ ] `grep -q "epic-evaluate" plugin/skills/loop-backlog/SKILL.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
<!-- SECTION:NOTES:BEGIN -->

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: Goals 1-4 mapped to Phases 1-4 — readable from plan
[E] TDD structure: ### Tests before ### Implementation in all 4 phases — readable from plan
[E] TDD order: first DoD item in each phase is bash scripts/validate-plugin.sh — readable from plan
[E] Acceptance gate: first item is bash scripts/validate-plugin.sh — readable from plan
[E] DoD executability: all items use grep -q or bash — valid shell commands
[E] Absence checks: no grep -qv present — readable from plan
[E] Phase ordering: 1→2→3→4, strictly linear, no circular deps
[E] Scope discipline: all phases backed by Goals
[C] File paths: feature-to-backlog/SKILL.md, epic-to-backlog/SKILL.md, loop-backlog/SKILL.md all confirmed present
GCL-self-report: E=8 C=1 H=0

claimed: 2026-06-24T06:49:42Z

feat(TASK-176.7) complete: added proposal gate GCL hook (gate_type=proposal, task_kind=basic) to feature-to-backlog/SKILL.md Phase 1b; added gate_type=proposal label to epic-to-backlog/SKILL.md (already had the hook); added epic-evaluate gate GCL hook (gate_type=epic-evaluate, task_kind=epic) to loop-backlog/SKILL.md onChildDone(). validate-plugin.sh: ALL CHECKS PASSED. Committed da12244.

Phase 1 ✓ 2026-06-24T06:53:21Z
Identified proposal gate locations in feature-to-backlog/SKILL.md (Phase 1b, step 4) and confirmed epic-to-backlog already has gate_type=proposal hook
Phase 2 ✓ 2026-06-24T06:53:21Z
Added proposal gate GCL hook (gate_type=proposal, task_kind=basic) to feature-to-backlog/SKILL.md Phase 1b; epic-to-backlog already had it (task_kind=epic)
Phase 3 ✓ 2026-06-24T06:53:21Z
Added epic-evaluate gate GCL hook (gate_type=epic-evaluate, task_kind=epic) to loop-backlog/SKILL.md onChildDone() after RECOMMENDATION write
Phase 4 ✓ 2026-06-24T06:53:21Z
bash scripts/validate-plugin.sh: ALL CHECKS PASSED (0 errors, 55 warnings pre-existing)

Completed: 2026-06-24T06:54:58Z
<!-- SECTION:NOTES:END -->

Architect review APPROVED (iteration 1, 2026-06-24).

Premise ledger:
- All 4 proposal Goals covered across Phases 1-4.
- TDD structure confirmed: every Phase has ### Tests before ### Implementation.
- First DoD item in every Phase is `bash scripts/validate-plugin.sh`.
- First Acceptance Gate item is `bash scripts/validate-plugin.sh`.
- All DoD and Acceptance Gate items are executable shell commands (grep -q / bash).
- No grep -qv anti-pattern found.
- No circular phase dependencies.
- All phases backed by Goals 1-4.
- All three target SKILL.md files confirmed to exist on disk.

GCL self-report: E=high (all criteria verified methodically), C=high (plan is internally consistent and maps cleanly to goals), H=medium (standard review task, no novel judgment required).
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 bash scripts/validate-plugin.sh
<!-- DOD:END -->
