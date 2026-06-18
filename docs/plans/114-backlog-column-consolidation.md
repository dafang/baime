# Plan: 改进 feature-to-backlog / task-to-backlog：finalise 合并写入 proposal + plan 到 task

## Context
feature-to-backlog 和 task-to-backlog 两个 skill 的 finalise 阶段将文档写入外部文件（docs/proposals/、docs/plans/）并提交 git，而非将最终内容写入 task 的 planSet 区块。本次改造去掉外部文件写入步骤，改为直接将 proposal + plan 合并写入 task planSet，使 task 成为唯一内容来源。

## Phase A: feature-to-backlog finalise 改造

### Tests (write first)

在实现前，以下 grep 检查必须 **FAIL**（字符串尚不存在）：

```bash
# A-T1: 新的 Step B 标题应不存在
! grep -q 'Step B — Write combined proposal+plan into task and add DoD' \
  plugin/skills/feature-to-backlog/SKILL.md

# A-T2: 合并写入命令应不存在
! grep -q 'ftb-combined.md' plugin/skills/feature-to-backlog/SKILL.md

# A-T3: 旧的 Step A（Plan number）应仍存在（将被删除）
grep -q 'Step A — Plan number' plugin/skills/feature-to-backlog/SKILL.md

# A-T4: 旧的 Step B（Copy docs）应仍存在（将被删除）
grep -q 'Step B — Copy docs' plugin/skills/feature-to-backlog/SKILL.md

# A-T5: 旧的 Step C（Commit）应仍存在（将被删除）
grep -q 'Step C — Commit' plugin/skills/feature-to-backlog/SKILL.md

# A-T6: 旧的"文档已提交"字样应仍存在（将被删除）
grep -q '文档已提交' plugin/skills/feature-to-backlog/SKILL.md
```

### Implementation

文件：`plugin/skills/feature-to-backlog/SKILL.md`

**1. 更新 frontmatter description 字段**

旧文本：
```
description: "Converts a feature description into a single backlog task with TDD implementation plan, moving through Proposal Draft → Proposal Review → Plan Draft → Plan Review → Backlog. Two iterative review loops (each converges on APPROVED, soft limit 8 rounds). Ends with a git commit of the docs and the task in Backlog status with native DoD items. No branch creation, no PRs."
```

新文本：
```
description: "Converts a feature description into a single backlog task with TDD implementation plan, moving through Proposal Draft → Proposal Review → Plan Draft → Plan Review → Backlog. Two iterative review loops (each converges on APPROVED, soft limit 8 rounds). Ends with the proposal and plan written into the task planSet and the task in Backlog status with native DoD items. No branch creation, no PRs."
```

**2. 更新 Phase 5 finalise 的调用描述行**

旧文本：
```
> Finalise the backlog task and commit documents to the repository.
```

新文本：
```
> Finalise the backlog task: write combined proposal + plan into task and add DoD items.
```

**3. 替换 Phase 5 finalise 的步骤 A/B/C/D/E**

旧文本（lines 419–471 of SKILL.md）：

```
> **Step A — Plan number**:
> ```bash
> NEXT_N=$(ls <CFG_DOC_PATH>/plans/ 2>/dev/null \
>   | grep -oP '^\d+' | sort -n | tail -1 \
>   | xargs -I{} expr {} + 1 2>/dev/null || echo "101")
> ```
>
> **Step B — Copy docs**:
> ```bash
> mkdir -p <CFG_DOC_PATH>/proposals <CFG_DOC_PATH>/plans
> cp $TMPDIR/ftb-proposal.md <CFG_DOC_PATH>/proposals/proposal-<SLUG>.md
> cp $TMPDIR/ftb-plan.md     <CFG_DOC_PATH>/plans/${NEXT_N}-<SLUG>.md
> ```
>
> **Step C — Commit**:
> ```bash
> git add <CFG_DOC_PATH>/proposals/proposal-<SLUG>.md \
>         <CFG_DOC_PATH>/plans/${NEXT_N}-<SLUG>.md
> git commit -m "docs(<SLUG>): add proposal and plan"
> ```
> Only these two files. Verify with `git status` first.
>
> **Step D — Add DoD to task**:
> ```bash
> grep -oP '(?<=- \[ \] `)[^`]+(?=`)' $TMPDIR/ftb-plan.md \
>   > $TMPDIR/ftb-dod-cmds.txt
>
> DOD_ARGS=()
> while IFS= read -r cmd; do
>   DOD_ARGS+=("--dod" "$cmd")
> done < $TMPDIR/ftb-dod-cmds.txt
>
> backlog task edit <TASK_ID> \
>   --status "Backlog" \
>   --append-notes "Docs committed: <CFG_DOC_PATH>/proposals/proposal-<SLUG>.md + <CFG_DOC_PATH>/plans/${NEXT_N}-<SLUG>.md" \
>   "${DOD_ARGS[@]}"
> ```
>
> **Step E — Print completion**:
> ```
> ✅ Task <TASK_ID> is now in Backlog.
>
> 两轮起草 + 两轮迭代审查已完成。文档已提交。
>
> 请在 web UI 审阅 Definition of Done 中的命令：
>   backlog browser --no-open --port 6421
>
> 确认无误后，将任务移入执行队列：
>   backlog task edit <TASK_ID> --status "Ready"
>
> 启动 L0 执行：
>   /loop-backlog
> ```
```

