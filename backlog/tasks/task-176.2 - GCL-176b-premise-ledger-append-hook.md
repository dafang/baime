---
id: TASK-176.2
title: 'GCL-176b: premise-ledger append hook'
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 06:11'
updated_date: '2026-06-24 06:30'
labels:
  - 'kind:basic'
dependencies: []
parent_task_id: TASK-176
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Modify plan-gate self-report step in feature-to-backlog/SKILL.md and epic-to-backlog/SKILL.md to append a JSONL line to gcl-events.jsonl after each gate approval.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: GCL-176b: premise-ledger append hook

## Background
GCL self-reports are currently written manually to task notes during gate reviews, but not simultaneously recorded in the structured `gcl-events.jsonl` file created in TASK-176a. Without an automated hook in the skill prompts, future gate events will fail to populate the JSONL store, breaking the longitudinal drift analysis that H5/H6/H7 depend on.

## Goals
1. `plugin/skills/feature-to-backlog/SKILL.md` contains an instruction after each GCL-self-report step to append a JSONL line to `docs/research/gcl-events.jsonl`.
2. `plugin/skills/epic-to-backlog/SKILL.md` contains the same append instruction at its gate approval point.
3. `bash scripts/validate-plugin.sh` exits 0 after all changes.

## Proposed Approach
Read both SKILL.md files to locate all `GCL-self-report:` write points. After each such write, insert an instruction block directing the executing agent to append one JSON line (with task_id, gate_type, task_kind, timestamp, E, C, H, GCL, reviewer_model, evidence_independence, gate_actor_type) to `docs/research/gcl-events.jsonl`. Validate with the plugin validation script.

## Trade-offs and Risks
- Not doing: actual shell execution within skill prompts — the instruction directs the agent, not a shell hook.
- Risk: agent may skip the append step; reliability depends on prompt fidelity (addressed by TASK-176e sampling).
- Not doing: write to a separate log file; the append goes directly to gcl-events.jsonl.

---

# Plan: GCL-176b: premise-ledger append hook

## Phase 1: Audit GCL-self-report injection points
### Tests (write first)
- `grep -q "GCL-self-report" plugin/skills/feature-to-backlog/SKILL.md` — self-report exists in feature-to-backlog
- `grep -q "GCL-self-report" plugin/skills/epic-to-backlog/SKILL.md` — self-report exists in epic-to-backlog

### Implementation
- Read `plugin/skills/feature-to-backlog/SKILL.md` and identify all lines/sections where `GCL-self-report:` is written.
- Read `plugin/skills/epic-to-backlog/SKILL.md` and identify all `GCL-self-report:` locations.
- Record file:line references for each injection point.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "GCL-self-report" plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `grep -q "GCL-self-report" plugin/skills/epic-to-backlog/SKILL.md`

## Phase 2: Insert JSONL append instruction in feature-to-backlog/SKILL.md
### Tests (write first)
- `grep -q "gcl-events.jsonl" plugin/skills/feature-to-backlog/SKILL.md` — append instruction present

### Implementation
- After each `GCL-self-report:` block in `plugin/skills/feature-to-backlog/SKILL.md`, insert an instruction directing the executing agent to append one JSON line to `docs/research/gcl-events.jsonl` with fields: task_id, gate_type=plan, task_kind=basic, timestamp (UTC ISO), E, C, H, GCL=E+C+H, reviewer_model=claude-sonnet-4-6, sample_run_id=null, evidence_independence=low, gate_actor_type=llm.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "gcl-events.jsonl" plugin/skills/feature-to-backlog/SKILL.md`

## Phase 3: Insert JSONL append instruction in epic-to-backlog/SKILL.md
### Tests (write first)
- `grep -q "gcl-events.jsonl" plugin/skills/epic-to-backlog/SKILL.md` — append instruction present

### Implementation
- After each `GCL-self-report:` block in `plugin/skills/epic-to-backlog/SKILL.md`, insert the same JSONL append instruction with `gate_type` set appropriately (plan or proposal depending on gate position).

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "gcl-events.jsonl" plugin/skills/epic-to-backlog/SKILL.md`

## Phase 4: Validate plugin
### Tests (write first)
- `bash scripts/validate-plugin.sh` exits 0

### Implementation
- Run `bash scripts/validate-plugin.sh` and fix any SKILL.md contract violations introduced by the edits.

### DoD
- [ ] `bash scripts/validate-plugin.sh`

## Constraints
- Do not alter the logical flow or existing review criteria in either SKILL.md.
- The JSONL append instruction must follow the existing GCL-self-report write, not replace it.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "gcl-events.jsonl" plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `grep -q "gcl-events.jsonl" plugin/skills/epic-to-backlog/SKILL.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
<!-- SECTION:NOTES:BEGIN -->

Plan review iteration 1: APPROVED
premise-ledger:
[C] goal coverage: Goals 1/2/3 mapped to Phases 2/3/4 and Acceptance Gate — verified by reading plan + proposal
[C] TDD structure: each Phase has ### Tests before ### Implementation — confirmed by reading plan
[C] TDD order: first DoD item in each Phase is bash scripts/validate-plugin.sh — confirmed by reading plan
[C] Acceptance gate: first item is bash scripts/validate-plugin.sh — confirmed by reading plan
[C] DoD executability: all items are shell commands — confirmed by reading plan
[E] Absence checks: no grep -qv pattern present — readable from plan text
[C] Phase ordering: audit → ftb edit → etb edit → validate, sequential, no circular deps
[C] Scope discipline: each Phase traces to a Goal in proposal
[C] File paths: plugin/skills/feature-to-backlog/SKILL.md, epic-to-backlog/SKILL.md, scripts/validate-plugin.sh all confirmed present
GCL-self-report: E=2 C=7 H=0

claimed: 2026-06-24T06:28:07Z

DoD: PASS. gcl-events.jsonl append hook added to both SKILL.md files. validate-plugin.sh: 0 errors, 55 warnings (pre-existing).
<!-- SECTION:NOTES:END -->

Plan review iteration 1: APPROVED
premise-ledger:
[E] Goal coverage: All 3 proposal goals are addressed by at least one Phase or Acceptance Gate item — Goals 1 & 2 by Phases 2 & 3, Goal 3 by Phase 4 and Acceptance Gate.
[C] TDD structure: Every Phase has ### Tests before ### Implementation in correct order.
[C] TDD order: First ### DoD item in every Phase is `bash scripts/validate-plugin.sh`.
[C] Acceptance gate: First Acceptance Gate item is `bash scripts/validate-plugin.sh`.
[C] DoD executability: All DoD and Acceptance Gate items are runnable shell commands.
[C] Absence checks: No absence checks present; no grep -qv anti-pattern.
[C] Phase ordering: Phases 1→2→3→4 are strictly sequential with no circular deps.
[C] Scope discipline: No Phase implements anything not backed by a Goal.
[E] File paths: All three referenced files verified to exist on disk (feature-to-backlog/SKILL.md, epic-to-backlog/SKILL.md, scripts/validate-plugin.sh); both SKILL.md files confirmed to contain GCL-self-report strings.
GCL-self-report: E=2 C=7 H=0
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 bash scripts/validate-plugin.sh
<!-- DOD:END -->
