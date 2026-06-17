#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERRORS=0

# ── Helper functions ─────────────────────────────────────────────────────────

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

validate_json_file() {
    local file="$1"
    [ -f "$file" ] || return 1
    python3 - "$file" <<'EOF' >/dev/null 2>&1
import json
import sys

with open(sys.argv[1]) as f:
    json.load(f)
EOF
}

json_field() {
    local file="$1"
    local field="$2"
    python3 - "$file" "$field" <<'EOF'
import json
import sys

filepath, field = sys.argv[1], sys.argv[2]
try:
    with open(filepath) as f:
        data = json.load(f)
except Exception:
    sys.exit(1)

value = data.get(field)
if value is None:
    sys.exit(1)
print(value)
EOF
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

cleanup() {
    if [ -n "${TMP_INSTALL_PROJECT:-}" ] && [ -d "$TMP_INSTALL_PROJECT" ]; then
        rm -rf "$TMP_INSTALL_PROJECT"
    fi
}

trap cleanup EXIT

# ── JSON validation ──────────────────────────────────────────────────────────

echo ""
echo "=== JSON Manifest Validation ==="

PLUGIN_JSON="$REPO_ROOT/.claude/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
CODEX_PLUGIN_JSON="$REPO_ROOT/.codex-plugin/plugin.json"

if validate_json_file "$PLUGIN_JSON"; then
    pass "plugin.json is valid JSON"
else
    fail "plugin.json is invalid JSON"
fi

if validate_json_file "$MARKETPLACE_JSON"; then
    pass "marketplace.json is valid JSON"
else
    fail "marketplace.json is invalid JSON"
fi

if validate_json_file "$CODEX_PLUGIN_JSON"; then
    pass "Codex plugin.json is valid JSON"
else
    fail "Codex plugin.json is invalid JSON"
fi

# ── Manifest identity parity ──────────────────────────────────────────────────

PLUGIN_NAME=""
MARKETPLACE_NAME=""
CODEX_PLUGIN_NAME=""
PLUGIN_VERSION=""
MARKETPLACE_VERSION=""
CODEX_PLUGIN_VERSION=""

if ! PLUGIN_NAME="$(json_field "$PLUGIN_JSON" "name")"; then
    fail "plugin.json missing name"
fi

if ! MARKETPLACE_NAME="$(json_field "$MARKETPLACE_JSON" "name")"; then
    fail "marketplace.json missing name"
fi

if ! CODEX_PLUGIN_NAME="$(json_field "$CODEX_PLUGIN_JSON" "name")"; then
    fail "Codex plugin.json missing name"
fi

if ! PLUGIN_VERSION="$(json_field "$PLUGIN_JSON" "version")"; then
    fail "plugin.json missing version"
fi

if ! MARKETPLACE_VERSION="$(python3 - "$MARKETPLACE_JSON" <<'PY' 2>/dev/null
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)

version = data.get("version")
if not version:
    plugins = data.get("plugins") or []
    if plugins:
        version = plugins[0].get("version")

if not version:
    sys.exit(1)
print(version)
PY
)"; then
    fail "marketplace.json missing plugin version"
fi

if ! CODEX_PLUGIN_VERSION="$(json_field "$CODEX_PLUGIN_JSON" "version")"; then
    fail "Codex plugin.json missing version"
fi

if [ -n "$PLUGIN_NAME" ] && [ "$PLUGIN_NAME" = "$MARKETPLACE_NAME" ] && [ "$PLUGIN_NAME" = "$CODEX_PLUGIN_NAME" ]; then
    pass "Name parity: plugin.json ($PLUGIN_NAME) == marketplace.json ($MARKETPLACE_NAME) == Codex plugin.json ($CODEX_PLUGIN_NAME)"
else
    fail "Name mismatch: plugin.json ($PLUGIN_NAME), marketplace.json ($MARKETPLACE_NAME), Codex plugin.json ($CODEX_PLUGIN_NAME)"
