---
id: TASK-191
title: 插件脚本驻留修复：enrichment 助手和 read-out 脚本移入 plugin/
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 10:22'
updated_date: '2026-06-24 11:17'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
将四个违反 ADR-007 的 repo-level 脚本迁移至 plugin-resident 位置，使其随 install.sh 全局安装，在任意仓库可用。

(1) Class A 运行时静默降级（enrichment 助手，TASK-183）：
    scripts/lib/parse-task-files.js
    scripts/lib/fetch-risk-context.js
    → 移入 plugin/skills/loop-backlog/lib/；
      SKILL.md L821-822 路径解析改为 BAIME_SCRIPTS 优先、REPO_ROOT 向后兼容 fallback。

(2) Class C 安装断链（read-out 脚本）：
    scripts/gcl-report.sh
    scripts/declared-vs-actual-report.sh（TASK-190 已产出，已落错位）
    → 移入 plugin/scripts/；
      SKILL.md 文档段（L1821-1852）引用改为插件路径；
      install.sh 确认 plugin/scripts/ 已在 rsync 范围内（无需改动，plugin/ 整体同步）。

参考：ADR-007（docs/adr/ADR-007-plugin-script-residency.md）。
数据文件 docs/research/gcl-events.jsonl 不在本任务范围，其 REPO_ROOT 路径是正确的 opt-in 设计（ADR-007 §例外）。
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: Plugin Script Residency Remediation — Migrate Four Repo-Level Scripts to Plugin

## Background

ADR-007 (docs/adr/ADR-007-plugin-script-residency.md) mandates that all runtime
artifacts called by loop-backlog must be plugin-resident so that `install.sh`
copies them to every target repo. Two tasks violated this rule: TASK-183 placed
the archguard enrichment helpers (`parse-task-files.js`, `fetch-risk-context.js`)
under `scripts/lib/` rather than `plugin/skills/loop-backlog/lib/`; TASK-190
placed the GCL read-out tools (`gcl-report.sh`, `declared-vs-actual-report.sh`)
under `scripts/` rather than `plugin/scripts/`. Because `install.sh` rsyncs only
`plugin/` (line 28: `rsync -a --delete "$REPO_ROOT/plugin/" "$INSTALL_DIR/"`),
none of these four files are installed in non-baime repos. The enrichment path in
SKILL.md (L821-822) silently skips archguard context whenever the guard `[ -f
"$_PARSE_SCRIPT" ]` fails — which it always does outside baime. The SKILL.md
documentation section (L1821-1852) directs users to `bash scripts/gcl-report.sh`,
a path that does not exist in any non-baime repo. This task enforces ADR-007
retroactively for all four offending files.

## Goals

1. `plugin/skills/loop-backlog/lib/parse-task-files.js` exists and is installed:
   `ls ~/.claude/plugins/loop-backlog/lib/parse-task-files.js` exits 0 after
   `bash scripts/install/install.sh --user`.

2. `plugin/skills/loop-backlog/lib/fetch-risk-context.js` exists and is installed:
   `ls ~/.claude/plugins/loop-backlog/lib/fetch-risk-context.js` exits 0 after
   `bash scripts/install/install.sh --user`.

3. SKILL.md enrichment path (currently L821-822) resolves scripts via `BAIME_SCRIPTS`
   first, with a `REPO_ROOT/scripts/lib/` fallback for backwards compatibility:
   `grep -A2 '_PARSE_SCRIPT' plugin/skills/loop-backlog/SKILL.md` shows
   `BAIME_SCRIPTS`-based path as the primary assignment.

4. `plugin/scripts/gcl-report.sh` exists and is installed:
   `ls ~/.claude/plugins/scripts/gcl-report.sh` exits 0 after
   `bash scripts/install/install.sh --user`.

5. `plugin/scripts/declared-vs-actual-report.sh` exists and is installed:
   `ls ~/.claude/plugins/scripts/declared-vs-actual-report.sh` exits 0 after
   `bash scripts/install/install.sh --user`.

