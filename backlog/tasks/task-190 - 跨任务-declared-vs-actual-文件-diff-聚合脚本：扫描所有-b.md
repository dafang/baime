---
id: TASK-190
title: 跨任务 declared-vs-actual 文件 diff 聚合脚本：扫描所有 b
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 09:56'
updated_date: '2026-06-24 10:13'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
跨任务 declared-vs-actual 文件 diff 聚合脚本：扫描所有 backlog/tasks/*.md 的 meta-cc session digest 段，提取 worker 声明修改文件 vs session trace 实际修改文件的 diff，输出系统性声明偏差聚合报告（GCL 观测机制第3类信息的聚合层，源自 TASK-182）
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: Cross-Task Declared-vs-Actual File Diff Aggregation Report

## Background
TASK-182 shipped `plugin/skills/loop-backlog/meta-cc-digest.sh`, whose
`## Gate Evidence Pack` section (with `FILE_ACTIVITY:` and `SCOPE_DIFF:` markers)
records each task's actual-vs-declared file scope — the 3rd class of GCL
observation information, declared-vs-actual deviation. Today that signal is
produced one task at a time and left scattered across individual
`backlog/tasks/*.md` Notes, so there is no way to see SYSTEMATIC patterns: how
many tasks drift from declared scope, or which files are repeatedly touched
outside any plan. This proposal adds the missing aggregation layer that reads
those per-task digests and emits one cross-task deviation report, completing the
GCL observation mechanism by making the 3rd-class signal queryable in aggregate.

## Goals
1. A standalone script `scripts/declared-vs-actual-report.sh` exists and
   `bash scripts/declared-vs-actual-report.sh --help` exits 0.
2. The script scans all `backlog/tasks/*.md`, and for each task that has a
   `## Gate Evidence Pack` section it extracts the `FILE_ACTIVITY:` (actual
   files) and `SCOPE_DIFF:` (out-of-scope files) markers.
3. The script prints a plain-text aggregate report with two parts: a per-task
   line (task id, actual-file count, scope-diff count) and a systematic-deviation
   summary (count of tasks with non-empty scope drift, and the most frequently
   out-of-scope drift files ranked by occurrence across tasks).
4. Tasks with no `## Gate Evidence Pack` section are counted as `no-digest` and
   listed in a summary count, never raised as errors; the script exits 0 when
   zero tasks have digests (verifiable: run against the current repo, exit 0).
5. The script is read-only over `backlog/tasks/*.md`: it writes no files and
   modifies no jsonl (verifiable: `git status --porcelain` is unchanged after a
   run), and uses only `bash` + `python3` with no external dependencies, matching
   `scripts/gcl-report.sh`.

## Proposed Approach
Add a single standalone script under `scripts/` that mirrors the shape and
conventions of `scripts/gcl-report.sh`: a `bash` wrapper with `set -euo pipefail`,
a `--help` early-exit, and an inlined `python3` heredoc that does the parsing and
printing (header banner, numbered sections, summary footer, no external deps).
The script globs `backlog/tasks/*.md`. For each file it locates the
`## Gate Evidence Pack` block and reads the `FILE_ACTIVITY:` and `SCOPE_DIFF:`
marker lines, splitting each on commas into a file set; `none` / empty values map
to empty sets. The declared (in-scope) set is derived as `FILE_ACTIVITY` minus
`SCOPE_DIFF`, so the report can show actual, in-scope, and out-of-scope per task
without re-parsing Implementation Plans. Files lacking the section are tallied as
`no-digest`. Cross-task aggregation accumulates a frequency map over out-of-scope
files (most-common drift files) and counts tasks with non-empty `SCOPE_DIFF`.
Output is a plain-text report: a per-task section, then a systematic-deviation
summary section, then a footer noting how many tasks had digests vs `no-digest`.
No implementation code is included here.

## Trade-offs and Risks
- Scope boundary: we are NOT modifying `meta-cc-digest.sh`, the `verifyDod` /
  `epicEvaluate` gate logic, or the digest emission format. The new script is a
  pure read-only consumer of what those already produce.
- Sparse early reports: most tasks do not yet carry a Gate Evidence Pack (digest
  injection is new as of TASK-182), so initial reports will show a high
  `no-digest` count and thin aggregate signal. This is expected and acceptable —
  coverage grows as new tasks flow through the gate; the report degrades
  gracefully rather than failing.
- Parsing fragility: the script depends on the textual `FILE_ACTIVITY:` /
  `SCOPE_DIFF:` markers and the `## Gate Evidence Pack` heading. If the digest
  format drifts, extraction silently under-counts. Mitigation: match the exact
  markers documented in `meta-cc-digest.sh` and treat unrecognized content as
  `no-digest` rather than erroring.
- No writes: aggregation stays read-only — it appends nothing to
  `docs/research/gcl-events.jsonl` and creates no derived data files, keeping the
  tool side-effect-free and safe to run repeatedly.

---

# Plan: Cross-Task Declared-vs-Actual File Diff Aggregation Report

Proposal: (inline — proposal lives in task plan field, no docs file)

The deliverable is a single standalone script `scripts/declared-vs-actual-report.sh`,
mirroring `scripts/gcl-report.sh` conventions (`set -euo pipefail`, a `--help`
early-exit, an inlined `python3` heredoc that parses and prints with a banner /
numbered sections / footer). It globs `backlog/tasks/*.md`, finds each
`## Gate Evidence Pack` block, reads its `FILE_ACTIVITY:` and `SCOPE_DIFF:` marker
lines (comma-split; `none`/empty → empty set), and emits a per-task diff section
(Phase A) plus a cross-task systematic-deviation summary (Phase B). Tasks without
the section are tallied as `no-digest`, never errored. The script is read-only and
uses only `bash` + `python3`.

## Phase A: parser + per-task diff + report skeleton
### Tests (write first)
(executable shell assertions, must fail before impl)
```bash
TMPDIR="${TMPDIR:-/tmp}"
# (T-A0) absence: script must not yet exist before impl
! test -f scripts/declared-vs-actual-report.sh

# (T-A1) after impl: --help exits 0
bash scripts/declared-vs-actual-report.sh --help

# (T-A2) after impl: --help text names the script
bash scripts/declared-vs-actual-report.sh --help | grep -q 'declared-vs-actual-report.sh'

# (T-A3) build a TMPDIR fixture task with a Gate Evidence Pack, then run the
# script pointed at that fixture dir; per-task line shows the task id with
# actual-file count = 3 and scope-diff count = 1
mkdir -p "$TMPDIR/fix_a/backlog/tasks"
cat > "$TMPDIR/fix_a/backlog/tasks/task-900 - fixture.md" <<'EOF'
## Gate Evidence Pack
FILE_ACTIVITY: a.go, b.go, c.go
ERROR_COUNT: 0
EDIT_OSCILLATION: none
SCOPE_DIFF: c.go
data_source: meta-cc-session
EOF
bash scripts/declared-vs-actual-report.sh "$TMPDIR/fix_a/backlog/tasks" \
  | grep -E 'task-900' | grep -q '3'
bash scripts/declared-vs-actual-report.sh "$TMPDIR/fix_a/backlog/tasks" \
  | grep -E 'task-900' | grep -q '1'

# (T-A4) a fixture task with SCOPE_DIFF: none yields a per-task line and no crash
mkdir -p "$TMPDIR/fix_a2/backlog/tasks"
cat > "$TMPDIR/fix_a2/backlog/tasks/task-901 - clean.md" <<'EOF'
## Gate Evidence Pack
FILE_ACTIVITY: x.go, y.go
SCOPE_DIFF: none
data_source: meta-cc-session
EOF
bash scripts/declared-vs-actual-report.sh "$TMPDIR/fix_a2/backlog/tasks" | grep -q 'task-901'
```
### Implementation
- Create `scripts/declared-vs-actual-report.sh` (`bash` wrapper + one inlined
  `python3` heredoc). Accept an optional first arg = tasks dir
  (default `backlog/tasks`), matching `gcl-report.sh`'s `${1:-default}` pattern,
  so fixtures can be exercised under `$TMPDIR`.
- `--help`/`-h` early-exit prints usage including the literal string
  `declared-vs-actual-report.sh` and exits 0.
- python heredoc: glob `*.md`; for each file scan for the `## Gate Evidence Pack`
  heading; within that block parse `FILE_ACTIVITY:` and `SCOPE_DIFF:` lines,
  comma-split, map `none`/empty to empty set; derive in-scope = actual − scope_diff.
- Print banner + Section 1 (per-task lines: task id, actual count, in-scope count,
  scope-diff count). Tasks without the section tallied as `no-digest`.
- Mirror `gcl-report.sh` style: `=`*70 banner, `──` section headers, footer.
### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash scripts/declared-vs-actual-report.sh --help`
- [ ] `bash scripts/declared-vs-actual-report.sh --help | grep -q 'declared-vs-actual-report.sh'`
- [ ] `TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_a/backlog/tasks" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: a.go, b.go, c.go\nSCOPE_DIFF: c.go\ndata_source: meta-cc-session\n' > "$TMPDIR/dod_a/backlog/tasks/task-900 - fixture.md" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_a/backlog/tasks" | grep -E 'task-900' | grep -q '3'`
- [ ] `TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_a/backlog/tasks" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: a.go, b.go, c.go\nSCOPE_DIFF: c.go\ndata_source: meta-cc-session\n' > "$TMPDIR/dod_a/backlog/tasks/task-900 - fixture.md" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_a/backlog/tasks" | grep -E 'task-900' | grep -q '1'`
- [ ] `TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_a2/backlog/tasks" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: x.go, y.go\nSCOPE_DIFF: none\ndata_source: meta-cc-session\n' > "$TMPDIR/dod_a2/backlog/tasks/task-901 - clean.md" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_a2/backlog/tasks" | grep -q 'task-901'`

## Phase B: cross-task aggregation + systematic-deviation summary
### Tests (write first)
(executable shell assertions, must fail before impl)
```bash
TMPDIR="${TMPDIR:-/tmp}"
# (T-B1) two fixture tasks both drift on shared.go; aggregate summary names
# shared.go as the most frequent out-of-scope drift file
mkdir -p "$TMPDIR/fix_b/backlog/tasks"
cat > "$TMPDIR/fix_b/backlog/tasks/task-910 - one.md" <<'EOF'
## Gate Evidence Pack
FILE_ACTIVITY: shared.go, one.go
SCOPE_DIFF: shared.go
data_source: meta-cc-session
EOF
cat > "$TMPDIR/fix_b/backlog/tasks/task-911 - two.md" <<'EOF'
## Gate Evidence Pack
FILE_ACTIVITY: shared.go, two.go
SCOPE_DIFF: shared.go
data_source: meta-cc-session
EOF
bash scripts/declared-vs-actual-report.sh "$TMPDIR/fix_b/backlog/tasks" | grep -q 'shared.go'
# summary reports a count of 2 tasks carrying non-empty scope drift
bash scripts/declared-vs-actual-report.sh "$TMPDIR/fix_b/backlog/tasks" | grep -q '2'

# (T-B2) no-digest tally: a fixture dir with a task lacking the section reports
# no-digest and still exits 0
mkdir -p "$TMPDIR/fix_b2/backlog/tasks"
cat > "$TMPDIR/fix_b2/backlog/tasks/task-920 - bare.md" <<'EOF'
## Implementation Plan
just a plan, no evidence pack
EOF
bash scripts/declared-vs-actual-report.sh "$TMPDIR/fix_b2/backlog/tasks" | grep -q 'no-digest'

# (T-B3) zero-digest degradation: empty tasks dir exits 0
mkdir -p "$TMPDIR/fix_b3/backlog/tasks"
bash scripts/declared-vs-actual-report.sh "$TMPDIR/fix_b3/backlog/tasks"

# (T-B4) read-only: running over the real repo leaves git status unchanged
BEFORE=$(git status --porcelain); bash scripts/declared-vs-actual-report.sh >/dev/null; AFTER=$(git status --porcelain); test "$BEFORE" = "$AFTER"
```
### Implementation
- Extend the python heredoc: accumulate a frequency `Counter` over out-of-scope
  files across all tasks; count tasks with non-empty `SCOPE_DIFF`.
- Add Section 2 (systematic-deviation summary): count of tasks with drift, and the
  most-frequent out-of-scope files ranked by occurrence (descending).
- Add footer: tasks-with-digest vs `no-digest` counts.
- Ensure empty/zero-digest input still prints a report and exits 0 (graceful
  degradation, mirroring `gcl-report.sh` empty-input handling).
### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_b/backlog/tasks" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: shared.go, one.go\nSCOPE_DIFF: shared.go\n' > "$TMPDIR/dod_b/backlog/tasks/task-910 - one.md" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: shared.go, two.go\nSCOPE_DIFF: shared.go\n' > "$TMPDIR/dod_b/backlog/tasks/task-911 - two.md" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_b/backlog/tasks" | grep -q 'shared.go'`
- [ ] `TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_b/backlog/tasks" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: shared.go, one.go\nSCOPE_DIFF: shared.go\n' > "$TMPDIR/dod_b/backlog/tasks/task-910 - one.md" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: shared.go, two.go\nSCOPE_DIFF: shared.go\n' > "$TMPDIR/dod_b/backlog/tasks/task-911 - two.md" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_b/backlog/tasks" | grep -q '2'`
- [ ] `TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_b2/backlog/tasks" && printf '## Implementation Plan\nno pack here\n' > "$TMPDIR/dod_b2/backlog/tasks/task-920 - bare.md" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_b2/backlog/tasks" | grep -q 'no-digest'`
- [ ] `TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_b3/backlog/tasks" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_b3/backlog/tasks"`
- [ ] `B=$(git status --porcelain); bash scripts/declared-vs-actual-report.sh >/dev/null; A=$(git status --porcelain); test "$B" = "$A"`

## Constraints
(non-executable criteria)
- Read-only over `backlog/tasks/*.md`: writes no files, appends nothing to
  `docs/research/gcl-events.jsonl`, creates no derived data files.
- Does NOT modify `plugin/skills/loop-backlog/meta-cc-digest.sh`, the
  `verifyDod` / `epicEvaluate` gate logic, or the digest emission format — the new
  script is a pure read-only consumer.
- Graceful no-digest degradation: tasks lacking the `## Gate Evidence Pack`
  section are tallied as `no-digest`, never raised as errors; exits 0 even when
  zero tasks carry digests.
- Uses only `bash` + `python3`, no external dependencies.
- Mirrors `scripts/gcl-report.sh` style: `set -euo pipefail`, `--help` early-exit,
  inlined `python3` heredoc, banner / numbered sections / footer.
- Matches the exact markers documented in `meta-cc-digest.sh` (`## Gate Evidence
  Pack`, `FILE_ACTIVITY:`, `SCOPE_DIFF:`); unrecognized content treated as
  `no-digest` rather than erroring.
- Each phase ≤ 200 LOC; total script kept small and single-file.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash scripts/declared-vs-actual-report.sh`
- [ ] `bash scripts/declared-vs-actual-report.sh --help`
- [ ] `B=$(git status --porcelain); bash scripts/declared-vs-actual-report.sh >/dev/null; A=$(git status --porcelain); test "$B" = "$A"`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Proposal self-review: APPROVED
premise-ledger:
[E] Consistency: proposal goals/approach checked against each other within the task plan text — Goal 3 'out-of-scope drift' matches Approach's FILE_ACTIVITY-minus-SCOPE_DIFF derivation, no contradiction.
[E] Motivation scope: this task file's Description states the deliverable is the 3rd-class GCL aggregation layer sourced from TASK-182, directly grounding the Background.
[C] Feasibility (markers): FILE_ACTIVITY:/SCOPE_DIFF:/## Gate Evidence Pack format confirmed by reading plugin/skills/loop-backlog/meta-cc-digest.sh (external file).
[C] Feasibility (style): standalone bash+python3 heredoc, set -euo pipefail, --help early-exit, banner+footer, no external deps confirmed by reading scripts/gcl-report.sh (external file).
[C] Completeness (parsing risk): digest format is plain textual markers (fragile) — read from meta-cc-digest.sh header comment (external file).
[C] Goals verifiability: --help exit 0 and read-only git-status-clean checks modeled on scripts/gcl-report.sh invocation contract (external file).
[H] Sparsity risk: 'most tasks lack a Gate Evidence Pack today' — inferred projection; grep confirmed only task-182 currently carries the markers, the rising-coverage claim is background inference.
GCL-self-report: E=2 C=4 H=1

Proposal approved. Starting plan draft.

Plan review: APPROVED
premise-ledger:
[E] Goal coverage: all 5 proposal Goals map to Phase A/B items or Acceptance Gate (script+help, marker extraction, per-task+summary, no-digest/exit0, read-only) — readable directly in plan and proposal text.
[E] TDD structure: both phases have ### Tests then ### Implementation in that order — visible in headings.
[E] TDD order: first ### DoD item of each phase is 'bash scripts/validate-plugin.sh' — visible at lines 70 and 126.
[E] Acceptance gate: first ## Acceptance Gate item is 'bash scripts/validate-plugin.sh' — visible at line 152.
[E] DoD executability: every DoD and Acceptance item is a shell command; non-executable criteria are in ## Constraints — readable in file.
[E] Absence checks: T-A0 uses '! test -f'; no 'grep -qv' anywhere — readable in file.
[E] Scope discipline: no Phase implements anything not backed by a Goal — cross-readable plan vs proposal.
[C] File paths: scripts/gcl-report.sh, plugin/skills/loop-backlog/meta-cc-digest.sh, backlog/tasks/, docs/research/gcl-events.jsonl all verified present; digest markers (## Gate Evidence Pack, FILE_ACTIVITY:, SCOPE_DIFF:) confirmed in meta-cc-digest.sh — required reading external repo files.
[H] Phase ordering: Phase A produces parser+skeleton that Phase B extends; no circular deps — inferred from dependency reasoning.
[H] Robustness: DoD commands embed $TMPDIR which may be unset under the loop-backlog worker; fixed by prefixing every $TMPDIR-referencing DoD command and both Tests blocks with TMPDIR="${TMPDIR:-/tmp}" and making each command self-contained — inferred from worker execution-environment background knowledge.
GCL-self-report: E=7 C=1 H=2

claimed: 2026-06-24T10:08:12Z

Phase A ✓ 2026-06-24T10:11:00Z: Parser + per-task diff + report skeleton implemented. Script parses ## Gate Evidence Pack sections, extracts FILE_ACTIVITY and SCOPE_DIFF, computes in-scope = FILE_ACTIVITY minus SCOPE_DIFF, prints per-task table.

Phase B ✓ 2026-06-24T10:11:00Z: Cross-task aggregation + systematic-deviation summary implemented. Counter over out-of-scope files across all tasks, tasks-with-drift count, ranked frequency table, graceful empty/zero-digest handling.

DoD #1: PASS — bash scripts/validate-plugin.sh
DoD #2: PASS — bash scripts/declared-vs-actual-report.sh --help
DoD #3: PASS — --help | grep -q 'declared-vs-actual-report.sh'
DoD #4: PASS — task-900 fixture contains actual count 3
DoD #5: PASS — task-900 fixture contains scope-diff count 1
DoD #6: PASS — task-901 with SCOPE_DIFF: none appears in output
DoD #7: PASS — bash scripts/validate-plugin.sh
DoD #8: PASS — shared.go appears in cross-task aggregation
DoD #9: PASS — occurrence count 2 for shared.go across two tasks
DoD #10: PASS — no-digest appears for tasks without Gate Evidence Pack
DoD #11: PASS — empty directory exits 0 with graceful report
DoD #12: PASS — git status unchanged after run (read-only)
DoD #13: PASS — bash scripts/validate-plugin.sh
DoD #14: PASS — runs against real repo (140 tasks, 0 with digest)
DoD #15: PASS — --help exits 0
DoD #16: PASS — git status unchanged after run (read-only)

## Execution Summary
Result: Done
Commit: f4079d0

Completed: 2026-06-24T10:13:34Z
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 bash scripts/declared-vs-actual-report.sh --help
- [ ] #3 bash scripts/declared-vs-actual-report.sh --help | grep -q 'declared-vs-actual-report.sh'
- [ ] #4 TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_a/backlog/tasks" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: a.go, b.go, c.go\nSCOPE_DIFF: c.go\ndata_source: meta-cc-session\n' > "$TMPDIR/dod_a/backlog/tasks/task-900 - fixture.md" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_a/backlog/tasks" | grep -E 'task-900' | grep -q '3'
- [ ] #5 TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_a/backlog/tasks" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: a.go, b.go, c.go\nSCOPE_DIFF: c.go\ndata_source: meta-cc-session\n' > "$TMPDIR/dod_a/backlog/tasks/task-900 - fixture.md" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_a/backlog/tasks" | grep -E 'task-900' | grep -q '1'
- [ ] #6 TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_a2/backlog/tasks" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: x.go, y.go\nSCOPE_DIFF: none\ndata_source: meta-cc-session\n' > "$TMPDIR/dod_a2/backlog/tasks/task-901 - clean.md" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_a2/backlog/tasks" | grep -q 'task-901'
- [ ] #7 bash scripts/validate-plugin.sh
- [ ] #8 TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_b/backlog/tasks" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: shared.go, one.go\nSCOPE_DIFF: shared.go\n' > "$TMPDIR/dod_b/backlog/tasks/task-910 - one.md" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: shared.go, two.go\nSCOPE_DIFF: shared.go\n' > "$TMPDIR/dod_b/backlog/tasks/task-911 - two.md" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_b/backlog/tasks" | grep -q 'shared.go'
- [ ] #9 TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_b/backlog/tasks" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: shared.go, one.go\nSCOPE_DIFF: shared.go\n' > "$TMPDIR/dod_b/backlog/tasks/task-910 - one.md" && printf '## Gate Evidence Pack\nFILE_ACTIVITY: shared.go, two.go\nSCOPE_DIFF: shared.go\n' > "$TMPDIR/dod_b/backlog/tasks/task-911 - two.md" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_b/backlog/tasks" | grep -q '2'
- [ ] #10 TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_b2/backlog/tasks" && printf '## Implementation Plan\nno pack here\n' > "$TMPDIR/dod_b2/backlog/tasks/task-920 - bare.md" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_b2/backlog/tasks" | grep -q 'no-digest'
- [ ] #11 TMPDIR="${TMPDIR:-/tmp}"; mkdir -p "$TMPDIR/dod_b3/backlog/tasks" && bash scripts/declared-vs-actual-report.sh "$TMPDIR/dod_b3/backlog/tasks"
- [ ] #12 B=$(git status --porcelain); bash scripts/declared-vs-actual-report.sh >/dev/null; A=$(git status --porcelain); test "$B" = "$A"
- [ ] #13 bash scripts/validate-plugin.sh
- [ ] #14 bash scripts/declared-vs-actual-report.sh
- [ ] #15 bash scripts/declared-vs-actual-report.sh --help
- [ ] #16 B=$(git status --porcelain); bash scripts/declared-vs-actual-report.sh >/dev/null; A=$(git status --porcelain); test "$B" = "$A"
<!-- DOD:END -->
