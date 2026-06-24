#!/usr/bin/env bash
# boss-evidence-pack.sh — Collect independent evidence for boss CC gate evaluation
#
# Usage: bash boss-evidence-pack.sh <EPIC-TASK-ID>
#        bash boss-evidence-pack.sh --help
#
# Output: JSON to stdout with fields:
#   task_id, change_risk, session_signals, evidence_source, worker_notes_included
#
# Evidence independence guarantee: this script NEVER reads the epic's Implementation
# Notes or worker summary. worker_notes_included is always false.
# Sources: archguard git-history file-metrics + meta-cc session signals (MCP).
#
# On any failure: outputs {"evidence_source":"unavailable","reason":"<msg>"} and exits 0.
# The boss gate is advisory, never blocking.

set -euo pipefail

# ── Help ──────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'EOF'
boss-evidence-pack.sh — Collect independent boss CC evidence for epicEvaluate gate

Usage:
  bash plugin/skills/loop-backlog/boss-evidence-pack.sh <EPIC-TASK-ID>
  bash plugin/skills/loop-backlog/boss-evidence-pack.sh --help

Arguments:
  EPIC-TASK-ID   The task ID of the epic being evaluated (e.g. TASK-42)

Output (stdout):
  JSON object with:
    task_id              : string  — the EPIC-TASK-ID provided
    change_risk          : object  — archguard file-metrics change risk data
    session_signals      : object  — meta-cc session signals (tool calls, errors, edits)
    evidence_source      : string  — "archguard+meta-cc" | "archguard-only" |
                                     "meta-cc-only" | "unavailable"
    worker_notes_included: false   — ALWAYS false (evidence independence hard constraint)
    collected_at         : string  — ISO 8601 UTC timestamp

On any failure:
  {"task_id":"<id>","evidence_source":"unavailable","reason":"<msg>","worker_notes_included":false}
  Exit code: 0 (advisory, never blocking)

Evidence independence:
  This script does NOT read the epic task's Implementation Notes or worker summary.
  Evidence comes from orthogonal channels:
    1. archguard git-history file-metrics (version control history)
    2. meta-cc session signals (MCP session log, not worker context window)

  See: docs/research/dyad-experiment-design.md §2
       docs/research/cc-actor-network.md §4.1
EOF
  exit 0
fi

# ── Argument validation ───────────────────────────────────────────────────────
TASK_ID="${1:-}"
if [ -z "$TASK_ID" ]; then
  printf '{"task_id":null,"evidence_source":"unavailable","reason":"missing required argument: EPIC-TASK-ID","worker_notes_included":false}\n'
  exit 0
fi

COLLECTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# ── Graceful failure helper ───────────────────────────────────────────────────
fail_gracefully() {
  local reason="$1"
  printf '{"task_id":"%s","evidence_source":"unavailable","reason":"%s","worker_notes_included":false,"collected_at":"%s"}\n' \
    "$TASK_ID" "$reason" "$COLLECTED_AT"
  exit 0
}

# ── Source 1: archguard change risk ──────────────────────────────────────────
# Read .archguard/query/git-history/file-metrics.json if present.
# Extract hot files (high churn/risk) relevant to the epic.
CHANGE_RISK_JSON='null'
ARCHGUARD_METRICS="${REPO_ROOT}/.archguard/query/git-history/file-metrics.json"

if [ -f "$ARCHGUARD_METRICS" ] && command -v python3 >/dev/null 2>&1; then
  CHANGE_RISK_JSON=$(python3 - <<PYEOF 2>/dev/null || echo 'null'
import json, sys

try:
    with open('${ARCHGUARD_METRICS}', 'r') as f:
        metrics = json.load(f)

    # metrics can be a list or dict depending on archguard version
    if isinstance(metrics, list):
        entries = metrics
    elif isinstance(metrics, dict):
        entries = metrics.get('data', metrics.get('items', [metrics]))
    else:
        entries = []

    # Sort by risk/churn indicators (commits, revisions, changes)
    def risk_score(e):
        if isinstance(e, dict):
            return (e.get('revisions', 0) or e.get('commits', 0) or
                    e.get('changes', 0) or 0)
        return 0

    sorted_entries = sorted(entries, key=risk_score, reverse=True)
    hot = sorted_entries[:5]  # top 5 hot files

    hot_files = []
    max_risk = 0
    for e in hot:
        if isinstance(e, dict):
            fname = (e.get('path') or e.get('file') or e.get('filename') or '')
            score = risk_score(e)
            hot_files.append(fname)
            if score > max_risk:
                max_risk = score

    result = {
        "hot_files": hot_files,
        "max_risk_score": max_risk,
        "churn_files": len([e for e in entries if risk_score(e) > 0]),
        "total_files_analyzed": len(entries),
        "source": "archguard-file-metrics"
    }
    print(json.dumps(result))
except Exception as ex:
    print('null')
    sys.exit(0)
PYEOF
  )
fi

