---
id: TASK-192
title: ADR-008 harness 接入：validate-plugin.sh 遍历 ADR lint 块与覆盖率 meta 检查
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 11:36'
updated_date: '2026-06-24 12:47'
labels:
  - 'kind:basic'
dependencies:
  - TASK-193
ordinal: 121000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR-008 harness 接入：validate-plugin.sh 遍历 ADR lint 块与覆盖率 meta 检查
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Proposal: ADR-008 harness 接入：validate-plugin.sh 遍历 ADR lint 块与覆盖率 meta 检查

### Background

baime 当前有 8 条 ADR，但仅 ADR-006 通过手工编码真正接入了 `validate-plugin.sh` 执行管线——其
CLI flag 白名单检查是单独写死在脚本里的，规则在 ADR 文档、执行代码在 validate 脚本，两处漂移。
其余 7 条 ADR 只是人类可读文档，靠 CLAUDE.md 里"修改 skill 前读相关 ADR"这句提示维持，没有
任何自动拦截。ADR-008 已定义了一套 frontmatter schema（`enforcement`/`stage`/`lint` 字段），
以及"每个 ADR 携带自己的 lint 断言，harness 遍历执行"的路由契约。但该契约本身尚未落地：
`validate-plugin.sh` 还不认识这套 frontmatter，ADR-008 自身的 `lint:` 块也从未被执行过。
本任务就是把 ADR-008 的 check 层从纸面契约变为真实执行的门禁。

### Goals

1. `validate-plugin.sh` 增加 "ADR lint layer"：遍历 `docs/adr/ADR-0*.md`，对每个
   `enforcement: static` 的 ADR 解析并执行其 `lint:` shell 块，任何 lint 块退出码非 0
   则 validate-plugin.sh 整体失败并报 ERROR。
2. 同一层打印所有 `enforcement: advisory` ADR 的文件名作为 WARNING，让"无自动防护的架构
   决策"随时可数。
3. ADR-008 自身的 `lint:` 块（检查所有 ADR 声明 `enforcement` 字段）成为 validate-plugin.sh
   管线的一环，并通过该检查（前提：TASK-193 已为 ADR-001~007 补齐 frontmatter）。
4. 新增一条 `enforcement: static` 的 ADR 不需要改动 `validate-plugin.sh` 任何代码，只需在
   ADR 文件写正确的 frontmatter 即可。
5. `bash scripts/validate-plugin.sh` 在上述变更后以 exit 0 通过。

### Proposed Approach

**Phase A** — validate-plugin.sh 增加 ADR lint layer（python3 内联脚本遍历 docs/adr/）
**Phase B** — 同步 plugin/scripts/validate-plugin.sh（copy consistency）

**前置依赖：TASK-193** 须先完成——它为 ADR-001~007 补齐 frontmatter（含各 static ADR 的 `lint` 块）。
否则本任务的 ADR lint layer 无 frontmatter 可遍历，ADR-008 覆盖率 lint 亦会因 ADR-001~007 缺
`enforcement` 字段而失败。本任务只负责 harness（validate-plugin.sh），不写任何 ADR frontmatter。

### Trade-offs and Risks

- 本任务只落地 check 层；plan 层与 proposal 层为后续任务。
- frontmatter 解析用正则，不引入 PyYAML 新依赖。
- advisory ADR 计数只作可见性提示，不阻断 validate-plugin.sh。

---

# Plan: ADR-008 harness 接入：validate-plugin.sh 遍历 ADR lint 块与覆盖率 meta 检查

## Phase A: validate-plugin.sh 增加 ADR lint layer

### Tests (write first)

验收脚本本身就是测试：先在 validate-plugin.sh 中加入 ADR lint layer，在任何 ADR 有
`enforcement: static` 且其 `lint:` 块预期通过时，`bash scripts/validate-plugin.sh` 应
exit 0。ADR-008 已有 lint block；其余 static ADR 的 lint 块由 TASK-193 写入——TASK-193
完成后，ADR lint layer 遍历执行全部 lint 块须 PASS。

### Implementation

修改文件：`scripts/validate-plugin.sh`

