#!/usr/bin/env bash

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS_DIR="$REPO_ROOT/.claude/agents"
CODEX_AGENTS_DIR="$REPO_ROOT/.codex/agents"

SCOPE=""
TARGET=""
DRY_RUN=0
FORCE=0
TMP_DIR=""
TOML_PYTHON=""
OVERLAY_DIR=""

usage() {
    cat <<'EOF'
Usage: bash scripts/install-codex-agents.sh --scope user|project [options]

Options:
  --scope user        Install agents to ${CODEX_HOME:-$HOME/.codex}/agents and launcher skills to ${CODEX_HOME:-$HOME/.codex}/skills.
  --scope project     Install agents to <target>/.codex/agents and launcher skills to <target>/.codex/skills.
  --target DIR        Project directory for --scope project.
  --dry-run           Generate and validate agents and launcher skills without writing files.
  --force             Overwrite existing BAIME agent TOML files and launcher skill directories.
  --help, -h          Show this help.

Examples:
  bash scripts/install-codex-agents.sh --scope user --dry-run
  bash scripts/install-codex-agents.sh --scope project --target /path/to/project
EOF
}

cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
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

while [ "$#" -gt 0 ]; do
    case "$1" in
        --scope)
            [ "$#" -ge 2 ] || fail "--scope requires a value"
            SCOPE="$2"
            shift
            ;;
        --target)
            [ "$#" -ge 2 ] || fail "--target requires a value"
            TARGET="$2"
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        --force)
            FORCE=1
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

case "$SCOPE" in
    user)
        if [ -n "$TARGET" ]; then
            fail "--target is only valid with --scope project"
        fi
        TARGET_AGENTS_DIR="${CODEX_HOME:-$HOME/.codex}/agents"
        TARGET_SKILLS_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
        ;;
    project)
        [ -n "$TARGET" ] || fail "--target is required with --scope project"
        TARGET_AGENTS_DIR="$TARGET/.codex/agents"
        TARGET_SKILLS_DIR="$TARGET/.codex/skills"
        ;;
    "")
        fail "--scope user|project is required"
        ;;
    *)
        fail "--scope must be user or project"
        ;;
esac

TOML_PYTHON="$(find_toml_python || true)"
if [ -z "$TOML_PYTHON" ]; then
    fail "Python 3.11+ with tomllib is required"
fi

[ -d "$AGENTS_DIR" ] || fail "missing shared agent source directory: $AGENTS_DIR"
[ -d "$CODEX_AGENTS_DIR" ] || fail "missing repo-local Codex agent adapter directory: $CODEX_AGENTS_DIR"

TMP_DIR="$(mktemp -d)"
[ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ] || fail "mktemp -d failed"
GENERATED_DIR="$TMP_DIR/agents"
GENERATED_SKILLS_DIR="$TMP_DIR/skills"
GENERATED_AGENT_LIST="$TMP_DIR/generated-agents.txt"
GENERATED_SKILL_LIST="$TMP_DIR/generated-skills.txt"
mkdir -p "$GENERATED_DIR"
mkdir -p "$GENERATED_SKILLS_DIR"

"$TOML_PYTHON" - "$REPO_ROOT" "$GENERATED_DIR" "$GENERATED_SKILLS_DIR" <<'PY'
import sys
from pathlib import Path
import tomllib

repo_root = Path(sys.argv[1])
generated_dir = Path(sys.argv[2])
generated_skills_dir = Path(sys.argv[3])
source_dir = repo_root / ".claude" / "agents"
adapter_dir = repo_root / ".codex" / "agents"

source_files = sorted(source_dir.glob("*.md"))
if len(source_files) != 6:
    print(f"expected 6 shared agent source files, found {len(source_files)}", file=sys.stderr)
    sys.exit(1)

def toml_string(value: str) -> str:
    escaped = (
        value
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\b", "\\b")
        .replace("\t", "\\t")
        .replace("\n", "\\n")
        .replace("\f", "\\f")
        .replace("\r", "\\r")
    )
    return f'"{escaped}"'

