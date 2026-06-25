---
id: TASK-193
title: 现有 ADR 001-007 迁移至 ADR-008 frontmatter schema
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 11:36'
updated_date: '2026-06-24 12:18'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
现有 ADR 001-007 迁移至 ADR-008 frontmatter schema
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Proposal: 现有 ADR 001-007 迁移至 ADR-008 frontmatter schema

## Background

ADR-008 确立了一套 7 字段 YAML frontmatter schema（adr、title、status、applies-to、enforcement、stage、lint），并在 `validate-plugin.sh` 的 lint 块中声明：凡 `enforcement: static` 的 ADR 必须附带可执行的 `lint` shell 断言；每个 ADR 必须声明 `enforcement` 字段。然而现有 ADR-001 至 ADR-007 均无 frontmatter（ADR-007 有部分 frontmatter 但缺少 enforcement/stage/lint 字段），导致 ADR-008 本身的 lint 检查（`grep -qE '^enforcement:...'`）立即失败。这一矛盾使 ADR-008 所描述的"静态后防线"在落地的第一天就处于断裂状态：schema 已定义，但无一历史 ADR 符合它。迁移不完成，validate-plugin.sh 的 ADR 覆盖率检查就无法通过，整套 ADR-as-contract 机制形同虚设。

## Goals

1. ADR-001 至 ADR-007 每个文件均新增符合 ADR-008 schema 的 YAML frontmatter（7 个字段全部填写），且内容与各 ADR 正文描述的决策语义一致。
2. `bash scripts/validate-plugin.sh` 在迁移后以 0 错误通过，且 ADR-008 的覆盖率 lint 块（检查所有 ADR 含 enforcement 字段）输出通过。
3. ADR-001/004/005/006/007（enforcement: static）各自附带 `lint` shell 断言，可从 REPO_ROOT 独立执行并以 exit 0 表示合规；凡有既有 canonical 检查脚本者（ADR-005→verify-kind-status.sh、ADR-006→backlog-cli-contract.json），lint 委托调用之而非重复实现。
4. ADR-002（enforcement: runtime）和 ADR-003（enforcement: semantic）不附 lint 块，frontmatter 中 `lint` 字段为 null 或省略，体现分类路由思想。
5. ADR-007 现有的不完整 frontmatter（缺 enforcement/stage/lint）被替换为完整的 ADR-008 兼容 frontmatter。

## Proposed Approach

逐文件在 `docs/adr/` 目录下为 ADR-001 至 ADR-007 预置 YAML frontmatter（`---` 分隔符之间）。

**分类原则（lint 委托而非重复实现）**：凡已有可复用的 canonical 检查脚本，ADR 的 `lint` 块直接调用它，不另写一份逻辑（杜绝 ADR-008 §65-68 警告的"规则在 ADR、代码在 validate-plugin.sh"两处漂移）；仅当无既有可复用脚本时，`lint` 块本身即该决策的单一 canonical 来源。

每条 frontmatter 的核心决策点：

- **ADR-001**（Daemon 脚本归属 plugin）：`enforcement: static`；无既有可复用脚本 → lint 块自包含（grep 检查 loop-backlog SKILL.md 中无直接 REPO_ROOT/scripts/basic-daemon 引用），即 canonical 单一来源。
- **ADR-002**（Monitor 生命周期）：`enforcement: runtime`；`lint: null`；`stage: [plan]`。
- **ADR-003**（prompt 自包含）：`enforcement: semantic`；`lint: null`；`stage: [proposal, plan]`。
- **ADR-004**（Skill 类型命名前缀）：`enforcement: static`；无既有可复用脚本 → lint 块自包含（grep 检查裸 TypeScript 类型定义），即 canonical 单一来源。
- **ADR-005**（kind 标签必填）：`enforcement: static`；**委托**既有 canonical 检查 `bash scripts/verify-kind-status.sh`（validate-plugin.sh §741 已调用同一脚本），不重复实现。
- **ADR-006**（CLI flag 白名单）：`enforcement: static`；**委托**——lint 验证 canonical 白名单数据 `scripts/backlog-cli-contract.json` 存在（validate-plugin.sh §824 同源消费）。
- **ADR-007**（Plugin script residency）：`enforcement: static`；无既有可复用脚本 → lint 块自包含（grep 检查 SKILL.md 中无不合规 REPO_ROOT/scripts/ 引用），即 canonical 单一来源。

