# Proposal: 改进 feature-to-backlog / task-to-backlog：finalise 合并写入 proposal + plan 到 task

## Background
feature-to-backlog 和 task-to-backlog 两个 skill 的 finalise 阶段均未将最终审定的文本写回 task。
前者的 finalise 只追加 notes（文件路径引用），后者同理。
Review loop 期间虽然有 `--planSet` 调用，但 finalise 没有做最终的覆盖写入，
若任意 review 迭代的写入失败，task 里的 planSet 就是旧版本。
实际观察到的问题：TASK-21 的 Implementation Plan 区块只有 proposal 文本，
完整 plan（554 行）只存在于 docs/plans/112-loop-backlog-parallel-agent.md，task 本身无法自给。
外部文件作为额外存储引入了同步负担：task 和文件可能不一致，需打开文件才能看完整内容。

## Goals
1. feature-to-backlog finalise 阶段将 proposal 和 plan 合并后通过 `--planSet` 写入 task，
   使 task 的 Implementation Plan 区块包含两份完整文本
2. task-to-backlog finalise 阶段将 plan 通过 `--planSet` 写入 task，
   使 task 的 Implementation Plan 区块包含完整 plan 文本
3. 两个 skill 不再 commit 外部 proposal/plan 文件（去掉 docs/proposals/ 和 docs/plans/ 的写入和 git commit 步骤）
4. finalise 完成后，task 是 proposal 和 plan 内容的唯一权威来源
5. 改动后 bash scripts/validate-plugin.sh 仍通过

## Proposed Approach

**feature-to-backlog Phase 5 finalise** 的 Step B/C（复制文件、git commit）替换为一步合并写入：

```bash
# 合并 proposal 和 plan 到 task planSet
{
  cat $TMPDIR/ftb-proposal.md
  echo ""
  echo "---"
  echo ""
  cat $TMPDIR/ftb-plan.md
} > $TMPDIR/ftb-combined.md

backlog task edit <TASK_ID> \
  --planSet "$(cat $TMPDIR/ftb-combined.md)" \
  --status "Backlog" \
  "${DOD_ARGS[@]}"
```

Step E 的完成提示去掉"文档已提交"字样，不再引用外部文件路径。

**task-to-backlog Phase 4 finalise** 的 Step B/C（复制文件、git commit）替换为：

```bash
backlog task edit <TASK_ID> \
  --planSet "$(cat $TMPDIR/ttb-plan.md)" \
  --status "Backlog" \
  "${DOD_ARGS[@]}"
```

Step E 的完成提示同理去掉文件引用。

两个 skill 的 `## Constraints` 删除"ephemeral $TMPDIR files"的外部文件相关约束。

## Trade-offs and Risks

**不做的事**：
- 不改变 proposal/plan 在 $TMPDIR 中的生成流程，只改 finalise 阶段的写入目标
- 不引入新的 review 逻辑，不修改 Spec 节的类型定义
- 不保留 docs/proposals/ 和 docs/plans/ 的归档（若需要可手动 commit）

**已知风险**：
- planSet 字段有 20000 字符上限（backlog task edit 的 maxLength: 20000）；
  若 proposal + plan 合并后超限，backlog CLI 会报错。
  缓解：plan review 阶段已有"每 Phase ≤ 200 行"约束，实践中合并文本不太可能超限；
  若超限，可在 finalise 里先写 plan，再 append proposal（plan 优先）。
- 已有的 task（如 TASK-21）里的 notes 仍引用旧路径，历史不受影响，新 task 行为正确即可。
- git history 里不再有 proposal/plan 的独立 commit；若团队依赖这些文件做 code review，需改用 task 作为 review 入口。
