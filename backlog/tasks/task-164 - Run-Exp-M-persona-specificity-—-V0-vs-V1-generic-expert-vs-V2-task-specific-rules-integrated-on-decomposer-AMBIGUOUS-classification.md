---
id: TASK-164
title: >-
  Run Exp-M: persona specificity — V0 vs V1 (generic expert) vs V2
  (task-specific, rules-integrated) on decomposer AMBIGUOUS classification
status: 'Basic: Backlog'
assignee: []
created_date: '2026-06-23 00:37'
updated_date: '2026-06-23 00:39'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 107000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Exp-I/Exp-J compared V0 (functional directive) vs V1 (generic expert architect persona), both followed by explicit classification rules. Result: cross-model disagreement. Exp-M adds V2: a task-specific persona that integrates the classification rules directly into the role definition ('You are the loop-backlog decomposer — an agent that classifies sub-tasks into CODE-CHANGE ... or DOC-ONLY ...'). This tests whether persona specificity (not just presence) is the relevant variable. If V2 > V1 ≈ V0 on AMBIGUOUS, rule integration into the role definition is the key; if V2 ≈ V1 > V0, any expert framing helps; if V2 ≈ V1 ≈ V0, persona framing has no effect regardless of specificity.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Plan: Run Exp-M — persona specificity on decomposer AMBIGUOUS classification

## Context
Exp-I and Exp-J found that a generic expert architect persona (V1) produces cross-model disagreement vs the functional directive (V0): Haiku benefits, Sonnet is hurt. Both experiments placed classification rules after the persona/directive as a separate block. Exp-M introduces V2: a task-specific persona that integrates the classification rules into the role definition itself, making the agent's identity inseparable from its classification behavior. This tests whether the problem was persona presence (any framing helps/hurts) or persona genericity (generic anchors compete with the explicit rules, while specific anchors subsume them).

## Phase 1: Pre-register Exp-M hypotheses
Create experiments/skill-quality/exp-m/hypotheses.md with:
- H-M1: V2 AMBIGUOUS accuracy > V1 AMBIGUOUS accuracy (specificity helps over genericity)
- H-M2: V2 AMBIGUOUS accuracy > V0 AMBIGUOUS accuracy (integrated persona beats no persona)
- H-M3: V1 AMBIGUOUS accuracy ≈ V0 (replication: generic persona has no net effect, consistent with Exp-J NULL)
- H-M4: Cross-model consistency on H-M1 (both Haiku and Sonnet agree on V2 vs V1 direction)
Git commit before any LLM call.
### DoD
- [ ] `test -f experiments/skill-quality/exp-m/hypotheses.md`
- [ ] `grep -q 'H-M1' experiments/skill-quality/exp-m/hypotheses.md`
- [ ] `grep -q 'H-M4' experiments/skill-quality/exp-m/hypotheses.md`
- [ ] `git log --oneline -1 -- experiments/skill-quality/exp-m/hypotheses.md | grep -q .`

## Phase 2: Implement run-exp-m.ts
Create experiments/skill-quality/exp-m/run-exp-m.ts. Port from experiments/skill-quality/exp-j/run-exp-j.ts with these changes:
- variants: { V0, V1, V2 } — all using the same 16 AMBIGUOUS fixtures from fixtures/exp-j/ambiguous/
- V0 prompt opening (identical to Exp-I/J): "You are the autonomous decomposer agent for epic TASK-N."
- V1 prompt opening (identical to Exp-I/J): "You are an experienced software architect decomposing an epic into independently implementable child tasks. Your primary skill is distinguishing implementation work (code and file changes) from analytical or documentation work (research, prose writing, audits)."
- V2 prompt opening (new): "You are the loop-backlog decomposer — an agent that classifies sub-tasks into CODE-CHANGE (tasks that create or modify files under plugin/, scripts/, any SKILL.md, or *.sh scripts) or DOC-ONLY (tasks whose output is exclusively research, prose documentation, or backlog notes). You have deep familiarity with this distinction and apply it consistently."
- V0 and V1 still include the separate explicit rule block after the opening; V2 omits the separate rule block (rules are already embedded in the persona definition to avoid double-stating them)
- modelList: ['claude-haiku-4-5-20251001', 'claude-sonnet-4-6']
- outDir default: artifacts/runs/exp-m
- analyze(): compute per-(variant, model) AMBIGUOUS accuracy; compute Δ(V2−V1), Δ(V2−V0), Δ(V1−V0); evaluate H-M1/M2/M3/M4; write artifacts/analysis/exp-m-results.json with "data_source": "measured"
- Sanity dir: reuse fixtures/exp-i/sanity/
Verify TypeScript: cd experiments/skill-quality && npx tsc --noEmit
### DoD
- [ ] `test -f experiments/skill-quality/exp-m/run-exp-m.ts`
- [ ] `grep -q 'V2' experiments/skill-quality/exp-m/run-exp-m.ts`
- [ ] `grep -q 'loop-backlog decomposer' experiments/skill-quality/exp-m/run-exp-m.ts`
- [ ] `! { cd experiments/skill-quality && npx tsc --noEmit 2>&1 | grep -q 'exp-m'; }`

