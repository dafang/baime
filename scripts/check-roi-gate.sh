#!/usr/bin/env bash
# check-roi-gate.sh — ROI gate measurement report for loop-meta P3→P4 decision.
#
# Scans backlog task notes for evaluator slice conclusions and replan trigger events.
# All measurements are data_source: measured (no estimates).
#
# Exit code reflects the gate DECISION (R2 — exit 0 must mean "gate unlocked",
# not merely "report produced"; see TASK-93 post-mortem):
#   PROCEED → exit 0   (P4 automation warranted)
#   HOLD    → exit 2   (insufficient sample / replan evidence / evaluator reliability)
# The report body is always printed regardless of exit code.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/backlog/tasks"
EMIT_JSON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tasks-dir) TASKS_DIR="$2"; shift 2 ;;
    --emit-json) EMIT_JSON="$2"; shift 2 ;;
    *) shift ;;
  esac
done
BASELINE_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

replan_events=0
evaluator_met=0
evaluator_not_met=0
total_tasks=0
meta_task_cycles=0

for f in "$TASKS_DIR"/*.md; do
  [ -f "$f" ] || continue
  total_tasks=$((total_tasks + 1))
  # Count meta-task cycles (tasks that went through Meta-Active)
  if grep -q 'status: Meta-Active\|status: Meta-Done\|idempotentReconcile:' "$f" 2>/dev/null; then
    meta_task_cycles=$((meta_task_cycles + 1))
  fi
  while IFS= read -r line; do
    case "$line" in
      *"replan:"*)              replan_events=$((replan_events + 1)) ;;
      *"evaluator: Met"*)       evaluator_met=$((evaluator_met + 1)) ;;
      *"evaluator: NotMet"*)    evaluator_not_met=$((evaluator_not_met + 1)) ;;
    esac
  done < "$f"
done

evaluator_total=$((evaluator_met + evaluator_not_met))

echo "============================================================"
echo " ROI Gate Measurement Report"
echo " Generated: ${BASELINE_TS}"
echo " data_source: measured"
echo "============================================================"
echo ""
echo " Task corpus"
echo "   Total tasks scanned:        ${total_tasks}"
echo "   Meta-task cycles detected:  ${meta_task_cycles}"
echo ""
echo " Evaluator slice results"
echo "   Met:     ${evaluator_met}"
echo "   NotMet:  ${evaluator_not_met}"
echo "   Total:   ${evaluator_total}"
if [ "$evaluator_total" -gt 0 ]; then
  # bash integer arithmetic: scale ×100 for percentage
  pct=$(( evaluator_met * 100 / evaluator_total ))
  echo "   Met rate: ${pct}%"
else
  echo "   Met rate: N/A (no slices recorded yet)"
fi
echo ""
echo " Replan trigger events"
echo "   Total replan events:        ${replan_events}"
if [ "$meta_task_cycles" -gt 0 ]; then
  rate_x10=$(( replan_events * 10 / meta_task_cycles ))
  echo "   Rate (per 10 cycles):       ${rate_x10}"
else
  echo "   Rate (per 10 cycles):       N/A (no meta-task cycles yet)"
  rate_x10=0
fi
echo ""

# P4 gate decision
echo " P4 Gate Decision"
if [ "$meta_task_cycles" -lt 10 ]; then
  echo "   Result: HOLD"
  echo "   Reason: Insufficient sample — need ≥10 meta-task cycles (have ${meta_task_cycles})"
  echo "   Action: Run more meta-task cycles, then re-evaluate"
  gate_exit=2
elif [ "$replan_events" -lt 2 ]; then
  echo "   Result: HOLD"
  echo "   Reason: Replan trigger frequency < 2 per 10 cycles (observed ${rate_x10}/10)"
  echo "   Action: P3 loop-meta is working; P4 gating is correct — automated scheduling not yet needed"
  gate_exit=2
elif [ "$evaluator_total" -gt 0 ] && [ "$(( evaluator_met * 100 / evaluator_total ))" -lt 70 ]; then
  echo "   Result: HOLD"
  echo "   Reason: Evaluator slice agreement < 70% (observed ${pct}%) — evaluator reliability insufficient"
  echo "   Action: Improve evaluator slice quality before enabling P4 automation"
  gate_exit=2
else
  echo "   Result: PROCEED"
  echo "   Reason: Sufficient replan evidence and evaluator reliability — P4 automation is warranted"
  gate_exit=0
fi
echo ""
echo " Baseline note: If zero events recorded, this is the pre-P3 baseline."
echo " Re-run after ≥10 meta-task cycles for a meaningful gate decision."
echo "============================================================"

# R4: emit a provenance-stamped baseline JSON. This is the ONLY sanctioned way to
# produce replan-stats.json — it carries generated_by so verify-provenance.sh can
# trace it. A hand-written baseline (TASK-93) has no generated_by and fails the gate.
if [ -n "$EMIT_JSON" ]; then
  mkdir -p "$(dirname "$EMIT_JSON")"
  decision=$([ "${gate_exit}" -eq 0 ] && echo "PROCEED" || echo "HOLD")
  cat > "$EMIT_JSON" <<JSON
{
  "data_source": "measured",
  "generated_by": "scripts/check-roi-gate.sh",
  "generated_at": "${BASELINE_TS}",
  "tasks_dir": "${TASKS_DIR}",
  "meta_task_cycles": ${meta_task_cycles},
  "replan_total": ${replan_events},
  "evaluator": { "Met": ${evaluator_met}, "NotMet": ${evaluator_not_met} },
  "decision": "${decision}"
}
JSON
  echo " Baseline JSON written to ${EMIT_JSON} (data_source: measured, generated_by: check-roi-gate.sh)"
fi

# R2: exit code reflects the gate decision (PROCEED→0 / HOLD→2)
exit "${gate_exit}"
