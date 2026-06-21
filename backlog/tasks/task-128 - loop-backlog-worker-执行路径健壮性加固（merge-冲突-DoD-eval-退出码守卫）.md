---
id: TASK-128
title: loop-backlog worker 执行路径健壮性加固（merge 冲突 / DoD eval / 退出码守卫）
status: 'Basic: Proposal'
assignee: []
created_date: '2026-06-21 12:05'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 87000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
在 TASK-126 的真实 loop-backlog 执行中暴露的三处 worker 正确性缺陷，归为单个 Basic Task（多 Phase）。

**Phase A — 消除 task `.md` 的结构性 merge 冲突（高，结构性）**
worker（main 侧）写 claim/status 笔记，后台 agent（worktree 侧）写 phase/DoD 笔记并提交到分支 —— 两侧修改同一 task 文件，merge 必然冲突。本次 TASK-126 即 abort，需手动 commit+resolve。方案候选：(a) agent 不写共享 task 文件，phase/DoD 笔记由 worker 在 main 侧统一追加；或 (b) 对 backlog/tasks/*.md 配 union merge driver（.gitattributes + merge driver）；或 (c) 把 task .md 排除出 worktree 合并路径。需在 SKILL.md（executePrompt 协议 + merge 段）与 .gitattributes 落实，并加回归用例。

**Phase B — DoD 验证对 `!`-前缀命令假失败（高）**
verifyDodInWorkerLoop 在循环 shell 内用 eval 跑 DoD，`! grep -q ...` 触发 history-expansion 给出 false FAIL（本次 DoD #6 在循环里 FAIL，bash -c 跑 PASS）。自治模式下会把已通过的任务误 escalate 到 Needs Human。方案：DoD 一律用 bash -c 干净子 shell 执行（agent verifyDod + workerLoop pre-merge 两处）；加 ! grep 回归用例。

**Phase C — merge 退出码守卫（中）**
SKILL 正文 if git merge 写法正确，但极易被 git merge | tail 之类管道掩盖退出码（本次执行即误把 abort 当成功、错误置 Basic: Done）。方案：merge 段加显式注释禁止管道包裹 git merge；加断言"仍有 MERGE_HEAD 或 unmerged 文件时不得置 Basic: Done"。

DoD 应包含 daemon-routing/daemon 自测、validate-plugin.sh、以及针对 A/B/C 的最小回归脚本。证据见本会话 TASK-126 执行记录。
<!-- SECTION:DESCRIPTION:END -->
