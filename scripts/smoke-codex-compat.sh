#!/usr/bin/env bash

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULT_DIR="$REPO_ROOT/compatibility/smoke/latest"
PREFLIGHT_LOG="$RESULT_DIR/preflight.log"
SUMMARY_JSON="$RESULT_DIR/summary.json"
AGENT_OUTPUT="$RESULT_DIR/agent-output.txt"
SKILL_OUTPUT="$RESULT_DIR/skill-output.txt"

MODE="preflight"
PREFLIGHT_ERRORS=0
PREFLIGHT_STATUS="not_run"
AGENT_STATUS="not_run"
SKILL_STATUS="not_run"
BLOCKED_REASON=""
TMP_HOME=""
TMP_MARKET=""
TOML_PYTHON=""

usage() {
    cat <<'EOF'
Usage: bash scripts/smoke-codex-compat.sh [--preflight|--live]

Modes:
  --preflight  Deterministic checks only. No model calls. Default.
  --live       Run preflight, then Codex exec smoke checks for one agent and one skill.
  --help       Show this help.
EOF
}

cleanup() {
    if [ -n "$TMP_HOME" ] && [ -d "$TMP_HOME" ]; then
        rm -rf "$TMP_HOME"
    fi
    if [ -n "$TMP_MARKET" ] && [ -d "$TMP_MARKET" ]; then
        rm -rf "$TMP_MARKET"
    fi
}

trap cleanup EXIT

while [ "$#" -gt 0 ]; do
    case "$1" in
        --preflight)
            MODE="preflight"
            ;;
        --live)
            MODE="live"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

prepare_result_dir() {
    rm -rf "$RESULT_DIR"
    mkdir -p "$RESULT_DIR"
    : > "$PREFLIGHT_LOG"
}

log() {
    echo "$*" | tee -a "$PREFLIGHT_LOG"
}

pass() {
    log "  PASS: $*"
}

fail() {
    log "  FAIL: $*"
    PREFLIGHT_ERRORS=$((PREFLIGHT_ERRORS + 1))
}

write_summary() {
    local status="$1"
    local preflight="$2"
    local agent="$3"
    local skill="$4"
    local blocked_reason="$5"

    python3 - "$SUMMARY_JSON" "$status" "$preflight" "$agent" "$skill" "$blocked_reason" <<'PY'
import json
import sys
from pathlib import Path

path, status, preflight, agent, skill, blocked_reason = sys.argv[1:]
data = {
    "status": status,
    "preflight": preflight,
    "agent_smoke": agent,
    "skill_smoke": skill,
    "blocked_reason": blocked_reason or None,
}
Path(path).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
}

run_logged() {
    local label="$1"
    local output="$2"
    shift 2

    log "  RUN: $label"
    "$@" > "$output" 2>&1
    local rc=$?
    sed 's/^/    /' "$output" >> "$PREFLIGHT_LOG"
    return "$rc"
}

