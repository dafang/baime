---
id: TASK-176
title: GCL 完整观测机制：三阶段增量实现（结构化日志 + 可
status: 'Epic: Done'
assignee: []
created_date: '2026-06-23 16:45'
updated_date: '2026-06-24 07:05'
labels:
  - 'kind:epic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GCL 完整观测机制：三阶段增量实现（结构化日志 + 可靠性采样 + 闭环告警）
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Epic Plan: GCL 完整観测机制：三阶段增量实现

## Background

GCL (Gate Comprehension Load) measures cognitive load at human gate decisions in the loop-backlog workflow. As loop-backlog autonomy deepens, the human role shifts from throughput contributor to gate judge — making GCL a proxy for whether human oversight is substantively functional, not a mere research metric. External evidence elevates this to a safety property: approval fatigue / YOLO mode (AI governance literature, 2025) documents how human-in-the-loop control degrades to rubber-stamping under cognitive overload; EU AI Act (August 2026 deadline) requires provable human oversight; and automation bias research (Buçinca et al., 2021) shows Scope− taken too far turns gates into pure mechanical pass-throughs. Current state: premise-ledger injects GCL self-report only at plan gates (TASK-151); TASK-152 performed one-time analysis of 13 events revealing delta_H = −1.46, but the result is unconfirmable because data is scattered in task Notes, analysis is not reproducible, and no feedback loop exists — the four pillars (instrumentation → persistence → analysis → feedback) are 75% empty.

## Goals

1. A structured, append-only event log (`docs/research/gcl-events.jsonl`) with defined schema exists, backfilled with all 13 historical gate events from TASK-151 onward, and all future gate events are appended automatically via premise-ledger hook.
2. A reproducible analysis script (`scripts/gcl-report.sh`) runs at any time and outputs stratified E/C/H statistics by gate_type × task_kind, delta_H trend, and GCL-vs-escape-rate pairing — enabling verification of TASK-152 findings and ongoing monitoring.
3. Reliability sampling is in place: ~10% of gates record intra-rater or inter-model H variance in gcl-events.jsonl, providing error bars that distinguish "direction credible" from "quantitatively credible" data, and enabling H5 validation (GCL below a threshold correlates with higher gate escape rate).
4. Gate escape rate is tracked post-hoc for each gate-passed task (sourced from backlog task state history: Basic: Needs Human / reaper requeue), and linked to GCL records, completing the GCL-vs-escape-rate pairing.
5. Premise-ledger self-report is extended to proposal gate and epic-evaluate gate (currently only plan gate), achieving full gate type coverage.
6. A scheduled or heartbeat-driven analysis runs gcl-report.sh periodically; when GCL mean drifts beyond a configured threshold, an alert is written to the backlog log or via PushNotification, closing the observation loop.

## Sub-Task Decomposition

1. **GCL-176a: gcl-events.jsonl schema + historical backfill** — Define the JSONL schema (task_id, gate_type, task_kind, timestamp, E, C, H, GCL, reviewer_model, sample_run_id, evidence_independence, gate_actor_type, premise_lines), create `docs/research/gcl-events.jsonl`, and backfill all 13 historical gate events from TASK-151 onward by parsing task Notes. The `evidence_independence` field (high/low/unknown) captures whether the gate's evidence source was independent of the system being reviewed — required for H6 validation. The `gate_actor_type` field (human/llm/hybrid/tool) records who performed the gate decision — required for H7 validation.
2. **GCL-176b: premise-ledger append hook** — Modify the premise-ledger injection step in `plugin/skills/feature-to-backlog/SKILL.md` and `plugin/skills/epic-to-backlog/SKILL.md` to also append one JSONL line to `docs/research/gcl-events.jsonl` after each plan gate self-report, capturing future events automatically.
3. **GCL-176c: gcl-report.sh reproducible analysis script** — Create `scripts/gcl-report.sh` that reads `gcl-events.jsonl` and outputs stratified E/C/H stats by gate_type × task_kind, delta_H, rolling 30-day trend, and a GCL-vs-escape-rate table.
4. **GCL-176d: gate escape rate tracking** — For each gate-passed task in `gcl-events.jsonl`, look up whether its status later reached Basic: Needs Human or was reaper-requeued; document the extraction procedure and add escape_rate field post-hoc to existing records.
5. **GCL-176e: reliability sampling protocol** — Implement ~10% sampling logic in the premise-ledger hook: when triggered, re-run GCL self-report on the same gate content with a second model or second run; record both scores in `gcl-events.jsonl` under a shared sample_run_id and compute intra-rater variance.
6. **GCL-176f: H5 + H6 + H7 hypothesis validation experiment** — Using `gcl-events.jsonl` with escape_rate, evidence_independence, and gate_actor_type populated, run statistical tests for: H5 (GCL below threshold predicts higher escape rate); H6 (evidence_independence predicts escape rate independently of GCL magnitude); H7 (controlling for evidence_independence, gate_actor_type human vs automated has no significant effect on escape rate in routine gate subset). Write results to `docs/research/gcl-h5-h6-h7-validation.md`.
7. **GCL-176g: premise-ledger extension to proposal and epic-evaluate gates** — Extend the premise-ledger injection in `plugin/skills/feature-to-backlog/SKILL.md` and `plugin/skills/epic-to-backlog/SKILL.md` to fire at proposal gate and epic-evaluate gate, adding gate_type tagging for full coverage.
8. **GCL-176h: scheduled GCL drift alerting** — Wire `scripts/gcl-report.sh` into a `/schedule` cron or loop-backlog heartbeat; when GCL mean exceeds a configured drift threshold, emit an alert (PushNotification or backlog log entry), closing the four-pillar feedback loop.

