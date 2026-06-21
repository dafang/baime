---
id: TASK-118
title: Implement B″ unified-board dual-state-machine architecture
status: Backlog
assignee: []
created_date: '2026-06-21 06:21'
updated_date: '2026-06-21 06:36'
labels:
  - architecture
  - epic-split-board
  - loop-backlog
  - loop-meta
dependencies: []
references:
  - docs/proposals/proposal-epic-split-board.md
  - docs/proposals/proposal-epic-capability-model.md
  - scripts/loop-backlog-daemon.js
  - backlog/config.yml
documentation:
  - docs/proposals/proposal-epic-split-board.md
priority: high
ordinal: 95000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Summary

Implement the B″ (unified-board dual-state-machine) architecture as specified in `docs/proposals/proposal-epic-split-board.md`. Replace the existing Meta-* column system and experimental Exp-K epic tasks with a production-grade two-daemon design on a single backlog board.

## Background

The current system has two problems:
1. **B档 conflict**: `status` (column) IS state; each capability also has state — two axes cannot coexist on one column namespace without type explosion.
2. **TASK-105 race condition**: Two daemons writing to the same rows on the same board.

B″ solves both by partitioning the column namespace: `Epic: *` columns for epic tasks, `Basic: *` columns for basic tasks. Each daemon exclusively writes its own subset. `kind:epic` / `kind:basic` label discriminates which state machine applies.

## 7-Phase Implementation Plan

### Phase 0 — Cleanup (prerequisite, ~1 day)
Delete all 17 experimental epic tasks:
- TASK-93, TASK-93.7, TASK-93.8, TASK-93.9, TASK-93.10
- TASK-106 through TASK-117

### Phase 1 — Board Migration (~1 day)
- Replace `backlog/config.yml` statuses (11 → 14 B″ columns):
  ```
  Epic: Proposal, Epic: Plan, Epic: Decomposing, Epic: Awaiting Children,
  Epic: Evaluating, Epic: Done, Epic: Needs Human,
  Basic: Proposal, Basic: Plan, Basic: Backlog, Basic: Ready,
  Basic: In Progress, Basic: Done, Basic: Needs Human
  ```
- `sed`-migrate all ~62 existing basic tasks: map old status → `Basic: <status>` (e.g. `Backlog` → `Basic: Backlog`, `Done` → `Basic: Done`)
- Add `kind:basic` label to all migrated tasks

### Phase 2 — Spec-Stdlib Extraction (~1 day)
- Create `docs/spec-stdlib.md §reviewLoop` with parameterized signature:
  `reviewLoop(needsHumanCol, returnTo, reviewCriteria, maxIter)`
- Remove inline `reviewLoop` copies from:
  - `plugin/skills/task-to-backlog/SKILL.md`
  - `plugin/skills/feature-to-backlog/SKILL.md`
  - `plugin/skills/loop-meta/SKILL.md`
- Replace with references to spec-stdlib

### Phase 3 — Daemon Refactor (~2 days)
- Split `scripts/loop-backlog-daemon.js` into two daemons:
  - `scripts/basic-daemon.js`: watches `basic-ready` events; processes `Basic: *` columns
  - `scripts/epic-daemon.js`: watches `epic-ready` events; processes `Epic: *` columns
- Replace Meta-status filter with `kind` label filter
- Implement dispatch logic per proposal pseudocode:
  - `basicDAG`: propose → plan → execute
  - `epicDAG`: propose → plan → decompose → evaluate
- Implement `cap:*` marker system (append-only notes for idempotency)
- Implement `notifyParentIfAny(id)` in basic-daemon
- Implement three-way reconcile in epic-daemon's `decomposeProcessor`
- Implement `evaluateProcessor` with full Escalated branch

### Phase 4 — Skills Refactor (~1 day)
- Refactor existing skills to seed-only mode (emit `cap:propose=approved` / `cap:plan=approved` and exit):
  - `epic-to-backlog` skill (new): seeds an epic task at `Epic: Proposal`
  - `task-to-backlog` skill: becomes seed-only for basic tasks
  - `feature-to-backlog` skill: becomes seed-only for basic tasks
- Daemon takes over all subsequent processing

### Phase 5 — Guardrails (~1 day)
- `scripts/verify-kind-status.sh`: assert every task has `kind:epic` or `kind:basic`, and its status is in the correct column subset
- `scripts/check-roi-gate.sh`: evaluator gate for epic evaluation phase
- Update `scripts/validate-plugin.sh` to run new guardrail scripts

### Phase 6 — Validation (~2 days)
- Rebuild Exp-K corpus: create 12 test epic tasks under B″ schema (at `Epic: Proposal`)
- Run full E2E cycle: epic-daemon and basic-daemon process corpus end-to-end
- Confirm: no column overlap violations, `parentTaskId` links correct, `notifyParentIfAny` fires correctly, human-intervention recovery works via `return-to` notes

