---
id: TASK-176.8
title: 'GCL-176h: scheduled GCL drift alerting'
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 06:12'
updated_date: '2026-06-24 07:02'
labels:
  - 'kind:basic'
dependencies:
  - TASK-176.3
parent_task_id: TASK-176
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Wire scripts/gcl-report.sh into a cron or loop-backlog heartbeat; alert when GCL mean exceeds drift threshold (two-sided).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: GCL-176h: scheduled GCL drift alerting

## Background
`gcl-report.sh` (TASK-176c) produces GCL statistics on demand, but without automated scheduling it will only be run manually. Gradual drift in GCL mean — either downward (rubber-stamp risk, H5) or upward (overload risk) — needs to be caught automatically before it compounds across many gate events. A scheduled daily run with configurable two-sided thresholds and alert output closes the monitoring loop and surfaces drift to the operator without requiring manual checks.

## Goals
1. `docs/research/gcl-alert-config.json` exists with `lower_bound` (default 5) and `upper_bound` (default 25) fields.
2. `scripts/gcl-report.sh` exits non-zero and prints an ALERT line when GCL mean is outside `[lower_bound, upper_bound]`.
3. A cron/schedule entry or loop-backlog heartbeat hook runs `scripts/gcl-report.sh` daily.
4. `bash scripts/validate-plugin.sh` exits 0 and `bash scripts/gcl-report.sh` exits 0 with valid in-range data.

## Proposed Approach
Create `docs/research/gcl-alert-config.json` with threshold configuration. Extend `scripts/gcl-report.sh` to read this config and exit non-zero with an ALERT line when thresholds are breached. Wire into daily schedule using `/schedule` (cron) or add a heartbeat call to the loop-backlog daemon script. Test with synthetic out-of-range data to confirm alert fires.

## Trade-offs and Risks
- Not doing: PushNotification — logging to backlog/.basic-daemon.log is sufficient for now.
- Risk: cron may not be available in all environments; document the loop-backlog heartbeat as fallback.
- Not doing: upper-bound-only alert — two-sided ensures both rubber-stamp and overload conditions are caught.

---

# Plan: GCL-176h: scheduled GCL drift alerting

## Phase 1: Create alert config file
### Tests (write first)
- `test -f docs/research/gcl-alert-config.json` — config file exists
- `python3 -c "import json; c=json.load(open('docs/research/gcl-alert-config.json')); assert 'lower_bound' in c and 'upper_bound' in c; print('PASS')"` — required fields present

### Implementation
- Create `docs/research/gcl-alert-config.json` with `{"lower_bound": 5, "upper_bound": 25}`.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/gcl-alert-config.json`
- [ ] `python3 -c "import json; c=json.load(open('docs/research/gcl-alert-config.json')); assert 'lower_bound' in c and 'upper_bound' in c; print('PASS')"`

## Phase 2: Extend gcl-report.sh with alert logic
### Tests (write first)
- `grep -q "lower_bound" scripts/gcl-report.sh` — alert config read by script
- `grep -q "ALERT" scripts/gcl-report.sh` — ALERT output present

### Implementation
- In `scripts/gcl-report.sh`, after computing GCL mean, read `docs/research/gcl-alert-config.json` (configurable via `${ALERT_CONFIG:-docs/research/gcl-alert-config.json}`).
- If GCL mean < lower_bound OR > upper_bound: print `"ALERT: GCL mean=<X> is outside safe range [<lower>, <upper>]"` and exit 1.
- If in range: exit 0 normally.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "lower_bound" scripts/gcl-report.sh`
- [ ] `grep -q "ALERT" scripts/gcl-report.sh`
- [ ] `bash scripts/gcl-report.sh`

## Phase 3: Wire into daily schedule
### Tests (write first)
- `crontab -l 2>/dev/null | grep -q "gcl-report.sh" || grep -q "gcl-report.sh" plugin/skills/loop-backlog/SKILL.md` — schedule entry present