## Sequencing

```
176a  →  176b  →  176c  →  176h
                  176d  ↗
176b  →  176e  →  176f (needs 176d + 176e)
176g  (independent; can run in parallel with 176a–176f)
176c + 176g  →  176h (alerting needs the report script and full gate coverage)
```

Detailed ordering:

- **176a must land first**: it establishes the schema and the seed data; every other child depends on a populated `gcl-events.jsonl`.
- **176b follows 176a**: the append hook writes to a file that must already exist with a validated schema.
- **176c follows 176b**: the analysis script is most useful once the hook is in place and producing consistent records; it also needs the schema stable.
- **176d follows 176b**: escape rate extraction requires records already in `gcl-events.jsonl`; can proceed in parallel with 176c.
- **176e follows 176b**: reliability sampling extends the hook; schema stability from 176b is a prerequisite.
- **176f follows 176d + 176e**: H5/H6/H7 validation requires escape_rate (176d), variance data (176e), and gate_actor_type populated to be meaningful.
- **176g is independent**: the proposal-gate and epic-evaluate-gate extension touches the same skill files as 176b but does not depend on the JSONL file being populated; it can be scheduled in parallel with 176a–176f, but should merge before 176h to ensure all gate types are covered in alerts.
- **176h follows 176c + 176g**: alerting needs the report script (176c) and full gate type coverage (176g).

Children that can proceed in parallel once 176a is done: 176b must be serial, but 176c and 176d can run concurrently after 176b. 176g can run at any time before 176h.

## Constraints

- Do not create child tasks in this plan — decomposition is performed by the autonomous worker.
- validate-plugin.sh must pass after each child that touches plugin/ or scripts/.
- The GCL measurement objective is NOT minimize(GCL) — maintain the two-sided range framing (H5).
- Alert thresholds in 176h must be configured as two-sided ranges, not one-sided minima.
- H6 frames automation bias as a general coupling failure (evidence source ↔ monitored system), not a human-vs-AI question; the `evidence_independence` field operationalizes this across all gate types.
- H7 proposes that in routine engineering gates, gate_actor_type has no significant effect on escape rate when controlling for evidence_independence; the `gate_actor_type` field enables joint H6+H7 testing.
- "Human oversight" is not a baseline; it is one gate actor type. Gate quality is measured by independence, accountability, and calibratability of the monitoring signal — not by whether the actor is human. The three-variable decomposition (A=epistemic contribution, B=preference anchoring, C=accountability) from gcl-complete-observation-mechanism.md §4.2 defines when human presence has genuine incremental value.
- Children that only write to docs/research/ are doc-only (use task-to-backlog, not feature-to-backlog).
- Children that create/modify scripts/ or plugin/ are code-change (use feature-to-backlog).

### Child task classification

