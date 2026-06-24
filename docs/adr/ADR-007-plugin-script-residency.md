---
adr: "007"
title: "Plugin Script Residency: All Runtime Artifacts Must Be Plugin-Resident"
status: Accepted
date: 2026-06-24
applies-to: ["plugin/skills/loop-backlog/SKILL.md", "plugin/skills/loop-backlog/**/*.sh", "plugin/scripts/**"]
enforcement: static
stage: [check]
lint: |
  violations=0
  for f in plugin/skills/*/SKILL.md; do
    while IFS= read -r line; do
      if echo "$line" | grep -qE '\$\{?REPO_ROOT\}?/scripts/' && ! echo "$line" | grep -q 'BAIME_SCRIPTS'; then
        echo "ADR-007 violation in $f: $line"
        violations=$((violations+1))
      fi
    done < "$f"
  done
  test "$violations" = "0"
---

## Context

The loop-backlog skill references two categories of executable scripts at runtime:

1. **Plugin-resident scripts** — live under `plugin/` (e.g. `plugin/scripts/basic-daemon.js`, `plugin/skills/loop-backlog/boss-evidence-pack.sh`). Installed via `rsync plugin/` in `install.sh`, resolved via `resolveBaimeScripts()` → `BAIME_SCRIPTS`.

2. **Repo-level scripts** — live under `scripts/` in the baime repo. NOT copied by `install.sh`. Only accessible when the target repo is baime itself.

The TASK-183 enrichment helpers (`scripts/lib/parse-task-files.js`, `scripts/lib/fetch-risk-context.js`) were shipped as repo-level scripts, causing silent feature degradation in every non-baime repo: the `[ -f ]` guard in the skill evaluates false and the archguard enrichment is silently skipped with no user-visible indication.

A separate category, **per-repo data files** (e.g. `docs/research/gcl-events.jsonl`), intentionally lives in the target repo as opt-in state. This is correct design and is NOT subject to this ADR.

## Decision

**All executable artifacts that the skill calls at runtime MUST be plugin-resident.**

Concretely:

1. Runtime scripts are placed under `plugin/skills/<skill-name>/` or `plugin/scripts/` — never under the repo-level `scripts/`.

2. Path resolution in SKILL.md and `.sh` helpers always uses `BAIME_SCRIPTS` (resolved by `resolveBaimeScripts()`), with a REPO_ROOT fallback only for backwards compatibility during migration:
   ```bash
   SCRIPT="${BAIME_SCRIPTS}/../../skills/loop-backlog/helper.sh"
   [ ! -f "$SCRIPT" ] && SCRIPT="${REPO_ROOT}/scripts/lib/helper.sh"  # migration fallback
   ```

3. Human-invoked read-out tools (e.g. `gcl-report.sh`, `declared-vs-actual-report.sh`) are placed under `plugin/scripts/` so they are installed and accessible from any repo. SKILL.md documentation references them as `$BAIME_SCRIPTS/gcl-report.sh` (or via a slash command), not as `scripts/gcl-report.sh`.

4. **Per-repo data files are the explicit exception.** `docs/research/gcl-events.jsonl` and `docs/research/gcl-alert-config.json` live in the target repo as opt-in GCL observation state. A `[ -f "$JSONL" ]` guard is the correct mechanism: its absence means "this repo has not opted into GCL logging", not an error. The seed file is created once by the user (`mkdir -p docs/research && echo '{}' > docs/research/gcl-events.jsonl` is sufficient to opt in).

## Consequences

- New runtime helpers shipped as part of loop-backlog (or any other skill) must be placed under `plugin/skills/<skill>/` or `plugin/scripts/` before merge.
- The pre-commit lint in `scripts/validate-plugin.sh` should be extended to reject SKILL.md references to `${REPO_ROOT}/scripts/` that are not preceded by a `BAIME_SCRIPTS`-based path resolution attempt (see TASK in backlog).
- Existing violations (TASK-183 enrichment helpers, gcl-report.sh, declared-vs-actual-report.sh) are tracked as a single remediation task.

## Alternatives Considered

- **Copy scripts at runtime into target repos** — rejected by the project owner: runtime copying is invisible, hard to audit, and creates version skew between repos.
- **Require all target repos to be git submodules of baime** — too invasive; defeats the purpose of a portable plugin.
- **Accept silent degradation as documented behavior** — rejected because silent degradation of a feature (enrichment) that users reasonably expect to work is worse than a clear "not installed" error.
