#!/usr/bin/env bash
# TDD test: loop-meta/SKILL.md must reference epic-daemon.js and epic-ready:
set -euo pipefail
SKILL="plugin/skills/loop-meta/SKILL.md"
FAIL=0

# Test 1: must reference epic-daemon.js
if ! grep -q 'epic-daemon' "$SKILL"; then
  echo "FAIL Test 1: no reference to epic-daemon in $SKILL"
  FAIL=1
else
  echo "PASS Test 1: epic-daemon referenced"
fi

# Test 2: must reference epic-ready:
if ! grep -q 'epic-ready' "$SKILL"; then
  echo "FAIL Test 2: no reference to epic-ready in $SKILL"
  FAIL=1
else
  echo "PASS Test 2: epic-ready referenced"
fi

# Test 3: must reference epicDAG or epic state machine columns
if ! grep -qE 'epicDAG|Epic: Proposal|Epic: Plan|Epic: Decomposing|Epic: Awaiting|Epic: Evaluating|Epic: Done' "$SKILL"; then
  echo "FAIL Test 3: no epicDAG or Epic:* column references in $SKILL"
  FAIL=1
else
  echo "PASS Test 3: epicDAG/Epic:* columns referenced"
fi

# Test 4: must reference three-way reconcile or reconcile
if ! grep -qiE 'reconcil|three.?way' "$SKILL"; then
  echo "FAIL Test 4: no reconcile logic referenced in $SKILL"
  FAIL=1
else
  echo "PASS Test 4: reconcile logic referenced"
fi

# Test 5: must reference evaluateProcessor or evaluate
if ! grep -qiE 'evaluateProcessor|evaluate' "$SKILL"; then
  echo "FAIL Test 5: no evaluateProcessor referenced in $SKILL"
  FAIL=1
else
  echo "PASS Test 5: evaluateProcessor referenced"
fi

# Test 6: must reference diverging condition (reconcileRunCount >= 3)
if ! grep -qiE 'diverging|reconcileRunCount|runCount.*3|3.*run' "$SKILL"; then
  echo "FAIL Test 6: no diverging condition (reconcileRunCount >= 3) referenced"
  FAIL=1
else
  echo "PASS Test 6: diverging condition referenced"
fi

# Test 7: must reference Epic: Needs Human (escalation target)
if ! grep -q 'Epic: Needs Human' "$SKILL"; then
  echo "FAIL Test 7: no escalation target 'Epic: Needs Human' referenced"
  FAIL=1
else
  echo "PASS Test 7: Epic: Needs Human escalation referenced"
fi

# Test 8: must reference cap:* idempotency markers
if ! grep -q 'cap:' "$SKILL"; then
  echo "FAIL Test 8: no cap:* marker references in $SKILL"
  FAIL=1
else
  echo "PASS Test 8: cap:* markers referenced"
fi

# Test 9: must reference parent_task_id (snake_case)
if ! grep -q 'parent_task_id' "$SKILL"; then
  echo "FAIL Test 9: no parent_task_id reference in $SKILL"
  FAIL=1
else
  echo "PASS Test 9: parent_task_id referenced"
fi

# Test 10: must NOT reference meta-ready (old channel) as primary event
if grep -q 'meta-ready' "$SKILL" && ! grep -q 'epic-ready' "$SKILL"; then
  echo "FAIL Test 10: still using meta-ready without epic-ready"
  FAIL=1
else
  echo "PASS Test 10: meta-ready not used as primary (or epic-ready present alongside it)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "TESTS FAILED"
  exit 1
fi
