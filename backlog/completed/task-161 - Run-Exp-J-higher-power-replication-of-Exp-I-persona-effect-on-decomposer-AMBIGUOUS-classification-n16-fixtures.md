---
id: TASK-161
title: >-
  Run Exp-J: higher-power replication of Exp-I persona effect on decomposer
  AMBIGUOUS classification (n=16 fixtures)
status: 'Basic: Done'
assignee: []
created_date: '2026-06-22 22:31'
updated_date: '2026-06-22 23:16'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 105000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Exp-I (TASK-160) found H-A CONFIRMED at the exact 5pp threshold on Haiku but H-A direction reversed on Sonnet (Δ=−0.025), triggering the cross-model [underpowered] flag. Exp-J resolves this by doubling the AMBIGUOUS fixture set to n=16 (from n=8), re-running both models at k=5, and computing a definitive verdict on whether the V1 expert persona improves CODE-CHANGE vs DOC-ONLY classification on ambiguous sub-task descriptions.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Plan: Run Exp-J — higher-power replication of persona effect on decomposer AMBIGUOUS classification

## Context

Exp-I (TASK-160) tested whether an expert architect persona (V1) in the loop-backlog decomposer prompt improves CODE-CHANGE vs DOC-ONLY classification accuracy on n=8 AMBIGUOUS fixtures at k=5. Haiku showed H-A CONFIRMED at exactly the 5pp threshold (Δ=+0.050), but Sonnet showed Δ=−0.025 (opposite direction), triggering the cross-model `[underpowered]` flag. With only n=8 AMBIGUOUS fixtures per model, a single fixture flip can swing Δ by 12.5pp, making it impossible to distinguish a real effect from noise. Exp-J is a pre-registered higher-power replication: double the AMBIGUOUS fixture set to n=16, re-run both models at k=5 with identical V0/V1 prompt templates, and compute a definitive verdict. If models still disagree on direction after n=16, verdict is NULL — no persona change made.

## Phase 1: Pre-register Exp-J hypotheses

Create `experiments/skill-quality/exp-j/hypotheses.md` mirroring the Exp-I hypotheses structure but scoped to n=16 AMBIGUOUS fixtures. Hypotheses H-A2/B2/C2/D2 use identical thresholds (H-A2: Δ ≥ 0.05; H-B2: CLEAR ≥ 0.90 — noting CLEAR fixtures are not re-run in Exp-J so H-B2 inherits the Exp-I CONFIRMED result; H-C2: overall Δ ≥ 0.05 on AMBIGUOUS-only run; H-D2: DO recall Δ > −0.10). Note: because Exp-J runs only AMBIGUOUS fixtures, H-B2 is carried forward from Exp-I as a prior CONFIRMED result rather than newly measured. Git commit the hypotheses file before any LLM call.

### DoD
- [ ] `test -f experiments/skill-quality/exp-j/hypotheses.md`
- [ ] `grep -q 'H-A2' experiments/skill-quality/exp-j/hypotheses.md`
- [ ] `git log --oneline -1 -- experiments/skill-quality/exp-j/hypotheses.md | grep -q .`

## Phase 2: Create 8 additional AMBIGUOUS fixtures

Create 8 new AMBIGUOUS fixture JSON files in `experiments/skill-quality/fixtures/exp-j/ambiguous/` following the same schema as Exp-I fixtures. Each new fixture must have a novel `subtaskHint` not present in Exp-I — cover a spread of CODE-CHANGE and DOC-ONLY cases (4 new CODE-CHANGE, 4 new DOC-ONLY). Then copy the 8 Exp-I AMBIGUOUS fixtures (`fixtures/exp-i/decomp-ambig-*.json`) into `fixtures/exp-j/ambiguous/` so the exp-j run directory contains all 16 AMBIGUOUS fixtures in one place. New fixture IDs use the same pattern: `decomp-ambig-cc-09` through `decomp-ambig-cc-12` and `decomp-ambig-do-09` through `decomp-ambig-do-12`. (IDs -05 through -08 are intentionally skipped to leave room for Exp-H or other future fixtures that may already have used those slots — verify against any existing fixtures before writing.) Each must include `id`, `fixtureClass: "AMBIGUOUS"`, `expectedClass`, `epicPlanExcerpt`, `subtaskHint`, `ground_truth_rationale`, and `tricky_aspect`.

Suggested new CODE-CHANGE hints (ambiguous framing, but SKILL.md/plugin/scripts scope implied):
- `decomp-ambig-cc-09`: "Refine the epic worker's gate-check logic to handle cross-task dependency edges" (logic → plugin code)
- `decomp-ambig-cc-10`: "Extend the decomposer's output schema to include a confidence field" (schema in SKILL.md or plugin)
- `decomp-ambig-cc-11`: "Wire up the R1-guard sanity check into the epic acceptance gate" (wire up → code integration)
- `decomp-ambig-cc-12`: "Tune the loop-backlog SKILL.md wording for the Epic: Awaiting Children transition" (SKILL.md → CODE-CHANGE)

