#!/usr/bin/env bash
# Smoke test: verify Monitor lifecycle invariants in loop-backlog SKILL.md.
# Block-scoped checks — verifies the right logic is in the right section,
# not just anywhere in the file.
set -euo pipefail

SKILL_FILE="$(dirname "$0")/../SKILL.md"
PASS=0
FAIL=0

check() {
  local label="$1" result="$2"
  if [ "$result" = "0" ]; then
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
echo "$stopStaleMonBlock" | grep -q "TaskStop"
check "stopStaleMon impl calls TaskStop (harness-level stop)" $?

echo "$stopStaleMonBlock" | grep -q "monitor-task-id"
check "stopStaleMon impl references .monitor-task-id file" $?

echo "$stopStaleMonBlock" | grep -q "MONITOR_TASK_ID_FILE\|STALE_MONITOR_ID"
check "stopStaleMon impl has TaskStop ID variables" $?

# ── Bug 2: daemonBootstrap must write baseline checkpoint before Monitor ────
echo "$daemonBootstrapBlock" | grep -q "baseline checkpoint"
check "daemonBootstrap writes baseline checkpoint before Monitor" $?

echo "$daemonBootstrapBlock" | grep -qP "wc -c.*DAEMON_LOG|CHECKPOINT_FILE.*wc -c"
check "daemonBootstrap checkpoint write uses wc -c of DAEMON_LOG" $?

# ── Bug 3: heartbeat filtering present ──────────────────────────────────────
grep -q "heartbeat, skipping\|heartbeat.*skipping" "$SKILL_FILE"
check "workerLoop contains heartbeat skipping logic" $?

# ── Validate-plugin still passes ────────────────────────────────────────────
REPO_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
bash "$REPO_ROOT/scripts/validate-plugin.sh" > /dev/null 2>&1
check "validate-plugin.sh passes" $?

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