fi

if [ -n "$PLUGIN_VERSION" ] && [ "$PLUGIN_VERSION" = "$MARKETPLACE_VERSION" ] && [ "$PLUGIN_VERSION" = "$CODEX_PLUGIN_VERSION" ]; then
    pass "Version parity: plugin.json ($PLUGIN_VERSION) == marketplace.json ($MARKETPLACE_VERSION) == Codex plugin.json ($CODEX_PLUGIN_VERSION)"
else
    fail "Version mismatch: plugin.json ($PLUGIN_VERSION), marketplace.json ($MARKETPLACE_VERSION), Codex plugin.json ($CODEX_PLUGIN_VERSION)"
fi

if python3 -c "import json, sys; d=json.load(open('$CODEX_PLUGIN_JSON')); sys.exit(0 if d.get('skills') == './.claude/skills/' else 1)" 2>/dev/null; then
    pass "Codex plugin skills path is ./.claude/skills/"
else
    fail "Codex plugin skills path must be ./.claude/skills/"
fi

# ── No mcpServers field ───────────────────────────────────────────────────────

if python3 -c "import json, sys; d=json.load(open('$PLUGIN_JSON')); sys.exit(0 if 'mcpServers' not in d else 1)" 2>/dev/null; then
    pass "plugin.json has no mcpServers field"
else
    fail "plugin.json must not contain mcpServers"
fi

# ── YAML frontmatter validation ───────────────────────────────────────────────

echo ""
echo "=== YAML Frontmatter Validation ==="

validate_frontmatter() {
    local file="$1"
    python3 - "$file" <<'EOF'
import sys, re

filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()

# Extract YAML frontmatter between --- delimiters (first occurrence)
match = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
if not match:
    print(f"  FAIL: {filepath} - no YAML frontmatter found")
    sys.exit(1)

frontmatter_text = match.group(1)

# Try strict YAML parse first; fall back to regex extraction for known-good fields
# (Some skill descriptions contain colons or special chars that defeat strict YAML)
meta = {}
try:
    import yaml
    parsed = yaml.safe_load(frontmatter_text)
    if isinstance(parsed, dict):
        meta = parsed
except Exception:
    pass

# Regex fallback: extract 'name' and detect 'description' presence
if not meta.get('name'):
    name_match = re.search(r'^name:\s*(.+)$', frontmatter_text, re.MULTILINE)
    if name_match:
        meta['name'] = name_match.group(1).strip().strip('"\'')

if 'description' not in meta:
    # Check for multiline block scalar (description: |) or inline
    if re.search(r'^description:', frontmatter_text, re.MULTILINE):
        meta['description'] = '__present__'

missing = [f for f in ('name', 'description') if not meta.get(f)]
if missing:
    print(f"  FAIL: {filepath} - missing fields: {missing}")
    sys.exit(1)
EOF
}

validate_skill_frontmatter() {
    local file="$1"
    local expected_name="$2"
    python3 - "$file" "$expected_name" <<'EOF'
import sys, re

filepath = sys.argv[1]
expected_name = sys.argv[2]
with open(filepath, 'r') as f:
    content = f.read()

match = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
if not match:
    print(f"  FAIL: {filepath} - no YAML frontmatter found")
    sys.exit(1)

frontmatter_text = match.group(1)

meta = {}
try:
    import yaml
    parsed = yaml.safe_load(frontmatter_text)
    if isinstance(parsed, dict):
        meta = parsed
except Exception:
    pass

if not meta.get('name'):
    name_match = re.search(r'^name:\s*(.+)$', frontmatter_text, re.MULTILINE)
    if name_match:
        meta['name'] = name_match.group(1).strip().strip('"\'')

if 'description' not in meta:
    if re.search(r'^description:', frontmatter_text, re.MULTILINE):
        meta['description'] = '__present__'

missing = [f for f in ('name', 'description') if not meta.get(f)]
if missing:
    print(f"  FAIL: {filepath} - missing fields: {missing}")
    sys.exit(1)

if meta['name'] != expected_name:
    print(f"  FAIL: {filepath} - name must be {expected_name!r} (got {meta['name']!r})")
    sys.exit(1)

if re.search(r'^allowed-tools:', frontmatter_text, re.MULTILINE):
    print(f"  NOTE: {filepath} - allowed-tools is optional host-specific metadata")
EOF
}