### Implementation
- Register a daily cron entry: `0 9 * * * cd /home/yale/work/baime && bash scripts/gcl-report.sh >> backlog/.basic-daemon.log 2>&1` OR add a heartbeat call to `plugin/skills/loop-backlog/SKILL.md` that runs `bash scripts/gcl-report.sh` at the start of each daemon loop iteration.
- Document the schedule entry.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `crontab -l 2>/dev/null | grep -q "gcl-report.sh" || grep -q "gcl-report.sh" plugin/skills/loop-backlog/SKILL.md`

## Phase 4: Validate
### Tests (write first)
- `bash scripts/validate-plugin.sh` exits 0
- `bash scripts/gcl-report.sh` exits 0 with valid in-range data

### Implementation
- Run `bash scripts/validate-plugin.sh`.
- Run `bash scripts/gcl-report.sh` with a valid gcl-events.jsonl containing in-range GCL mean.
- Fix any issues found.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash scripts/gcl-report.sh`

## Constraints
- Alert logic must be in gcl-report.sh, not a separate script.
- `gcl-alert-config.json` thresholds must be configurable (not hardcoded).
- Depends on TASK-176.3 (gcl-report.sh) being complete.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash scripts/gcl-report.sh`
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
[E] DoD executability: all items are shell commands; Phase 3 compound command validated via bash -n — valid shell syntax
[E] Absence checks: no grep -qv present — readable from plan
[E] Phase ordering: 1→2→3→4, strictly linear, no circular deps
[E] Scope discipline: each phase maps to exactly one Goal
[C] File paths: scripts/validate-plugin.sh and loop-backlog/SKILL.md confirmed; gcl-report.sh from TASK-176.3 dep; gcl-alert-config.json is new
GCL-self-report: E=8 C=1 H=0

claimed: 2026-06-24T06:56:04Z

Phase 1-4 complete. Created gcl-alert-config.json with [5,25] bounds. Extended gcl-report.sh with two-sided alert check (exits 1 on drift, 0 in-range). Added GCL Drift Alerting section to loop-backlog/SKILL.md. validate-plugin.sh: 0 errors. gcl-report.sh exits 0 with real data (mean=6.57). Committed: 9cf8fad.

Phase 1 ✓ 2026-06-24T06:59:51Z
Created docs/research/gcl-alert-config.json with lower_bound=5, upper_bound=25
Phase 2 ✓ 2026-06-24T06:59:51Z
Extended gcl-report.sh with two-sided alert logic; exits 1 on drift, 0 in-range (mean 6.57 in [5,25])
Phase 3 ✓ 2026-06-24T06:59:51Z
Added GCL Drift Alerting section to loop-backlog/SKILL.md with heartbeat and cron documentation
Phase 4 ✓ 2026-06-24T06:59:51Z
validate-plugin.sh: 0 errors, gcl-report.sh exits 0 with real data (mean 6.57 in [5,25])

Completed: 2026-06-24T07:02:08Z
<!-- SECTION:NOTES:END -->

Architect review iteration 1 (2026-06-24): Plan APPROVED. All criteria passed — Goal coverage (4/4), TDD structure correct in all 4 phases, first DoD item is `bash scripts/validate-plugin.sh` in every phase, Acceptance Gate first item is `bash scripts/validate-plugin.sh`, all DoD items are valid shell commands (Phase 3 compound OR syntax verified), no `grep -qv` anti-pattern, no circular phase deps, all phases backed by Goals, file paths correct (validate-plugin.sh and loop-backlog/SKILL.md exist; gcl-report.sh dependency on TASK-176.3 documented; gcl-alert-config.json created by this task). GCL self-report: E=1 (single-pass review, no iteration needed), C=1, H=1 (structured checklist review, low creativity required).
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh && bash scripts/gcl-report.sh
- [ ] #2 bash scripts/validate-plugin.sh
<!-- DOD:END -->