## Phase 3: Run experiment and compute verdicts
Run: cd experiments/skill-quality && npx tsx exp-m/run-exp-m.ts --k 5 --out artifacts/runs/exp-m
This executes 16 fixtures × 3 variants × 5 reps × 2 models = 480 LLM calls.
After run, fill verdict table: per model, V0/V1/V2 AMBIGUOUS accuracy and pairwise Δ. Evaluate H-M1 through H-M4. Write results to exp-m-results.json.
### DoD
- [ ] `test -f experiments/skill-quality/artifacts/analysis/exp-m-results.json`
- [ ] `grep -q '"data_source": "measured"' experiments/skill-quality/artifacts/analysis/exp-m-results.json`
- [ ] `grep -q 'V2' experiments/skill-quality/artifacts/analysis/exp-m-results.json`

## Phase 4: Write back evidence
Create docs/experiments/exp-m-decomposer-persona.md with full design doc (motivation, three variants defined precisely, fixture reuse justification, hypotheses, verdict table with measured values, V_meta_experiment, interpretation including whether specificity vs genericity explains the Exp-J cross-model result). Update docs/baime-and-quantitative-experiments.md with Exp-M section. Add note to TASK-164: "exp-m: <one-line verdict>".
### DoD
- [ ] `test -f docs/experiments/exp-m-decomposer-persona.md`
- [ ] `grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-m-decomposer-persona.md`
- [ ] `grep -q 'Exp-M' docs/baime-and-quantitative-experiments.md`
- [ ] `backlog task view TASK-164 --plain | grep -q 'exp-m:'`

## Constraints
- Hypotheses must be git-committed before any LLM call in Phase 3
- V2 must omit the separate classification rule block (rules are already in the persona definition) — otherwise the confound is not isolated
- V0 and V1 must be identical to Exp-I/Exp-J prompt templates
- Do not modify plugin/skills/loop-backlog/SKILL.md in this task
- If H-M1 CONFIRMED and H-M2 CONFIRMED: V2 is a candidate for replacing V0 in SKILL.md — flag for follow-up

## Acceptance Gate
- [ ] `grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-m-decomposer-persona.md`
- [ ] `grep -q '"data_source": "measured"' experiments/skill-quality/artifacts/analysis/exp-m-results.json`
- [ ] `grep -q 'Exp-M' docs/baime-and-quantitative-experiments.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan review iteration 1: APPROVED

cap:propose=approved
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 test -f experiments/skill-quality/exp-m/hypotheses.md
- [ ] #2 grep -q 'H-M1' experiments/skill-quality/exp-m/hypotheses.md
- [ ] #3 grep -q 'H-M4' experiments/skill-quality/exp-m/hypotheses.md
- [ ] #4 git log --oneline -1 -- experiments/skill-quality/exp-m/hypotheses.md | grep -q .
- [ ] #5 test -f experiments/skill-quality/exp-m/run-exp-m.ts
- [ ] #6 grep -q 'V2' experiments/skill-quality/exp-m/run-exp-m.ts
- [ ] #7 grep -q 'loop-backlog decomposer' experiments/skill-quality/exp-m/run-exp-m.ts
- [ ] #8 ! { cd experiments/skill-quality && npx tsc --noEmit 2>&1 | grep -q 'exp-m'; }
- [ ] #9 test -f experiments/skill-quality/artifacts/analysis/exp-m-results.json
- [ ] #10 grep -q '"data_source": "measured"' experiments/skill-quality/artifacts/analysis/exp-m-results.json
- [ ] #11 grep -q 'V2' experiments/skill-quality/artifacts/analysis/exp-m-results.json
- [ ] #12 test -f docs/experiments/exp-m-decomposer-persona.md
- [ ] #13 grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-m-decomposer-persona.md
- [ ] #14 grep -q 'Exp-M' docs/baime-and-quantitative-experiments.md
- [ ] #15 backlog task view TASK-164 --plain | grep -q 'exp-m:'
<!-- DOD:END -->