| Child   | Touches plugin/ or scripts/? | Type        |
|---------|------------------------------|-------------|
| 176a    | No (docs/research/ only)     | doc-only    |
| 176b    | Yes (plugin/skills/)         | code-change |
| 176c    | Yes (scripts/)               | code-change |
| 176d    | No (docs/research/ only)     | doc-only    |
| 176e    | Yes (plugin/skills/)         | code-change |
| 176f    | No (docs/research/ only)     | doc-only    |
| 176g    | Yes (plugin/skills/)         | code-change |
| 176h    | Yes (scripts/ + schedule)    | code-change |
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Epic proposal self-review: APPROVED
premise-ledger:
[E] Motivation (3-8 lines, WHY not WHAT): Background names approval fatigue, EU AI Act, automation bias, and four-pillar gap as the WHY — 8 lines, within range.
[E] Goals all verifiable: Each goal names a concrete artifact or observable behavior (file exists, script runs and outputs X, sampling in place, escape_rate field populated, gates extended, alert fires).
[E] Decomposition covers all goals: GCL-176a+b cover Goal 1, 176c covers Goal 2, 176e covers Goal 3, 176d covers Goal 4, 176g covers Goal 5, 176h covers Goal 6, 176f adds H5 validation.
[E] Feasibility consistent with codebase: premise-ledger injection exists (TASK-151), backlog task state history is mechanically queryable, /schedule skill is available.
[E] Trade-offs and risks identified: Scope (no UI, no human panels, no auto-enforcement), LLM self-enhancement bias named explicitly, escape rate circularity, GCL minimization scope creep, throughput overhead.
[C] Consistency check: Three increments from research doc map cleanly to child groups; no contradictions between Background, Goals, and Decomposition.
GCL-self-report: E=5 C=1 H=0

Epic proposal approved. Starting epic plan draft.

Epic plan review iteration 1: APPROVED
premise-ledger:
[E] Sub-Task Decomposition present: 8 children (176a–176h) each with title and one-line description.
[E] Goal coverage: All 6 proposal Goals covered by at least one child (176a+176b→G1, 176c→G2, 176e→G3, 176d→G4, 176g→G5, 176h→G6).
[E] Sequencing coherence: Dependencies stated explicitly and verified acyclic (176a→176b→176c→176h; 176b→176d,176e; 176d+176e→176f; 176g→176h).
[E] Scope discipline: All children map directly to proposal Goals; none oversized to warrant a separate epic.
[E] No premature creation: Plan explicitly states children are not created here; describes only intended decomposition.
[E] File paths / feasibility: scripts/, docs/research/, plugin/skills/feature-to-backlog/SKILL.md, plugin/skills/epic-to-backlog/SKILL.md all confirmed to exist.
[E] Child classification correct: doc-only for 176a/176d/176f (docs/research/ only); code-change for 176b/176c/176e/176g/176h (plugin/ or scripts/).
GCL-self-report: E=7 C=0 H=0

cap:propose=approved

Plan updated 2026-06-23: added H6 (evidence_independence), evidence_independence field to schema (176a), H5+H6 combined validation (176f), two-sided alert constraint (176h).

Plan updated 2026-06-23: added H7 hypothesis and gate_actor_type field to schema (176a), extended 176f to cover H7 validation (now gcl-h5-h6-h7-validation.md), added H7 constraint and three-variable decomposition (A/B/C) framing to Constraints section.

cap:decompose=started
Epic decomposition started: 2026-06-24T06:10Z
Agent will create 8 child tasks (176a–176h) via task-to-backlog (doc-only) and feature-to-backlog (code-change).

cap:decompose=done
All 8 children created: TASK-176.1, TASK-176.2, TASK-176.3, TASK-176.4, TASK-176.5, TASK-176.6, TASK-176.7, TASK-176.8. R1 guard passed.

Sub-task TASK-176.3 completed: 2026-06-24T06:42:56Z

Sub-task TASK-176.4 completed: 2026-06-24T06:44:19Z

Sub-task TASK-176.5 completed: 2026-06-24T06:47:58Z

Sub-task TASK-176.6 completed: 2026-06-24T06:54:57Z

Sub-task TASK-176.7 completed: 2026-06-24T06:54:59Z

Sub-task TASK-176.8 completed: 2026-06-24T07:02:10Z

cap:evaluate=recommendation:FINISH | done=8/8 needsHuman=0 dod_pass=true | all children Basic: Done, DoD verified | data_source: measured

RECOMMENDATION: FINISH.
To finish: set status → Epic: Done.
To iterate: set status → Epic: Proposal or Epic: Plan and re-run /epic-to-backlog.

Epic closed: 2026-06-24T07:05:54Z. All 8 sub-tasks Basic: Done. RECOMMENDATION was FINISH.
<!-- SECTION:NOTES:END -->
