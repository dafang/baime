---
id: TASK-163
title: >-
  Run Exp-L: model-size effect on decomposer persona Δ — Haiku / Sonnet / Opus
  across 16 AMBIGUOUS fixtures
status: 'Basic: Backlog'
assignee: []
created_date: '2026-06-23 00:36'
updated_date: '2026-06-23 00:38'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 106000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Exp-J found Haiku Δ=+0.037 and Sonnet Δ=−0.037 when adding an expert persona to the decomposer prompt. One explanation: larger models have stronger internal priors for CODE-CHANGE vs DOC-ONLY classification, making the persona anchor redundant or disruptive. Exp-L tests this by running V0 vs V1 across three model tiers (Haiku, Sonnet, Opus) on the 16 AMBIGUOUS fixtures from Exp-J. If Δ(persona) is monotonically decreasing across model scale, the model-size hypothesis is supported.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Plan: Run Exp-L — model-size effect on decomposer persona Δ

## Context
Exp-I and Exp-J found that Haiku (smaller model) benefits from expert persona framing (+3.7pp on AMBIGUOUS fixtures) while Sonnet (larger model) is hurt (−3.7pp), with cross-model disagreement triggering a NULL verdict. One interpretation: larger models have stronger internal representations of CODE-CHANGE vs DOC-ONLY distinctions, so the persona anchor is either redundant or activates an over-aggressive implementation bias. Exp-L extends the scale axis by adding Opus, using the same V0/V1 prompt templates and the 16 AMBIGUOUS fixtures from Exp-J. If persona Δ is monotonically decreasing (Haiku > Sonnet > Opus), the model-size hypothesis is supported and the Exp-J result was not a fluke.

## Phase 1: Pre-register Exp-L hypotheses
Create experiments/skill-quality/exp-l/hypotheses.md with:
- H-L1: Δ(persona, Haiku) > Δ(persona, Sonnet) — smaller model benefits more
- H-L2: Δ(persona, Sonnet) > Δ(persona, Opus) — trend continues to larger model
- H-L3: Δ(persona, Haiku) > 0 — Haiku still benefits in this run (replication check)
- H-L4: Δ(persona, Opus) < 0 — Opus is actively hurt by persona (strongest form of hypothesis)
Git commit before any LLM call.
### DoD
- [ ] `test -f experiments/skill-quality/exp-l/hypotheses.md`
- [ ] `grep -q 'H-L1' experiments/skill-quality/exp-l/hypotheses.md`
- [ ] `grep -q 'H-L4' experiments/skill-quality/exp-l/hypotheses.md`
- [ ] `git log --oneline -1 -- experiments/skill-quality/exp-l/hypotheses.md | grep -q .`

