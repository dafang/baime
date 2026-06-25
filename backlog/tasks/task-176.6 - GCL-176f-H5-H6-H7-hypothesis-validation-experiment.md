---
id: TASK-176.6
title: 'GCL-176f: H5 + H6 + H7 hypothesis validation experiment'
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 06:12'
updated_date: '2026-06-24 06:54'
labels:
  - 'kind:basic'
dependencies:
  - TASK-176.1
  - TASK-176.4
parent_task_id: TASK-176
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Using gcl-events.jsonl with escape_rate, evidence_independence, and gate_actor_type populated, run statistical tests for H5/H6/H7 and write results to docs/research/gcl-h5-h6-h7-validation.md.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: GCL-176f: H5 + H6 + H7 hypothesis validation experiment

## Background
Three research hypotheses about gate confidence and task reliability (H5, H6, H7) have been pre-registered in the BAIME methodology documentation but never tested against real data. TASK-176a/d populate `gcl-events.jsonl` with the required fields (`GCL`, `escape_rate`, `evidence_independence`, `gate_actor_type`). This task runs the statistical tests and writes the results to a permanent research artifact, closing the measurement loop opened by TASK-176.

## Goals
1. `docs/research/gcl-h5-h6-h7-validation.md` exists and contains pre-registered hypothesis statements for H5, H6, and H7.
2. Statistical test results (N, test statistic, p-value, confidence level) are reported for each hypothesis.
3. The file is present and `docs/research/gcl-events.jsonl` is readable: `test -f docs/research/gcl-h5-h6-h7-validation.md && python3 -c "import json; recs=list(open('docs/research/gcl-events.jsonl')); print(f'Input: {len(recs)} events')"` exits 0.

## Proposed Approach
Write the pre-registration section first (H5: GCL < threshold predicts escape_rate=1; H6: evidence_independence predicts escape_rate independently of GCL; H7: gate_actor_type has no significant effect on escape_rate when controlling for evidence_independence). Then run Python 3 with scipy.stats against gcl-events.jsonl. Write results section with findings, limitations (sample size caveat), and next steps.

## Trade-offs and Risks
- Not doing: Bayesian analysis — frequentist tests are sufficient for the current sample size.
- Risk: N < 13 records may be underpowered; the results section will note this explicitly.
- Not doing: automated re-run on new data — this is a point-in-time analysis; 176h handles ongoing monitoring.

---

# Plan: GCL-176f: H5 + H6 + H7 hypothesis validation experiment

## Phase 1: Write pre-registration section
### Tests (write first)
- `test -f docs/research/gcl-h5-h6-h7-validation.md` — file exists
- `grep -q "H5" docs/research/gcl-h5-h6-h7-validation.md` — H5 hypothesis present
- `grep -q "H6" docs/research/gcl-h5-h6-h7-validation.md` — H6 hypothesis present
- `grep -q "H7" docs/research/gcl-h5-h6-h7-validation.md` — H7 hypothesis present

### Implementation
- Create `docs/research/gcl-h5-h6-h7-validation.md` with:
  - Pre-registration section: H5 (GCL < threshold predicts escape_rate=1; Spearman or Fisher exact), H6 (evidence_independence predicts escape_rate independently of GCL), H7 (controlling for evidence_independence, gate_actor_type has no significant effect on escape_rate in routine gate subset).
  - Analysis plan: describe fields used, test selection rationale.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/gcl-h5-h6-h7-validation.md`
- [ ] `grep -q "H5" docs/research/gcl-h5-h6-h7-validation.md`
- [ ] `grep -q "H6" docs/research/gcl-h5-h6-h7-validation.md`
- [ ] `grep -q "H7" docs/research/gcl-h5-h6-h7-validation.md`

## Phase 2: Run statistical analysis and write results
### Tests (write first)
- `python3 -c "import json; recs=list(open('docs/research/gcl-events.jsonl')); print(f'Input: {len(recs)} events')"` exits 0 — JSONL readable
- `grep -q "p-value" docs/research/gcl-h5-h6-h7-validation.md` — results present

### Implementation
- Run Python 3 with scipy.stats to test H5 (Spearman correlation between GCL and escape_rate), H6 (partial correlation of evidence_independence and escape_rate), H7 (Fisher exact on gate_actor_type × escape_rate subsets).
- Write results section to `docs/research/gcl-h5-h6-h7-validation.md`: N, test statistic, p-value, confidence level per hypothesis. Note if N is underpowered.
- Write limitations and next steps sections.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 -c "import json; recs=list(open('docs/research/gcl-events.jsonl')); print(f'Input: {len(recs)} events')"`
- [ ] `grep -q "p-value" docs/research/gcl-h5-h6-h7-validation.md`