AGENTS_DIR="$REPO_ROOT/.claude/agents"
SKILLS_DIR="$REPO_ROOT/.claude/skills"
CODEX_SKILLS_DIR="$REPO_ROOT/.codex/skills"
CODEX_AGENTS_DIR="$REPO_ROOT/.codex/agents"

AGENT_COUNT=0
SKILL_COUNT=0
CODEX_SKILL_COUNT=0
CODEX_CUSTOM_AGENT_COUNT=0
FRONTMATTER_ERRORS=0

for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    if validate_frontmatter "$agent_file"; then
        pass "Agent: $(basename "$agent_file")"
    else
        ERRORS=$((ERRORS + 1))
        FRONTMATTER_ERRORS=$((FRONTMATTER_ERRORS + 1))
    fi
    AGENT_COUNT=$((AGENT_COUNT + 1))
done

for skill_dir in "$SKILLS_DIR"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_file="$skill_dir/SKILL.md"
    skill_name="$(basename "$skill_dir")"
    if [ -f "$skill_file" ]; then
        if validate_skill_frontmatter "$skill_file" "$skill_name"; then
            pass "Skill: $skill_name"
        else
            ERRORS=$((ERRORS + 1))
            FRONTMATTER_ERRORS=$((FRONTMATTER_ERRORS + 1))
        fi
    else
        fail "Skill directory $(basename "$skill_dir") has no SKILL.md"
    fi
    SKILL_COUNT=$((SKILL_COUNT + 1))
done

echo ""
echo "=== Codex Skills Validation ==="

if [ -d "$CODEX_SKILLS_DIR" ]; then
    pass "Codex skills directory exists"
else
    fail "Codex skills directory missing: $CODEX_SKILLS_DIR"
fi

