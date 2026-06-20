#!/usr/bin/env bash
# test-loop-meta-idempotent.sh — unit tests for loop-meta idempotentReconcile logic.
#
# Uses a dry-run fixture approach: no live backlog MCP calls.
# Simulates the desired ⊖ actual diff logic with bash functions and a temp dir.
#
# Asserts:
#   1. First reconcile creates expected gap sub-tasks.
#   2. Second reconcile on same input creates zero new sub-tasks (idempotent).
#   3. Partial gap (some sub-tasks already exist) creates only missing ones.
#
# Exits 0 on all assertions pass, 1 on any failure.

set -euo pipefail

PASS=0
FAIL=0

assert() {
  local desc="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc"
    echo "      expected: $expected"
    echo "      got:      $actual"
    FAIL=$((FAIL + 1))
  fi
}

# ── Fixture state (in-memory, file-backed) ────────────────────────────────────
TMPDIR_BASE="$(mktemp -d)"
TASKS_FILE="${TMPDIR_BASE}/tasks.tsv"  # tab-separated: TASK-ID \t TITLE \t PARENT
touch "$TASKS_FILE"
NEXT_ID=100

cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

# Create a mock task; echoes new TASK-ID
mock_create_task() {
  local TITLE="$1" PARENT="${2:-}"
  NEXT_ID=$((NEXT_ID + 1))
  local TID="TASK-${NEXT_ID}"
  printf '%s\t%s\t%s\n' "$TID" "$TITLE" "$PARENT" >> "$TASKS_FILE"
  echo "$TID"
}

# List child task titles for a given parent ID
mock_list_children_titles() {
  local PARENT="$1"
  awk -F'\t' -v p="$PARENT" '$3 == p { print $2 }' "$TASKS_FILE"
}

# Count child tasks for a given parent ID
mock_count_children() {
  local PARENT="$1"
  awk -F'\t' -v p="$PARENT" '$3 == p { count++ } END { print count+0 }' "$TASKS_FILE"
}

# idempotentReconcile dry-run: takes META_ID and a desired titles list (one per line)
# Creates sub-tasks for titles not already present as children of META_ID.
# Returns number of tasks created.
idempotentReconcile() {
  local META_ID="$1"
  local DESIRED_TITLES="$2"
  local ACTUAL
  ACTUAL="$(mock_list_children_titles "$META_ID")"
  local CREATED=0

  while IFS= read -r TITLE; do
    [ -z "$TITLE" ] && continue
    if ! echo "$ACTUAL" | grep -qxF "$TITLE"; then
      mock_create_task "$TITLE" "$META_ID" > /dev/null
      CREATED=$((CREATED + 1))
    fi
  done <<< "$DESIRED_TITLES"

  echo "$CREATED"
}

# ── Setup ─────────────────────────────────────────────────────────────────────
META_ID="TASK-1"
DESIRED=$(printf '%s\n' "Sub-task A" "Sub-task B" "Sub-task C")

# ── Test suite ────────────────────────────────────────────────────────────────
echo "First reconcile:"
CREATED1=$(idempotentReconcile "$META_ID" "$DESIRED")
assert "creates 3 sub-tasks on first call" "$CREATED1" "3"
assert "3 children exist after first call" "$(mock_count_children "$META_ID")" "3"

echo "Second reconcile (same desired, same parent — idempotent):"
CREATED2=$(idempotentReconcile "$META_ID" "$DESIRED")
assert "creates 0 sub-tasks on second call" "$CREATED2" "0"
assert "still 3 children (no duplicates)" "$(mock_count_children "$META_ID")" "3"

echo "Third reconcile (same again — stable):"
CREATED3=$(idempotentReconcile "$META_ID" "$DESIRED")
assert "creates 0 sub-tasks on third call" "$CREATED3" "0"
assert "still 3 children after third call" "$(mock_count_children "$META_ID")" "3"

echo "Partial gap (one new desired added later):"
DESIRED_EXTENDED=$(printf '%s\n' "Sub-task A" "Sub-task B" "Sub-task C" "Sub-task D")
CREATED4=$(idempotentReconcile "$META_ID" "$DESIRED_EXTENDED")
assert "creates 1 new sub-task for gap" "$CREATED4" "1"
assert "4 children after extended desired" "$(mock_count_children "$META_ID")" "4"

echo "Partial gap reconcile again (idempotent):"
CREATED5=$(idempotentReconcile "$META_ID" "$DESIRED_EXTENDED")
assert "creates 0 sub-tasks (gap already filled)" "$CREATED5" "0"
assert "still 4 children" "$(mock_count_children "$META_ID")" "4"

echo "Empty desired list:"
META_ID2="TASK-2"
CREATED6=$(idempotentReconcile "$META_ID2" "")
assert "empty desired → 0 sub-tasks created" "$CREATED6" "0"
assert "0 children for empty desired" "$(mock_count_children "$META_ID2")" "0"

echo "Different parent isolation:"
META_ID3="TASK-3"
DESIRED3=$(printf '%s\n' "Sub-task A" "Sub-task B")
CREATED7=$(idempotentReconcile "$META_ID3" "$DESIRED3")
assert "TASK-3 creates its own 2 children" "$CREATED7" "2"
assert "TASK-1 children unchanged at 4" "$(mock_count_children "$META_ID")" "4"
assert "TASK-3 has 2 children" "$(mock_count_children "$META_ID3")" "2"

echo ""
echo "${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
