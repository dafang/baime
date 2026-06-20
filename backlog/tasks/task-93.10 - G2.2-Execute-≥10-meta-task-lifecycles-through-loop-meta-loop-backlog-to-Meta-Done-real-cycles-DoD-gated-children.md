---
id: TASK-93.10
title: >-
  G2.2: Execute ≥10 meta-task lifecycles through loop-meta/loop-backlog to
  Meta-Done (real cycles, DoD-gated children)
status: Backlog
assignee: []
created_date: '2026-06-20 10:05'
updated_date: '2026-06-20 10:06'
labels: []
dependencies:
  - TASK-93.7
parent_task_id: TASK-93
priority: high
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run each of the ≥10 meta-task inputs from G2.1 through the full loop-meta lifecycle: Meta-Plan → Meta-Active → (sub-tasks created with DoD shell-gates) → sub-tasks executed by loop-backlog to Done → evaluateAndReplan → Meta-Done. This is the core data-collection phase of Exp-K.

Each lifecycle must:
- Be a real meta-task in the backlog (not simulated or hand-written)
- Have sub-tasks created by draftDecomposition via createSubTask (each with a ## Definition of Done shell-gate; verified by verify-subtask-dod.sh)
- Have sub-tasks promoted to Ready by setReady and executed to Done by loop-backlog with real verifyDod
- End with an evaluateAndReplan call that appends an `evaluator: Met|NotMet | data_source: measured` note to the meta-task
- Append a `replan: <rootCause> — <summary>` note if a replan event occurred

At the end of all 10+ cycles, the backlog must contain ≥10 tasks in Meta-Done status carrying both evaluator: and idempotentReconcile: markers — these are what check-roi-gate.sh counts as "real meta-task cycles".

This sub-task is the core experiment of TASK-93. It is large and sequential; WIP_CAP means it starts only after G2.1 is Done.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Plan: G2.2 — Execute ≥10 meta-task lifecycles through loop-meta/loop-backlog to Meta-Done

## Context
This is the core data-collection phase of Exp-K (TASK-93). G2.1 produced ≥10 meta-task input files;
G2.2 drives each through the full loop-meta lifecycle so check-roi-gate.sh can measure replan
frequency and root-cause distribution. No simulated or hand-written cycles are permitted — every
Meta-Done task must carry both `evaluator:` and `idempotentReconcile:` markers appended by the
framework itself.

## Phase 1: Pre-flight — verify G2.1 completion and tooling readiness
Confirm that TASK-93.7 (G2.1) is in Done status and that all required scripts exist.

```bash
backlog task view TASK-93.7 --plain 2>/dev/null | grep -q "Status:.*Done"
```
```bash
test -f scripts/verify-subtask-dod.sh
```
```bash
test -f scripts/check-roi-gate.sh
```
```bash
bash scripts/validate-plugin.sh >/dev/null 2>&1
```

### DoD
- [ ] `backlog task view TASK-93.7 --plain 2>/dev/null | grep -q "Status:.*Done"`
- [ ] `test -f scripts/verify-subtask-dod.sh && test -f scripts/check-roi-gate.sh`

## Phase 2: Load meta-task inputs and promote each to Meta-Plan
Read the meta-task input file produced by G2.1 at `plugin/loop-meta/data/task-notes/meta-task-inputs.json`.
For each entry, if not already in the backlog as a meta-task, create it with status Meta-Plan:

```bash
# For each entry in plugin/loop-meta/data/task-notes/meta-task-inputs.json:
#   backlog task create "<entry.goal>" \
#     --status "Meta-Plan" --description "<entry.goal> (rationale: <entry.rationale>)"
```

Verify at least 10 meta-tasks exist at or beyond Meta-Plan:

### DoD
- [ ] `[ "$(backlog task list --status Meta-Plan --plain 2>/dev/null | grep -c 'TASK-')" -ge 1 ] || [ "$(backlog task list --status Meta-Active --plain 2>/dev/null | grep -c 'TASK-')" -ge 1 ]`

## Phase 3: Run loop-meta to drive each meta-task to Meta-Done
Start loop-meta (or run it per-task) to process each Meta-Plan task through:
  Meta-Plan → Meta-Active (draftDecomposition + createSubTask with DoD shell-gates)
            → sub-tasks promoted to Ready by setReady
            → sub-tasks executed to Done by loop-backlog (real verifyDod)
            → evaluateAndReplan appends evaluator: and idempotentReconcile: notes
            → Meta-Done

For each meta-task, monitor that:
- Sub-tasks have `## Definition of Done` shell-gates (verified by verify-subtask-dod.sh)
- loop-backlog executed each sub-task with verifyDod returning exit 0
- evaluateAndReplan appended `evaluator: Met|NotMet | data_source: measured`
- If replan occurred, `replan: <rootCause> — <summary>` note is present

Run loop-meta (invoke the skill) and let it process all inputs. This may take multiple sessions.

### DoD
- [ ] `[ "$(backlog task list --status Meta-Done --plain 2>/dev/null | grep -c 'TASK-')" -ge 10 ]`

## Phase 4: Verify evaluator and idempotentReconcile markers on all Meta-Done tasks
For each Meta-Done task, confirm both required markers are present in notes.

Run check-roi-gate.sh count check:

```bash
bash scripts/check-roi-gate.sh 2>/dev/null | grep -oP "Meta-task cycles detected:\s*\K\d+"
```

### DoD
- [ ] `[ "$(bash scripts/check-roi-gate.sh 2>/dev/null | grep -oP 'Meta-task cycles detected:\s*\K\d+')" -ge 10 ]`
- [ ] `bash scripts/check-roi-gate.sh >/dev/null 2>&1 || [ $? -eq 2 ]`

## Phase 5: Capture replan events and annotate
For any meta-task where evaluateAndReplan triggered a replan cycle, verify the `replan:` note
is present. Collect the set of root-cause labels for downstream analysis by G3.

```bash
grep -rl "replan:" backlog/tasks/ backlog/archive/tasks/ 2>/dev/null | grep -c "."
```

### DoD
- [ ] `bash scripts/check-roi-gate.sh 2>/dev/null | grep -q "Total replan events:"`

## Constraints
- All meta-task cycles must be driven by loop-meta skill, not hand-written
- Sub-tasks must have real shell-verifiable DoD gates (not natural language)
- evaluator: and idempotentReconcile: markers must be appended by the framework, not manually
- This phase may not begin until TASK-93.7 (G2.1) is Done
- Simulated or mock cycles do not count toward the ≥10 threshold

## Acceptance Gate
- [ ] `[ "$(bash scripts/check-roi-gate.sh 2>/dev/null | grep -oP 'Meta-task cycles detected:\s*\K\d+')" -ge 10 ]`
- [ ] `bash scripts/validate-plugin.sh >/dev/null 2>&1`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
parentTask: TASK-93
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 [ "$(bash scripts/check-roi-gate.sh 2>/dev/null | grep -oP 'Meta-task cycles detected:\s*\K\d+')" -ge 10 ]
- [ ] #2 bash scripts/check-roi-gate.sh >/dev/null 2>&1 || [ $? -eq 2 ]
- [ ] #3 bash scripts/validate-plugin.sh >/dev/null 2>&1
<!-- DOD:END -->
