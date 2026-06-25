---
id: TASK-189
title: 跨项目验证（D2 行为接地）：BAIME 在外部项目的可移植性试用
status: 'Epic: Proposal'
assignee: []
created_date: '2026-06-24 09:35'
labels:
  - 'kind:epic'
  - 'area:research'
dependencies: []
references:
  - docs/research/grounding-infrastructure.md
  - docs/research/gate-temporal-portfolio.md
  - docs/research/gcl-synthesis.md
ordinal: 120000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build the D2 (cross-context portability) behavioral grounding channel — the most expensive and currently untooled grounding gap for BAIME. For a methodology framework (not a product), the in-repo escape rate is only a weak proxy; the strong behavioral ground truth is whether BAIME actually works when applied to a *different* project. grounding-infrastructure.md §3.3 now splits behavioral grounding into D1 (production telemetry, future/automatable) and D2 (cross-context portability, now/manual/bottleneck); this epic builds D2.

Goal: turn "try BAIME on another project and see what breaks" from an unstructured manual activity into a repeatable protocol with structured observation capture, then run it at least once against a real external project and feed results back into the methodology.

Candidate decomposition (to be refined in Epic: Decomposing):
1. Cross-project trial protocol (doc): define what "installing and using BAIME on a new repo" entails — install path, the minimal task set to exercise (feature-to-backlog, loop-backlog, a gate cycle), and the success/failure criteria per step.
2. Structured observation record format (doc + lightweight tooling): a schema for capturing what broke, what was missing, what assumptions failed (e.g. repo-shape assumptions, L0 config detection, MCP availability), portable across trials. Should connect to gcl-events.jsonl where a trial produces gate events.
3. Friction inventory from one real trial: run the protocol against one concrete external project, capture the observation record, produce a ranked friction list (blocking / degraded / cosmetic).
4. Feedback loop into methodology: convert the top frictions into backlog tasks or doc updates; document which BAIME assumptions are project-specific vs. genuinely portable.

Trade-offs: this is genuinely open-ended and external-facing; protocol and record format are designed first (doc-heavy), real trial follows. Premature structuring is wasteful, so the observation format must stay lightweight. Depends on no other task to start the protocol design, but the real trial depends on having a candidate external project.

Acceptance (epic-level): a cross-project trial protocol doc exists; a structured observation record format exists; at least one real external-project trial has been run and its friction inventory captured; the top frictions are converted into tracked follow-up tasks or doc updates.
<!-- SECTION:DESCRIPTION:END -->