## Constraints
- scipy.stats may be unavailable; fall back to manual Fisher exact computation if needed.
- Sample size caveat must be stated explicitly in the results.
- Depends on TASK-176.1 (gcl-events.jsonl) and TASK-176.4 (escape_rate field) being complete.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/gcl-h5-h6-h7-validation.md && python3 -c "import json; recs=list(open('docs/research/gcl-events.jsonl')); print(f'Input: {len(recs)} events')"`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
<!-- SECTION:NOTES:BEGIN -->

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: Goals 1/2/3 covered by Phase 1 (pre-registration) and Phase 2 (statistical results + acceptance gate) — readable from plan
[E] TDD structure: ### Tests before ### Implementation in both phases — readable from plan
[E] TDD order: first DoD item in each phase is bash scripts/validate-plugin.sh — readable from plan
[E] Acceptance gate: first item is bash scripts/validate-plugin.sh — readable from plan
[E] DoD executability: all items are shell commands — readable from plan
[E] Absence checks: no grep -qv present — readable from plan
[E] Phase ordering: P1 creates file, P2 reads+updates it — no circular deps
[E] Scope discipline: both phases backed by Goals
[C] File paths: scripts/validate-plugin.sh confirmed; gcl-h5-h6-h7-validation.md is new; gcl-events.jsonl from TASK-176.1 dependency
GCL-self-report: E=8 C=1 H=0

claimed: 2026-06-24T06:48:31Z

Analysis complete 2026-06-24. H5/H6/H7 all untestable with current data: escape_rate=0 for all N=23 records (zero variance), evidence_independence='unknown' for all records, gate_actor_type='llm' only. Spearman rho=NaN (undefined). Power analysis: min detectable |rho| at N=23 is 0.413 — only large effects detectable even if outcome variance existed. Results written to docs/research/gcl-h5-h6-h7-validation.md with pre-registration, null results, power analysis, limitations, and next steps for unblocking the tests.

Phase 1 ✓ 2026-06-24T06:51:55Z
Pre-registration and analysis plan written to docs/research/gcl-h5-h6-h7-validation.md
Phase 2 ✓ 2026-06-24T06:51:59Z
Statistical analysis complete: H5/H6/H7 all untestable — escape_rate=0 for all N=23, evidence_independence='unknown', gate_actor_type='llm' only; power analysis and next steps documented

Completed: 2026-06-24T06:54:56Z
<!-- SECTION:NOTES:END -->

Architect review iteration 1 — APPROVED (2026-06-24).

Premise ledger:
- scripts/validate-plugin.sh: EXISTS (verified)
- docs/research/gcl-h5-h6-h7-validation.md: CREATED by this task (correct)
- docs/research/gcl-events.jsonl: created by TASK-176.1 (dependency declared in Constraints)

All criteria passed:
- Goal coverage: all 3 proposal goals addressed across Phase 1 and Phase 2
- TDD structure: ### Tests precedes ### Implementation in both phases
- TDD order: first DoD item in each phase is `bash scripts/validate-plugin.sh`
- Acceptance Gate: first item is `bash scripts/validate-plugin.sh`
- DoD executability: all DoD and Acceptance Gate items are runnable shell commands
- Absence checks: no grep -qv anti-pattern found
- Phase ordering: no circular deps (Phase 1 creates file, Phase 2 reads it)
- Scope discipline: both phases map directly to proposal goals
- File paths: all correct

GCL self-report: E=high (all checks executed, file paths verified), C=high (clear mapping between goals and phases), H=medium (analysis is point-in-time with declared underpowering risk — appropriate scope given pre-registration intent).
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 test -f docs/research/gcl-h5-h6-h7-validation.md && python3 -c "import json; recs=list(open('docs/research/gcl-events.jsonl')); print(f'Input: {len(recs)} events')"
- [ ] #2 bash scripts/validate-plugin.sh
<!-- DOD:END -->
