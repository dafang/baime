#!/usr/bin/env bash
# check-provenance.sh — Phase 2 provenance check
#
# Usage:
#   check-provenance.sh              # scan all artifacts/analysis/*-results.json
#   check-provenance.sh <file.json>  # check single file; also enforces "estimated" rules
#
# Valid data_source values: measured | prior-data | estimated
#
# Rules:
#   - Every file must have a top-level "data_source" field
#   - data_source must be one of: measured, prior-data, estimated
#   - If data_source == "estimated", the file must NOT have top-level "hypothesis" or "verdict" fields

set -euo pipefail

VALID_SOURCES=("measured" "prior-data" "estimated")

check_file() {
  local file="$1"
  local strict_estimated="${2:-false}"

  if [ ! -f "$file" ]; then
    echo "ERROR: File not found: $file"
    return 1
  fi

  # Extract data_source using python3 (always available, no external deps)
  local ds
  ds=$(python3 -c "
import json, sys
try:
    d = json.load(open('$file'))
    print(d.get('data_source', '__MISSING__'))
except Exception as e:
    print('__ERROR__: ' + str(e), file=sys.stderr)
    sys.exit(1)
")

  if [ "$ds" = "__MISSING__" ]; then
    echo "FAIL: Missing 'data_source' field in $file"
    return 1
  fi

  # Validate value
  local valid=false
  for v in "${VALID_SOURCES[@]}"; do
    if [ "$ds" = "$v" ]; then
      valid=true
      break
    fi
  done

  if [ "$valid" = false ]; then
    echo "FAIL: Invalid data_source='$ds' in $file (must be: measured | prior-data | estimated)"
    return 1
  fi

  echo "OK: $file  data_source=$ds"

  # If single-file mode: enforce estimated rule
  if [ "$strict_estimated" = "true" ] && [ "$ds" = "estimated" ]; then
    local has_hypothesis has_verdict
    has_hypothesis=$(python3 -c "
import json, sys
d = json.load(open('$file'))
print('yes' if 'hypothesis' in d else 'no')
")
    has_verdict=$(python3 -c "
import json, sys
d = json.load(open('$file'))
print('yes' if 'verdict' in d else 'no')
")

    if [ "$has_hypothesis" = "yes" ]; then
      echo "FAIL: data_source=estimated but file has top-level 'hypothesis' field: $file"
      return 1
    fi
    if [ "$has_verdict" = "yes" ]; then
      echo "FAIL: data_source=estimated but file has top-level 'verdict' field: $file"
      return 1
    fi
    echo "OK (estimated): no forbidden hypothesis/verdict fields in $file"
  fi

  return 0
}

FAILURES=0

if [ $# -eq 1 ]; then
  # Single file mode
  FILE="$1"
  check_file "$FILE" "true" || FAILURES=$((FAILURES + 1))
else
  # Scan all *-results.json in artifacts/analysis/
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ANALYSIS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/artifacts/analysis"

  if [ ! -d "$ANALYSIS_DIR" ]; then
    echo "ERROR: Analysis directory not found: $ANALYSIS_DIR"
    exit 1
  fi

  FOUND=0
  for f in "$ANALYSIS_DIR"/*-results.json; do
    [ -f "$f" ] || continue
    FOUND=$((FOUND + 1))
    check_file "$f" "false" || FAILURES=$((FAILURES + 1))
  done

  if [ $FOUND -eq 0 ]; then
    echo "ERROR: No *-results.json files found in $ANALYSIS_DIR"
    exit 1
  fi

  echo ""
  echo "Checked $FOUND file(s)."
fi

if [ $FAILURES -gt 0 ]; then
  echo "FAIL: $FAILURES file(s) failed provenance check."
  exit 1
fi

echo "PASS: All files passed provenance check."
