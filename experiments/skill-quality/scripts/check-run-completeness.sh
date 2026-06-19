#!/usr/bin/env bash
# check-run-completeness.sh — Phase 4 run completeness check
#
# Usage:
#   check-run-completeness.sh <runs-dir>
#
# For each <runs-dir>/*/result.json:
#   - responses array is non-empty
#   - fixture count >= 1
#   - within an experiment, all fixtures have consistent responses length (= k)
#
# Exits non-zero if any check fails.
# If runs-dir does not exist or has no result.json files, exits 0 with a notice.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: check-run-completeness.sh <runs-dir>"
  exit 1
fi

RUNS_DIR="$1"

if [ ! -d "$RUNS_DIR" ]; then
  echo "NOTICE: Runs directory does not exist: $RUNS_DIR"
  echo "PASS: No runs to validate (vacuously complete)."
  exit 0
fi

# Find all result.json files (up to 3 levels deep to support skill/fixture/result.json)
mapfile -t RESULT_FILES < <(find "$RUNS_DIR" -name "result.json" -type f | sort)

TOTAL=${#RESULT_FILES[@]}
if [ "$TOTAL" -eq 0 ]; then
  echo "NOTICE: No result.json files found under: $RUNS_DIR"
  echo "PASS: No runs to validate (vacuously complete)."
  exit 0
fi

echo "Found $TOTAL result.json file(s) under $RUNS_DIR"

FAILURES=0
declare -A SKILL_K_LENGTHS  # track k per skill for consistency check

for result_file in "${RESULT_FILES[@]}"; do
  # Use python3 to parse JSON
  CHECK_OUTPUT=$(python3 - "$result_file" <<'PYEOF'
import json, sys

path = sys.argv[1]
try:
    d = json.load(open(path))
except Exception as e:
    print(f"ERROR: Cannot parse JSON in {path}: {e}")
    sys.exit(1)

responses = d.get('responses', None)
skill = d.get('skill', 'unknown')
fixture_id = d.get('fixtureId', path)

errors = []

if responses is None:
    errors.append(f"Missing 'responses' array in {path}")
elif not isinstance(responses, list):
    errors.append(f"'responses' is not an array in {path}")
elif len(responses) == 0:
    errors.append(f"Empty 'responses' array in {path} ({skill}/{fixture_id})")

if errors:
    for e in errors:
        print(f"FAIL: {e}")
    sys.exit(1)

k = len(responses)
print(f"OK: {path}  skill={skill} fixtureId={fixture_id} k={k}")
print(f"META: skill={skill} k={k}")
PYEOF
  )
  CHECK_EXIT=$?

  echo "$CHECK_OUTPUT" | grep -v '^META:' || true

  if [ $CHECK_EXIT -ne 0 ]; then
    FAILURES=$((FAILURES + 1))
    continue
  fi

  # Extract skill and k for consistency check
  META_LINE=$(echo "$CHECK_OUTPUT" | grep '^META:' || true)
  if [ -n "$META_LINE" ]; then
    SKILL=$(echo "$META_LINE" | sed 's/META: skill=\([^ ]*\) k=.*/\1/')
    K_VAL=$(echo "$META_LINE" | sed 's/META: skill=[^ ]* k=\(.*\)/\1/')

    if [ -n "${SKILL_K_LENGTHS[$SKILL]+_}" ]; then
      PREV_K="${SKILL_K_LENGTHS[$SKILL]}"
      if [ "$PREV_K" != "$K_VAL" ]; then
        echo "FAIL: Inconsistent k within skill '$SKILL': previous=$PREV_K, current=$K_VAL (in $result_file)"
        FAILURES=$((FAILURES + 1))
      fi
    else
      SKILL_K_LENGTHS[$SKILL]="$K_VAL"
    fi
  fi
done

# Fixture count check (must be >= 1 per skill)
for skill in "${!SKILL_K_LENGTHS[@]}"; do
  FIXTURE_COUNT=$(find "$RUNS_DIR" -path "*/$skill/*/result.json" -type f 2>/dev/null | wc -l || echo 0)
  if [ "$FIXTURE_COUNT" -lt 1 ]; then
    echo "FAIL: Skill '$skill' has fewer than 1 fixture result"
    FAILURES=$((FAILURES + 1))
  else
    echo "OK: skill=$skill fixture_count=$FIXTURE_COUNT k=${SKILL_K_LENGTHS[$skill]}"
  fi
done

echo ""
echo "Checked $TOTAL result.json file(s)."

if [ $FAILURES -gt 0 ]; then
  echo "FAIL: $FAILURES check(s) failed."
  exit 1
fi

echo "PASS: All run completeness checks passed."
