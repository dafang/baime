#!/usr/bin/env bash
# test-fixture-lint.sh — Regression test for fixture-lint.sh
#
# Tests:
#   1. A bad fixture (answer not in specSection) causes fixture-lint.sh to exit non-zero
#   2. A good fixture (answer appears in specSection) causes fixture-lint.sh to exit zero
#   3. The actual exp-h fixtures all pass lint

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT_SH="$SCRIPT_DIR/fixture-lint.sh"

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

PASS=0
FAIL=0

check_pass() {
  local label="$1"
  local dir="$2"
  if bash "$LINT_SH" "$dir" > /dev/null 2>&1; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (expected exit 0, got non-zero)" >&2
    FAIL=$((FAIL + 1))
  fi
}

check_fail() {
  local label="$1"
  local dir="$2"
  if bash "$LINT_SH" "$dir" > /dev/null 2>&1; then
    echo "FAIL: $label (expected exit non-zero, got exit 0)" >&2
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $label (correctly rejected)"
    PASS=$((PASS + 1))
  fi
}

echo "=== fixture-lint regression tests ==="
echo ""

# ---- Test 1: Bad fixture — answer NOT in specSection ----
BAD_DIR="$TMPDIR_WORK/bad"
mkdir -p "$BAD_DIR"
cat > "$BAD_DIR/bad-fixture.json" <<'JSON'
{
  "id": "bad-fixture-01",
  "skill": "test-skill",
  "taskClass": "A",
  "taskType": "binary-gate",
  "decisionPoint": "testGate",
  "specSection": "testGate :: () → Result\ntestGate() =\n  | condition → ALPHA\n  | otherwise  → BETA",
  "answer": "GAMMA",
  "answerType": "exact",
  "fixtureClass": "CLEAR",
  "ground_truth_rationale": "Bad fixture: answer GAMMA does not appear in specSection."
}
JSON

check_fail "Bad fixture (answer not in specSection) is rejected" "$BAD_DIR"

# ---- Test 2: Good fixture — answer appears in specSection ----
GOOD_DIR="$TMPDIR_WORK/good"
mkdir -p "$GOOD_DIR"
cat > "$GOOD_DIR/good-fixture.json" <<'JSON'
{
  "id": "good-fixture-01",
  "skill": "test-skill",
  "taskClass": "A",
  "taskType": "binary-gate",
  "decisionPoint": "testGate",
  "specSection": "testGate :: () → Result\ntestGate() =\n  | condition → ALPHA\n  | otherwise  → BETA",
  "answer": "ALPHA",
  "answerType": "exact",
  "fixtureClass": "CLEAR",
  "ground_truth_rationale": "Good fixture: answer ALPHA appears in specSection."
}
JSON

check_pass "Good fixture (answer in specSection) passes lint" "$GOOD_DIR"

# ---- Test 3: answer_vocab — answer in vocab but not in spec ----
VOCAB_DIR="$TMPDIR_WORK/vocab"
mkdir -p "$VOCAB_DIR"
cat > "$VOCAB_DIR/vocab-fixture.json" <<'JSON'
{
  "id": "vocab-fixture-01",
  "skill": "test-skill",
  "taskClass": "A",
  "taskType": "binary-gate",
  "decisionPoint": "testGate",
  "specSection": "testGate :: () → Result\ntestGate() = see answer_vocab below",
  "answer_vocab": ["YES", "NO"],
  "answer": "YES",
  "answerType": "exact",
  "fixtureClass": "CLEAR",
  "ground_truth_rationale": "Fixture uses answer_vocab; answer YES is in vocab."
}
JSON

check_pass "answer_vocab fixture (answer in vocab) passes lint" "$VOCAB_DIR"

# ---- Test 4: answer_vocab — answer NOT in vocab ----
BAD_VOCAB_DIR="$TMPDIR_WORK/bad-vocab"
mkdir -p "$BAD_VOCAB_DIR"
cat > "$BAD_VOCAB_DIR/bad-vocab-fixture.json" <<'JSON'
{
  "id": "bad-vocab-fixture-01",
  "skill": "test-skill",
  "taskClass": "A",
  "taskType": "binary-gate",
  "decisionPoint": "testGate",
  "specSection": "testGate :: () → Result\ntestGate() = see answer_vocab below",
  "answer_vocab": ["YES", "NO"],
  "answer": "MAYBE",
  "answerType": "exact",
  "fixtureClass": "CLEAR",
  "ground_truth_rationale": "Bad fixture: answer MAYBE is not in answer_vocab."
}
JSON

check_fail "answer_vocab fixture (answer not in vocab) is rejected" "$BAD_VOCAB_DIR"

# ---- Test 5: non-exact answerType is skipped ----
SET_DIR="$TMPDIR_WORK/set"
mkdir -p "$SET_DIR"
cat > "$SET_DIR/set-fixture.json" <<'JSON'
{
  "id": "set-fixture-01",
  "skill": "test-skill",
  "taskClass": "B",
  "taskType": "set-check",
  "decisionPoint": "getMissing",
  "specSection": "getMissing :: () → [Item]\nRequired: Proposal, Plan, Backlog",
  "answer": ["Proposal", "Backlog"],
  "answerType": "set",
  "fixtureClass": "CLEAR",
  "ground_truth_rationale": "Set fixture: answerType is set, skipped by lint."
}
JSON

check_pass "Set fixture (non-exact answerType) is skipped (passes lint)" "$SET_DIR"

# ---- Test 6: Real exp-h fixtures ----
EXP_H_DIR="$SCRIPT_DIR/../fixtures/exp-h"
if [[ -d "$EXP_H_DIR" ]]; then
  check_pass "Real exp-h fixtures pass lint (regression baseline)" "$EXP_H_DIR"
else
  echo "SKIP: exp-h fixture dir not found at $EXP_H_DIR"
fi

echo ""
echo "--- Results: $PASS passed, $FAIL failed ---"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
echo "test-fixture-lint: ALL PASSED"