## Trade-offs and Risks

**不做什么**：不修改 validate-plugin.sh；不修改 ADR 正文；不添加新 ADR；不修改 ADR-008。

**已知风险**：lint 模式过宽可能误报；ADR-007 替换现有 frontmatter 须保留正文；ADR-004 lint 采用保守范围。

---

# Plan: 现有 ADR 001-007 迁移至 ADR-008 frontmatter schema

Proposal: stored in TASK-193 Implementation Plan field

## Phase A: 为 ADR-002 和 ADR-003 添加 frontmatter（runtime/semantic，无 lint）

### Tests (write first)

验证 ADR-002 存在 enforcement 字段且值为 runtime：
```
grep -qE '^enforcement:\s*runtime\s*$' docs/adr/ADR-002-monitor-lifecycle.md
```

验证 ADR-003 存在 enforcement 字段且值为 semantic：
```
grep -qE '^enforcement:\s*semantic\s*$' docs/adr/ADR-003-monitor-prompt-self-contained.md
```

验证两者均无 lint 块（lint: null 或不含 lint 字段）：
```
! grep -q '^lint:' docs/adr/ADR-002-monitor-lifecycle.md || grep -q '^lint: null' docs/adr/ADR-002-monitor-lifecycle.md
! grep -q '^lint:' docs/adr/ADR-003-monitor-prompt-self-contained.md || grep -q '^lint: null' docs/adr/ADR-003-monitor-prompt-self-contained.md
```

### Implementation

修改 `docs/adr/ADR-002-monitor-lifecycle.md`：在文件头部插入 YAML frontmatter。
修改 `docs/adr/ADR-003-monitor-prompt-self-contained.md`：在文件头部插入 YAML frontmatter。

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -qE '^enforcement:\s*runtime\s*$' docs/adr/ADR-002-monitor-lifecycle.md`
- [ ] `grep -qE '^enforcement:\s*semantic\s*$' docs/adr/ADR-003-monitor-prompt-self-contained.md`

---

## Phase B: 为 ADR-001 添加 frontmatter（static + lint）

### Tests (write first)

验证 ADR-001 存在 enforcement: static：
```
grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-001-daemon-script-location.md
```

验证 ADR-001 含有 lint 块：
```
grep -q '^lint: |' docs/adr/ADR-001-daemon-script-location.md
```

### Implementation

修改 `docs/adr/ADR-001-daemon-script-location.md`：在文件头部插入 YAML frontmatter，包含检查 REPO_ROOT/scripts/basic-daemon 引用的 lint 块。

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-001-daemon-script-location.md`
- [ ] `grep -q 'adr: "001"' docs/adr/ADR-001-daemon-script-location.md`

---

## Phase C: 为 ADR-004 和 ADR-005 添加 frontmatter（static + lint）

### Tests (write first)

验证 ADR-004 存在 enforcement: static：
```
grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-004-skill-type-naming.md
```

验证 ADR-005 存在 enforcement: static：
```
grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-005-task-creation-kind-label.md
```

验证 ADR-005 lint 通过（委托既有 canonical 检查 verify-kind-status.sh）：
```
bash scripts/verify-kind-status.sh
```

### Implementation