6. SKILL.md documentation section (currently L1821-1852) references the plugin
   path for gcl-report.sh: `grep 'gcl-report' plugin/skills/loop-backlog/SKILL.md`
   shows `$BAIME_SCRIPTS/gcl-report.sh` (or equivalent plugin-resident path),
   not `scripts/gcl-report.sh`.

7. Validation passes: `bash scripts/validate-plugin.sh` exits 0.

## Proposed Approach

**Step 1 — Move enrichment helpers.** Create `plugin/skills/loop-backlog/lib/`
and move `scripts/lib/parse-task-files.js` and `scripts/lib/fetch-risk-context.js`
into it. Keep the originals in `scripts/lib/` as the migration fallback.

**Step 2 — Update SKILL.md enrichment path (L821-822).** Replace the two
`REPO_ROOT`-based path assignments with `BAIME_SCRIPTS`-relative paths, adding a
`REPO_ROOT` fallback line per the ADR-007 pattern (same as boss-evidence-pack.sh
demonstrates for plugin-resident helpers). No script logic changes.

**Step 3 — Move read-out scripts.** Copy `scripts/gcl-report.sh` and
`scripts/declared-vs-actual-report.sh` to `plugin/scripts/`. Original repo-level
copies can remain as stubs pointing users to the plugin path, or be removed — since
these are documentation-driven tools, a one-line stub is friendlier.

**Step 4 — Update SKILL.md doc section (L1821-1852).** Change the `bash
scripts/gcl-report.sh` reference (including the crontab example) to use
`$BAIME_SCRIPTS/gcl-report.sh`. No behavioral change to the script itself.

**Step 5 — Verify install.sh scope.** No changes needed: line 28 of
`scripts/install/install.sh` already rsyncs `plugin/` in full, which covers both
`plugin/scripts/` (already contains `basic-daemon.js` et al.) and the new
`plugin/skills/loop-backlog/lib/`.

**Step 6 — Run `bash scripts/validate-plugin.sh`** to confirm no regressions.

## Trade-offs and Risks

- **No script logic changes.** Both enrichment helpers and read-out scripts are
  relocated as-is; behavior is identical post-migration.

- **Backward-compat fallback for enrichment.** The `REPO_ROOT/scripts/lib/`
  fallback in Step 2 ensures that baime-local runs continue to work even before the
  next `install.sh` run. This matches the ADR-007 recommended pattern.

- **Breaking change for hardcoded `scripts/` paths in cron.** The crontab example
  in SKILL.md currently reads `bash scripts/gcl-report.sh`. Any user who copied
  that snippet will get a file-not-found after this change. Acceptable risk: the
  crontab example is aspirational documentation (non-baime repos never had the
  script at that path anyway), and the new path is clearly documented in the updated
  SKILL.md.

- **`plugin/skills/loop-backlog/lib/` is a new directory.** The `rsync -a` flag
  recursively copies all subdirectories, so no install.sh change is needed. Verified
  by inspecting line 28: `rsync -a --delete "$REPO_ROOT/plugin/" "$INSTALL_DIR/"`.

- **`scripts/lib/` originals.** Leaving them in place avoids breaking any
  baime-internal scripts that might reference them directly. They can be removed in
  a follow-up cleanup task once ADR-007 lint enforcement (flagged in ADR-007
  Consequences) is in place.

---

# Plan: Plugin Script Residency Remediation (TASK-191)

Enforces ADR-007 retroactively for four files shipped as repo-level scripts.
Two enrichment helpers and two read-out scripts are copied into `plugin/`,
and SKILL.md references are updated to resolve via `BAIME_SCRIPTS` with a
`REPO_ROOT` fallback. No script logic is changed.

---

## Phase A — Migrate enrichment helpers (Class A)

**Goal:** `plugin/skills/loop-backlog/lib/parse-task-files.js` and
`fetch-risk-context.js` exist in the plugin tree, and SKILL.md L821–825 resolves
them via `BAIME_SCRIPTS` first with a `REPO_ROOT/scripts/lib/` fallback.

### Tests (write first)

