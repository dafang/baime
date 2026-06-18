---
id: TASK-16
title: 为无形式规格的 14 个 skill 评估并补充规格覆盖
status: Proposal
assignee: []
created_date: '2026-06-17 16:04'
updated_date: '2026-06-18 02:27'
labels:
  - spec-quality
  - documentation
dependencies: []
priority: low
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 问题

22 个 skill 中有 14 个（占 64%）完全没有形式化规格（无 `## Spec` 节，无 `λ` 入口，无类型签名）：

agent-prompt-evolution, api-design, baseline-quality-assessment, build-quality-gates, ci-cd-optimization, cross-cutting-concerns, dependency-health, documentation-management, feature-developer, knowledge-transfer, next-step-generation, observability-instrumentation, rapid-convergence, technical-debt-management, testing-strategy

另有 2 个（code-refactoring, subagent-prompt-construction）只有 `λ` 入口，无 spec 体。

这些 skill 的行为完全依赖自然语言描述，没有可验证的约束，也无法做静态分析。

## 建议方向

1. 先调研这些 skill 的实际使用情况（是否有用户/项目在用）
2. 对高价值 skill 补充至少：`λ` 入口签名 + 核心数据类型定义 + 主流程函数签名
3. 制定"skill 规格最低标准"，作为新 skill 合并的门槛
4. 评估是否所有 skill 都需要 Haskell spec，或部分 skill 用自然语言描述已足够
<!-- SECTION:DESCRIPTION:END -->
