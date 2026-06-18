# Plan: 为 prompt engineering artifact（SKILL.md）建设分层自动测试与验证框架

Proposal: docs/proposals/proposal-skill-layered-test-framework.md

## Phase A: Layer 1 — 单测自动发现（unit test auto-discovery）

### Tests (write first)

Test cases to assert before implementing `run_skill_unit_tests` in validate-plugin.sh:

- `loop-backlog-daemon.test.js` is discovered and reported in validate-plugin.sh output
- validate-plugin.sh exits non-zero when a discovered `.test.js` exits 1
- validate-plugin.sh exits zero when all discovered tests pass
- A `.test.js` path that does not exist is silently skipped (no spurious FAIL)

Manual verification approach: temporarily replace `loop-backlog-daemon.test.js` with a stub that `process.exit(1)`, confirm validate-plugin.sh fails; restore the real file, confirm PASS.

### Implementation

File to modify:
- `/home/yale/work/baime/scripts/validate-plugin.sh` — add `run_skill_unit_tests()` function and `=== Unit Tests ===` section (~35 lines)

```bash
# ── Unit test auto-discovery ──────────────────────────────────────────────────

echo ""
echo "=== Unit Tests ==="

run_skill_unit_tests() {
  local test_dir="$REPO_ROOT/scripts"
  for test_file in "$test_dir"/*.test.js "$test_dir"/*.test.sh; do
    [ -f "$test_file" ] || continue
    local name
    name="$(basename "$test_file")"
    if [[ "$test_file" == *.test.js ]]; then
      if node "$test_file" >/dev/null 2>&1; then
        pass "unit test: $name"
      else
        fail "unit test: $name"
      fi
    elif [[ "$test_file" == *.test.sh ]]; then
      if bash "$test_file" >/dev/null 2>&1; then
        pass "unit test: $name"
      else
        fail "unit test: $name"
      fi
    fi
  done
}

run_skill_unit_tests
```

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash scripts/validate-plugin.sh 2>&1 | grep -q "unit test: loop-backlog-daemon.test.js"`
- [ ] `node scripts/loop-backlog-daemon.test.js`

---

## Phase B: Layer 2 — contracts: フォーマット定義とバリデーター

### Tests (write first)

Test cases to assert before implementing the contract validator:

- A SKILL.md with `contracts: [{grep: "pattern", target: self}]` where pattern exists → PASS reported
- A SKILL.md with `contracts: [{not-grep: "absent", target: self}]` where pattern is absent → PASS reported
- A SKILL.md with `contracts: [{grep: "missing", target: self}]` where pattern is absent → FAIL reported
- A SKILL.md with no `contracts:` field → silently skipped (no FAIL)
- validate-plugin.sh `=== Contract Tests ===` section header appears in output

Manual verification: create two minimal SKILL.md stubs in a temp dir to exercise pass/fail paths.

### Implementation

File to modify:
- `/home/yale/work/baime/scripts/validate-plugin.sh` — add `validate_contracts()` function and `=== Contract Tests ===` section (~70 lines)

Implementation approach:
1. Add a python3 inline script that extracts `contracts:` from YAML frontmatter; returns empty list if field absent
2. For each rule: resolve `target: self` → the SKILL.md file path; external path → `$REPO_ROOT/<path>`
3. Execute `grep -q "<pattern>" <file>` for `grep:` rules; `! grep -q "<pattern>" <file>` for `not-grep:` rules
4. Report `PASS: contracts[N] <skill>` or `FAIL: contracts[N] <skill> — <rule>`
5. Call `validate_contracts "$skill_file"` inside the existing `for skill_dir in "$SKILLS_DIR"/*/` loop

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash scripts/validate-plugin.sh 2>&1 | grep -q "Contract Tests"`
- [ ] `! python3 -c "import yaml; yaml.safe_load(open('plugin/skills/loop-backlog/SKILL.md').read().split('---')[1])" 2>&1 | grep -q "Error"`

---

## Phase C: loop-backlog の contracts: 追加 + 陳腐化スクリプト削除

### Tests (write first)

Test cases to assert before modifying loop-backlog/SKILL.md and deleting stale scripts:

- `plugin/skills/loop-backlog/SKILL.md` frontmatter contains `contracts:` key
- `validate-plugin.sh` reports PASS for all loop-backlog contract rules
- `scripts/test-loop-backlog-skill-monitor.sh` is absent
- `scripts/test-loop-backlog-skill-bootstrap.sh` is absent
- `scripts/test-loop-backlog-skill-template.sh` is absent

### Implementation

File to modify:
- `/home/yale/work/baime/plugin/skills/loop-backlog/SKILL.md` — add `contracts:` block to YAML frontmatter (~15 lines):

```yaml
contracts:
  - grep: "Monitor(persistent=true"
    target: self
  - not-grep: "schedule("
    target: self
  - grep: "loop-stop"
    target: self
  - grep: "## Shutdown"
    target: self
  - grep: "daemonBootstrap"
    target: self
  - grep: "Monitor"
    target: self
  - not-grep: "ScheduleWakeup"
    target: self
  - grep: "loop-backlog-daemon"
    target: self
  - grep: ".daemon.pid"
    target: self
```

Files to delete:
- `/home/yale/work/baime/scripts/test-loop-backlog-skill-monitor.sh`
- `/home/yale/work/baime/scripts/test-loop-backlog-skill-bootstrap.sh`
- `/home/yale/work/baime/scripts/test-loop-backlog-skill-template.sh`

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "contracts:" plugin/skills/loop-backlog/SKILL.md`
- [ ] `! test -f scripts/test-loop-backlog-skill-monitor.sh`
- [ ] `! test -f scripts/test-loop-backlog-skill-bootstrap.sh`
- [ ] `! test -f scripts/test-loop-backlog-skill-template.sh`

---

## Phase D: Layer 0 — validate-plugin.sh に静的内部一致性チェックを追加

### Tests (write first)

Test cases to assert before implementing `validate_skill_internals()`:

- A SKILL.md with `## Implementation` section missing a `### funcName` heading for a function called in `## Spec` → FAIL reported
- A SKILL.md with no `## Implementation` section → check silently skipped (no spurious FAIL)
- A SKILL.md whose body uses `Bash(` but `allowed-tools` omits `Bash` → WARNING reported
- A SKILL.md whose `allowed-tools` covers all tool keywords present → PASS reported
- All 23 existing SKILL.md files pass with zero new FAIL items (regressions forbidden)

Manual verification: create two minimal temp SKILL.md stubs to exercise pass/fail paths.

### Implementation

File to modify:
- `/home/yale/work/baime/scripts/validate-plugin.sh` — add `validate_skill_internals()` function and `=== Layer 0: Internal Consistency ===` section (~80 lines)

Three sub-checks in a single python3 inline script called per SKILL.md:

1. **Function coverage** (only when `## Implementation` exists):
   - Extract `funcName(` patterns from `## Spec` section (conservative regex: word-char sequences immediately followed by `(`)
   - Extract `### funcName` headings from `## Implementation` section
   - FAIL for each function in Spec missing a `### funcName` heading

2. **allowed-tools completeness** (WARNING, not FAIL, for existing skills):
   - Known tool set: `Bash`, `Read`, `Write`, `Edit`, `Glob`, `Grep`, `Monitor`, `Agent`, `Task`, `WebFetch`, `WebSearch`
   - Scan body (excluding frontmatter) for `ToolName(` patterns
   - Compare against `allowed-tools` value; report undeclared tools

3. **daemon-version consistency** (only when frontmatter has `daemon-version:` field):
   - Scan body for `// daemon-version: vN` or `# daemon-version: vN`
   - FAIL if value differs from frontmatter

Call `validate_skill_internals "$skill_file"` inside the existing skill loop.

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash scripts/validate-plugin.sh 2>&1 | grep -q "Layer 0"`
- [ ] `bash scripts/validate-plugin.sh 2>&1 | grep -c "FAIL" | xargs -I{} test {} -eq 0`

---

## Phase E: DoD テンプレート正規化 — task-to-backlog と feature-to-backlog

### Tests (write first)

Test cases to assert before modifying the skill Implementation sections:

- `plugin/skills/feature-to-backlog/SKILL.md` Implementation section contains `validate-plugin.sh`
- `plugin/skills/feature-to-backlog/SKILL.md` Implementation section contains `contracts:` guidance
- `plugin/skills/task-to-backlog/SKILL.md` Implementation section contains `validate-plugin.sh`
- Both skills still pass `bash scripts/validate-plugin.sh` with zero errors

### Implementation

Files to modify:

1. `/home/yale/work/baime/plugin/skills/feature-to-backlog/SKILL.md` — in the `## Implementation` section, find the final-phase DoD template block and append (~10 lines):

```markdown
Layer 0-2 gate — add as mandatory final-phase DoD items:
- [ ] `bash scripts/validate-plugin.sh`  (Layer 0-2 all green)
- [ ] `grep -q "contracts:" plugin/skills/<skill-name>/SKILL.md`  (≥1 contract rule present)
```

2. `/home/yale/work/baime/plugin/skills/task-to-backlog/SKILL.md` — same location in `## Implementation`, append (~8 lines):

```markdown
Layer 0-2 gate — add as mandatory final-phase DoD item:
- [ ] `bash scripts/validate-plugin.sh`  (Layer 0-2 all green)
```

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "validate-plugin.sh" plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `grep -q "validate-plugin.sh" plugin/skills/task-to-backlog/SKILL.md`
- [ ] `grep -q "contracts:" plugin/skills/feature-to-backlog/SKILL.md`

---

## Constraints

- Layer 3 smoke test scaffold (`run-smoke-test.sh`, `smoke/` directories) is out of scope for this plan; it is defined in proposal Goal 4 and belongs in a separate task.
- Layer 0 allowed-tools check reports at WARNING level (not FAIL) to avoid breaking existing green baseline; FAIL is reserved for function-coverage and daemon-version mismatches where evidence is unambiguous.
- Function coverage check is silently skipped for the 16 skills currently lacking `## Implementation`; no new regressions are permitted after this change.
- `contracts:` field is optional in frontmatter; absence is not an error for existing skills. Failing contract rules (pattern not found) increment ERRORS and cause non-zero exit.
- All new shell logic must be compatible with bash 4+; python3 and node are already in use and are the only permitted new runtime dependencies.
- Phases A, B, C, D each touch validate-plugin.sh; implement in order to avoid merge conflicts within a single worktree.

## Acceptance Gate

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash scripts/validate-plugin.sh 2>&1 | grep -q "unit test: loop-backlog-daemon.test.js"`
- [ ] `bash scripts/validate-plugin.sh 2>&1 | grep -q "Contract Tests"`
- [ ] `bash scripts/validate-plugin.sh 2>&1 | grep -q "Layer 0"`
- [ ] `! test -f scripts/test-loop-backlog-skill-monitor.sh`
- [ ] `! test -f scripts/test-loop-backlog-skill-bootstrap.sh`
- [ ] `grep -q "contracts:" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "validate-plugin.sh" plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `grep -q "validate-plugin.sh" plugin/skills/task-to-backlog/SKILL.md`