## Phase 2: Implement run-exp-l.ts
Create experiments/skill-quality/exp-l/run-exp-l.ts. Port from experiments/skill-quality/exp-j/run-exp-j.ts with these changes:
- modelList: ['claude-haiku-4-5-20251001', 'claude-sonnet-4-6', 'claude-opus-4-8'] (three tiers)
- fixtureDir: fixtures/exp-j/ambiguous/ (reuse Exp-J's 16 AMBIGUOUS fixtures unchanged)
- V0/V1 prompt builders: copy verbatim from run-exp-j.ts — no changes
- outDir default: artifacts/runs/exp-l
- analyze(): compute per-(model, variant) accuracy on AMBIGUOUS fixtures; compute Δ(V1−V0) per model; evaluate H-L1/L2/L3/L4; check monotone ordering Haiku > Sonnet > Opus; write artifacts/analysis/exp-l-results.json with "data_source": "measured"
- Sanity dir: reuse fixtures/exp-i/sanity/
Verify TypeScript: cd experiments/skill-quality && npx tsc --noEmit
### DoD
- [ ] `test -f experiments/skill-quality/exp-l/run-exp-l.ts`
- [ ] `grep -q 'claude-opus-4-8' experiments/skill-quality/exp-l/run-exp-l.ts`
- [ ] `grep -q 'V0' experiments/skill-quality/exp-l/run-exp-l.ts`
- [ ] `grep -q 'V1' experiments/skill-quality/exp-l/run-exp-l.ts`
- [ ] `! { cd experiments/skill-quality && npx tsc --noEmit 2>&1 | grep -q 'exp-l'; }`

## Phase 3: Run experiment and compute verdicts
Run: cd experiments/skill-quality && npx tsx exp-l/run-exp-l.ts --k 5 --out artifacts/runs/exp-l
This executes 16 fixtures × 2 variants × 5 reps × 3 models = 480 LLM calls.
After run, fill verdict table: for each model, record V0 acc, V1 acc, Δ. Check if Haiku Δ > Sonnet Δ > Opus Δ (H-L1 + H-L2). Write artifacts/analysis/exp-l-results.json.
### DoD
- [ ] `test -f experiments/skill-quality/artifacts/analysis/exp-l-results.json`
- [ ] `grep -q '"data_source": "measured"' experiments/skill-quality/artifacts/analysis/exp-l-results.json`
- [ ] `grep -q 'claude-opus' experiments/skill-quality/artifacts/analysis/exp-l-results.json`

## Phase 4: Write back evidence
Create docs/experiments/exp-l-decomposer-persona.md with full design doc (motivation, variants, fixture reuse justification, hypotheses, verdict table with measured values, V_meta_experiment, interpretation). Update docs/baime-and-quantitative-experiments.md with Exp-L section. Add note to TASK-163: "exp-l: <one-line verdict>".
### DoD
- [ ] `test -f docs/experiments/exp-l-decomposer-persona.md`
- [ ] `grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-l-decomposer-persona.md`
- [ ] `grep -q 'Exp-L' docs/baime-and-quantitative-experiments.md`
- [ ] `backlog task view TASK-163 --plain | grep -q 'exp-l:'`

## Constraints
- Hypotheses must be git-committed before any LLM call in Phase 3
- Use identical V0/V1 prompt templates as Exp-I/Exp-J (P-rules condition) — no prompt changes
- Do not modify plugin/skills/loop-backlog/SKILL.md in this task
- Opus cost note: Opus calls are ~15× more expensive than Haiku — confirm budget before running Phase 3

## Acceptance Gate
- [ ] `grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-l-decomposer-persona.md`
- [ ] `grep -q '"data_source": "measured"' experiments/skill-quality/artifacts/analysis/exp-l-results.json`
- [ ] `grep -q 'Exp-L' docs/baime-and-quantitative-experiments.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan review iteration 1: APPROVED

cap:propose=approved
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 test -f experiments/skill-quality/exp-l/hypotheses.md
- [ ] #2 grep -q 'H-L1' experiments/skill-quality/exp-l/hypotheses.md
- [ ] #3 grep -q 'H-L4' experiments/skill-quality/exp-l/hypotheses.md
- [ ] #4 git log --oneline -1 -- experiments/skill-quality/exp-l/hypotheses.md | grep -q .
- [ ] #5 test -f experiments/skill-quality/exp-l/run-exp-l.ts
- [ ] #6 grep -q 'claude-opus-4-8' experiments/skill-quality/exp-l/run-exp-l.ts
- [ ] #7 grep -q 'V0' experiments/skill-quality/exp-l/run-exp-l.ts
- [ ] #8 grep -q 'V1' experiments/skill-quality/exp-l/run-exp-l.ts
- [ ] #9 ! { cd experiments/skill-quality && npx tsc --noEmit 2>&1 | grep -q 'exp-l'; }
- [ ] #10 test -f experiments/skill-quality/artifacts/analysis/exp-l-results.json
- [ ] #11 grep -q '"data_source": "measured"' experiments/skill-quality/artifacts/analysis/exp-l-results.json
- [ ] #12 grep -q 'claude-opus' experiments/skill-quality/artifacts/analysis/exp-l-results.json
- [ ] #13 test -f docs/experiments/exp-l-decomposer-persona.md
- [ ] #14 grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-l-decomposer-persona.md
- [ ] #15 grep -q 'Exp-L' docs/baime-and-quantitative-experiments.md
- [ ] #16 backlog task view TASK-163 --plain | grep -q 'exp-l:'
<!-- DOD:END -->