Suggested new DOC-ONLY hints:
- `decomp-ambig-do-09`: "Benchmark decomposer latency across 50 historical epics and record in latency-log.md" (benchmarking = measurement → DOC-ONLY)
- `decomp-ambig-do-10`: "Assess whether the current oracle scoring rubric penalises partial credit correctly" (assess → research)
- `decomp-ambig-do-11`: "Map the sequence of skill invocations during a typical epic lifecycle" (map = prose diagram/doc)
- `decomp-ambig-do-12`: "Identify all open questions about cross-task dependency handling and document them" (identify + document → DOC-ONLY)

Write the rationale and tricky_aspect for each fixture carefully — ambiguity should come from verb framing, not from rule ambiguity.

### DoD
- [ ] `[ $(ls experiments/skill-quality/fixtures/exp-j/ambiguous/*.json 2>/dev/null | wc -l) -ge 16 ]`
- [ ] `grep -q 'AMBIGUOUS' experiments/skill-quality/fixtures/exp-j/ambiguous/decomp-ambig-cc-09.json`
- [ ] `grep -q 'expectedClass' experiments/skill-quality/fixtures/exp-j/ambiguous/decomp-ambig-do-09.json`

## Phase 3: Implement run-exp-j.ts

Create `experiments/skill-quality/exp-j/run-exp-j.ts` by porting `exp-i/run-exp-i.ts` with these targeted changes:
1. All references to `exp-i` renamed to `exp-j` (directory paths, output paths, log messages).
2. `fixtureDir` points to `fixtures/exp-j/ambiguous/` instead of `fixtures/exp-i/`.
3. Only AMBIGUOUS fixtures are loaded — no CLEAR class in this replication (CLEAR ceiling already established in Exp-I; H-B2 is inherited).
4. `buildConfig` sets `outDir` default to `artifacts/runs/exp-j`.
5. `analyze()` writes results to `artifacts/analysis/exp-j-results.json`.
6. The `hypothesisVerdict` calls and cross-model consistency logic are identical to Exp-I.
7. Because only AMBIGUOUS fixtures are present, H-B2 is skipped in analysis and marked `INHERITED_FROM_EXP_I: CONFIRMED` in the output JSON rather than computed fresh.
8. V0 and V1 prompt builders are copied verbatim from `run-exp-i.ts` — no changes to prompt templates.
9. Sanity dir still points to `fixtures/exp-i/sanity` (reuse the same sanity fixtures; no new sanity fixtures needed).

### DoD
- [ ] `test -f experiments/skill-quality/exp-j/run-exp-j.ts`
- [ ] `grep -q 'V0' experiments/skill-quality/exp-j/run-exp-j.ts`
- [ ] `grep -q 'V1' experiments/skill-quality/exp-j/run-exp-j.ts`
- [ ] `cd experiments/skill-quality && ! npx tsc --noEmit 2>&1 | grep -q 'exp-j'`

## Phase 4: Run experiment and compute definitive verdict

Run from within `experiments/skill-quality/`:

```bash
npx tsx exp-j/run-exp-j.ts --k 5 --out artifacts/runs/exp-j
```

This executes 16 AMBIGUOUS fixtures × 2 variants × 5 repetitions × 2 models = 320 LLM calls (same total as Exp-I, but all in AMBIGUOUS class instead of split 50/50 with CLEAR).

After the run completes, the `analyze()` function writes `artifacts/analysis/exp-j-results.json`. Apply the cross-model verdict rule in this priority order:

1. **H-A2 CONFIRMED** — Haiku Δ(AMBIG) ≥ 0.05 AND Sonnet Δ(AMBIG) ≥ 0.00 (both models agree V1 is at least non-negative; Haiku meets the primary threshold)
2. **H-A2 REJECTED** — Both models show Δ < −0.05 (models agree V1 is harmful)
3. **NULL [cross-model disagreement]** — sign(Haiku Δ) ≠ sign(Sonnet Δ) after n=16 (one model positive, the other negative) — do not add persona
4. **H-A2 NULL** — All other cases: both models show |Δ| < 0.05 or agreement is positive but sub-threshold — insufficient evidence to conclude

For rule 3, "disagree on direction" means one model's Δ > 0 and the other's Δ < 0 (zero counts as non-negative for Haiku but would fall to rule 4 for Sonnet).

The `data_source` field in the output JSON must be `"measured"` (written automatically by the runner).

