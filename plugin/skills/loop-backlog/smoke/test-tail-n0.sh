#!/usr/bin/env bash
# Smoke test: verify that loop-backlog SKILL.md uses 'tail -f -n 0' (not plain 'tail -f')
# to prevent stale log replay on Monitor restart.
set -euo pipefail

SKILL_FILE="$(dirname "$0")/../SKILL.md"

if [ ! -f "$SKILL_FILE" ]; then
    echo "FAIL: SKILL.md not found at $SKILL_FILE"
    exit 1
fi

# Confirm -n 0 flag is present in the Monitor command
if grep -qP 'tail -f -n 0' "$SKILL_FILE"; then
    echo "PASS: SKILL.md uses 'tail -f -n 0' (no stale replay on restart)"
else
    echo "FAIL: SKILL.md does not use 'tail -f -n 0'"
    exit 1
fi

# Confirm bare 'tail -f' (without -n flag) is absent
if grep -qP 'tail -f [^-]' "$SKILL_FILE"; then
    echo "FAIL: SKILL.md still contains bare 'tail -f' without -n 0 flag"
    grep -nP 'tail -f [^-]' "$SKILL_FILE" || true
    exit 1
else
    echo "PASS: No bare 'tail -f' (without -n flag) found"
fi

echo "All smoke tests passed."
exit 0
