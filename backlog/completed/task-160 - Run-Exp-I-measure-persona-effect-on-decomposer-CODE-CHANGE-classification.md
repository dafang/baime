---
id: TASK-160
title: 'Run Exp-I: measure persona effect on decomposer CODE-CHANGE classification'
status: 'Basic: Done'
assignee: []
created_date: '2026-06-22 17:00'
updated_date: '2026-06-22 17:44'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Execute the pre-registered quantitative experiment (Exp-I) described in docs/experiments/exp-i-decomposer-persona.md. Freeze hypotheses via git commit, construct 16 fixtures (8 CLEAR + 8 AMBIGUOUS), implement run-exp-i.ts following Exp-H structure, run multi-model k=5 trials, compute verdicts for H-A/B/C/D, and write back evidence.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Plan: Run Exp-I — decomposer persona effect on CODE-CHANGE classification

## Context
Exp-I tests whether adding an expert architect persona to the loop-backlog decomposer prompt improves CODE-CHANGE vs DOC-ONLY classification accuracy. The design is documented in docs/experiments/exp-i-decomposer-persona.md. This task executes the experiment following the project's established quantitative methodology (multi-model, k=5, pre-registered hypotheses, hard verdicts).

## Phase 1: Freeze hypotheses

Create `experiments/skill-quality/exp-i/hypotheses.md` containing the four pre-registered hypotheses (H-A/B/C/D) with their thresholds and directions exactly as specified in the design doc. Git commit the file before any LLM call is made — the commit timestamp is the freeze proof.

### DoD
- `test -f experiments/skill-quality/exp-i/hypotheses.md`
- `grep -q 'H-A' experiments/skill-quality/exp-i/hypotheses.md`
- `grep -q 'H-D' experiments/skill-quality/exp-i/hypotheses.md`
- `git log --oneline -1 -- experiments/skill-quality/exp-i/hypotheses.md | grep -q .`

## Phase 2: Construct fixtures

Create 16 fixture JSON files in `experiments/skill-quality/fixtures/exp-i/`:
- 4 CLEAR CODE-CHANGE (obvious file mentions: .ts, SKILL.md, .sh, scripts/)
- 4 CLEAR DOC-ONLY (explicit: research, write analysis, survey, document)
- 4 AMBIGUOUS CODE-CHANGE (vague descriptions that imply file changes: "improve prompt", "add rationale", "port logic", "audit and patch")
- 4 AMBIGUOUS DOC-ONLY (vague descriptions that imply research: "calibrate oracle", "investigate", "evaluate and report", "define criteria")

Each fixture follows the schema in the design doc: `id`, `fixtureClass`, `expectedClass`, `epicPlanExcerpt`, `subtaskHint`, `ground_truth_rationale`, `tricky_aspect`.

Also create 2 sanity fixtures in `experiments/skill-quality/fixtures/exp-i/sanity/`.

### DoD
- `[ $(ls experiments/skill-quality/fixtures/exp-i/*.json 2>/dev/null | wc -l) -ge 16 ]`
- `[ $(ls experiments/skill-quality/fixtures/exp-i/sanity/*.json 2>/dev/null | wc -l) -ge 2 ]`
- `grep -q 'AMBIGUOUS' experiments/skill-quality/fixtures/exp-i/decomp-ambig-cc-01.json`
- `grep -q 'expectedClass' experiments/skill-quality/fixtures/exp-i/decomp-clear-cc-01.json`

## Phase 3: Implement run-exp-i.ts

Write `experiments/skill-quality/exp-i/run-exp-i.ts` following Exp-H structure (`run-exp-h.ts` as template). The script must:
- Define V0 (functional directive) and V1 (expert persona) prompt builders
- Load fixtures from `fixtures/exp-i/`
- Use automated scoring (CODE-CHANGE/DOC-ONLY string match vs expectedClass)
- Run via `runExperiment()` from `lib/runner.ts`
- Write per-cell results to `artifacts/runs/exp-i/`
- Write analysis JSON to `artifacts/analysis/exp-i-results.json` with per-class accuracy by variant and model
- Support `--k`, `--out` CLI flags and checkpoint/resume

### DoD
- `test -f experiments/skill-quality/exp-i/run-exp-i.ts`
- `grep -q 'V0' experiments/skill-quality/exp-i/run-exp-i.ts`
- `grep -q 'V1' experiments/skill-quality/exp-i/run-exp-i.ts`
- `grep -q 'AMBIGUOUS' experiments/skill-quality/exp-i/run-exp-i.ts`
- `cd experiments/skill-quality && npx tsc --noEmit 2>&1 | ! grep -q 'exp-i'`

## Phase 4: Run experiment and compute verdicts

Execute against Haiku (primary) and Sonnet (cross-check):

```bash
cd experiments/skill-quality
npx tsx exp-i/run-exp-i.ts --k 5 --out artifacts/runs/exp-i
```

After run completes, fill the verdict table in `docs/experiments/exp-i-decomposer-persona.md`: record V0/V1 accuracy per class per model, compute Δ, assign CONFIRMED/NULL/REJECTED to each hypothesis, and compute V_meta_experiment score.