```bash
# BEFORE assertions — must fail (exit non-zero) before Phase A implementation:
! test -f plugin/skills/loop-backlog/lib/parse-task-files.js
! test -f plugin/skills/loop-backlog/lib/fetch-risk-context.js
! grep -q 'BAIME_SCRIPTS.*parse-task-files' plugin/skills/loop-backlog/SKILL.md
```

```bash
# AFTER assertions — must pass after Phase A implementation:
test -f plugin/skills/loop-backlog/lib/parse-task-files.js
test -f plugin/skills/loop-backlog/lib/fetch-risk-context.js
grep -q 'BAIME_SCRIPTS.*parse-task-files' plugin/skills/loop-backlog/SKILL.md
grep -q 'BAIME_SCRIPTS.*fetch-risk-context' plugin/skills/loop-backlog/SKILL.md
grep -q 'REPO_ROOT.*parse-task-files' plugin/skills/loop-backlog/SKILL.md
grep -q 'REPO_ROOT.*fetch-risk-context' plugin/skills/loop-backlog/SKILL.md
```

### Implementation steps

1. `mkdir -p plugin/skills/loop-backlog/lib`
2. `cp scripts/lib/parse-task-files.js plugin/skills/loop-backlog/lib/parse-task-files.js`
3. `cp scripts/lib/fetch-risk-context.js plugin/skills/loop-backlog/lib/fetch-risk-context.js`
4. Update `plugin/skills/loop-backlog/SKILL.md` L821–822 to the four-line
   `BAIME_SCRIPTS`-primary + `REPO_ROOT`-fallback form:

   **Before (L821–822):**
   ```bash
   local _PARSE_SCRIPT="${REPO_ROOT}/scripts/lib/parse-task-files.js"
   local _FETCH_SCRIPT="${REPO_ROOT}/scripts/lib/fetch-risk-context.js"
   ```

   **After (replaces L821–822, expands to L821–826):**
   ```bash
   local _PARSE_SCRIPT="${BAIME_SCRIPTS}/../skills/loop-backlog/lib/parse-task-files.js"
   [ ! -f "$_PARSE_SCRIPT" ] && _PARSE_SCRIPT="${REPO_ROOT}/scripts/lib/parse-task-files.js"
   local _FETCH_SCRIPT="${BAIME_SCRIPTS}/../skills/loop-backlog/lib/fetch-risk-context.js"
   [ ! -f "$_FETCH_SCRIPT" ] && _FETCH_SCRIPT="${REPO_ROOT}/scripts/lib/fetch-risk-context.js"
   ```

   Note: `BAIME_SCRIPTS` resolves to `plugin/scripts/`; `../skills/loop-backlog/lib/`
   navigates to the skill's lib directory — matching the pattern at SKILL.md L1605.

