#!/bin/bash
# Establish .claude/skills/<skill> → plugin/skills/<skill> symlinks.
# Run this after a fresh clone or if symlinks are accidentally replaced with real dirs.
# See backlog/decisions/ADR-001-plugin-skills-single-source-of-truth.md
set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLAUDE_SKILLS="${REPO_ROOT}/.claude/skills"
PLUGIN_SKILLS="${REPO_ROOT}/plugin/skills"

ERRORS=0
CREATED=0
OK=0

for skill_dir in "$PLUGIN_SKILLS"/*/; do
  skill="$(basename "$skill_dir")"
  target="../../plugin/skills/${skill}"
  link="${CLAUDE_SKILLS}/${skill}"

  if [ -L "$link" ]; then
    current="$(readlink "$link")"
    if [ "$current" = "$target" ]; then
      echo "  OK:      .claude/skills/$skill -> $target"
      OK=$((OK + 1))
      continue
    else
      echo "  FIXING:  .claude/skills/$skill (was -> $current)"
      rm "$link"
    fi
  elif [ -e "$link" ]; then
    echo "  REPLACING real dir: .claude/skills/$skill"
    rm -rf "$link"
  fi

  ln -s "$target" "$link"
  echo "  CREATED: .claude/skills/$skill -> $target"
  CREATED=$((CREATED + 1))
done

echo ""
if [ $ERRORS -eq 0 ]; then
  echo "setup-skill-symlinks: OK=$OK created=$CREATED errors=0"
else
  echo "setup-skill-symlinks: FAILED with $ERRORS error(s)"
  exit 1
fi