find_toml_python() {
    for candidate in python3 python3.13 python3.12 python3.11; do
        if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "import tomllib" >/dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

assert_json_field() {
    local file="$1"
    local field="$2"
    local expected="$3"

    python3 - "$file" "$field" "$expected" <<'PY' >/dev/null 2>&1
import json
import sys

path, field, expected = sys.argv[1:]
with open(path) as f:
    data = json.load(f)
actual = data.get(field)
sys.exit(0 if actual == expected else 1)
PY
}

assert_workflow_coach_toml() {
    local file="$1"

    "$TOML_PYTHON" - "$file" "$REPO_ROOT/.claude/agents/workflow-coach.md" <<'PY'
import sys
from pathlib import Path
import tomllib

path = Path(sys.argv[1])
source = Path(sys.argv[2])

try:
    data = tomllib.loads(path.read_text())
except Exception as exc:
    print(f"invalid TOML: {exc}")
    sys.exit(1)

required = ["name", "description", "developer_instructions"]
missing = [field for field in required if not data.get(field)]
if missing:
    print(f"missing required fields: {', '.join(missing)}")
    sys.exit(1)

if data["name"] != "workflow-coach":
    print(f"name must be workflow-coach, got {data['name']!r}")
    sys.exit(1)

instructions = data["developer_instructions"]
if ".claude/agents/workflow-coach.md" not in instructions:
    print("developer_instructions must reference .claude/agents/workflow-coach.md")
    sys.exit(1)

if not source.is_file():
    print("referenced workflow-coach source file is missing")
    sys.exit(1)
PY
}

assert_installed_agents_portable() {
    local agents_dir="$1"
    local skills_dir="$2"

    "$TOML_PYTHON" - "$agents_dir" "$skills_dir" <<'PY'
import sys
import re
from pathlib import Path
import tomllib

agents_dir = Path(sys.argv[1])
skills_dir = Path(sys.argv[2])
expected = {
    "iteration-executor",
    "iteration-prompt-designer",
    "knowledge-extractor",
    "project-planner",
    "stage-executor",
    "workflow-coach",
}

files = sorted(agents_dir.glob("*.toml"))
actual = {path.stem for path in files}
if actual != expected:
    print(f"installed agent set mismatch: expected {sorted(expected)}, got {sorted(actual)}")
    sys.exit(1)

for path in files:
    try:
        data = tomllib.loads(path.read_text())
    except Exception as exc:
        print(f"invalid TOML in {path}: {exc}")
        sys.exit(1)

    missing = [field for field in ("name", "description", "developer_instructions") if not data.get(field)]
    if missing:
        print(f"{path} missing required fields: {', '.join(missing)}")
        sys.exit(1)

    if data["name"] != path.stem:
        print(f"{path} name must be {path.stem!r}, got {data['name']!r}")
        sys.exit(1)

    instructions = data["developer_instructions"]
    preamble = instructions.split("--- BEGIN BAIME WORKFLOW SOURCE ---", 1)[0]
    if ".claude/agents/" in preamble:
        print(f"{path} preamble must not reference .claude/agents/")
        sys.exit(1)
    if "Use the shared workflow source at" in preamble:
        print(f"{path} preamble contains repo-local adapter wording")
        sys.exit(1)
    if "--- BEGIN BAIME WORKFLOW SOURCE ---" not in instructions:
        print(f"{path} does not embed BAIME workflow source")
        sys.exit(1)

for slug in expected:
    skill_dir = skills_dir / f"{slug}-agent"
    skill_file = skill_dir / "SKILL.md"
    policy_file = skill_dir / "agents" / "openai.yaml"
    if not skill_file.is_file():
        print(f"missing launcher skill: {skill_file}")
        sys.exit(1)
    content = skill_file.read_text()
    match = re.match(r"^---\s*\n(.*?)\n---", content, re.DOTALL)
    if not match:
        print(f"{skill_file} missing YAML frontmatter")
        sys.exit(1)
    frontmatter = match.group(1)
    if f"name: {slug}-agent" not in frontmatter or "description:" not in frontmatter:
        print(f"{skill_file} has invalid frontmatter")
        sys.exit(1)
    if f"`{slug}` custom agent" not in content:
        print(f"{skill_file} does not point at {slug} custom agent")
        sys.exit(1)
    if not policy_file.is_file() or "allow_implicit_invocation: false" not in policy_file.read_text():
        print(f"{policy_file} must disable implicit invocation")
        sys.exit(1)
PY
}

assert_skill_frontmatter() {
    local file="$1"
    local expected_name="$2"

    python3 - "$file" "$expected_name" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected_name = sys.argv[2]
content = path.read_text()
match = re.match(r"^---\s*\n(.*?)\n---", content, re.DOTALL)
if not match:
    print("missing YAML frontmatter")
    sys.exit(1)

frontmatter = match.group(1)
name_match = re.search(r"^name:\s*(.+)$", frontmatter, re.MULTILINE)
if not name_match:
    print("frontmatter missing name")
    sys.exit(1)

actual_name = name_match.group(1).strip().strip("\"'")
if actual_name != expected_name:
    print(f"name must be {expected_name!r}, got {actual_name!r}")
    sys.exit(1)
PY
}

preflight_cli() {
    log "=== Codex CLI ==="

    if command -v codex >/dev/null 2>&1; then
        pass "codex CLI is available: $(command -v codex)"
    else
        fail "codex CLI is not on PATH"
        return
    fi

    if codex --help 2>&1 | grep -Eq '(^|[[:space:]])exec([[:space:]]|$)' && codex --help 2>&1 | grep -Eq '(^|[[:space:]])plugin([[:space:]]|$)'; then
        pass "codex --help includes exec and plugin"
    else
        fail "codex --help must include exec and plugin"
    fi

    if codex plugin list --help 2>&1 | grep -q -- '--json' && codex plugin list --help 2>&1 | grep -q -- '--available'; then
        pass "codex plugin list supports --available --json"
    else
        fail "codex plugin list must support --available --json"
    fi
}

preflight_manifest() {
    local manifest="$REPO_ROOT/.codex-plugin/plugin.json"

    log ""
    log "=== Plugin Manifest ==="

    if [ -f "$manifest" ]; then
        pass ".codex-plugin/plugin.json exists"
    else
        fail ".codex-plugin/plugin.json is missing"
        return
    fi

    if python3 -m json.tool "$manifest" >/dev/null 2>&1; then
        pass ".codex-plugin/plugin.json is valid JSON"
    else
        fail ".codex-plugin/plugin.json is invalid JSON"
    fi

    if assert_json_field "$manifest" "name" "baime"; then
        pass "plugin manifest name is baime"
    else
        fail "plugin manifest name must be baime"
    fi
}

preflight_agents() {
    local agents_dir="$REPO_ROOT/.codex/agents"
    local target="$agents_dir/workflow-coach.toml"
    local count

    log ""
    log "=== Codex Custom Agents ==="

    if [ -d "$agents_dir" ]; then
        pass ".codex/agents exists"
    else
        fail ".codex/agents is missing"
        return
    fi

    count="$(find "$agents_dir" -maxdepth 1 -type f -name '*.toml' | wc -l | tr -d ' ')"
    if [ "$count" = "6" ]; then
        pass ".codex/agents contains 6 TOML files"
    else
        fail ".codex/agents must contain 6 TOML files, found $count"
    fi

    if [ -f "$target" ]; then
        pass "workflow-coach custom agent TOML exists"
    else
        fail "workflow-coach custom agent TOML is missing"
        return
    fi

    if assert_workflow_coach_toml "$target" >> "$PREFLIGHT_LOG" 2>&1; then
        pass "workflow-coach TOML parses and references shared source"
    else
        fail "workflow-coach TOML is invalid; see preflight.log"
    fi
}

preflight_agent_installer() {
    local installer="$REPO_ROOT/scripts/install-codex-agents.sh"
    local tmp_project

    log ""
    log "=== Codex Agent Installer ==="

    if [ -x "$installer" ]; then
        pass "install-codex-agents.sh exists and is executable"
    else
        fail "install-codex-agents.sh is missing or not executable"
        return
    fi

    if run_logged "install-codex-agents.sh --scope user --dry-run" "$RESULT_DIR/agent-installer-dry-run.txt" "$installer" --scope user --dry-run; then
        pass "agent installer dry-run generated and validated 6 portable agents and 6 launcher skills"
    else
        fail "agent installer dry-run failed; see agent-installer-dry-run.txt"
    fi

    tmp_project="$(mktemp -d)"
    if run_logged "install-codex-agents.sh --scope project --target <temp>" "$RESULT_DIR/agent-installer-project.txt" "$installer" --scope project --target "$tmp_project"; then
        pass "agent installer wrote agents and launcher skills into a temporary project"
    else
        fail "agent installer temporary project install failed; see agent-installer-project.txt"
        rm -rf "$tmp_project"
        return
    fi

    if assert_installed_agents_portable "$tmp_project/.codex/agents" "$tmp_project/.codex/skills" >> "$PREFLIGHT_LOG" 2>&1; then
        pass "temporary project agents and launcher skills are valid"
    else
        fail "temporary project agents or launcher skills are invalid"
    fi

    if run_logged "install-codex-agents.sh conflict check" "$RESULT_DIR/agent-installer-conflict.txt" "$installer" --scope project --target "$tmp_project"; then
        fail "agent installer must not overwrite existing agents without --force"
    else
        pass "agent installer rejects existing agents without --force"
    fi

    if run_logged "install-codex-agents.sh --force overwrite" "$RESULT_DIR/agent-installer-force.txt" "$installer" --scope project --target "$tmp_project" --force; then
        pass "agent installer overwrites existing agents with --force"
    else
        fail "agent installer --force overwrite failed; see agent-installer-force.txt"
    fi

    if assert_installed_agents_portable "$tmp_project/.codex/agents" "$tmp_project/.codex/skills" >> "$PREFLIGHT_LOG" 2>&1; then
        pass "forced project agents and launcher skills remain valid"
    else
        fail "forced project agents or launcher skills are invalid"
    fi

    rm -rf "$tmp_project"
}

preflight_skills() {
    local skills_dir="$REPO_ROOT/.codex/skills"
    local target_dir="$skills_dir/methodology-bootstrapping"
    local target_skill="$target_dir/SKILL.md"
    local count
    local errors=0
    local entry
    local slug
    local link_target

    log ""
    log "=== Codex Shared Skills ==="

    if [ -d "$skills_dir" ]; then
        pass ".codex/skills exists"
    else
        fail ".codex/skills is missing"
        return
    fi

    count="$(find "$skills_dir" -maxdepth 1 -type l | wc -l | tr -d ' ')"
    if [ "$count" -gt 0 ]; then
        pass ".codex/skills contains $count symlinked skill entries"
    else
        fail ".codex/skills must contain at least one symlinked skill entry"
    fi

    for entry in "$skills_dir"/*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        slug="$(basename "$entry")"
        if [ ! -L "$entry" ]; then
            log "  FAIL: .codex/skills/$slug is not a symlink"
            errors=$((errors + 1))
            continue
        fi
        link_target="$(readlink "$entry")"
        if [ "$link_target" != "../../.claude/skills/$slug" ]; then
            log "  FAIL: .codex/skills/$slug points to $link_target"
            errors=$((errors + 1))
        fi
    done

    if [ "$errors" -eq 0 ]; then
        pass ".codex/skills symlinks point to matching shared skill sources"
    else
        fail ".codex/skills symlink validation found $errors issue(s)"
    fi

    if [ -f "$target_skill" ]; then
        pass "methodology-bootstrapping/SKILL.md resolves through symlink"
    else
        fail "methodology-bootstrapping/SKILL.md is missing"
        return
    fi

    if assert_skill_frontmatter "$target_skill" "methodology-bootstrapping" >> "$PREFLIGHT_LOG" 2>&1; then
        pass "methodology-bootstrapping frontmatter name is valid"
    else
        fail "methodology-bootstrapping frontmatter is invalid; see preflight.log"
    fi

    pass "agent launcher skills are generated by scripts/install-codex-agents.sh, not stored in .codex/skills"
}

preflight_marketplace() {
    local output="$RESULT_DIR/marketplace-available.json"
    local market_json

    log ""
    log "=== Temporary Codex Marketplace ==="

    TMP_HOME="$(mktemp -d)"
    TMP_MARKET="$(mktemp -d)"
    mkdir -p "$TMP_MARKET/.agents/plugins" "$TMP_MARKET/plugins"
    ln -s "$REPO_ROOT" "$TMP_MARKET/plugins/baime"
    market_json="$TMP_MARKET/.agents/plugins/marketplace.json"

    python3 - "$market_json" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "name": "baime-smoke",
    "plugins": [{
        "name": "baime",
        "source": {
            "source": "local",
            "path": "./plugins/baime"
        },
        "policy": {
            "installation": "AVAILABLE",
            "authentication": "ON_INSTALL"
        },
        "category": "Productivity"
    }]
}, indent=2) + "\n")
PY

    if CODEX_HOME="$TMP_HOME" run_logged "codex plugin marketplace add <temp>" "$RESULT_DIR/marketplace-add.txt" codex plugin marketplace add "$TMP_MARKET" --json; then
        pass "temporary marketplace added with isolated CODEX_HOME"
    else
        fail "failed to add temporary marketplace; see marketplace-add.txt"
        return
    fi

    if CODEX_HOME="$TMP_HOME" run_logged "codex plugin list --available --json" "$output" codex plugin list --available --json; then
        pass "codex plugin list --available --json ran in isolated CODEX_HOME"
    else
        fail "failed to list available plugins; see marketplace-available.json"
        return
    fi

    if python3 - "$output" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)

def walk(value):
    if isinstance(value, dict):
        if value.get("name") == "baime":
            return True
        return any(walk(child) for child in value.values())
    if isinstance(value, list):
        return any(walk(child) for child in value)
    return False

sys.exit(0 if walk(data) else 1)
PY
    then
        pass "temporary marketplace lists baime plugin"
    else
        fail "temporary marketplace did not list baime plugin"
    fi

    if CODEX_HOME="$TMP_HOME" run_logged "codex plugin add baime@baime-smoke" "$RESULT_DIR/marketplace-install.txt" codex plugin add baime@baime-smoke --json; then
        pass "temporary marketplace installs baime plugin"
    else
        fail "temporary marketplace failed to install baime plugin"
        return
    fi

    if python3 - "$TMP_HOME" <<'PY'
import sys
from pathlib import Path

home = Path(sys.argv[1])
roots = list((home / "plugins" / "cache").glob("baime-smoke/baime/*"))
if not roots:
    sys.exit(1)

root = roots[0]
checks = [
    root / ".claude" / "skills" / "methodology-bootstrapping" / "SKILL.md",
    root / ".codex-plugin" / "plugin.json",
]
if not all(path.exists() for path in checks):
    sys.exit(1)

skill_count = sum(1 for entry in (root / ".claude" / "skills").iterdir() if (entry / "SKILL.md").is_file())
sys.exit(0 if skill_count > 0 else 1)
PY
    then
        pass "installed baime plugin cache contains shared methodology skills"
    else
        fail "installed baime plugin cache is missing shared methodology skills"
    fi
}

run_preflight() {
    preflight_cli
    preflight_manifest
    preflight_agents
    preflight_agent_installer
    preflight_skills
    preflight_marketplace

    if [ "$PREFLIGHT_ERRORS" -eq 0 ]; then
        PREFLIGHT_STATUS="passed"
        log ""
        log "preflight passed"
        return 0
    fi

    PREFLIGHT_STATUS="failed"
    log ""
    log "preflight failed with $PREFLIGHT_ERRORS issue(s)"
    return 1
}

classify_live_failure() {
    local file="$1"
    local exec_log="$2"
    local rc="$3"

    if grep -Eiq 'auth|login|sign in|credential|api key|unauthorized|forbidden|country|region|network|timeout|model|quota|rate limit|permission|connection|dns|tls' "$file" "$exec_log"; then
        echo "blocked: codex exec exited $rc; likely auth/model/network/environment issue"
    else
        echo "failed: codex exec exited $rc"
    fi
}

codex_exec_approval_args() {
    if codex exec --help 2>&1 | grep -q -- '--ask-for-approval'; then
        printf '%s\n' '--ask-for-approval' 'never'
    else
        printf '%s\n' '-c' 'approval_policy="never"'
    fi
}

run_live_target() {
    local label="$1"
    local output="$2"
    local marker="$3"
    local target="$4"
    local prompt="$5"
    local exec_log="$RESULT_DIR/$label-exec.log"
    local approval_args=()
    local approval_display=""
    local arg

    log ""
    log "=== Live $label Smoke ==="
    while IFS= read -r arg; do
        approval_args+=("$arg")
        approval_display="${approval_display}${approval_display:+ }$arg"
    done < <(codex_exec_approval_args)

    log "  RUN: codex exec --cd \"$REPO_ROOT\" --sandbox read-only $approval_display --output-last-message \"$output\""

    codex exec \
        --cd "$REPO_ROOT" \
        --sandbox read-only \
        "${approval_args[@]}" \
        --output-last-message "$output" \
        "$prompt" > "$exec_log" 2>&1
    local rc=$?
    sed 's/^/    /' "$exec_log" >> "$PREFLIGHT_LOG"

    if [ "$rc" -ne 0 ]; then
        if [ ! -f "$output" ]; then
            : > "$output"
        fi
        local reason
        reason="$(classify_live_failure "$output" "$exec_log" "$rc")"
        log "  FAIL: $label codex exec did not complete: $reason"
        BLOCKED_REASON="${BLOCKED_REASON}${BLOCKED_REASON:+; }$label $reason"
        case "$reason" in
            blocked:*) return 2 ;;
            *) return 1 ;;
        esac
    fi

    if grep -q "$marker" "$output" && grep -q "$target" "$output"; then
        pass "$label output contains $marker and $target"
        return 0
    fi

    log "  FAIL: $label output is missing $marker or $target"
    return 1
}

run_live() {
    local agent_prompt
    local skill_prompt
    local agent_rc
    local skill_rc
    local live_status="passed"

    agent_prompt='Use the workflow-coach custom agent to inspect this BAIME Codex compatibility smoke request. Keep the response concise and include both strings exactly: BAIME_SMOKE_AGENT_OK and workflow-coach.'
    skill_prompt='Use $methodology-bootstrapping to inspect this BAIME Codex compatibility smoke request. Keep the response concise and include both strings exactly: BAIME_SMOKE_SKILL_OK and methodology-bootstrapping.'

    run_live_target "agent" "$AGENT_OUTPUT" "BAIME_SMOKE_AGENT_OK" "workflow-coach" "$agent_prompt"
    agent_rc=$?
    case "$agent_rc" in
        0) AGENT_STATUS="passed" ;;
        2) AGENT_STATUS="blocked"; live_status="blocked" ;;
        *) AGENT_STATUS="failed"; live_status="failed" ;;
    esac

    run_live_target "skill" "$SKILL_OUTPUT" "BAIME_SMOKE_SKILL_OK" "methodology-bootstrapping" "$skill_prompt"
    skill_rc=$?
    case "$skill_rc" in
        0) SKILL_STATUS="passed" ;;
        2)
            SKILL_STATUS="blocked"
            if [ "$live_status" = "passed" ]; then
                live_status="blocked"
            fi
            ;;
        *)
            SKILL_STATUS="failed"
            live_status="failed"
            ;;
    esac

    if [ "$live_status" = "passed" ]; then
        log ""
        log "live smoke passed"
        return 0
    fi

    log ""
    log "live smoke $live_status"
    return 1
}

prepare_result_dir

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for smoke summary and metadata parsing" >&2
    exit 1
fi

TOML_PYTHON="$(find_toml_python || true)"
if [ -z "$TOML_PYTHON" ]; then
    echo "Python 3.11+ with tomllib is required for TOML smoke checks" >&2
    exit 1
fi

if ! run_preflight; then
    write_summary "failed" "$PREFLIGHT_STATUS" "$AGENT_STATUS" "$SKILL_STATUS" ""
    echo "summary: $SUMMARY_JSON"
    exit 1
fi

if [ "$MODE" = "preflight" ]; then
    write_summary "passed" "$PREFLIGHT_STATUS" "$AGENT_STATUS" "$SKILL_STATUS" ""
    echo "summary: $SUMMARY_JSON"
    exit 0
fi

if run_live; then
    write_summary "passed" "$PREFLIGHT_STATUS" "$AGENT_STATUS" "$SKILL_STATUS" ""
    echo "summary: $SUMMARY_JSON"
    exit 0
fi

if [ "$AGENT_STATUS" = "blocked" ] || [ "$SKILL_STATUS" = "blocked" ]; then
    write_summary "blocked" "$PREFLIGHT_STATUS" "$AGENT_STATUS" "$SKILL_STATUS" "$BLOCKED_REASON"
    echo "summary: $SUMMARY_JSON"
    exit 2
fi

write_summary "failed" "$PREFLIGHT_STATUS" "$AGENT_STATUS" "$SKILL_STATUS" "$BLOCKED_REASON"
echo "summary: $SUMMARY_JSON"
exit 1
