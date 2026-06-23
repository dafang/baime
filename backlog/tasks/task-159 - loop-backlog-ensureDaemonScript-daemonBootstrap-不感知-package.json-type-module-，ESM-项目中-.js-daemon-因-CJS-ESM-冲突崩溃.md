---
id: TASK-159
title: >-
  loop-backlog ensureDaemonScript/daemonBootstrap 不感知 package.json "type":
  "module"，ESM 项目中 .js daemon 因 CJS/ESM 冲突崩溃
status: 'Basic: Done'
assignee: []
created_date: '2026-06-22 16:13'
updated_date: '2026-06-22 16:27'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
loop-backlog 的 ensureDaemonScript 和 daemonBootstrap 不感知 package.json "type": "module"，在 ESM 项目（如 archguard）中写入 scripts/basic-daemon.js 后 node 立即因 CommonJS/ESM 冲突崩溃，导致 Monitor 结束、worker 中断。需检测 "type": "module" 并在此类项目中改用 .cjs 后缀。
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: loop-backlog ensureDaemonScript/daemonBootstrap ESM/CJS 兼容性修复

## Background

`loop-backlog` 的 `ensureDaemonScript` 将 `basic-daemon.js` 以 CommonJS 格式（`'use strict'; const fs = require('fs');`）写入目标项目的 `scripts/` 目录。当目标项目的 `package.json` 包含 `"type": "module"` 时，Node.js 会将目录下所有 `.js` 文件视为 ESM 模块；CJS 语法（`require()`、`module.exports`）在 ESM 上下文中是非法的，Node.js 会立即抛出 `SyntaxError: Cannot use import statement in a module`（或 `require is not defined in ES module scope`）并退出。这导致 `daemonBootstrap` 启动的守护进程在写入 PID 文件之前崩溃，Monitor 的事件流立即终止，整个 `loop-backlog` worker 中断，所有后续的 Basic: Ready 事件无法触发。这个问题在 archguard 等 ESM-first 的 TypeScript/Node.js 项目中会必然复现，且没有明显的错误提示——守护进程无声消失，worker 陷入永久空转。

## Goals

1. 在 `ensureDaemonScript` 中，执行前检测目标项目 `package.json` 中的 `"type"` 字段：若值为 `"module"`，则将守护脚本写入 `scripts/basic-daemon.cjs` 而非 `scripts/basic-daemon.js`。
2. `daemonBootstrap` 中的 `node` 启动命令和 `DAEMON_SCRIPT` 变量引用均使用与 `ensureDaemonScript` 一致的路径（`.cjs` 或 `.js`），确保两处路径同步，不存在不一致。
3. 版本检测逻辑（`head -3 | grep daemon-version`）也作用于正确后缀的文件，避免每次启动都重写脚本。
4. `ensureDaemonTest` 中的测试文件同步使用 `.cjs` 后缀（当项目为 ESM 时），确保 `node scripts/basic-daemon.test.cjs` 能正常运行。
5. 修复后，在 `"type": "module"` 的项目中执行 `/loop-backlog`，守护进程能成功写入 PID 文件并持续运行，Monitor 事件流正常工作。

## Proposed Approach

在 `ensureDaemonScript` 的 bash 实现段新增一个 ESM 检测步骤：读取 `${REPO_ROOT}/package.json`（若存在），用 `grep` 或 `python3 -c / node -e` 提取 `"type"` 字段值；若为 `"module"`，则将 `DAEMON_SCRIPT` 变量设置为 `${REPO_ROOT}/scripts/basic-daemon.cjs`，否则保持 `basic-daemon.js`。同一检测结果以 shell 变量（如 `DAEMON_EXT`）传递到 `daemonBootstrap` 和 `ensureDaemonTest`，使三处路径引用共享同一来源，不重复检测。

`SKILL.md` 中的 `### ensureDaemonScript` 和 `### daemonBootstrap` 两个 bash 代码块需要同步更新；`plugin/scripts/basic-daemon.js`（作为仓库内的参考副本/默认模板）的文件名和内容保持不变，因为本仓库（baime）本身不是 ESM 项目。