新文本：

```
> **Step B — Write combined proposal+plan into task and add DoD**:
> ```bash
> grep -oP '(?<=- \[ \] `)[^`]+(?=`)' $TMPDIR/ftb-plan.md \
>   > $TMPDIR/ftb-dod-cmds.txt
>
> DOD_ARGS=()
> while IFS= read -r cmd; do
>   DOD_ARGS+=("--dod" "$cmd")
> done < $TMPDIR/ftb-dod-cmds.txt
>
> {
>   cat $TMPDIR/ftb-proposal.md
>   printf '\n\n---\n\n'
>   cat $TMPDIR/ftb-plan.md
> } > $TMPDIR/ftb-combined.md
>
> backlog task edit <TASK_ID> \
>   --planSet "$(cat $TMPDIR/ftb-combined.md)" \
>   --status "Backlog" \
>   "${DOD_ARGS[@]}"
> ```
>
> **Step E — Print completion**:
> ```
> ✅ Task <TASK_ID> is now in Backlog.
>
> 两轮起草 + 两轮迭代审查已完成。
>
> 请在 web UI 审阅 Definition of Done 中的命令：
>   backlog browser --no-open --port 6421
>
> 确认无误后，将任务移入执行队列：
>   backlog task edit <TASK_ID> --status "Ready"
>
> 启动 L0 执行：
>   /loop-backlog
> ```
```

**4. 替换 Constraints 中关于 $TMPDIR 的行**

旧文本：
```
- `$TMPDIR` files are ephemeral; do not reference them after Phase 5 completes
```

新文本：
```
- `$TMPDIR` files are ephemeral; do not reference them after Phase 5 completes
- Proposal and plan text live in the task's Implementation Plan field; no docs/ files are written
```

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'Step B — Write combined proposal+plan into task and add DoD' plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `grep -q 'ftb-combined.md' plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `! grep -q 'Step A — Plan number' plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `! grep -q 'Step B — Copy docs' plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `! grep -q 'Step C — Commit' plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `! grep -q '文档已提交' plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `! grep -q 'docs(<SLUG>): add proposal and plan' plugin/skills/feature-to-backlog/SKILL.md`

## Phase B: task-to-backlog finalise 改造

### Tests (write first)

在实现前，以下 grep 检查必须 **FAIL**（字符串尚不存在）：

```bash
# B-T1: 新的 Step B 标题应不存在
! grep -q 'Step B — Write plan into task and add DoD' \
  plugin/skills/task-to-backlog/SKILL.md

# B-T2: 旧的 Step A（Plan number）应仍存在（将被删除）
grep -q 'Step A — Plan number' plugin/skills/task-to-backlog/SKILL.md

# B-T3: 旧的 Step B（Copy plan doc）应仍存在（将被删除）
grep -q 'Step B — Copy plan doc' plugin/skills/task-to-backlog/SKILL.md

# B-T4: 旧的 Step C（Commit）应仍存在（将被删除）
grep -q 'Step C — Commit' plugin/skills/task-to-backlog/SKILL.md