def render(slug: str, data: dict, source_text: str) -> str:
    description = data["description"]
    model_reasoning_effort = data.get("model_reasoning_effort")
    instructions = (
        f"You are the BAIME {slug} custom agent.\n\n"
        "The following BAIME workflow source is embedded so this installed Codex custom agent is portable. "
        "Preserve the workflow semantics in this source. If host-specific Claude syntax appears there, "
        "treat it as source material and adapt invocation details to Codex.\n\n"
        "--- BEGIN BAIME WORKFLOW SOURCE ---\n"
        f"{source_text.rstrip()}\n"
        "--- END BAIME WORKFLOW SOURCE ---\n"
    )

    lines = [
        f"name = {toml_string(slug)}",
        f"description = {toml_string(description)}",
        f"developer_instructions = {toml_string(instructions)}",
    ]
    if model_reasoning_effort:
        lines.append(f"model_reasoning_effort = {toml_string(str(model_reasoning_effort))}")
    return "\n".join(lines) + "\n"

def render_launcher_skill(slug: str, description: str) -> str:
    name = f"{slug}-agent"
    return f"""---
name: {name}
description: Codex skill-picker entrypoint for the BAIME {slug} workflow profile. Use when the user selects this skill or asks to run the {slug} agent workflow.
---

# BAIME {slug} Workflow Entrypoint

Use this skill as a selectable Codex entrypoint for the BAIME `{slug}` workflow profile.

When invoked:

1. Do not create, spawn, delegate to, or invoke another agent or subagent.
2. Do not invoke `$` skills recursively, including `${name}` itself.
3. Run the workflow in the current Codex session by loading and applying the installed BAIME `{slug}` agent instructions.
4. Read the installed TOML from `$CODEX_HOME/agents/{slug}.toml` when `CODEX_HOME` is set; otherwise read `$HOME/.codex/agents/{slug}.toml`.
5. Extract and follow the TOML `developer_instructions` for this turn, adapting host-specific details to the current Codex environment.
6. Preserve the user's request, files, paths, constraints, and acceptance criteria while applying those instructions.

Workflow purpose:

{description}

If the installed TOML file is missing or unreadable, tell the user to run `scripts/install-codex-agents.sh --scope user` or the matching project-scoped install command. Do not fall back to recursive delegation.
"""