### DoD
- [ ] `test -f experiments/skill-quality/artifacts/analysis/exp-j-results.json`
- [ ] `grep -q '"data_source": "measured"' experiments/skill-quality/artifacts/analysis/exp-j-results.json`

## Phase 5: Write back evidence and update design docs

1. Create `docs/experiments/exp-j-decomposer-persona.md` with full design doc mirroring Exp-I format: motivation, variants, fixture design (16 AMBIGUOUS), hypotheses table, verdict table filled from measured results, V_meta_experiment score, and interpretation section.

2. Update `docs/baime-and-quantitative-experiments.md` with an Exp-J section (one paragraph: purpose, method, verdict, implication).

3. Conditional follow-up: If H-A2 is CONFIRMED (both models agree on positive direction), create a follow-up task via `/feature-to-backlog` to add V1 persona to loop-backlog `SKILL.md` decomposer prompt. If H-A2 is NULL or REJECTED, document as definitive negative evidence — no persona change.

4. Add a one-line note to TASK-161 backlog entry: `"exp-j: <verdict summary>"` (e.g. `exp-j: H-A2 CONFIRMED — both models agree V1 +Xpp on AMBIGUOUS` or `exp-j: H-A2 NULL — cross-model disagreement persists at n=16`).

### DoD
- [ ] `test -f docs/experiments/exp-j-decomposer-persona.md`
- [ ] `grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-j-decomposer-persona.md`
- [ ] `grep -q 'Exp-J' docs/baime-and-quantitative-experiments.md`
- [ ] `backlog task view TASK-161 --plain | grep -q 'exp-j:'`

## Constraints
- Hypotheses MUST be git-committed before any LLM call in Phase 4
- Only AMBIGUOUS fixtures in this run (CLEAR class ceiling check already done in Exp-I)
- Do not modify `plugin/skills/loop-backlog/SKILL.md` in this task
- If cross-model disagreement persists after n=16, verdict is NULL — do not add persona
- V0/V1 prompt templates must be identical to Exp-I (only fixture set changes)
- Sanity fixtures reused from `fixtures/exp-i/sanity` — no new sanity fixtures needed

## Acceptance Gate
- [ ] `grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-j-decomposer-persona.md`
- [ ] `grep -q '"data_source": "measured"' experiments/skill-quality/artifacts/analysis/exp-j-results.json`
- [ ] `grep -q 'Exp-J' docs/baime-and-quantitative-experiments.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan review iteration 2: APPROVED

cap:propose=approved

exp-j: H-A2 NULL — cross-model disagreement persists at n=16 (Haiku Δ=+0.037, Sonnet Δ=−0.037); definitive negative; no persona change to SKILL.md
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 test -f experiments/skill-quality/exp-j/hypotheses.md
- [ ] #2 grep -q 'H-A2' experiments/skill-quality/exp-j/hypotheses.md
- [ ] #3 git log --oneline -1 -- experiments/skill-quality/exp-j/hypotheses.md | grep -q .
- [ ] #4 [ $(ls experiments/skill-quality/fixtures/exp-j/ambiguous/*.json 2>/dev/null | wc -l) -ge 16 ]
- [ ] #5 grep -q 'AMBIGUOUS' experiments/skill-quality/fixtures/exp-j/ambiguous/decomp-ambig-cc-09.json
- [ ] #6 grep -q 'expectedClass' experiments/skill-quality/fixtures/exp-j/ambiguous/decomp-ambig-do-09.json
- [ ] #7 test -f experiments/skill-quality/exp-j/run-exp-j.ts
- [ ] #8 grep -q 'V0' experiments/skill-quality/exp-j/run-exp-j.ts
- [ ] #9 grep -q 'V1' experiments/skill-quality/exp-j/run-exp-j.ts
- [ ] #10 cd experiments/skill-quality && ! npx tsc --noEmit 2>&1 | grep -q 'exp-j'
- [ ] #11 test -f experiments/skill-quality/artifacts/analysis/exp-j-results.json
- [ ] #12 grep -q '"data_source": "measured"' experiments/skill-quality/artifacts/analysis/exp-j-results.json
- [ ] #13 test -f docs/experiments/exp-j-decomposer-persona.md
- [ ] #14 grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-j-decomposer-persona.md
- [ ] #15 grep -q 'Exp-J' docs/baime-and-quantitative-experiments.md
- [ ] #16 backlog task view TASK-161 --plain | grep -q 'exp-j:'
- [ ] #17 grep -q 'CONFIRMED\|NULL\|REJECTED' docs/experiments/exp-j-decomposer-persona.md
- [ ] #18 grep -q '"data_source": "measured"' experiments/skill-quality/artifacts/analysis/exp-j-results.json
- [ ] #19 grep -q 'Exp-J' docs/baime-and-quantitative-experiments.md
<!-- DOD:END -->
