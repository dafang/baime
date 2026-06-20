#!/usr/bin/env bash
# check-roi-gate.test.sh — TDD spec for check-roi-gate.sh exit semantics.
#
# Before R2 the script always exited 0 regardless of HOLD/PROCEED, so an
# acceptance criterion of "exit 0 == gate unlocked" was always satisfied
# (TASK-93 post-mortem, root cause R2). After R2:
#   PROCEED → exit 0   (gate genuinely unlocked)
#   HOLD    → exit 2   (insufficient/failing evidence)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPT_DIR/check-roi-gate.sh"

PASS=0
FAIL=0
check() { if [ "$2" -eq "$3" ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 (expected $2, got $3)"; FAIL=$((FAIL+1)); fi; }

# A meta-task-cycle fixture: a file the gate counts as one cycle, optionally
# carrying replan: and evaluator: markers.
mk_cycle() { # mk_cycle <dir> <n> <replan?> <verdict: Met|NotMet|none>
  local dir="$1" n="$2" replan="$3" verdict="$4"
  {
    echo "---"; echo "id: TASK-${n}"; echo "status: Meta-Done"; echo "---"
    echo "idempotentReconcile: cycle ${n}"
    [ "$replan" = "yes" ] && echo "replan: impl — fixture cycle ${n}"
    [ "$verdict" != "none" ] && echo "evaluator: ${verdict} | data_source: measured"
  } > "$dir/task-${n}.md"
}

build() { # build <met_count> <notmet_count> <replan_count> <total_cycles>
  local met="$1" notmet="$2" replan="$3" total="$4"
  local d; d=$(mktemp -d)
  local i=0
  while [ "$i" -lt "$met" ];    do i=$((i+1)); mk_cycle "$d" "$i" "$( [ "$i" -le "$replan" ] && echo yes || echo no )" Met; done
  local base=$i
  local j=0
  while [ "$j" -lt "$notmet" ]; do j=$((j+1)); mk_cycle "$d" "$((base+j))" no NotMet; done
  base=$((base+j))
  local k=0
  while [ "$base" -lt "$total" ]; do base=$((base+1)); mk_cycle "$d" "$base" no none; done
  echo "$d"
}

# ---- Test 1: <10 cycles → HOLD → exit 2 ---------------------------------
D=$(build 3 0 2 3)
bash "$GATE" --tasks-dir "$D" >/dev/null 2>&1
check "insufficient sample (<10 cycles) → exit 2" 2 $?
rm -rf "$D"

# ---- Test 2: 10 cycles, ≥2 replan, Met rate 80% → PROCEED → exit 0 ------
D=$(build 8 2 3 10)
bash "$GATE" --tasks-dir "$D" >/dev/null 2>&1
check "10 cycles, replan≥2, met 80% → PROCEED → exit 0" 0 $?
rm -rf "$D"

# ---- Test 3: 10 cycles but replan<2 → HOLD → exit 2 ---------------------
D=$(build 9 1 1 10)
bash "$GATE" --tasks-dir "$D" >/dev/null 2>&1
check "10 cycles, replan<2 → HOLD → exit 2" 2 $?
rm -rf "$D"

# ---- Test 4: 10 cycles, ≥2 replan, Met rate 50% (<70%) → HOLD → exit 2 --
D=$(build 5 5 3 10)
bash "$GATE" --tasks-dir "$D" >/dev/null 2>&1
check "10 cycles, met rate 50% (<70%) → HOLD → exit 2" 2 $?
rm -rf "$D"

# ---- Test 5: report still prints (stdout non-empty) on HOLD -------------
D=$(build 3 0 2 3)
OUT=$(bash "$GATE" --tasks-dir "$D" 2>&1)
echo "$OUT" | grep -q "ROI Gate Measurement Report"
check "report body still produced on HOLD" 0 $?
rm -rf "$D"

# ---- Test 6: --emit-json writes a provenance-stamped baseline ----------
D=$(build 8 2 3 10)
B=$(mktemp -d)              # clean baseline dir (holds only generated artifacts)
J="$B/replan-stats.json"
bash "$GATE" --tasks-dir "$D" --emit-json "$J" >/dev/null 2>&1
gate_rc=$?
grep -q '"generated_by": "scripts/check-roi-gate.sh"' "$J" 2>/dev/null && \
  grep -q '"data_source": "measured"' "$J" 2>/dev/null
check "--emit-json stamps generated_by + data_source" 0 $?
# the emitted baseline dir passes the provenance gate
bash "$SCRIPT_DIR/verify-provenance.sh" "$B" >/dev/null 2>&1
check "emitted baseline passes verify-provenance" 0 $?
check "emit run still returns PROCEED exit 0" 0 "$gate_rc"
rm -rf "$D" "$B"

echo ""
echo "check-roi-gate.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