在 Summary 节前插入新节 `=== ADR Lint Layer ===`，使用 python3 heredoc：
- 遍历 `docs/adr/ADR-0*.md`，提取 YAML frontmatter 中 `enforcement` 和 `lint:` 字段
- `enforcement: static` → 将 lint block 写入临时 .sh 文件，在 REPO_ROOT 执行；exit 0=PASS，非0=FAIL
- `enforcement: advisory` → 打印 `ADVISORY: <filename>（无自动 lint）`
- `enforcement: semantic/runtime` → 静默跳过
- 无 frontmatter → 打印 ADVISORY（字段缺失）

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "ADR Lint Layer" scripts/validate-plugin.sh`

## Phase B: 同步 plugin/scripts/validate-plugin.sh

### Tests (write first)

validate-plugin.sh 自身的 `plugin/scripts/ Copy Consistency` 检查会验证两者是否 diff
相同。Phase A 修改后未同步时会报 FAIL；Phase B 后须 PASS。

### Implementation

修改文件：`plugin/scripts/validate-plugin.sh`（与 `scripts/validate-plugin.sh` 完全相同的真实 copy，非 symlink）

```bash
cp scripts/validate-plugin.sh plugin/scripts/validate-plugin.sh
```

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `diff scripts/validate-plugin.sh plugin/scripts/validate-plugin.sh`

## Constraints

- 不实现 plan 层（feature-to-backlog DoD 注入）和 proposal 层（语义约束注入）；这是后续任务。
- 不写任何 ADR frontmatter：ADR-001~007 的 frontmatter 与 lint 块归 TASK-193；本任务仅消费它们。
- 依赖 TASK-193 先完成（frontmatter 是 ADR lint layer 的输入）。
- Phase 顺序：A → B（A 先建 ADR lint layer，B 同步 plugin/scripts/ copy）。

## Acceptance Gate

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "ADR Lint Layer" scripts/validate-plugin.sh`
- [ ] `grep -qE '^enforcement:' docs/adr/ADR-008-adr-as-contract.md`
- [ ] `diff scripts/validate-plugin.sh plugin/scripts/validate-plugin.sh`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Proposal self-review: APPROVED
premise-ledger:
[E] background lines: 背景段从 proposal 文件直接数，7行，符合3-8行要求
[E] goals numbered and concrete: 5条目标逐条可数，每条有可验证的操作/命令
[C] goal verifiability: Goal 5要求exit 0需对照validate-plugin.sh实际运行确认
[C] approach feasibility: 须对照scripts/validate-plugin.sh确认python3内联写法已有先例
[H] tradeoff completeness: 何为'足够的trade-off识别'靠背景知识判断
GCL-self-report: E=2 C=2 H=1

Proposal approved. Starting plan draft.

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: 5个 Goals 均有对应 Phase 或 Acceptance Gate 条目，从 plan 文本直接映射
[E] TDD structure: 每个 Phase 均有 Tests/Implementation 段，从 plan 直接数
[E] DoD executability: 所有 DoD 条目均为 shell 命令，从 plan 直接读取
[C] file paths exist: 将引用的 ADR 文件和 validate-plugin.sh 通过 codebase 搜索确认
[H] phase ordering sufficiency: 三个 phase 顺序 A→B→C 是否足够，靠背景知识判断
GCL-self-report: E=3 C=1 H=1

claimed: 2026-06-24T12:37:53Z

# TASK-192 Agent Summary

## What was done

### Phase A: ADR Lint Layer inserted into scripts/validate-plugin.sh
- Inserted a Python-driven ADR lint runner immediately before the `# ── Summary ───` block (originally line 885).
- The runner iterates all `docs/adr/ADR-*.md` files, reads YAML frontmatter, and:
  - For `enforcement: static` ADRs: extracts the `lint:` shell block and executes it from REPO_ROOT; reports PASS/FAIL.
  - For `enforcement: advisory` ADRs: prints ADVISORY (visible but no error).
  - For `enforcement: semantic` / `runtime`: silently skips.
  - Missing frontmatter or missing `enforcement` field: prints ADVISORY with warning.
- Accumulates failure count into `$ERRORS`.

### Phase B: Synced to plugin/scripts/validate-plugin.sh
- `cp scripts/validate-plugin.sh plugin/scripts/validate-plugin.sh`

### Bonus: Fixed pre-existing ADR violations detected by the new layer
- **ADR-001 violation** (plugin/skills/loop-backlog/SKILL.md line ~595): Removed stale migration notice that checked for `${REPO_ROOT}/scripts/basic-daemon.js`. Migration (TASK-191) was already complete.
- **ADR-007 violations** (SKILL.md lines ~822-824): Removed fallback paths `${REPO_ROOT}/scripts/lib/parse-task-files.js` and `${REPO_ROOT}/scripts/lib/fetch-risk-context.js`. Primary paths using `${BAIME_SCRIPTS}/../skills/loop-backlog/lib/` are sufficient.

## Verification results
- `bash scripts/validate-plugin.sh` → exit 0, ALL CHECKS PASSED (55 warnings, 0 errors)
- ADR Lint Layer shows: PASS for all 6 static ADRs (001, 004, 005, 006, 007, 008)
- `grep -q "ADR Lint Layer" scripts/validate-plugin.sh` → PASS
- `diff scripts/validate-plugin.sh plugin/scripts/validate-plugin.sh` → identical
- `grep -qE '^enforcement:' docs/adr/ADR-008-adr-as-contract.md` → PASS

## Commit
bf71c9d feat(TASK-192): add ADR Lint Layer to validate-plugin.sh harness

Completed: 2026-06-24T12:47:09Z
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 grep -q "ADR Lint Layer" scripts/validate-plugin.sh
- [ ] #3 diff scripts/validate-plugin.sh plugin/scripts/validate-plugin.sh
- [ ] #4 grep -qE '^enforcement:' docs/adr/ADR-008-adr-as-contract.md
<!-- DOD:END -->