无需修改 `basic-daemon.js` 的内容本身——CJS 语法在 `.cjs` 后缀下始终有效，Node.js 无论父项目 `"type"` 设置如何都会以 CommonJS 解析 `.cjs` 文件。

## Trade-offs and Risks

**不做的事：** 不将 `basic-daemon.js` 改写为 ESM 语法，因为 ESM 不支持 `require()` 的同步文件读取模式且会引入更大改动面；不支持 `.mjs` 后缀（`.cjs` 已足够解决问题）。

**已知风险：** 若目标项目通过 `.npmrc` 或工具链覆盖 Node.js 的模块解析行为（极少见），`.cjs` 策略仍然安全，因为 `.cjs` 是 Node.js 规范中强制 CommonJS 解析的官方机制。极少数项目可能在 `scripts/` 目录设置独立的 `package.json` 覆盖 `"type"`，此边界情况本提案不处理，留作后续迭代。

**替代方案考虑：** 曾考虑将守护脚本改写为 ESM（`import`/`export`），但会破坏 CJS 项目兼容性且实现复杂；也考虑用 `--input-type=commonjs` 标志，但该标志只适用于 `--eval`，不适用于文件执行。选用 `.cjs` 后缀是侵入性最小、最符合 Node.js 规范的方案。

---

# Plan: loop-backlog ensureDaemonScript/daemonBootstrap ESM/CJS 兼容性修复

Proposal: docs/proposals/proposal-loop-backlog-daemon-esm-cjs-compat.md

## Phase A: 在 ensureDaemonScript 中检测 ESM 并动态设置 DAEMON_SCRIPT / DAEMON_EXT

### Tests (write first)

These grep commands must FAIL before implementation (proving the fix is absent):

```bash
# A1: ensureDaemonScript 中尚无 DAEMON_EXT 变量
! grep -q 'DAEMON_EXT' plugin/skills/loop-backlog/SKILL.md

# A2: ensureDaemonScript 中尚无 package.json ESM 检测
! grep -q '"type".*module\|DAEMON_EXT\|basic-daemon\.cjs' plugin/skills/loop-backlog/SKILL.md

# A3: DAEMON_SCRIPT 硬编码为 .js（无条件分支）
grep -q 'DAEMON_SCRIPT=.*basic-daemon\.js"$' plugin/skills/loop-backlog/SKILL.md
```

After implementation, these must PASS:

```bash
# A4: DAEMON_EXT 变量出现在 ensureDaemonScript 代码块中
grep -q 'DAEMON_EXT' plugin/skills/loop-backlog/SKILL.md

# A5: basic-daemon.cjs 路径出现（ESM 分支）
grep -q 'basic-daemon\.cjs' plugin/skills/loop-backlog/SKILL.md

# A6: package.json type 检测逻辑存在
grep -q '"type"' plugin/skills/loop-backlog/SKILL.md
```

### Implementation

Edit `plugin/skills/loop-backlog/SKILL.md`, section `### ensureDaemonScript` (currently lines 517–707).

Replace the opening variable block:

```bash
DAEMON_SCRIPT="${REPO_ROOT}/scripts/basic-daemon.js"
DAEMON_VERSION="v7"
```

with:

```bash
# Detect ESM project: if package.json sets "type": "module", use .cjs suffix
DAEMON_EXT="js"
if [ -f "${REPO_ROOT}/package.json" ] && \
   node -e "const p=require('${REPO_ROOT}/package.json');process.exit(p.type==='module'?0:1)" \
   2>/dev/null; then
  DAEMON_EXT="cjs"
fi
DAEMON_SCRIPT="${REPO_ROOT}/scripts/basic-daemon.${DAEMON_EXT}"
DAEMON_VERSION="v7"
```

No other content in the heredoc changes. The `cat > "$DAEMON_SCRIPT" << 'DAEMON_EOF'` and its close `DAEMON_EOF` remain; Node.js treats `.cjs` as CJS regardless of the project's `"type"` setting.