修改 `docs/adr/ADR-004-skill-type-naming.md`：在文件头部插入 YAML frontmatter，包含检查裸 TypeScript 类型定义的 lint 块。
修改 `docs/adr/ADR-005-task-creation-kind-label.md`：在文件头部插入 YAML frontmatter，包含检查 task_create kind 标签的 lint 块。

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-004-skill-type-naming.md`
- [ ] `grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-005-task-creation-kind-label.md`
- [ ] `bash scripts/verify-kind-status.sh`

---

## Phase D: 为 ADR-006 和 ADR-007 添加 frontmatter（static + lint）

### Tests (write first)

验证 ADR-006 存在 enforcement: static：
```
grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-006-backlog-cli-flag-whitelist.md
```

验证 ADR-007 存在 enforcement: static（替换现有不完整 frontmatter）：
```
grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-007-plugin-script-residency.md
```

验证 ADR-007 lint 通过（SKILL.md 中无不合规的 REPO_ROOT/scripts/ 引用）：
```
bash -c 'violations=0; for f in plugin/skills/*/SKILL.md; do while IFS= read -r line; do if echo "$line" | grep -qE "\$\{?REPO_ROOT\}?/scripts/" && ! echo "$line" | grep -q "BAIME_SCRIPTS"; then echo "ADR-007 violation in $f: $line"; violations=$((violations+1)); fi; done < "$f"; done; test "$violations" = "0"'
```

### Implementation

修改 `docs/adr/ADR-006-backlog-cli-flag-whitelist.md`：在文件头部插入 YAML frontmatter，lint 验证 backlog-cli-contract.json 存在。
修改 `docs/adr/ADR-007-plugin-script-residency.md`：替换现有 frontmatter，补充 applies-to/enforcement/stage/lint 字段。

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-006-backlog-cli-flag-whitelist.md`
- [ ] `grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-007-plugin-script-residency.md`
- [ ] `grep -q 'adr: "007"' docs/adr/ADR-007-plugin-script-residency.md`
- [ ] `test -f scripts/backlog-cli-contract.json`

---

## Phase E: 验证 ADR-008 覆盖率 lint 通过

### Tests (write first)

验证所有 ADR-001 至 ADR-008 均含 enforcement 字段（ADR-008 lint 块的实际内容）：
```
bash -c 'missing=0; for f in docs/adr/ADR-0*.md; do grep -qE "^enforcement:\s*(static|semantic|runtime|advisory)\s*$" "$f" || { echo "ADR missing enforcement: $f"; missing=1; }; done; test "$missing" = "0"'
```

### Implementation

无代码改动。此阶段仅为验证阶段 A–D 的叠加效果是否满足 ADR-008 meta-lint 条件。

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash -c 'missing=0; for f in docs/adr/ADR-0*.md; do grep -qE "^enforcement:\s*(static|semantic|runtime|advisory)\s*$" "$f" || { echo "ADR missing enforcement: $f"; missing=1; }; done; test "$missing" = "0"'`

---

## Constraints

- 每个 ADR 的正文（`## Context`、`## Decision`、`## Consequences` 等章节）不得修改
- frontmatter 内容须与 ADR 正文的决策语义一致，不得矛盾
- ADR-007 已有 frontmatter 中的 `adr`/`title`/`status` 值须保持不变，只新增缺失字段
- lint 块须从 REPO_ROOT 可独立执行（不依赖额外环境变量）
- static ADR 的 lint 块禁止复制已存在于可复用脚本中的检查逻辑：有 canonical 脚本则委托调用（ADR-005→verify-kind-status.sh、ADR-006→backlog-cli-contract.json），无则 lint 块自身即单一来源（ADR-001/004/007）
- 不修改 validate-plugin.sh