## Key Design Decisions
- One physical board, 14 columns, non-overlapping subsets
- Two daemons (basic-daemon + epic-daemon) — future merge possible once stable
- `cap:*` markers in notes = idempotency + audit trail
- `return-to` notes = human-readable only (no machine parsing)
- `diverging(id)` = `reconcileRunCount(id) ≥ 3` → escalate to `Epic: Needs Human`
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Summary

Implement the B″ (unified-board dual-state-machine) architecture as specified in `docs/proposals/proposal-epic-split-board.md`. Replace the existing Meta-* column system and experimental Exp-K epic tasks with a production-grade two-daemon design on a single backlog board.

## Background

The current system has two problems:
1. **B档 conflict**: `status` (column) IS state; each capability also has state — two axes cannot coexist on one column namespace without type explosion.
2. **TASK-105 race condition**: Two daemons writing to the same rows on the same board.

B″ solves both by partitioning the column namespace: `Epic: *` columns for epic tasks, `Basic: *` columns for basic tasks. Each daemon exclusively writes its own subset. `kind:epic` / `kind:basic` label discriminates which state machine applies.

## Goals

1. `backlog/config.yml` contains exactly 14 B″ statuses (7 `Epic:*` + 7 `Basic:*`) and zero legacy `Meta-*` or bare statuses — verified by `grep -c 'Epic:\|Basic:' backlog/config.yml` returning 14 and `grep -c 'Meta-\|^  - Backlog\|^  - Done\|^  - Ready\|^  - In Progress' backlog/config.yml` returning 0.
2. All existing non-archived tasks carry a `kind:basic` or `kind:epic` label and a status within the matching column subset — verified by `scripts/verify-kind-status.sh` with exit 0.
3. `scripts/basic-daemon.js` and `scripts/epic-daemon.js` exist; `scripts/loop-backlog-daemon.js` is retired; each daemon exclusively writes its own column subset without touching the other's columns.
4. `cap:*` idempotency markers are present in notes of every processed task — verified by `scripts/verify-cap-markers.sh` with exit 0 (script checks that any task in a non-initial status has at least one `cap:*` line in its notes).
5. `docs/spec-stdlib.md` contains a single canonical `reviewLoop` definition; inline copies are removed from `task-to-backlog/SKILL.md`, `feature-to-backlog/SKILL.md`, and `loop-meta/SKILL.md`.
6. End-to-end validation: 12 Exp-K epic tasks progress from `Epic: Proposal` to `Epic: Done` (or `Epic: Needs Human`) in a run whose output is captured to `logs/exp-k-e2e.log`; `grep -c 'column-overlap-violation' logs/exp-k-e2e.log` returns 0 and `grep -c 'terminal:' logs/exp-k-e2e.log` returns 12.

## 7-Phase Implementation Plan

### Phase 0 — Cleanup (prerequisite, ~1 day)
Delete all 17 experimental epic tasks:
- TASK-93, TASK-93.7, TASK-93.8, TASK-93.9, TASK-93.10
- TASK-106 through TASK-117

### Phase 1 — Board Migration (~1 day)
- Replace `backlog/config.yml` statuses (11 → 14 B″ columns)
- `sed`-migrate all ~62 existing basic tasks: map old status → `Basic: <status>`
- Add `kind:basic` label to all migrated tasks

### Phase 2 — Spec-Stdlib Extraction (~1 day)
- Create `docs/spec-stdlib.md §reviewLoop` with parameterized signature
- Remove inline `reviewLoop` copies from task-to-backlog, feature-to-backlog, loop-meta skills
- Replace with references to spec-stdlib

### Phase 3 — Daemon Refactor (~2 days)
- Split `scripts/loop-backlog-daemon.js` into `scripts/basic-daemon.js` + `scripts/epic-daemon.js`
- Implement `cap:*` marker system, `notifyParentIfAny(id)`, three-way reconcile, `evaluateProcessor`

### Phase 4 — Skills Refactor (~1 day)
- Create `plugin/skills/epic-to-backlog/SKILL.md` (seed-only)
- Refactor `task-to-backlog` and `feature-to-backlog` to seed-only mode

### Phase 5 — Guardrails (~1 day)
- Write `scripts/verify-kind-status.sh` and `scripts/verify-cap-markers.sh`
- Update `scripts/validate-plugin.sh` to run new guardrail scripts

### Phase 6 — Validation (~2 days)
- Rebuild Exp-K corpus: create 12 test epic tasks under B″ schema
- Run full E2E cycle and confirm no column overlap violations

