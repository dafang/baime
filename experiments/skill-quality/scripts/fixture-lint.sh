#!/usr/bin/env bash
# fixture-lint.sh — Quality gate: answer must appear in specSection vocabulary
#
# Usage: fixture-lint.sh <fixtures-dir>
#
# For each *.json file with "answerType": "exact":
#   - If the fixture has an explicit "answer_vocab" array, the answer must be in that array
#   - Otherwise, the answer value must appear (case-insensitive) in the "specSection" text
# Exits non-zero if any fixture fails the check.

set -euo pipefail

FIXTURES_DIR="${1:-}"
if [[ -z "$FIXTURES_DIR" ]]; then
  echo "Usage: $0 <fixtures-dir>" >&2
  exit 1
fi

if [[ ! -d "$FIXTURES_DIR" ]]; then
  echo "ERROR: Not a directory: $FIXTURES_DIR" >&2
  exit 1
fi

FAIL=0
CHECKED=0

# Find all JSON files recursively in the directory
while IFS= read -r -d '' fixture_file; do
  # Use Python to parse and validate each fixture
  result=$(python3 - "$fixture_file" <<'PYEOF'
import sys, json

path = sys.argv[1]
with open(path) as f:
    d = json.load(f)

answer_type = d.get("answerType", "")
if answer_type != "exact":
    print("SKIP")
    sys.exit(0)

fixture_id = d.get("id", path)
answer = d.get("answer", "")
answer_str = str(answer) if answer is not None else ""

# Check answer_vocab first (explicit vocabulary list)
vocab = d.get("answer_vocab")
if vocab is not None:
    if not isinstance(vocab, list):
        print(f"FAIL:{fixture_id}:answer_vocab is not an array")
        sys.exit(0)
    vocab_lower = [str(v).lower() for v in vocab]
    if answer_str.lower() in vocab_lower:
        print("PASS")
    else:
        print(f"FAIL:{fixture_id}:answer '{answer_str}' not in answer_vocab {vocab}")
    sys.exit(0)

# Fall back to specSection check
spec = d.get("specSection", "")
if answer_str.lower() in spec.lower():
    print("PASS")
else:
    print(f"FAIL:{fixture_id}:answer '{answer_str}' not found in specSection")
PYEOF
  )

  if [[ "$result" == "SKIP" ]]; then
    continue
  fi

  CHECKED=$((CHECKED + 1))

  if [[ "$result" == "PASS" ]]; then
    : # OK
  elif [[ "$result" == FAIL:* ]]; then
    fixture_info="${result#FAIL:}"
    echo "LINT FAIL: $fixture_info" >&2
    FAIL=$((FAIL + 1))
  else
    echo "ERROR: unexpected lint result '$result' for $fixture_file" >&2
    FAIL=$((FAIL + 1))
  fi
done < <(find "$FIXTURES_DIR" -name "*.json" -print0 | sort -z)

if [[ $FAIL -gt 0 ]]; then
  echo "fixture-lint: $FAIL fixture(s) failed, $CHECKED exact fixture(s) checked." >&2
  exit 1
else
  echo "fixture-lint: all $CHECKED exact fixture(s) passed."
  exit 0
fi