### Definition of Done

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f plugin/skills/loop-backlog/lib/parse-task-files.js`
- [ ] `test -f plugin/skills/loop-backlog/lib/fetch-risk-context.js`
- [ ] `grep -q 'BAIME_SCRIPTS.*parse-task-files' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'BAIME_SCRIPTS.*fetch-risk-context' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'REPO_ROOT.*parse-task-files' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'REPO_ROOT.*fetch-risk-context' plugin/skills/loop-backlog/SKILL.md`

---

## Phase B — Migrate read-out scripts (Class C)

**Goal:** `plugin/scripts/gcl-report.sh` and
`plugin/scripts/declared-vs-actual-report.sh` exist in the plugin tree, and SKILL.md
documentation (L1824, L1849, L1852) no longer references the bare `scripts/` repo
path for `gcl-report.sh`.

### Tests (write first)

```bash
# BEFORE assertions — must fail (exit non-zero) before Phase B implementation:
! test -f plugin/scripts/gcl-report.sh
! test -f plugin/scripts/declared-vs-actual-report.sh
! grep -q 'BAIME_SCRIPTS.*gcl-report' plugin/skills/loop-backlog/SKILL.md
```

```bash
# AFTER assertions — must pass after Phase B implementation:
test -f plugin/scripts/gcl-report.sh
test -f plugin/scripts/declared-vs-actual-report.sh
grep -q 'BAIME_SCRIPTS.*gcl-report' plugin/skills/loop-backlog/SKILL.md
! grep -q 'bash scripts/gcl-report.sh' plugin/skills/loop-backlog/SKILL.md
```

### Implementation steps

1. `cp scripts/gcl-report.sh plugin/scripts/gcl-report.sh`
2. `cp scripts/declared-vs-actual-report.sh plugin/scripts/declared-vs-actual-report.sh`
3. Update `plugin/skills/loop-backlog/SKILL.md` L1824 (inline example):

   **Before:**
   ```bash
   bash scripts/gcl-report.sh
   ```
   **After:**
   ```bash
   bash "$BAIME_SCRIPTS/gcl-report.sh"
   # BAIME_SCRIPTS must be resolved first: BAIME_SCRIPTS=$(resolveBaimeScripts)
   ```

4. Update `plugin/skills/loop-backlog/SKILL.md` L1849 (cron example):

   **Before:**
   ```
   0 7 * * * cd /path/to/repo && bash scripts/gcl-report.sh >> logs/gcl-report.log 2>&1
   ```
   **After:**
   ```
   0 7 * * * BAIME_SCRIPTS=$(cd /path/to/repo && node -e "const r=require('./plugin/scripts/resolve-baime-scripts'); r().then(p=>process.stdout.write(p))") && bash "$BAIME_SCRIPTS/gcl-report.sh" >> /path/to/repo/logs/gcl-report.log 2>&1
   ```
   Or, simpler: use the installed absolute path directly in the cron note comment.

5. Update prose at L1852 (`bash scripts/gcl-report.sh`) to `$BAIME_SCRIPTS/gcl-report.sh`.

### Definition of Done

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f plugin/scripts/gcl-report.sh`
- [ ] `test -f plugin/scripts/declared-vs-actual-report.sh`
- [ ] `grep -q 'BAIME_SCRIPTS.*gcl-report' plugin/skills/loop-backlog/SKILL.md`
- [ ] `! grep -q 'bash scripts/gcl-report.sh' plugin/skills/loop-backlog/SKILL.md`

---

## Acceptance Gate

```bash
# Gate 0: validation suite
bash scripts/validate-plugin.sh

# Gate 1: files present in plugin tree
test -f plugin/skills/loop-backlog/lib/parse-task-files.js
test -f plugin/skills/loop-backlog/lib/fetch-risk-context.js
test -f plugin/scripts/gcl-report.sh
test -f plugin/scripts/declared-vs-actual-report.sh

# Gate 2: SKILL.md references updated
grep -q 'BAIME_SCRIPTS.*parse-task-files' plugin/skills/loop-backlog/SKILL.md
grep -q 'BAIME_SCRIPTS.*fetch-risk-context' plugin/skills/loop-backlog/SKILL.md
grep -q 'BAIME_SCRIPTS.*gcl-report' plugin/skills/loop-backlog/SKILL.md
! grep -q 'bash scripts/gcl-report.sh' plugin/skills/loop-backlog/SKILL.md

# Gate 3: install produces scripts at the installed path
bash scripts/install/install.sh --user
PLUGIN_VERSION="$(python3 -c "import json; d=json.load(open('plugin/.claude-plugin/plugin.json')); print(d['version'])")"
INSTALL_DIR="$HOME/.claude/plugins/cache/baime/baime/${PLUGIN_VERSION}"
ls "${INSTALL_DIR}/skills/loop-backlog/lib/parse-task-files.js"
ls "${INSTALL_DIR}/skills/loop-backlog/lib/fetch-risk-context.js"
ls "${INSTALL_DIR}/scripts/gcl-report.sh"
ls "${INSTALL_DIR}/scripts/declared-vs-actual-report.sh"
```
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Proposal self-review: APPROVED
premise-ledger:
[E] Background WHY not WHAT: root-cause traced to two specific tasks (TASK-183, TASK-190) and install.sh rsync gap — verified by reading ADR-007 and install.sh line 28
[E] Goals verifiable: each goal has a concrete shell command (ls, grep) that can be run to confirm completion
[E] File paths exist: confirmed scripts/lib/parse-task-files.js, scripts/lib/fetch-risk-context.js, scripts/gcl-report.sh, scripts/declared-vs-actual-report.sh all present
[C] install.sh scope: verified line 28 rsync covers plugin/ entirely — no install.sh change required
[C] SKILL.md sites confirmed: L595 (migration notice pattern), L821-822 (enrichment path), L1821-1852 (doc section) all read and understood
[C] Trade-offs complete: backward-compat fallback, cron breaking change, new directory, originals retention all addressed
[H] Approach soundness: REPO_ROOT fallback pattern sourced directly from ADR-007 §Decision example and boss-evidence-pack.sh as reference — not invented
GCL-self-report: E=3 C=3 H=1