Also export `DAEMON_EXT` at the end of the `### ensureDaemonScript` block (after `fi`) so Phase B can consume it without re-detecting:

```bash
export DAEMON_EXT
```

Estimated change: ~8 lines added, 2 lines modified — well within 200-line limit.

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'DAEMON_EXT' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'basic-daemon\.cjs' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q '"type"' plugin/skills/loop-backlog/SKILL.md`
- [ ] `! grep -q 'DAEMON_SCRIPT=.*basic-daemon\.js"$' plugin/skills/loop-backlog/SKILL.md`

---

## Phase B: 在 daemonBootstrap 中使用 DAEMON_EXT / DAEMON_SCRIPT

### Tests (write first)

These grep commands must FAIL before implementation:

```bash
# B1: daemonBootstrap 中硬编码了 basic-daemon.js（无变量引用）
grep -A 30 '### daemonBootstrap' plugin/skills/loop-backlog/SKILL.md \
  | grep -q 'scripts/basic-daemon\.js'

# B2: daemonBootstrap 中尚无 DAEMON_SCRIPT 变量引用
! grep -A 30 '### daemonBootstrap' plugin/skills/loop-backlog/SKILL.md \
  | grep -q '\$DAEMON_SCRIPT\|DAEMON_EXT'
```

After implementation, these must PASS:

```bash
# B3: daemonBootstrap 使用 $DAEMON_SCRIPT 变量而非硬编码路径
grep -A 30 '### daemonBootstrap' plugin/skills/loop-backlog/SKILL.md \
  | grep -q '\$DAEMON_SCRIPT'

# B4: daemonBootstrap 中不再出现硬编码的 basic-daemon.js
! grep -A 30 '### daemonBootstrap' plugin/skills/loop-backlog/SKILL.md \
  | grep -q 'scripts/basic-daemon\.js[^"]'
```

### Implementation

Edit `plugin/skills/loop-backlog/SKILL.md`, section `### daemonBootstrap` (currently lines 837–875).

Replace the hard-coded `nohup node` line:

```bash
  nohup node "${REPO_ROOT}/scripts/basic-daemon.js" \
```

with:

```bash
  nohup node "$DAEMON_SCRIPT" \
```

Also add a guard at the top of the `daemonBootstrap` bash block (before the `BACKLOG_DIR` assignment) to re-detect `DAEMON_EXT` if it was not exported by `ensureDaemonScript` (defensive, for callers that skip the write step):

```bash
# Re-derive DAEMON_SCRIPT if not already set by ensureDaemonScript
if [ -z "${DAEMON_SCRIPT:-}" ]; then
  DAEMON_EXT="js"
  if [ -f "${REPO_ROOT}/package.json" ] && \
     node -e "const p=require('${REPO_ROOT}/package.json');process.exit(p.type==='module'?0:1)" \
     2>/dev/null; then
    DAEMON_EXT="cjs"
  fi
  DAEMON_SCRIPT="${REPO_ROOT}/scripts/basic-daemon.${DAEMON_EXT}"
fi
```

Estimated change: ~10 lines added, 1 line modified — well within 200-line limit.

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -A 30 '### daemonBootstrap' plugin/skills/loop-backlog/SKILL.md | grep -q '\$DAEMON_SCRIPT'`
- [ ] `! grep -A 30 '### daemonBootstrap' plugin/skills/loop-backlog/SKILL.md | grep -q 'scripts/basic-daemon\.js[^"]'`

---

## Phase C: 在 ensureDaemonTest 中同步使用 DAEMON_EXT 后缀

### Tests (write first)

```bash
# C1: ensureDaemonTest 中 TEST_SCRIPT 硬编码为 .test.js（无条件）
grep -A 5 '### ensureDaemonTest' plugin/skills/loop-backlog/SKILL.md \
  | grep -q 'basic-daemon\.test\.js"$'