## Acceptance Gate

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `bash -c 'missing=0; for f in docs/adr/ADR-0*.md; do grep -qE "^enforcement:\s*(static|semantic|runtime|advisory)\s*$" "$f" || { echo "ADR missing enforcement: $f"; missing=1; }; done; test "$missing" = "0"'`
- [ ] `grep -qE '^enforcement:\s*runtime\s*$' docs/adr/ADR-002-monitor-lifecycle.md`
- [ ] `grep -qE '^enforcement:\s*semantic\s*$' docs/adr/ADR-003-monitor-prompt-self-contained.md`
- [ ] `grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-001-daemon-script-location.md`
- [ ] `grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-004-skill-type-naming.md`
- [ ] `grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-005-task-creation-kind-label.md`
- [ ] `grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-006-backlog-cli-flag-whitelist.md`
- [ ] `grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-007-plugin-script-residency.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Proposal self-review: APPROVED
premise-ledger:
[E] background lines: 从 proposal 文件直接数行数（8行内）
[E] goal verifiability: Goal 2 含可执行命令，其余 Goals 可检视验证
[C] feasibility — ADR enforcement types: 须读取 ADR-001~007 正文确认决策类型
[C] feasibility — ADR-007 partial frontmatter: 须检查 ADR-007 文件确认已有 frontmatter 状态
[H] lint 模式充分性: 何为'足够精确的 grep 模式'靠背景知识判断
[H] ADR-004 lint 可行性: TypeScript 类型命名模式是否可 grep 无法从文件直接读出
GCL-self-report: E=2 C=2 H=2

Proposal approved. Starting plan draft.

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: 5 goals 全部映射到 Phase A-E
[E] TDD structure: 每个 Phase 均有 Tests/Implementation/DoD 三节
[E] DoD[0] = bash scripts/validate-plugin.sh: 所有 Phase DoD 第一条可直接数
[E] Acceptance Gate[0] = bash scripts/validate-plugin.sh: 可直接读到
[C] file paths exist: docs/adr/ADR-0*.md 和 plugin/skills/ 存在已经搜索确认
[C] DoD commands executable: grep/bash 命令符合 shell 语法，需对照文件确认
[H] lint 充分性判断: ADR-004 TypeScript 类型模式覆盖充分性靠背景知识判断
[H] Phase 顺序定义: A→B→C→D→E 的分组逻辑合理性靠背景知识判断
GCL-self-report: E=4 C=2 H=2

claimed: 2026-06-24T12:13:00Z

# TASK-193 Agent Summary

## Task
Migrate ADR-001 through ADR-007 to ADR-008 compliant 7-field YAML frontmatter schema.

## Phases Completed

### Phase A: ADR-002, ADR-003 (runtime/semantic, no lint)
- ADR-002-monitor-lifecycle.md: added frontmatter with enforcement:runtime, stage:[plan], lint:null
- ADR-003-monitor-prompt-self-contained.md: added frontmatter with enforcement:semantic, stage:[proposal, plan], lint:null

### Phase B: ADR-001 (static + self-contained lint)
- ADR-001-daemon-script-location.md: added frontmatter with enforcement:static, stage:[check], self-contained lint checking for bare REPO_ROOT/scripts/basic-daemon references

### Phase C: ADR-004, ADR-005 (static)
- ADR-004-skill-type-naming.md: added frontmatter with enforcement:static, self-contained lint for bare TypeScript type definitions
- ADR-005-task-creation-kind-label.md: added frontmatter with enforcement:static, delegating to scripts/verify-kind-status.sh

### Phase D: ADR-006, ADR-007 (static)
- ADR-006-backlog-cli-flag-whitelist.md: added frontmatter with enforcement:static, lint checks scripts/backlog-cli-contract.json exists
- ADR-007-plugin-script-residency.md: replaced partial 4-field frontmatter with complete 8-field schema including multi-line lint script

### Phase E: Validation
- bash scripts/validate-plugin.sh: ALL CHECKS PASSED (0 errors, 55 warnings — all pre-existing)

## Commit
84e798a feat(TASK-193): migrate ADR 001-007 to ADR-008 frontmatter schema

Completed: 2026-06-24T12:18:56Z
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 grep -qE '^enforcement:\s*runtime\s*$' docs/adr/ADR-002-monitor-lifecycle.md
- [ ] #3 grep -qE '^enforcement:\s*semantic\s*$' docs/adr/ADR-003-monitor-prompt-self-contained.md
- [ ] #4 grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-001-daemon-script-location.md
- [ ] #5 grep -q 'adr: "001"' docs/adr/ADR-001-daemon-script-location.md
- [ ] #6 grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-004-skill-type-naming.md
- [ ] #7 grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-005-task-creation-kind-label.md
- [ ] #8 bash scripts/verify-kind-status.sh
- [ ] #9 grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-006-backlog-cli-flag-whitelist.md
- [ ] #10 grep -qE '^enforcement:\s*static\s*$' docs/adr/ADR-007-plugin-script-residency.md
- [ ] #11 grep -q 'adr: "007"' docs/adr/ADR-007-plugin-script-residency.md
- [ ] #12 test -f scripts/backlog-cli-contract.json
- [ ] #13 bash -c 'missing=0; for f in docs/adr/ADR-0*.md; do grep -qE "^enforcement:\s*(static|semantic|runtime|advisory)\s*$" "$f" || { echo "ADR missing enforcement: $f"; missing=1; }; done; test "$missing" = "0"'
<!-- DOD:END -->
