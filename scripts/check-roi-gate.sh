#!/usr/bin/env bash
# check-roi-gate.sh — ROI gate measurement report for loop-meta P3→P4 decision.
#
# Scans backlog task notes for evaluator slice conclusions and replan trigger events.
# All measurements are data_source: measured (no estimates).
# Exits 0 when the report is produced (even if zero events — zero is valid baseline).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/backlog/tasks"
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
elif [ "$replan_events" -lt 2 ]; then
  echo "   Result: HOLD"
  echo "   Reason: Replan trigger frequency < 2 per 10 cycles (observed ${rate_x10}/10)"
  echo "   Action: P3 loop-meta is working; P4 gating is correct — automated scheduling not yet needed"
elif [ "$evaluator_total" -gt 0 ] && [ "$(( evaluator_met * 100 / evaluator_total ))" -lt 70 ]; then
  echo "   Result: HOLD"
  echo "   Reason: Evaluator slice agreement < 70% (observed ${pct}%) — evaluator reliability insufficient"
  echo "   Action: Improve evaluator slice quality before enabling P4 automation"
else
  echo "   Result: PROCEED"
  echo "   Reason: Sufficient replan evidence and evaluator reliability — P4 automation is warranted"
fi
echo ""
echo " Baseline note: If zero events recorded, this is the pre-P3 baseline."
echo " Re-run after ≥10 meta-task cycles for a meaningful gate decision."
echo "============================================================"