# C2: 无 DAEMON_EXT 或 .test.cjs 引用
! grep -A 20 '### ensureDaemonTest' plugin/skills/loop-backlog/SKILL.md \
  | grep -q 'test\.cjs\|DAEMON_EXT'
```

After implementation:

```bash
# C3: TEST_SCRIPT 使用 DAEMON_EXT 变量
grep -A 5 '### ensureDaemonTest' plugin/skills/loop-backlog/SKILL.md \
  | grep -q 'DAEMON_EXT\|basic-daemon\.test\.\${DAEMON_EXT}'

# C4: validate-plugin.sh 中的 unit test runner 支持 .test.cjs（或仍匹配 .test.js）
grep -q '\.test\.js\|\.test\.cjs\|\*\.test\.' scripts/validate-plugin.sh
```

### Implementation

Edit `plugin/skills/loop-backlog/SKILL.md`, section `### ensureDaemonTest` (currently lines 709–835).

Replace:

```bash
TEST_SCRIPT="${REPO_ROOT}/scripts/basic-daemon.test.js"
```

with:

```bash
# Use same extension as daemon script (cjs when target project is ESM)
TEST_EXT="${DAEMON_EXT:-js}"
TEST_SCRIPT="${REPO_ROOT}/scripts/basic-daemon.test.${TEST_EXT}"
```

Also replace the `node "$TEST_SCRIPT"` line's guard check: the `if [ ! -f "$TEST_SCRIPT" ]` block correctly uses `$TEST_SCRIPT`, so no additional change is needed there.

Note: `scripts/validate-plugin.sh` unit test runner (lines 262–279) scans `scripts/*.test.js` and `scripts/*.test.sh`. For `.cjs` files to be picked up, we must also update the glob. Edit `scripts/validate-plugin.sh` line 262:

Replace:

```bash
  for test_file in "$test_dir"/*.test.js "$test_dir"/*.test.sh; do
```

with:

```bash
  for test_file in "$test_dir"/*.test.js "$test_dir"/*.test.cjs "$test_dir"/*.test.sh; do
```

And add handling for `.test.cjs` alongside `.test.js` at line 267:

```bash
    if [[ "$test_file" == *.test.js ]] || [[ "$test_file" == *.test.cjs ]]; then
```

Also copy the updated `validate-plugin.sh` to `plugin/scripts/validate-plugin.sh` to keep them in sync (required by the copy-consistency check in validate-plugin.sh itself):

```bash
cp scripts/validate-plugin.sh plugin/scripts/validate-plugin.sh
```