### DoD
- `test -f experiments/skill-quality/artifacts/analysis/exp-i-results.json`
- `grep -q '"data_source": "measured"' experiments/skill-quality/artifacts/analysis/exp-i-results.json`
- `grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-i-decomposer-persona.md`
- `grep -q 'V_meta_experiment' docs/experiments/exp-i-decomposer-persona.md`

## Phase 5: Write-back evidence

Based on verdict:
- If H-A or H-C CONFIRMED: create a follow-up task proposing the SKILL.md edit via `/feature-to-backlog`, titled "Add expert persona to loop-backlog decomposer prompt"
- If NULL or REJECTED: add a note to `docs/baime-and-quantitative-experiments.md` under a new "Exp-I" section documenting the null/negative result and its implication (rules already sufficient)

In both branches, add a one-line note to this task: `exp-i: <verdict summary>`.

### DoD
- `grep -q 'Exp-I' docs/baime-and-quantitative-experiments.md`
- `backlog task view TASK-160 --plain | grep -q 'exp-i:'`
- `grep -q 'CONFIRMED' docs/experiments/exp-i-decomposer-persona.md && backlog task list --plain | grep -qi 'decomposer.*persona\|persona.*decomposer' || grep -q 'NULL\|REJECTED' docs/experiments/exp-i-decomposer-persona.md`

## Constraints
- Hypotheses must be git-committed before any LLM call in Phase 4 (pre-registration discipline)
- Do not modify the loop-backlog SKILL.md during this task — that is a follow-up if warranted
- Fixture ground truth follows the explicit CODE-CHANGE/DOC-ONLY rules in the design doc, not subjective quality judgment
- Cross-model consistency required: if Haiku and Sonnet verdicts disagree on direction, downgrade confidence to [underpowered]

## Acceptance Gate
- `grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-i-decomposer-persona.md`
- `test -f experiments/skill-quality/artifacts/analysis/exp-i-results.json`
- `grep -q 'Exp-I' docs/baime-and-quantitative-experiments.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan review iteration 2: APPROVED
cap:propose=approved

exp-i: H-A CONFIRMED (Haiku AMBIG Δ=+0.050, exactly at threshold), H-B CONFIRMED (CLEAR 100% both variants), H-C NULL (overall Δ=+0.025 < 5pp), H-D CONFIRMED (no DO recall degradation). Cross-model: [underpowered] — Haiku positive, Sonnet negative on AMBIG direction. Scenario: persona helps on AMBIGUOUS but not overall. If underpowered signal accepted, V1 persona can be added to decomposer; otherwise run Exp-J (n=16 AMBIGUOUS fixtures) for higher power. Note: H-A CONFIRMED → follow-up task for adding persona to SKILL.md should be reviewed by human before creating.
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 test -f experiments/skill-quality/exp-i/hypotheses.md
- [ ] #2 grep -q 'H-A' experiments/skill-quality/exp-i/hypotheses.md
- [ ] #3 grep -q 'H-D' experiments/skill-quality/exp-i/hypotheses.md
- [ ] #4 git log --oneline -1 -- experiments/skill-quality/exp-i/hypotheses.md | grep -q .
- [ ] #5 [ $(ls experiments/skill-quality/fixtures/exp-i/*.json 2>/dev/null | wc -l) -ge 16 ]
- [ ] #6 [ $(ls experiments/skill-quality/fixtures/exp-i/sanity/*.json 2>/dev/null | wc -l) -ge 2 ]
- [ ] #7 grep -q 'AMBIGUOUS' experiments/skill-quality/fixtures/exp-i/decomp-ambig-cc-01.json
- [ ] #8 grep -q 'expectedClass' experiments/skill-quality/fixtures/exp-i/decomp-clear-cc-01.json
- [ ] #9 test -f experiments/skill-quality/exp-i/run-exp-i.ts
- [ ] #10 grep -q 'V0' experiments/skill-quality/exp-i/run-exp-i.ts
- [ ] #11 grep -q 'V1' experiments/skill-quality/exp-i/run-exp-i.ts
- [ ] #12 grep -q 'AMBIGUOUS' experiments/skill-quality/exp-i/run-exp-i.ts
- [ ] #13 cd experiments/skill-quality && npx tsc --noEmit 2>&1 | ! grep -q 'exp-i'
- [ ] #14 test -f experiments/skill-quality/artifacts/analysis/exp-i-results.json
- [ ] #15 grep -q '"data_source": "measured"' experiments/skill-quality/artifacts/analysis/exp-i-results.json
- [ ] #16 grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-i-decomposer-persona.md
- [ ] #17 grep -q 'V_meta_experiment' docs/experiments/exp-i-decomposer-persona.md
- [ ] #18 grep -q 'Exp-I' docs/baime-and-quantitative-experiments.md
- [ ] #19 backlog task view TASK-160 --plain | grep -q 'exp-i:'
- [ ] #20 grep -q 'CONFIRMED' docs/experiments/exp-i-decomposer-persona.md && backlog task list --plain | grep -qi 'decomposer.*persona\|persona.*decomposer' || grep -q 'NULL\|REJECTED' docs/experiments/exp-i-decomposer-persona.md
- [ ] #21 grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-i-decomposer-persona.md
- [ ] #22 test -f experiments/skill-quality/artifacts/analysis/exp-i-results.json
- [ ] #23 grep -q 'Exp-I' docs/baime-and-quantitative-experiments.md
<!-- DOD:END -->