# B-T5: 旧的完成语句应仍存在（将被删除）
grep -q '计划草拟 + 审查已完成。文档已提交。' plugin/skills/task-to-backlog/SKILL.md
```

### Implementation

文件：`plugin/skills/task-to-backlog/SKILL.md`

**1. 更新 frontmatter description 字段**

旧文本：
```
description: "Converts a non-development task (analysis, research, documentation, experiment, survey) into a backlog task. Single draft + review loop produces a phase-based execution plan with shell-verifiable DoD. No TDD structure required. Ends with a git commit of the plan doc and the task in Backlog status."
```

新文本：
```
description: "Converts a non-development task (analysis, research, documentation, experiment, survey) into a backlog task. Single draft + review loop produces a phase-based execution plan with shell-verifiable DoD. No TDD structure required. Ends with the plan written into the task planSet and the task in Backlog status with native DoD items."
```

**2. 更新 Phase 4 finalise 的调用描述行**

旧文本：
```
> Finalise the backlog task and commit the plan document.
```

新文本：
```
> Finalise the backlog task: write plan into task and add DoD items.
```

**3. 替换 Phase 4 finalise 的步骤 A/B/C/D/E**

旧文本（lines 279–328 of SKILL.md）：

```
> **Step A — Plan number**:
> ```bash
> NEXT_N=$(ls <CFG_DOC_PATH>/plans/ 2>/dev/null \
>   | grep -oP '^\d+' | sort -n | tail -1 \
>   | xargs -I{} expr {} + 1 2>/dev/null || echo "101")
> ```
>
> **Step B — Copy plan doc**:
> ```bash
> mkdir -p <CFG_DOC_PATH>/plans
> cp $TMPDIR/ttb-plan.md <CFG_DOC_PATH>/plans/${NEXT_N}-<SLUG>.md
> ```
>
> **Step C — Commit**:
> ```bash
> git add <CFG_DOC_PATH>/plans/${NEXT_N}-<SLUG>.md
> git commit -m "docs(<SLUG>): add task plan"
> ```
> Only this file. Verify with `git status` first.
>
> **Step D — Extract DoD commands and add to task**:
> ```bash
> grep -oP '(?<=- \[ \] `)[^`]+(?=`)' $TMPDIR/ttb-plan.md \
>   > $TMPDIR/ttb-dod-cmds.txt
>
> DOD_ARGS=()
> while IFS= read -r cmd; do
>   DOD_ARGS+=("--dod" "$cmd")
> done < $TMPDIR/ttb-dod-cmds.txt
>
> backlog task edit <TASK_ID> \
>   --status "Backlog" \
>   --append-notes "Plan committed: <CFG_DOC_PATH>/plans/${NEXT_N}-<SLUG>.md" \
>   "${DOD_ARGS[@]}"
> ```
>
> **Step E — Print completion**:
> ```
> ✅ Task <TASK_ID> is now in Backlog.
>
> 计划草拟 + 审查已完成。文档已提交。
>
> 请在 web UI 确认 Definition of Done 命令：
>   backlog browser --no-open --port 6421
>
> 确认无误后，将任务移入执行队列：
>   backlog task edit <TASK_ID> --status "Ready"
>
> 等待 loop-backlog 自动拾取，或立即启动：
>   /loop-backlog
> ```
```

新文本：

```
> **Step B — Write plan into task and add DoD**:
> ```bash
> grep -oP '(?<=- \[ \] `)[^`]+(?=`)' $TMPDIR/ttb-plan.md \
>   > $TMPDIR/ttb-dod-cmds.txt
>
> DOD_ARGS=()
> while IFS= read -r cmd; do
>   DOD_ARGS+=("--dod" "$cmd")
> done < $TMPDIR/ttb-dod-cmds.txt
>
> backlog task edit <TASK_ID> \
>   --planSet "$(cat $TMPDIR/ttb-plan.md)" \
>   --status "Backlog" \
>   "${DOD_ARGS[@]}"
> ```
>
> **Step E — Print completion**:
> ```
> ✅ Task <TASK_ID> is now in Backlog.
>
> 计划草拟 + 审查已完成。
>
> 请在 web UI 确认 Definition of Done 命令：
>   backlog browser --no-open --port 6421
>
> 确认无误后，将任务移入执行队列：
>   backlog task edit <TASK_ID> --status "Ready"
>
> 等待 loop-backlog 自动拾取，或立即启动：
>   /loop-backlog
> ```
```

**4. 替换 Constraints 中关于 $TMPDIR 的行**

旧文本：
```
- `$TMPDIR` files are ephemeral; do not reference them after Phase 4 completes
```

新文本：
```
- `$TMPDIR` files are ephemeral; do not reference them after Phase 4 completes
- Plan text lives in the task's Implementation Plan field; no docs/ files are written
```

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'Step B — Write plan into task and add DoD' plugin/skills/task-to-backlog/SKILL.md`
- [ ] `! grep -q 'Step A — Plan number' plugin/skills/task-to-backlog/SKILL.md`
- [ ] `! grep -q 'Step B — Copy plan doc' plugin/skills/task-to-backlog/SKILL.md`
- [ ] `! grep -q 'Step C — Commit' plugin/skills/task-to-backlog/SKILL.md`
- [ ] `! grep -q '计划草拟 + 审查已完成。文档已提交。' plugin/skills/task-to-backlog/SKILL.md`
- [ ] `! grep -q 'docs(<SLUG>): add task plan' plugin/skills/task-to-backlog/SKILL.md`

## Constraints

- 只修改两个 SKILL.md 文件的 finalise 阶段，不改 Spec 类型定义、review loop、draftProposal/draftPlan 阶段
- 不引入新依赖，不创建新文件
- 改动后 `bash scripts/validate-plugin.sh` 必须通过
- 不保留 docs/proposals/ 和 docs/plans/ 的写入逻辑
- planSet 字段上限 20000 字符；若合并后超限，finalise 实现时应优先写 plan，再 append proposal

## Acceptance Gate

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'ftb-combined.md' plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `grep -q 'Step B — Write combined proposal+plan into task and add DoD' plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `grep -q 'Step B — Write plan into task and add DoD' plugin/skills/task-to-backlog/SKILL.md`
- [ ] `! grep -q 'Step A — Plan number' plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `! grep -q 'Step A — Plan number' plugin/skills/task-to-backlog/SKILL.md`
- [ ] `! grep -q '文档已提交' plugin/skills/feature-to-backlog/SKILL.md`
- [ ] `! grep -q '计划草拟 + 审查已完成。文档已提交。' plugin/skills/task-to-backlog/SKILL.md`
