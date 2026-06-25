#!/usr/bin/env bash
# Smoke test: verify Monitor lifecycle invariants in loop-backlog SKILL.md.
# Block-scoped checks — verifies the right logic is in the right section,
# not just anywhere in the file.
set -uo pipefail

SKILL_FILE="$(dirname "$0")/../SKILL.md"
PASS=0
FAIL=0

check() {
  local label="$1"
  if eval "$2" >/dev/null 2>&1; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

# Extract impl blocks by section header
stopStaleMonBlock=$(awk '/^### stopStaleMon/,/^### [^s]/' "$SKILL_FILE")
daemonBootstrapBlock=$(awk '/^### daemonBootstrap/,/^### [^d]/' "$SKILL_FILE")

# ── Bug 1: stopStaleMon must call TaskStop and track .monitor-task-id ──────
check "stopStaleMon impl calls TaskStop (harness-level stop)" \
  "echo \"\$stopStaleMonBlock\" | grep -q 'TaskStop'"

check "stopStaleMon impl references .monitor-task-id file" \
  "echo \"\$stopStaleMonBlock\" | grep -q 'monitor-task-id'"

check "stopStaleMon impl has TaskStop ID variables" \
  "echo \"\$stopStaleMonBlock\" | grep -q 'MONITOR_TASK_ID_FILE\|STALE_MONITOR_ID'"

# ── Bug 2: daemonBootstrap must write baseline checkpoint before Monitor ────
check "daemonBootstrap writes baseline checkpoint before Monitor" \
  "echo \"\$daemonBootstrapBlock\" | grep -q 'baseline checkpoint'"

check "daemonBootstrap checkpoint write uses wc -c of DAEMON_LOG" \
  "echo \"\$daemonBootstrapBlock\" | grep -qP 'wc -c.*DAEMON_LOG|CHECKPOINT_FILE.*wc -c'"

# ── Bug 3: heartbeat filtered at Monitor command level (not in dispatch) ────
check "Monitor command grep excludes heartbeat (actionable events only)" \
  "grep -q 'grep.*--line-buffered.*basic-ready.*epic-ready.*child-done' \"$SKILL_FILE\""

check "heartbeat not in Monitor grep filter pattern" \
  "! grep -qP 'grep.*--line-buffered.*heartbeat' \"$SKILL_FILE\""

# ── Validate-plugin still passes ────────────────────────────────────────────
REPO_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
check "validate-plugin.sh passes" \
  "bash \"$REPO_ROOT/scripts/validate-plugin.sh\""

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
