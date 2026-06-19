---
id: TASK-46
title: Exp-H：验证 Layer 2.5 Oracle 阈值的跨 skill 泛化能力
status: Needs Human
assignee: []
created_date: '2026-06-19 12:51'
updated_date: '2026-06-19 14:59'
labels:
  - experiment
  - skill-quality
  - layer-2.5
  - oracle
dependencies: []
references:
  - docs/baime-oca-process-refinements.md
  - experiments/skill-quality/artifacts/analysis/exp-b-results.json
  - experiments/skill-quality/lib/score.ts
  - docs/skill-quality-engineering.md
priority: medium
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Background

当前 Layer 2.5 Oracle 阈值（Class A ≥ 0.85、Class B ≥ 0.70 verdict-only、Class C ≥ 0.80）仅在 loop-backlog / task-from-template / task-to-backlog 上标定（Exp-B/D/E）。尚不清楚这些阈值对其他 operator skill（feature-to-backlog、backlog-setup）是否成立，以及跨 skill 的 Haiku 准确率方差有多大。

这直接影响 OCA 第 10 步的发行门设计：若跨 skill 方差大，全局阈值会误判；若方差小，全局阈值安全可用。

## Goals

1. 在 Exp-B/D/E 未覆盖的 2-3 个 operator skill 上标定 Layer 2.5 准确率
2. 计算跨 skill 准确率方差，确定阈值通用性
3. 给出发行门设计建议：全局阈值 vs per-skill 标定

## Proposed Approach

### Phase 1：选取目标 skill 并审计 fixture 可构造性

- `feature-to-backlog`：λ 分支可对照 Exp-D freshnessCheck 结果比较
- `backlog-setup`：初始化类 skill，决策点不同于现有标定 skill
- 可选：task-from-template 的非 freshnessCheck 分支

对每个 skill：审计 λ spec 识别可测决策点（Class A/B/C），构造每类至少 6 个 CLEAR fixture（人工审计 ground truth）。

### Phase 2：标定准确率

P-full，Haiku，k=5；同时报告 composite 和 verdict-only。

估计总调用量：3 skill × 6 fixture × k=5 = 90 次。

### Phase 3：分析方差与建议

输出 `artifacts/analysis/exp-h-results.json`，含每个 skill 的准确率、跨 skill 方差（σ）、阈值通用性建议。

## Pre-registered Hypotheses

- **H-universal**：跨 skill 准确率方差 σ < 0.10（全局阈值可用）
- **H-per-skill**：σ ≥ 0.10（需 per-skill 标定）

## Decision Table

| 结果 | 发行门设计 |
|---|---|
| H-universal CONFIRMED | 全局阈值；新 skill 直接复用现有阈值 |
| H-per-skill CONFIRMED | Per-skill 标定；validate-plugin.sh 须记录每 skill 历史基线 |
| 部分偏离 | 混合：全局阈值 WARNING + per-skill 基线 FAIL |

## Constraints

- Fixture ground truth 须经人工审计（CLEAR/AMBIGUOUS/ERROR），不可跳过
- 每 skill ≥ 6 CLEAR fixture，否则 defer
- 假设文件在任何 LLM 调用前冻结
- 复用已修复的 lib/score.ts 和 lib/llm-client.ts
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Plan: Exp-H：验证 Layer 2.5 Oracle 阈值的跨 skill 泛化能力

## Context
Layer 2.5 Oracle 阈值（Class A ≥0.85、Class B ≥0.70、Class C ≥0.80 verdict-only）仅在 loop-backlog/task-from-template/task-to-backlog 三个 skill 上标定（Exp-B/D/E）。若跨 skill 准确率方差大，全局阈值会误判发行门；若方差小，现有阈值可安全复用。

## Phase 1: 选取目标 skill 并构造 fixtures

对 `feature-to-backlog` 和 `backlog-setup` 两个 skill（Exp-B/D/E 未覆盖）：

1. 读取各自 `SKILL.md` 的 λ spec 节，识别可测决策点；依照 `experiments/skill-quality/README.md`（或 Exp-B 标注惯例）将每个决策点标注 Class A/B/C：A = 高风险 gate、B = 中等判断、C = verdict-only 轻量核查
2. 对每个决策点构造 ≥6 个 fixture，格式与 `experiments/skill-quality/fixtures/exp-a/` 一致
3. 手工审计每个 fixture ground truth，标注 CLEAR/AMBIGUOUS/ERROR
4. 将 CLEAR fixture 写入 `experiments/skill-quality/fixtures/exp-h/<skill-name>/`

### DoD
- [ ] `[ $(ls experiments/skill-quality/fixtures/exp-h/feature-to-backlog/*.json 2>/dev/null | wc -l) -ge 6 ]`
- [ ] `[ $(ls experiments/skill-quality/fixtures/exp-h/backlog-setup/*.json 2>/dev/null | wc -l) -ge 6 ]`
- [ ] `grep -rq '"answer"' experiments/skill-quality/fixtures/exp-h/feature-to-backlog/`

## Phase 2: 标定 Layer 2.5 准确率

