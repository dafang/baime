#!/usr/bin/env bash
# Unit tests for skill-lint.sh --manifest subcommand
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/skill-lint.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

PASS=0; FAIL=0

assert_exits_0() {
  local desc="$1"; shift
  if bash "$LINT" "$@" >/dev/null 2>&1; then
    echo "  PASS: $desc"; PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (expected exit 0)"; FAIL=$((FAIL+1))
  fi
}

assert_exits_nonzero() {
  local desc="$1"; shift
  if ! bash "$LINT" "$@" >/dev/null 2>&1; then
    echo "  PASS: $desc"; PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (expected non-zero exit)"; FAIL=$((FAIL+1))
  fi
}

echo "=== skill-lint.sh --manifest tests ==="
assert_exits_0        "valid manifest exits 0"              --manifest "$FIXTURES/manifest-valid.json"
assert_exits_nonzero  "bad field=description rejected"      --manifest "$FIXTURES/manifest-bad-field-description.json"
assert_exits_nonzero  "bad missing phase rejected"          --manifest "$FIXTURES/manifest-bad-missing-phase.json"
assert_exits_nonzero  "bad entry point rejected"            --manifest "$FIXTURES/manifest-bad-entry-point.json"
assert_exits_nonzero  "bad skip_draft mismatch rejected"    --manifest "$FIXTURES/manifest-bad-skip-draft-mismatch.json"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
