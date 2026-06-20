---
id: TASK-103
title: >-
  Implement a provenance-gate pre-commit hook: install
  scripts/verify-provenance.sh as a git pre-commit hook so that any commit
  adding or modifying a results JSON file that lacks data_source: measured is
  rejected before it reaches CI
status: Meta-Plan
assignee: []
created_date: '2026-06-20 10:27'
labels: []
dependencies: []
ordinal: 84000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement a provenance-gate pre-commit hook: install scripts/verify-provenance.sh as a git pre-commit hook so that any commit adding or modifying a results JSON file that lacks data_source: measured is rejected before it reaches CI.

Rationale: Three sub-tasks: (1) adapt verify-provenance.sh to detect modified JSON files via git diff --cached, (2) write install-hooks.sh to place the hook at .git/hooks/pre-commit, (3) add test cases in verify-provenance.test.sh for the hook path. Well-defined, tested gate exists already (verify-provenance.sh).

This meta-task is part of TASK-93 Exp-K experiment corpus (input MT-09).
Source: plugin/loop-meta/data/task-notes/meta-task-inputs.json
<!-- SECTION:DESCRIPTION:END -->