for source_file in source_files:
    slug = source_file.stem
    adapter_file = adapter_dir / f"{slug}.toml"
    if not adapter_file.is_file():
        print(f"missing repo-local adapter for {slug}: {adapter_file}", file=sys.stderr)
        sys.exit(1)

    try:
        data = tomllib.loads(adapter_file.read_text())
    except Exception as exc:
        print(f"invalid adapter TOML for {slug}: {exc}", file=sys.stderr)
        sys.exit(1)

    missing = [field for field in ("name", "description", "developer_instructions") if not data.get(field)]
    if missing:
        print(f"adapter {adapter_file} missing fields: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)
    if data["name"] != slug:
        print(f"adapter {adapter_file} name must be {slug!r}, got {data['name']!r}", file=sys.stderr)
        sys.exit(1)

    source_text = source_file.read_text()
    generated_file = generated_dir / f"{slug}.toml"
    rendered = render(slug, data, source_text)
    generated_file.write_text(rendered)

    skill_dir = generated_skills_dir / f"{slug}-agent"
    (skill_dir / "agents").mkdir(parents=True, exist_ok=True)
    (skill_dir / "SKILL.md").write_text(render_launcher_skill(slug, data["description"]))
    (skill_dir / "agents" / "openai.yaml").write_text("policy:\n  allow_implicit_invocation: false\n")

    try:
        generated_data = tomllib.loads(rendered)
    except Exception as exc:
        print(f"generated TOML for {slug} is invalid: {exc}", file=sys.stderr)
        sys.exit(1)

    missing_generated = [field for field in ("name", "description", "developer_instructions") if not generated_data.get(field)]
    if missing_generated:
        print(f"generated TOML for {slug} missing fields: {', '.join(missing_generated)}", file=sys.stderr)
        sys.exit(1)
    if generated_data["name"] != slug:
        print(f"generated TOML for {slug} name mismatch", file=sys.stderr)
        sys.exit(1)
    generated_instructions = generated_data["developer_instructions"]
    preamble = generated_instructions.split("--- BEGIN BAIME WORKFLOW SOURCE ---", 1)[0]
    if ".claude/agents/" in preamble:
        print(f"generated TOML for {slug} preamble contains a .claude/agents/ path reference", file=sys.stderr)
        sys.exit(1)
    if "Use the shared workflow source at" in preamble:
        print(f"generated TOML for {slug} preamble contains repo-local adapter wording", file=sys.stderr)
        sys.exit(1)
    if source_text.strip() not in generated_data["developer_instructions"]:
        print(f"generated TOML for {slug} does not embed source content", file=sys.stderr)
        sys.exit(1)

print(f"generated {len(source_files)} portable Codex custom agent TOML files and launcher skills")
PY

find "$GENERATED_DIR" -maxdepth 1 -type f -name '*.toml' | sort > "$GENERATED_AGENT_LIST"
find "$GENERATED_SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | sort > "$GENERATED_SKILL_LIST"

GENERATED_AGENT_COUNT="$(wc -l < "$GENERATED_AGENT_LIST" | tr -d ' ')"
if [ "$GENERATED_AGENT_COUNT" -ne 6 ]; then
    fail "expected 6 generated agent TOML files, found $GENERATED_AGENT_COUNT"
fi

GENERATED_SKILL_COUNT="$(wc -l < "$GENERATED_SKILL_LIST" | tr -d ' ')"
if [ "$GENERATED_SKILL_COUNT" -ne 6 ]; then
    fail "expected 6 generated agent launcher skills, found $GENERATED_SKILL_COUNT"
fi

echo "BAIME Codex custom agent installer"
echo "Scope: $SCOPE"
echo "Target agents dir: $TARGET_AGENTS_DIR"
echo "Target launcher skills dir: $TARGET_SKILLS_DIR"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "Mode: dry-run"
else
    echo "Mode: install"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Planned agents:"
    while IFS= read -r generated_file; do
        echo "  $(basename "$generated_file" .toml) -> $TARGET_AGENTS_DIR/$(basename "$generated_file")"
    done < "$GENERATED_AGENT_LIST"
    echo "Planned launcher skills:"
    while IFS= read -r generated_skill_dir; do
        echo "  $(basename "$generated_skill_dir") -> $TARGET_SKILLS_DIR/$(basename "$generated_skill_dir")"
    done < "$GENERATED_SKILL_LIST"
    echo "DRY RUN: 6 agents and 6 launcher skills generated and validated; no files written."
    exit 0
fi

CONFLICTS=0
while IFS= read -r generated_file; do
    name="$(basename "$generated_file")"
    target_file="$TARGET_AGENTS_DIR/$name"
    if { [ -e "$target_file" ] || [ -L "$target_file" ]; } && [ "$FORCE" -ne 1 ]; then
        echo "CONFLICT: $target_file exists; rerun with --force to overwrite" >&2
        CONFLICTS=$((CONFLICTS + 1))
    fi
done < "$GENERATED_AGENT_LIST"
while IFS= read -r generated_skill_dir; do
    name="$(basename "$generated_skill_dir")"
    target_dir="$TARGET_SKILLS_DIR/$name"
    if { [ -e "$target_dir" ] || [ -L "$target_dir" ]; } && [ "$FORCE" -ne 1 ]; then
        echo "CONFLICT: $target_dir exists; rerun with --force to overwrite" >&2
        CONFLICTS=$((CONFLICTS + 1))
    fi
done < "$GENERATED_SKILL_LIST"

if [ "$CONFLICTS" -gt 0 ]; then
    fail "$CONFLICTS existing Codex agent or launcher skill path(s) would be overwritten"
fi

mkdir -p "$TARGET_AGENTS_DIR"
mkdir -p "$TARGET_SKILLS_DIR"
OVERLAY_DIR="$TMP_DIR/overlay"
rm -rf "$OVERLAY_DIR"
mkdir -p "$OVERLAY_DIR/agents" "$OVERLAY_DIR/skills"
while IFS= read -r generated_file; do
    cp "$generated_file" "$OVERLAY_DIR/agents/$(basename "$generated_file")" || fail "failed to stage $(basename "$generated_file")"
done < "$GENERATED_AGENT_LIST"
while IFS= read -r generated_skill_dir; do
    cp -R "$generated_skill_dir" "$OVERLAY_DIR/skills/$(basename "$generated_skill_dir")" || fail "failed to stage $(basename "$generated_skill_dir")"
done < "$GENERATED_SKILL_LIST"

while IFS= read -r generated_file; do
    staged_file="$OVERLAY_DIR/agents/$(basename "$generated_file")"
    cp "$staged_file" "$TARGET_AGENTS_DIR/$(basename "$generated_file")" || fail "failed to write $TARGET_AGENTS_DIR/$(basename "$generated_file")"
done < "$GENERATED_AGENT_LIST"
while IFS= read -r generated_skill_dir; do
    name="$(basename "$generated_skill_dir")"
    rm -rf "$TARGET_SKILLS_DIR/$name"
    cp -R "$OVERLAY_DIR/skills/$name" "$TARGET_SKILLS_DIR/$name" || fail "failed to write $TARGET_SKILLS_DIR/$name"
done < "$GENERATED_SKILL_LIST"

"$TOML_PYTHON" - "$TARGET_AGENTS_DIR" "$TARGET_SKILLS_DIR" <<'PY'
import sys
import re
from pathlib import Path
import tomllib

target_dir = Path(sys.argv[1])
skills_dir = Path(sys.argv[2])
files = sorted(target_dir.glob("*.toml"))
expected = {
    "iteration-executor",
    "iteration-prompt-designer",
    "knowledge-extractor",
    "project-planner",
    "stage-executor",
    "workflow-coach",
}
baime_files = [path for path in files if path.stem in expected]

if len(baime_files) != 6:
    print(f"expected 6 installed BAIME agent TOML files, found {len(baime_files)}", file=sys.stderr)
    sys.exit(1)

for path in baime_files:
    data = tomllib.loads(path.read_text())
    missing = [field for field in ("name", "description", "developer_instructions") if not data.get(field)]
    if missing:
        print(f"{path} missing fields: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)
    if data["name"] != path.stem:
        print(f"{path} name must be {path.stem!r}, got {data['name']!r}", file=sys.stderr)
        sys.exit(1)
    instructions = data["developer_instructions"]
    preamble = instructions.split("--- BEGIN BAIME WORKFLOW SOURCE ---", 1)[0]
    if ".claude/agents/" in preamble or "Use the shared workflow source at" in preamble:
        print(f"{path} preamble contains repo-local source path wording", file=sys.stderr)
        sys.exit(1)
    if "--- BEGIN BAIME WORKFLOW SOURCE ---" not in instructions:
        print(f"{path} does not contain embedded BAIME workflow source", file=sys.stderr)
        sys.exit(1)

for slug in expected:
    skill_dir = skills_dir / f"{slug}-agent"
    skill_file = skill_dir / "SKILL.md"
    policy_file = skill_dir / "agents" / "openai.yaml"
    if not skill_file.is_file():
        print(f"missing launcher skill: {skill_file}", file=sys.stderr)
        sys.exit(1)
    content = skill_file.read_text()
    match = re.match(r"^---\s*\n(.*?)\n---", content, re.DOTALL)
    if not match:
        print(f"{skill_file} missing frontmatter", file=sys.stderr)
        sys.exit(1)
    frontmatter = match.group(1)
    if f"name: {slug}-agent" not in frontmatter:
        print(f"{skill_file} has wrong skill name", file=sys.stderr)
        sys.exit(1)
    if "description:" not in frontmatter:
        print(f"{skill_file} missing description", file=sys.stderr)
        sys.exit(1)
    required_phrases = [
        "Do not create, spawn, delegate to, or invoke another agent or subagent.",
        f"Do not invoke `$` skills recursively, including `${slug}-agent` itself.",
        f"$CODEX_HOME/agents/{slug}.toml",
        f"$HOME/.codex/agents/{slug}.toml",
        "Do not fall back to recursive delegation.",
    ]
    for phrase in required_phrases:
        if phrase not in content:
            print(f"{skill_file} missing anti-recursion launcher phrase: {phrase}", file=sys.stderr)
            sys.exit(1)
    forbidden_phrases = [
        "Spawn or delegate",
        "spawn the custom agent",
        "Wait for the custom agent result",
    ]
    for phrase in forbidden_phrases:
        if phrase in content:
            print(f"{skill_file} contains recursive launcher wording: {phrase}", file=sys.stderr)
            sys.exit(1)
    if not policy_file.is_file() or "allow_implicit_invocation: false" not in policy_file.read_text():
        print(f"{policy_file} must disable implicit invocation", file=sys.stderr)
        sys.exit(1)
PY

echo "Installed agents:"
while IFS= read -r generated_file; do
    echo "  $(basename "$generated_file" .toml) -> $TARGET_AGENTS_DIR/$(basename "$generated_file")"
done < "$GENERATED_AGENT_LIST"
echo "Installed launcher skills:"
while IFS= read -r generated_skill_dir; do
    echo "  $(basename "$generated_skill_dir") -> $TARGET_SKILLS_DIR/$(basename "$generated_skill_dir")"
done < "$GENERATED_SKILL_LIST"
echo "DONE: 6 BAIME Codex custom agents and 6 launcher skills installed."