Estimated change: ~4 lines in SKILL.md + ~3 lines in validate-plugin.sh — well within 200-line limit.

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -A 5 '### ensureDaemonTest' plugin/skills/loop-backlog/SKILL.md | grep -q 'DAEMON_EXT\|test\.\${TEST_EXT}'`
- [ ] `grep -q '\.test\.cjs' scripts/validate-plugin.sh`
- [ ] `diff -q scripts/validate-plugin.sh plugin/scripts/validate-plugin.sh`

---

## Constraints

- `plugin/scripts/basic-daemon.js` content is NOT changed (only SKILL.md references change)
- No new files added to `plugin/scripts/`
- `validate-plugin.sh` contract count (`EXPECTED_SKILLS=25`) unchanged
- Each Phase ≤ 200 lines of change
- All DoD absence checks use `! grep -q <pattern> <file>` form (not `grep -qv`)

## Acceptance Gate

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'DAEMON_EXT' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'basic-daemon\.cjs' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -A 30 '### daemonBootstrap' plugin/skills/loop-backlog/SKILL.md | grep -q '\$DAEMON_SCRIPT'`
- [ ] `! grep -A 30 '### daemonBootstrap' plugin/skills/loop-backlog/SKILL.md | grep -q 'scripts/basic-daemon\.js[^"]'`
- [ ] `grep -q '\.test\.cjs' scripts/validate-plugin.sh`
- [ ] `diff -q scripts/validate-plugin.sh plugin/scripts/validate-plugin.sh`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Proposal approved. Starting plan draft.

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: Goal 1 → Phase A (ESM detection + DAEMON_SCRIPT/.cjs write); Goal 2 → Phase B (daemonBootstrap uses $DAEMON_SCRIPT); Goal 3 → Phase A (version check uses $DAEMON_SCRIPT variable, covers correct suffix); Goal 4 → Phase C (ensureDaemonTest uses DAEMON_EXT); Goal 5 → all three phases combined, validated by Acceptance Gate
[E] TDD structure: all three phases have ### Tests before ### Implementation; first DoD item in each phase is bash scripts/validate-plugin.sh; Acceptance Gate first item is bash scripts/validate-plugin.sh
[C] file paths exist: plugin/skills/loop-backlog/SKILL.md confirmed (ensureDaemonScript at line 517, ensureDaemonTest at 709, daemonBootstrap at 837 — all match); scripts/validate-plugin.sh confirmed (test glob at line 262 matches plan's target lines); plugin/scripts/validate-plugin.sh confirmed; plugin/scripts/basic-daemon.js confirmed
[H] DoD sufficiency baseline: all DoD items are executable shell commands; absence checks use ! grep -q (not grep -qv); phase ordering is acyclic (A exports DAEMON_EXT → B and C consume it); no scope creep beyond stated goals
GCL-self-report: E=2 C=1 H=1

claimed: 2026-06-22T16:23:20Z

## Execution Summary
Result: Done
Commit: cf035b8

Completed: 2026-06-22T16:27:07Z
## Execution Summary
Result: Done
Commit: 80be4134f98317a0f6e7e7d0bb5115d72e31e7f1
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 grep -q 'DAEMON_EXT' plugin/skills/loop-backlog/SKILL.md
- [ ] #3 grep -q 'basic-daemon\.cjs' plugin/skills/loop-backlog/SKILL.md
- [ ] #4 grep -q '"type"' plugin/skills/loop-backlog/SKILL.md
- [ ] #5 ! grep -q 'DAEMON_SCRIPT=.*basic-daemon\.js"$' plugin/skills/loop-backlog/SKILL.md
- [ ] #6 bash scripts/validate-plugin.sh
- [ ] #7 grep -A 30 '### daemonBootstrap' plugin/skills/loop-backlog/SKILL.md | grep -q '\$DAEMON_SCRIPT'
- [ ] #8 ! grep -A 30 '### daemonBootstrap' plugin/skills/loop-backlog/SKILL.md | grep -q 'scripts/basic-daemon\.js[^"]'
- [ ] #9 bash scripts/validate-plugin.sh
- [ ] #10 grep -A 5 '### ensureDaemonTest' plugin/skills/loop-backlog/SKILL.md | grep -q 'DAEMON_EXT\|test\.\${TEST_EXT}'
- [ ] #11 grep -q '\.test\.cjs' scripts/validate-plugin.sh
- [ ] #12 diff -q scripts/validate-plugin.sh plugin/scripts/validate-plugin.sh
- [ ] #13 bash scripts/validate-plugin.sh
- [ ] #14 grep -q 'DAEMON_EXT' plugin/skills/loop-backlog/SKILL.md
- [ ] #15 grep -q 'basic-daemon\.cjs' plugin/skills/loop-backlog/SKILL.md
- [ ] #16 grep -A 30 '### daemonBootstrap' plugin/skills/loop-backlog/SKILL.md | grep -q '\$DAEMON_SCRIPT'
- [ ] #17 ! grep -A 30 '### daemonBootstrap' plugin/skills/loop-backlog/SKILL.md | grep -q 'scripts/basic-daemon\.js[^"]'
- [ ] #18 grep -q '\.test\.cjs' scripts/validate-plugin.sh
- [ ] #19 diff -q scripts/validate-plugin.sh plugin/scripts/validate-plugin.sh
- [ ] #20 bash scripts/validate-plugin.sh
- [ ] #21 grep -q 'contracts:' plugin/skills/loop-backlog/SKILL.md
<!-- DOD:END -->
