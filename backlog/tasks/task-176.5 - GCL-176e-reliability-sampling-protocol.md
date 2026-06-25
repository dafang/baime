---
id: TASK-176.5
title: 'GCL-176e: reliability sampling protocol'
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 06:12'
updated_date: '2026-06-24 06:47'
labels:
  - 'kind:basic'
dependencies:
  - TASK-176.2
parent_task_id: TASK-176
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement ~10% sampling logic in the premise-ledger hook to re-run GCL self-report with a second run and record intra-rater variance.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: GCL-176e: reliability sampling protocol

## Background
The GCL self-report is a single-rater judgment made by the same LLM agent that performed the gate review. Without any re-test reliability measurement, we cannot distinguish genuine score variance from measurement noise. A ~10% sampling protocol that re-runs GCL scoring on the same gate content in a second independent pass provides an intra-rater variance estimate and flags unstable scores — improving trust in the longitudinal drift data.

## Goals
1. The premise-ledger hook in `plugin/skills/feature-to-backlog/SKILL.md` includes a ~10% sampling trigger: when `hash(task_id) mod 10 == 0`, re-invoke GCL self-report and append a second JSONL line with `sample_run_id = task_id + "-r2"`.
2. The same sampling trigger is present in `plugin/skills/epic-to-backlog/SKILL.md`.
3. `bash scripts/validate-plugin.sh` exits 0 after all changes.

## Proposed Approach
After the primary GCL-self-report write and JSONL append (from TASK-176b), add an instruction block: "If `int(hashlib.md5(task_id.encode()).hexdigest(), 16) % 10 == 0`: re-run GCL self-report on the same gate content as a second independent pass. Append second JSONL line with same fields but `sample_run_id=task_id+'-r2'`. Log `intra-rater-variance: |H_run1 - H_run2|`." This is a prompt instruction, not shell execution.

## Trade-offs and Risks
- Not doing: true inter-rater (different model) reliability — intra-rater is sufficient to detect prompt instability.
- Risk: ~10% rate is too low for fast feedback; acceptable given low gate volume (~2-3 gates per session).
- Not doing: automatic recalibration on high variance — human review handles outliers.

---

# Plan: GCL-176e: reliability sampling protocol

## Phase 1: Add sampling trigger to feature-to-backlog/SKILL.md
### Tests (write first)
- `grep -q "sample_run_id" plugin/skills/feature-to-backlog/SKILL.md` — sampling instruction present
- `grep -q "intra-rater" plugin/skills/feature-to-backlog/SKILL.md` — variance logging present

### Implementation
- In `plugin/skills/feature-to-backlog/SKILL.md`, after the primary JSONL append instruction (added by TASK-176b), insert a sampling check block: if `int(hashlib.md5(task_id.encode()).hexdigest(), 16) % 10 == 0`, re-run GCL self-report, append second JSONL line with `sample_run_id=task_id+"-r2"`, log `intra-rater-variance: |H_run1 - H_run2|`.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "sample_run_id" plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `grep -q "intra-rater" plugin/skills/feature-to-backlog/SKILL.md`

## Phase 2: Add sampling trigger to epic-to-backlog/SKILL.md
### Tests (write first)
- `grep -q "sample_run_id" plugin/skills/epic-to-backlog/SKILL.md` — sampling instruction present
- `grep -q "intra-rater" plugin/skills/epic-to-backlog/SKILL.md` — variance logging present

### Implementation
- In `plugin/skills/epic-to-backlog/SKILL.md`, after the primary JSONL append instruction, insert the same sampling check block.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "sample_run_id" plugin/skills/epic-to-backlog/SKILL.md`
- [ ] `grep -q "intra-rater" plugin/skills/epic-to-backlog/SKILL.md`

## Phase 3: Validate plugin
### Tests (write first)
- `bash scripts/validate-plugin.sh` exits 0

### Implementation
- Run `bash scripts/validate-plugin.sh` and fix any contract violations.

### DoD
- [ ] `bash scripts/validate-plugin.sh`

## Constraints
- Do not alter the primary GCL-self-report or JSONL append instruction from TASK-176b.
- The sampling instruction must be clearly conditional (~10% only).
- Depends on TASK-176b having added the primary JSONL append hook.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "sample_run_id" plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `grep -q "sample_run_id" plugin/skills/epic-to-backlog/SKILL.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
<!-- SECTION:NOTES:BEGIN -->

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: Goals 1/2/3 addressed by Phases 1/2/3 — readable from plan
[E] TDD structure: ### Tests before ### Implementation in all 3 phases — readable from plan
[E] TDD order: first DoD item in each phase is bash scripts/validate-plugin.sh — readable from plan
[E] Acceptance gate: first item is bash scripts/validate-plugin.sh — readable from plan
[E] DoD executability: all items are shell commands — readable from plan
[E] Absence checks: no grep -qv present — readable from plan
[E] Phase ordering: 1→2→3 strictly linear, no circular deps
[E] Scope discipline: all phases backed by Goals
[C] File paths: scripts/validate-plugin.sh, feature-to-backlog/SKILL.md, epic-to-backlog/SKILL.md all confirmed present
GCL-self-report: E=8 C=1 H=0

claimed: 2026-06-24T06:43:17Z

Phase 1-3 complete. Added ~10% reliability sampling blocks after primary JSONL append in: feature-to-backlog/SKILL.md (plan review gate) and epic-to-backlog/SKILL.md (proposal gate + plan review gate). Sampling condition: hashlib.md5(task_id) % 10 == 0. Second pass appends JSONL with sample_run_id=<TASK_ID>-r2 and logs intra-rater-variance H-count diff to task notes. validate-plugin.sh: ALL CHECKS PASSED (0 errors).

Phase 1 ✓ 2026-06-24T06:46:30Z
Added sampling block to feature-to-backlog/SKILL.md after JSONL append in Phase 4 plan review
Phase 2 ✓ 2026-06-24T06:46:30Z
Added sampling blocks to epic-to-backlog/SKILL.md (Phase 1b proposal + Phase 4 plan review)
Phase 3 ✓ 2026-06-24T06:46:30Z
validate-plugin.sh passed: 0 errors, 55 warnings (pre-existing)

Completed: 2026-06-24T06:47:57Z
<!-- SECTION:NOTES:END -->

Architect review (iteration 1, 2026-06-24): Plan APPROVED.

Premise-ledger:
- All 3 proposal Goals addressed by Phases 1-3.
- Every Phase has ### Tests before ### Implementation (TDD structure satisfied).
- First DoD item in each Phase is `bash scripts/validate-plugin.sh`.
- First Acceptance Gate item is `bash scripts/validate-plugin.sh`.
- All DoD and Acceptance Gate items are executable shell commands.
- No `grep -qv` anti-pattern present.
- Phases are linear (1→2→3), no circular dependencies.
- All phases are backed by Goals; no scope creep.
- File paths verified: scripts/validate-plugin.sh, plugin/skills/feature-to-backlog/SKILL.md, plugin/skills/epic-to-backlog/SKILL.md all exist.

GCL self-report: E=3 (all criteria checked systematically), C=3 (clear pass/fail on each criterion, no ambiguity), H=3 (full coverage, no shortcuts).
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 bash scripts/validate-plugin.sh
<!-- DOD:END -->
