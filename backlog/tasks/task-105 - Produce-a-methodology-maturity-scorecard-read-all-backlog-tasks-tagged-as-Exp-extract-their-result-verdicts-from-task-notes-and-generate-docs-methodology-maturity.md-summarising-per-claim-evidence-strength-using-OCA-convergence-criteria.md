---
id: TASK-105
title: >-
  Produce a methodology maturity scorecard: read all backlog tasks tagged as
  Exp-*, extract their result verdicts from task notes, and generate
  docs/methodology-maturity.md summarising per-claim evidence strength using OCA
  convergence criteria
status: Meta-Plan
assignee: []
created_date: '2026-06-20 10:27'
labels: []
dependencies: []
ordinal: 86000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Produce a methodology maturity scorecard: read all backlog tasks tagged as Exp-*, extract their result verdicts (Met/NotMet/Inconclusive) from task notes, and generate docs/methodology-maturity.md summarising per-claim evidence strength using the OCA convergence criteria.

Rationale: Four sub-tasks: (1) write scripts/extract-exp-verdicts.sh to parse Exp-* task notes, (2) implement scoring logic using OCA criteria in a Python script, (3) generate docs/methodology-maturity.md from scores, (4) add a gate that fails if any P0 claim has zero measured evidence. Real project need: baime lacks a consolidated evidence-strength dashboard.

This meta-task is part of TASK-93 Exp-K experiment corpus (input MT-11).
Source: plugin/loop-meta/data/task-notes/meta-task-inputs.json
<!-- SECTION:DESCRIPTION:END -->
