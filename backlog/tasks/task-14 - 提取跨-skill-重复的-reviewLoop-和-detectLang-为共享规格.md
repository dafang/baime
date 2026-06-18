---
id: TASK-14
title: 提取跨 skill 重复的 reviewLoop 和 detectLang 为共享规格
status: Proposal
assignee: []
created_date: '2026-06-17 16:04'
updated_date: '2026-06-18 02:27'
labels:
  - spec-quality
  - deduplication
dependencies: []
priority: medium
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 问题

多个 skill 存在逐字或结构性重复的 spec 函数，当前已出现分歧：

**`detectLang`**：`loop-backlog` 与 `feature-to-backlog` 逐字相同，`task-to-backlog` 已删除。

**`loadConfig`**：三个 skill 签名相同（`() → Config`），但 `autoDetect` 实现各异（返回不同字段集），且注释已出现差异。

**`reviewLoop` / `reviewPlan`**：`feature-to-backlog` 和 `task-to-backlog` 结构几乎相同，仅 max rounds（8 vs 4）和类型别名不同。

## 建议方向

评估是否引入共享规格文档（如 `docs/spec-stdlib.md`），将 `detectLang`、`loadConfig` 的公共逻辑集中定义，各 skill spec 以 `-- see spec-stdlib` 引用。`reviewLoop` 可参数化 max rounds 后合并。需权衡"共享规格"与"每个 skill 自包含"之间的可读性 trade-off。
<!-- SECTION:DESCRIPTION:END -->