for codex_skill in "$CODEX_SKILLS_DIR"/*; do
    [ -e "$codex_skill" ] || continue
    skill_name="$(basename "$codex_skill")"
    skill_file="$codex_skill/SKILL.md"
    expected_target="../../.claude/skills/$skill_name"
    if [ -L "$codex_skill" ]; then
        actual_target="$(readlink "$codex_skill")"
        if [ "$actual_target" = "$expected_target" ]; then
            pass "Codex Skill Symlink: $skill_name -> $actual_target"
        else
            fail "Codex skill entry $skill_name must point to $expected_target (got $actual_target)"
        fi
    else
        fail "Codex skill entry $skill_name must be a symlink to $expected_target"
    fi

    if [ -f "$skill_file" ]; then
        if validate_skill_frontmatter "$skill_file" "$skill_name"; then
            pass "Codex Skill: $skill_name"
        else
            ERRORS=$((ERRORS + 1))
            FRONTMATTER_ERRORS=$((FRONTMATTER_ERRORS + 1))
        fi
    else
        fail "Codex skill entry $skill_name has no resolvable SKILL.md"
    fi
    CODEX_SKILL_COUNT=$((CODEX_SKILL_COUNT + 1))
done

echo ""
echo "=== Codex Custom Agents Validation ==="

TOML_PYTHON="$(find_toml_python || true)"
if [ -n "$TOML_PYTHON" ]; then
    pass "TOML parser available: $TOML_PYTHON"
else
    fail "No Python with tomllib available for Codex custom agent TOML validation"
fi

validate_codex_custom_agent() {
    local agent_file="$1"
    local expected_name="$2"
    local expected_source=".claude/agents/$expected_name.md"
    if [ -z "$TOML_PYTHON" ]; then
        return 1
    fi
    "$TOML_PYTHON" - "$agent_file" "$expected_name" "$expected_source" "$REPO_ROOT" <<'EOF'
import sys
from pathlib import Path
import tomllib

agent_file = Path(sys.argv[1])
expected_name = sys.argv[2]
expected_source = sys.argv[3]
repo_root = Path(sys.argv[4])

try:
    data = tomllib.loads(agent_file.read_text())
except Exception as exc:
    print(f"  FAIL: {agent_file} - invalid TOML: {exc}")
    sys.exit(1)

missing = [field for field in ("name", "description", "developer_instructions") if not data.get(field)]
if missing:
    print(f"  FAIL: {agent_file} - missing fields: {missing}")
    sys.exit(1)

if data["name"] != expected_name:
    print(f"  FAIL: {agent_file} - name must be {expected_name!r} (got {data['name']!r})")
    sys.exit(1)

developer_instructions = data["developer_instructions"]
if expected_source not in developer_instructions:
    print(f"  FAIL: {agent_file} - developer_instructions must reference {expected_source}")
    sys.exit(1)

if not (repo_root / expected_source).is_file():
    print(f"  FAIL: {agent_file} - referenced source missing: {expected_source}")
    sys.exit(1)
EOF
}

if [ -d "$CODEX_AGENTS_DIR" ]; then
    pass "Codex custom agents directory exists"
else
    fail "Codex custom agents directory missing: $CODEX_AGENTS_DIR"
fi

for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    agent_name="$(basename "$agent_file" .md)"
    codex_agent="$CODEX_AGENTS_DIR/$agent_name.toml"
    if [ -f "$codex_agent" ]; then
        if validate_codex_custom_agent "$codex_agent" "$agent_name"; then
            pass "Codex Custom Agent: $agent_name"
        else
            ERRORS=$((ERRORS + 1))
        fi
    else
        fail "Codex custom agent missing: $agent_name.toml"
    fi
done

for codex_agent in "$CODEX_AGENTS_DIR"/*.toml; do
    [ -f "$codex_agent" ] || continue
    CODEX_CUSTOM_AGENT_COUNT=$((CODEX_CUSTOM_AGENT_COUNT + 1))
done

echo ""
echo "=== Codex Agent Installer Validation ==="

INSTALLER="$REPO_ROOT/scripts/install-codex-agents.sh"
TMP_INSTALL_PROJECT=""

validate_installed_codex_agents() {
    local target_agents_dir="$1"
    local target_skills_dir="$2"
    if [ -z "$TOML_PYTHON" ]; then
        return 1
    fi
    "$TOML_PYTHON" - "$target_agents_dir" "$target_skills_dir" <<'EOF'
import sys
import re
from pathlib import Path
import tomllib

target_dir = Path(sys.argv[1])
skills_dir = Path(sys.argv[2])
expected = {
    "iteration-executor",
    "iteration-prompt-designer",
    "knowledge-extractor",
    "project-planner",
    "stage-executor",
    "workflow-coach",
}

files = sorted(target_dir.glob("*.toml"))
actual = {path.stem for path in files}
if actual != expected:
    print(f"  FAIL: installed agent set mismatch: expected {sorted(expected)}, got {sorted(actual)}")
    sys.exit(1)

for path in files:
    try:
        data = tomllib.loads(path.read_text())
    except Exception as exc:
        print(f"  FAIL: {path} - invalid TOML: {exc}")
        sys.exit(1)

    missing = [field for field in ("name", "description", "developer_instructions") if not data.get(field)]
    if missing:
        print(f"  FAIL: {path} - missing fields: {missing}")
        sys.exit(1)

    if data["name"] != path.stem:
        print(f"  FAIL: {path} - name must be {path.stem!r} (got {data['name']!r})")
        sys.exit(1)

    instructions = data["developer_instructions"]
    preamble = instructions.split("--- BEGIN BAIME WORKFLOW SOURCE ---", 1)[0]
    if ".claude/agents/" in preamble:
        print(f"  FAIL: {path} - installed developer_instructions preamble must not reference .claude/agents/")
        sys.exit(1)
    if "Use the shared workflow source at" in preamble:
        print(f"  FAIL: {path} - installed developer_instructions preamble contains repo-local adapter wording")
        sys.exit(1)
    if "--- BEGIN BAIME WORKFLOW SOURCE ---" not in instructions:
        print(f"  FAIL: {path} - embedded BAIME workflow source marker missing")
        sys.exit(1)

for slug in expected:
    skill_dir = skills_dir / f"{slug}-agent"
    skill_file = skill_dir / "SKILL.md"
    policy_file = skill_dir / "agents" / "openai.yaml"
    if not skill_file.is_file():
        print(f"  FAIL: launcher skill missing: {skill_file}")
        sys.exit(1)
    content = skill_file.read_text()
    match = re.match(r"^---\s*\n(.*?)\n---", content, re.DOTALL)
    if not match:
        print(f"  FAIL: {skill_file} - missing YAML frontmatter")
        sys.exit(1)
    frontmatter = match.group(1)
    if f"name: {slug}-agent" not in frontmatter or "description:" not in frontmatter:
        print(f"  FAIL: {skill_file} - invalid launcher frontmatter")
        sys.exit(1)
    if f"`{slug}` custom agent" not in content:
        print(f"  FAIL: {skill_file} - does not point at {slug} custom agent")
        sys.exit(1)
    if not policy_file.is_file() or "allow_implicit_invocation: false" not in policy_file.read_text():
        print(f"  FAIL: {policy_file} - must disable implicit invocation")
        sys.exit(1)
EOF
}

if [ -x "$INSTALLER" ]; then
    pass "Codex agent installer exists and is executable"
else
    fail "Codex agent installer missing or not executable: scripts/install-codex-agents.sh"
fi

if [ -x "$INSTALLER" ]; then
    if "$INSTALLER" --scope user --dry-run >/dev/null 2>&1; then
        pass "Codex agent installer dry-run generates portable agents and launcher skills"
    else
        fail "Codex agent installer dry-run failed"
    fi

    TMP_INSTALL_PROJECT="$(mktemp -d)"
    if "$INSTALLER" --scope project --target "$TMP_INSTALL_PROJECT" >/dev/null 2>&1; then
        pass "Codex agent installer writes project-scoped agents and launcher skills"
    else
        fail "Codex agent installer project install failed"
    fi

    if [ -d "$TMP_INSTALL_PROJECT/.codex/agents" ] && [ -d "$TMP_INSTALL_PROJECT/.codex/skills" ] && validate_installed_codex_agents "$TMP_INSTALL_PROJECT/.codex/agents" "$TMP_INSTALL_PROJECT/.codex/skills"; then
        pass "Installed Codex custom agents and launcher skills are valid"
    else
        fail "Installed Codex custom agents or launcher skills are invalid"
    fi
fi

# ── Count assertions ──────────────────────────────────────────────────────────

echo ""
echo "=== Count Assertions ==="

EXPECTED_AGENTS=6
EXPECTED_SKILLS="$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
EXPECTED_CODEX_SKILLS="$(find "$CODEX_SKILLS_DIR" -maxdepth 1 -type l | wc -l | tr -d ' ')"
EXPECTED_CODEX_CUSTOM_AGENTS="$(find "$CODEX_AGENTS_DIR" -maxdepth 1 -type f -name '*.toml' | wc -l | tr -d ' ')"

if [ "$AGENT_COUNT" -eq "$EXPECTED_AGENTS" ]; then
    pass "Agent count: $AGENT_COUNT (expected $EXPECTED_AGENTS)"
else
    fail "Agent count: $AGENT_COUNT (expected $EXPECTED_AGENTS)"
fi

if [ "$SKILL_COUNT" -eq "$EXPECTED_SKILLS" ]; then
    pass "Skill count: $SKILL_COUNT (expected $EXPECTED_SKILLS)"
else
    fail "Skill count: $SKILL_COUNT (expected $EXPECTED_SKILLS)"
fi

if [ "$CODEX_SKILL_COUNT" -eq "$EXPECTED_CODEX_SKILLS" ]; then
    pass "Codex skill count: $CODEX_SKILL_COUNT (expected $EXPECTED_CODEX_SKILLS)"
else
    fail "Codex skill count: $CODEX_SKILL_COUNT (expected $EXPECTED_CODEX_SKILLS)"
fi

if [ "$CODEX_CUSTOM_AGENT_COUNT" -eq "$EXPECTED_CODEX_CUSTOM_AGENTS" ]; then
    pass "Codex custom agent count: $CODEX_CUSTOM_AGENT_COUNT (expected $EXPECTED_CODEX_CUSTOM_AGENTS)"
else
    fail "Codex custom agent count: $CODEX_CUSTOM_AGENT_COUNT (expected $EXPECTED_CODEX_CUSTOM_AGENTS)"
fi

# ── Forbidden agents check ────────────────────────────────────────────────────

echo ""
echo "=== Forbidden File Check ==="

for forbidden in "feature-developer.md" "phase-planner-executor.md"; do
    if [ -f "$AGENTS_DIR/$forbidden" ]; then
        fail "Forbidden agent present: $forbidden"
    else
        pass "Forbidden agent absent: $forbidden"
    fi
done

# ── no-mcp-dependency check for workflow-coach ───────────────────────────────

COACH_FILE="$AGENTS_DIR/workflow-coach.md"
if [ -f "$COACH_FILE" ]; then
    # Hard mcp_meta_cc calls are those NOT inside an optional section
    # Strategy: strip the optional section then check for mcp_meta_cc
    UNCONDITIONAL=$(python3 - "$COACH_FILE" <<'EOF'
import sys, re

with open(sys.argv[1]) as f:
    content = f.read()

# Remove optional enrichment blocks (lines after "## Optional" until next "##" or EOF)
optional_stripped = re.sub(
    r'(?m)^##\s+Optional.*?(?=^##|\Z)',
    '',
    content,
    flags=re.DOTALL | re.MULTILINE
)

matches = re.findall(r'mcp_meta_cc\.\w+\s*\(', optional_stripped)
print(len(matches))
EOF
)
    if [ "$UNCONDITIONAL" -eq 0 ]; then
        pass "workflow-coach.md has no unconditional mcp_meta_cc calls"
    else
        fail "workflow-coach.md has $UNCONDITIONAL unconditional mcp_meta_cc call(s)"
    fi
else
    fail "workflow-coach.md missing"
fi

# ── next-step-generation: no mcp_ calls ──────────────────────────────────────

NSG="$SKILLS_DIR/next-step-generation/SKILL.md"
if [ -f "$NSG" ]; then
    MCP_REFS=$(grep -c 'mcp_' "$NSG" || true)
    if [ "$MCP_REFS" -eq 0 ]; then
        pass "next-step-generation/SKILL.md has no mcp_ references"
    else
        fail "next-step-generation/SKILL.md has $MCP_REFS mcp_ reference(s)"
    fi
else
    fail "next-step-generation/SKILL.md missing"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Summary ==="
echo "Claude Agents: $AGENT_COUNT, Claude Skills: $SKILL_COUNT"
echo "Codex Custom Agents: $CODEX_CUSTOM_AGENT_COUNT, Codex Skills: $CODEX_SKILL_COUNT"
if [ "$ERRORS" -eq 0 ]; then
    echo ""
    echo "ALL CHECKS PASSED"
    exit 0
else
    echo ""
    echo "FAILED: $ERRORS error(s) found"
    exit 1
fi