# ── Source 2: meta-cc session signals ────────────────────────────────────────
# Read meta-cc session signals via MCP if available.
# This is invoked from a bash script; MCP calls happen in the Claude Code context.
# In the Claude Code agent context, the caller (LLM) should use:
#   mcp__plugin_meta-cc_meta-cc__get_session_metadata
#   mcp__plugin_meta-cc_meta-cc__query_session_signals
#   mcp__plugin_meta-cc_meta-cc__analyze_errors
# This script provides a fallback for direct shell execution (no MCP).
#
# When called from within a Claude Code epicEvaluate context, the agent should:
# 1. Call this script to get the archguard change_risk portion
# 2. Call meta-cc MCP tools directly for session_signals
# 3. Merge both into the final evidence pack
#
# For direct shell execution (CI, debugging), session_signals is "unavailable".
SESSION_SIGNALS_JSON='"unavailable (direct-shell: no MCP context)"'

# Check if meta-cc data directory exists as a fallback
META_CC_DIR="${HOME}/.claude/meta-cc"
if [ -d "$META_CC_DIR" ]; then
  # Try to read latest session signals from disk
  LATEST_SESSION=$(ls -t "${META_CC_DIR}"/*.jsonl 2>/dev/null | head -1 || true)
  if [ -n "$LATEST_SESSION" ] && command -v python3 >/dev/null 2>&1; then
    SESSION_SIGNALS_JSON=$(python3 - <<PYEOF 2>/dev/null || echo '"unavailable (parse-error)"'
import json, sys

try:
    signals = []
    with open('${LATEST_SESSION}', 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    signals.append(json.loads(line))
                except Exception:
                    pass

    if not signals:
        print('"unavailable (empty-session-log)"')
        sys.exit(0)

    # Count tool calls and errors
    tool_calls = sum(1 for s in signals if s.get('type') in ('tool_use', 'tool_call'))
    errors = sum(1 for s in signals if 'error' in str(s.get('type', '')).lower()
                 or s.get('is_error', False))

    result = {
        "event_count": len(signals),
        "tool_call_count": tool_calls,
        "error_count": errors,
        "edit_oscillation": "unknown",
        "source": "meta-cc-session-log"
    }
    print(json.dumps(result))
except Exception as ex:
    print('"unavailable (exception: ' + str(ex)[:80].replace('"', "'") + ')"')
    sys.exit(0)
PYEOF
    )
  fi
fi

# ── Determine evidence_source ─────────────────────────────────────────────────
HAS_CHANGE_RISK=false
HAS_SESSION_SIGNALS=false

if [ "$CHANGE_RISK_JSON" != "null" ] && [ -n "$CHANGE_RISK_JSON" ]; then
  HAS_CHANGE_RISK=true
fi
if echo "$SESSION_SIGNALS_JSON" | grep -qv '"unavailable'; then
  HAS_SESSION_SIGNALS=true
fi

if [ "$HAS_CHANGE_RISK" = "true" ] && [ "$HAS_SESSION_SIGNALS" = "true" ]; then
  EVIDENCE_SOURCE="archguard+meta-cc"
elif [ "$HAS_CHANGE_RISK" = "true" ]; then
  EVIDENCE_SOURCE="archguard-only"
elif [ "$HAS_SESSION_SIGNALS" = "true" ]; then
  EVIDENCE_SOURCE="meta-cc-only"
else
  EVIDENCE_SOURCE="unavailable"
fi

# ── Output structured JSON ────────────────────────────────────────────────────
# worker_notes_included is ALWAYS false — this is the evidence independence guarantee.
# Use environment variables to safely pass values into Python (avoids shell quoting issues).
export _BOSS_TASK_ID="$TASK_ID"
export _BOSS_COLLECTED_AT="$COLLECTED_AT"
export _BOSS_EVIDENCE_SOURCE="$EVIDENCE_SOURCE"
export _BOSS_CHANGE_RISK="$CHANGE_RISK_JSON"
export _BOSS_SESSION_SIGNALS="$SESSION_SIGNALS_JSON"

python3 - <<'PYEOF' 2>/dev/null || \
  printf '{"task_id":"%s","evidence_source":"unavailable","reason":"json-assembly-error","worker_notes_included":false,"collected_at":"%s"}\n' \
    "$TASK_ID" "$COLLECTED_AT"
import json, os, sys

task_id        = os.environ.get('_BOSS_TASK_ID', '')
collected_at   = os.environ.get('_BOSS_COLLECTED_AT', '')
evidence_source = os.environ.get('_BOSS_EVIDENCE_SOURCE', 'unavailable')
change_risk_raw = os.environ.get('_BOSS_CHANGE_RISK', 'null')
session_raw     = os.environ.get('_BOSS_SESSION_SIGNALS', '"unavailable"')

try:
    change_risk = json.loads(change_risk_raw)
except Exception:
    change_risk = None

try:
    session_signals = json.loads(session_raw)
except Exception:
    session_signals = session_raw.strip('"')

result = {
    "task_id": task_id,
    "change_risk": change_risk,
    "session_signals": session_signals,
    "evidence_source": evidence_source,
    "worker_notes_included": False,
    "collected_at": collected_at
}

print(json.dumps(result, indent=2))
PYEOF