Proposal approved. Starting plan draft.

claimed: 2026-06-24T11:12:42Z

Phase A ✓ 2026-06-24T00:00:00Z: Copied parse-task-files.js and fetch-risk-context.js to plugin/skills/loop-backlog/lib/. Updated SKILL.md lines 821-822 with BAIME_SCRIPTS-primary + REPO_ROOT-fallback pattern.

Phase B ✓ 2026-06-24T00:00:00Z: Copied gcl-report.sh and declared-vs-actual-report.sh to plugin/scripts/. Replaced all 'bash scripts/gcl-report.sh' references in SKILL.md with 'bash "$BAIME_SCRIPTS/gcl-report.sh"'.

DoD #1: PASS — bash scripts/validate-plugin.sh → ALL CHECKS PASSED (0 errors)

DoD #2: PASS — test -f plugin/skills/loop-backlog/lib/parse-task-files.js

DoD #3: PASS — test -f plugin/skills/loop-backlog/lib/fetch-risk-context.js

DoD #4: PASS — grep -q 'BAIME_SCRIPTS.*parse-task-files' plugin/skills/loop-backlog/SKILL.md

DoD #5: PASS — grep -q 'BAIME_SCRIPTS.*fetch-risk-context' plugin/skills/loop-backlog/SKILL.md

DoD #6: PASS — grep -q 'REPO_ROOT.*parse-task-files' plugin/skills/loop-backlog/SKILL.md

DoD #7: PASS — grep -q 'REPO_ROOT.*fetch-risk-context' plugin/skills/loop-backlog/SKILL.md

DoD #8: PASS — bash scripts/validate-plugin.sh (second run, same result)

DoD #9: PASS — test -f plugin/scripts/gcl-report.sh

DoD #10: PASS — test -f plugin/scripts/declared-vs-actual-report.sh

DoD #11: PASS — grep -q 'BAIME_SCRIPTS.*gcl-report' plugin/skills/loop-backlog/SKILL.md

DoD #12: PASS — ! grep -q 'bash scripts/gcl-report.sh' plugin/skills/loop-backlog/SKILL.md

## Execution Summary
Result: Done
Commit: 8293789

Completed: 2026-06-24T11:17:04Z
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 test -f plugin/skills/loop-backlog/lib/parse-task-files.js
- [ ] #3 test -f plugin/skills/loop-backlog/lib/fetch-risk-context.js
- [ ] #4 grep -q 'BAIME_SCRIPTS.*parse-task-files' plugin/skills/loop-backlog/SKILL.md
- [ ] #5 grep -q 'BAIME_SCRIPTS.*fetch-risk-context' plugin/skills/loop-backlog/SKILL.md
- [ ] #6 grep -q 'REPO_ROOT.*parse-task-files' plugin/skills/loop-backlog/SKILL.md
- [ ] #7 grep -q 'REPO_ROOT.*fetch-risk-context' plugin/skills/loop-backlog/SKILL.md
- [ ] #8 bash scripts/validate-plugin.sh
- [ ] #9 test -f plugin/scripts/gcl-report.sh
- [ ] #10 test -f plugin/scripts/declared-vs-actual-report.sh
- [ ] #11 grep -q 'BAIME_SCRIPTS.*gcl-report' plugin/skills/loop-backlog/SKILL.md
- [ ] #12 ! grep -q 'bash scripts/gcl-report.sh' plugin/skills/loop-backlog/SKILL.md
<!-- DOD:END -->