## Risks and Trade-offs

- **In-place migration risk**: Bulk sed-migrating ~62 task files may introduce malformed status fields. Mitigation: run `verify-kind-status.sh` immediately after migration.
- **Daemon split regression**: Splitting daemon may break existing event-wiring. Mitigation: preserve existing basic-task logic verbatim before adding epic logic.
- **Column tooling compatibility**: Scripts matching bare status names will break after migration. Mitigation: audit all `scripts/` files before Phase 1.

## Key Design Decisions
- One physical board, 14 columns, non-overlapping subsets
- Two daemons (basic-daemon + epic-daemon) — future merge possible once stable
- `cap:*` markers in notes = idempotency + audit trail
- `diverging(id)` = `reconcileRunCount(id) ≥ 3` → escalate to `Epic: Needs Human`

---

# Plan: Implement B″ unified-board dual-state-machine architecture

Proposal: docs/proposals/proposal-epic-split-board.md

## Phase A: Cleanup — Delete Experimental Epic Tasks
### Tests (write first)
- Test: `backlog task list --plain | grep -E 'TASK-93\b|TASK-10[6-9]|TASK-11[0-7]'` returns empty
### Implementation
- Archive TASK-93, TASK-93.7, TASK-93.8, TASK-93.9, TASK-93.10 via `backlog task archive <id>`
- Archive TASK-106 through TASK-117 via `backlog task archive <id>` (TASK-106–108 may already be archived — treat as no-op)
### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `! backlog task list --plain | grep -qE 'TASK-93\b|TASK-10[6-9]|TASK-11[0-7]'`

## Phase B: Board Migration — Update config.yml + Migrate Task Files
### Tests (write first)
- Test: `grep -c 'Epic:\|Basic:' backlog/config.yml` returns 14
- Test: `bash scripts/verify-kind-status.sh` exits 0
### Implementation
- Replace statuses in `backlog/config.yml` with exactly 14 B″ columns
- Write `scripts/migrate-board.sh` (new) that sed-migrates all ~62 task files
- Audit all files in `scripts/` for hardcoded bare status strings before running migration
- Run `bash scripts/migrate-board.sh` then `bash scripts/verify-kind-status.sh`
### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `[ "$(grep -c 'Epic:\|Basic:' backlog/config.yml)" -eq 14 ]`
- [ ] `bash scripts/verify-kind-status.sh`

## Phase C: Spec-Stdlib — Extract Canonical reviewLoop
### Implementation
- Add `§ reviewLoop` section to `docs/spec-stdlib.md` with parameterized signature
- Remove inline `reviewLoop` definition blocks from task-to-backlog, feature-to-backlog, loop-meta SKILL.md files
- Replace with `-- see spec-stdlib § reviewLoop` reference comments
### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q '§ reviewLoop' docs/spec-stdlib.md`
- [ ] `! grep -qF 'reviewLoop :: (Task, Doc, MaxRounds)' plugin/skills/task-to-backlog/SKILL.md`
- [ ] `! grep -qF 'reviewLoop :: (Task, Doc, MaxRounds)' plugin/skills/feature-to-backlog/SKILL.md`

## Phase D: Daemon Refactor — Split into basic-daemon + epic-daemon
### Implementation
- Create `scripts/basic-daemon.js` (new): event channel `basic-ready`, `basicDAG`, `cap:*` markers, `notifyParentIfAny(id)`
- Create `scripts/epic-daemon.js` (new): event channel `epic-ready`, `epicDAG`, three-way reconcile, `evaluateProcessor`, `diverging(id)` = reconcileRunCount >= 3
- Retire `scripts/loop-backlog-daemon.js`: add deprecation comment, do not delete
### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f scripts/basic-daemon.js`
- [ ] `test -f scripts/epic-daemon.js`
- [ ] `! grep -qF 'Epic:' scripts/basic-daemon.js`
- [ ] `! grep -qF 'Basic:' scripts/epic-daemon.js`

## Phase E: Skills Refactor — Seed-Only Mode
### Implementation
- Create `plugin/skills/epic-to-backlog/SKILL.md` (new): seeds epic task at `Epic: Proposal` with `kind:epic` label
- Update `plugin/skills/task-to-backlog/SKILL.md`: strip post-proposal processing, emit `cap:propose=approved` and exit
- Update `plugin/skills/feature-to-backlog/SKILL.md`: same as task-to-backlog
### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -d plugin/skills/epic-to-backlog`
- [ ] `grep -q 'cap:propose=approved' plugin/skills/task-to-backlog/SKILL.md`

