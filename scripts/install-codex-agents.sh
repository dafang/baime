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
  --scope user        Install to ${CODEX_HOME:-$HOME/.codex}/agents.
  --scope project     Install to <target>/.codex/agents.
  --target DIR        Project directory for --scope project.
  --dry-run           Generate and validate agents without writing files.
  --force             Overwrite existing BAIME agent TOML files.
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
        ;;
    project)
        [ -n "$TARGET" ] || fail "--target is required with --scope project"
        TARGET_AGENTS_DIR="$TARGET/.codex/agents"
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
GENERATED_LIST="$TMP_DIR/generated-files.txt"
mkdir -p "$GENERATED_DIR"

"$TOML_PYTHON" - "$REPO_ROOT" "$GENERATED_DIR" <<'PY'
import sys
from pathlib import Path
import tomllib

repo_root = Path(sys.argv[1])
generated_dir = Path(sys.argv[2])
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

print(f"generated {len(source_files)} portable Codex custom agent TOML files")
PY

find "$GENERATED_DIR" -maxdepth 1 -type f -name '*.toml' | sort > "$GENERATED_LIST"

GENERATED_COUNT="$(wc -l < "$GENERATED_LIST" | tr -d ' ')"
if [ "$GENERATED_COUNT" -ne 6 ]; then
    fail "expected 6 generated agent TOML files, found $GENERATED_COUNT"
fi

echo "BAIME Codex custom agent installer"
echo "Scope: $SCOPE"
echo "Target agents dir: $TARGET_AGENTS_DIR"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "Mode: dry-run"
else
    echo "Mode: install"
fi

CONFLICTS=0
while IFS= read -r generated_file; do
    name="$(basename "$generated_file")"
    target_file="$TARGET_AGENTS_DIR/$name"
    if { [ -e "$target_file" ] || [ -L "$target_file" ]; } && [ "$FORCE" -ne 1 ]; then
        echo "CONFLICT: $target_file exists; rerun with --force to overwrite" >&2
        CONFLICTS=$((CONFLICTS + 1))
    fi
done < "$GENERATED_LIST"

if [ "$CONFLICTS" -gt 0 ]; then
    fail "$CONFLICTS existing agent file(s) would be overwritten"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Planned agents:"
    while IFS= read -r generated_file; do
        echo "  $(basename "$generated_file" .toml) -> $TARGET_AGENTS_DIR/$(basename "$generated_file")"
    done < "$GENERATED_LIST"
    echo "DRY RUN: 6 agents generated and validated; no files written."
    exit 0
fi

mkdir -p "$TARGET_AGENTS_DIR"
OVERLAY_DIR="$TMP_DIR/overlay"
rm -rf "$OVERLAY_DIR"
mkdir -p "$OVERLAY_DIR"
while IFS= read -r generated_file; do
    cp "$generated_file" "$OVERLAY_DIR/$(basename "$generated_file")" || fail "failed to stage $(basename "$generated_file")"
done < "$GENERATED_LIST"

while IFS= read -r generated_file; do
    staged_file="$OVERLAY_DIR/$(basename "$generated_file")"
    cp "$staged_file" "$TARGET_AGENTS_DIR/$(basename "$generated_file")" || fail "failed to write $TARGET_AGENTS_DIR/$(basename "$generated_file")"
done < "$GENERATED_LIST"

"$TOML_PYTHON" - "$TARGET_AGENTS_DIR" <<'PY'
import sys
from pathlib import Path
import tomllib

target_dir = Path(sys.argv[1])
files = sorted(target_dir.glob("*.toml"))
baime_files = [path for path in files if path.stem in {
    "iteration-executor",
    "iteration-prompt-designer",
    "knowledge-extractor",
    "project-planner",
    "stage-executor",
    "workflow-coach",
}]

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
PY

echo "Installed agents:"
while IFS= read -r generated_file; do
    echo "  $(basename "$generated_file" .toml) -> $TARGET_AGENTS_DIR/$(basename "$generated_file")"
done < "$GENERATED_LIST"
echo "DONE: 6 BAIME Codex custom agents installed."