对 Phase 1 中 CLEAR ≥6 的 skill，使用 `experiments/skill-quality/lib/llm-client.ts` 和已修复的 `lib/score.ts`，P-full 注入，Haiku，k=5，同时报告 composite 和 verdict-only 准确率。

编写 `experiments/skill-quality/exp-h/run-exp-h.ts`（可参考 run-exp-d.ts/run-exp-g.ts 结构）。

估计调用量：2 skill × 6 fixture × 5 runs = 60 次。

### DoD
- [ ] `grep -qE 'writeFile|appendFile|JSON\.stringify' experiments/skill-quality/exp-h/run-exp-h.ts`
- [ ] `grep -q '"feature-to-backlog"' experiments/skill-quality/artifacts/analysis/exp-h-raw.json`
- [ ] `grep -q '"verdict_only"' experiments/skill-quality/artifacts/analysis/exp-h-raw.json`

## Phase 3: 分析跨 skill 方差并更新文档

读取 Phase 2 产出的 `exp-h-raw.json`，计算各 skill verdict-only 准确率的方差（σ），对照假设阈值（σ<0.10 → H-universal；σ≥0.10 → H-per-skill）。

输出 `experiments/skill-quality/artifacts/analysis/exp-h-results.json`（汇总分析结果，引用 raw 数据）：
```json
{
  "per_skill": { "<skill>": { "verdict_only": 0.XX, "composite": 0.XX } },
  "sigma": 0.XX,
  "hypothesis": "H-universal CONFIRMED|H-per-skill CONFIRMED|INCONCLUSIVE",
  "recommendation": "global-threshold|per-skill-calibration|hybrid"
}
```

根据 `exp-h-results.json` 中的 `recommendation` 字段更新 `docs/baime-oca-process-refinements.md` §3（第 10 步发行门设计）：若 `global-threshold` 则保留现有单一阈值并注明 Exp-H 验证；若 `per-skill-calibration` 则在 §3 新增 per-skill 阈值表；若 `hybrid` 则说明分组策略。将 Exp-H 结论（sigma 值、hypothesis、recommendation）追加到 `docs/skill-quality-experiments-summary.md` 的末尾新节中。

### DoD
- [ ] `grep -q '"sigma"' experiments/skill-quality/artifacts/analysis/exp-h-results.json`
- [ ] `grep -q '"hypothesis"' experiments/skill-quality/artifacts/analysis/exp-h-results.json`
- [ ] `grep -q 'Exp-H' docs/skill-quality-experiments-summary.md`
- [ ] `grep -qE 'H-universal|H-per-skill|INCONCLUSIVE' docs/baime-oca-process-refinements.md`

## Constraints

- Fixture ground truth 须经人工审计（CLEAR/AMBIGUOUS/ERROR），不可跳过
- 每 skill ≥6 CLEAR fixture，否则 defer（不计入结论）
- 假设文件在任何 LLM 调用前冻结
- 复用已修复的 lib/score.ts 和 lib/llm-client.ts
- 不修改 Exp-B/D/E/F/G 已有结果

## Acceptance Gate

- [ ] `grep -q '"sigma"' experiments/skill-quality/artifacts/analysis/exp-h-results.json`
- [ ] `grep -q '"hypothesis"' experiments/skill-quality/artifacts/analysis/exp-h-results.json`
- [ ] `grep -q 'Exp-H' docs/skill-quality-experiments-summary.md`
- [ ] `grep -qE 'H-universal|H-per-skill|INCONCLUSIVE' docs/baime-oca-process-refinements.md`
- [ ] `bash scripts/validate-plugin.sh`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan review: 4 iterations, revisions fixed phase ordering (Phase 2→raw artifact), outcome-agnostic DoD checks, Class A/B/C classification criteria, and concrete doc-update instructions per recommendation branch.

claimed: 2026-06-19T14:44:54Z

Merge conflict: 2026-06-19T14:59:11Z
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 [ $(ls experiments/skill-quality/fixtures/exp-h/feature-to-backlog/*.json 2>/dev/null | wc -l) -ge 6 ]
- [ ] #2 [ $(ls experiments/skill-quality/fixtures/exp-h/backlog-setup/*.json 2>/dev/null | wc -l) -ge 6 ]
- [ ] #3 grep -rq '"answer"' experiments/skill-quality/fixtures/exp-h/feature-to-backlog/
- [ ] #4 grep -qE 'writeFile|appendFile|JSON\.stringify' experiments/skill-quality/exp-h/run-exp-h.ts
- [ ] #5 grep -q '"feature-to-backlog"' experiments/skill-quality/artifacts/analysis/exp-h-raw.json
- [ ] #6 grep -q '"verdict_only"' experiments/skill-quality/artifacts/analysis/exp-h-raw.json
- [ ] #7 grep -q '"sigma"' experiments/skill-quality/artifacts/analysis/exp-h-results.json
- [ ] #8 grep -q '"hypothesis"' experiments/skill-quality/artifacts/analysis/exp-h-results.json
- [ ] #9 grep -q 'Exp-H' docs/skill-quality-experiments-summary.md
- [ ] #10 grep -qE 'H-universal|H-per-skill|INCONCLUSIVE' docs/baime-oca-process-refinements.md
- [ ] #11 bash scripts/validate-plugin.sh
<!-- DOD:END -->