## Phase F: Guardrails — Verification Scripts
### Implementation
- Write `scripts/verify-kind-status.sh` (new): assert kind label + status column subset match
- Write `scripts/verify-cap-markers.sh` (new): assert cap:* marker in notes for non-initial tasks
- Update `scripts/validate-plugin.sh` to call both scripts
### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash scripts/verify-kind-status.sh`
- [ ] `bash scripts/verify-cap-markers.sh`
- [ ] `grep -q 'verify-kind-status' scripts/validate-plugin.sh`

## Phase G: Validation — Rebuild Exp-K Corpus and E2E Run
### Implementation
- Create `logs/` directory: `mkdir -p logs`
- Create 12 test epic tasks with `kind:epic` label and `Epic: Proposal` status
- Run both daemons, redirect output to `logs/exp-k-e2e.log`
- Let daemons run until all 12 tasks reach terminal state
### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `[ "$(grep -c 'column-overlap-violation' logs/exp-k-e2e.log)" -eq 0 ]`
- [ ] `[ "$(grep -c 'terminal:' logs/exp-k-e2e.log)" -eq 12 ]`

## Constraints
- Phase A → B → D → E (sequential dependencies)
- Phase C can run in parallel with Phase B
- Phase F must complete before Phase G
- Each phase must change <= 200 lines of code
- Do not force-push or amend published commits

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash scripts/verify-kind-status.sh`
- [ ] `bash scripts/verify-cap-markers.sh`
- [ ] `[ "$(grep -c 'column-overlap-violation' logs/exp-k-e2e.log)" -eq 0 ]`
- [ ] `[ "$(grep -c 'terminal:' logs/exp-k-e2e.log)" -eq 12 ]`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Proposal review iteration 1: NEEDS_REVISION — Added missing Goals section (6 numbered verifiable items) and filled in empty Acceptance Criteria. Background and feasibility passed. Revised proposal saved back to planSet.

Proposal review iteration 2: NEEDS_REVISION — two items fixed: (1) Goal 4 now cites scripts/verify-cap-markers.sh with exit 0 as the observable verification criterion; (2) added explicit Risks and Trade-offs section covering in-place migration risk, daemon split regression, column tooling compatibility, Phase 0 archival ambiguity, and Exp-K corpus cascade dependency. All other checks (Motivation, Goals 1-3/5-6, Feasibility, Consistency) passed.

Proposal review iteration 3: NEEDS_REVISION — two Goals lacked executable verification commands. Goal 1 added grep commands to verify config.yml column count. Goal 6 added log file path (logs/exp-k-e2e.log) and grep-based terminal/violation checks. All other sections passed.

Proposal review iteration 4: APPROVED

Proposal approved. Starting plan draft.

Plan review iteration 1: NEEDS_REVISION — Fixed: Acceptance Gate was missing the Goal 6 terminal-state check. Added `[ "$(grep -c 'terminal:' logs/exp-k-e2e.log)" -eq 12 ]` as the fifth Acceptance Gate item to match Goal 6's requirement that all 12 Exp-K epic tasks reach a terminal state.

Plan review iteration 2: APPROVED
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 grep -q 'contracts:' plugin/skills/epic-to-backlog/SKILL.md
- [ ] #3 ! backlog task list --plain | grep -qE 'TASK-93\b|TASK-10[6-9]|TASK-11[0-7]'
- [ ] #4 [ "$(grep -c 'Epic:\|Basic:' backlog/config.yml)" -eq 14 ]
- [ ] #5 bash scripts/verify-kind-status.sh
- [ ] #6 grep -q '§ reviewLoop' docs/spec-stdlib.md
- [ ] #7 ! grep -qF 'reviewLoop :: (Task, Doc, MaxRounds)' plugin/skills/task-to-backlog/SKILL.md
- [ ] #8 ! grep -qF 'reviewLoop :: (Task, Doc, MaxRounds)' plugin/skills/feature-to-backlog/SKILL.md
- [ ] #9 test -f scripts/basic-daemon.js
- [ ] #10 test -f scripts/epic-daemon.js
- [ ] #11 ! grep -qF 'Epic:' scripts/basic-daemon.js
- [ ] #12 ! grep -qF 'Basic:' scripts/epic-daemon.js
- [ ] #13 test -d plugin/skills/epic-to-backlog
- [ ] #14 grep -q 'cap:propose=approved' plugin/skills/task-to-backlog/SKILL.md
- [ ] #15 bash scripts/verify-cap-markers.sh
- [ ] #16 grep -q 'verify-kind-status' scripts/validate-plugin.sh
- [ ] #17 [ "$(grep -c 'column-overlap-violation' logs/exp-k-e2e.log)" -eq 0 ]
- [ ] #18 [ "$(grep -c 'terminal:' logs/exp-k-e2e.log)" -eq 12 ]
<!-- DOD:END -->
