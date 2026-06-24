---
id: TASK-184
title: baime-self-reference-analysis 与 grounding-infrastructure 双向交叉引用
status: 'Epic: Backlog'
assignee: []
created_date: '2026-06-24 05:50'
updated_date: '2026-06-24 05:51'
labels:
  - 'kind:epic'
dependencies: []
ordinal: 122000
---

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: baime-self-reference-analysis 与 grounding-infrastructure 双向交叉引用

## Background

`docs/baime-self-reference-analysis.md` §3"观测即自观测"确立了自观测是 BAIME 中最快反馈机制，并提及 meta-cc self-trace 是自指的工具化应用。但该节没有把自观测接进 H6/evidence independence 框架，读者不知道自观测为何仍能满足（部分）独立性要求。

`docs/baime-self-reference-analysis.md` §"挑战 / 接地问题"提出"纯自指脱离现实"风险，建议需要外部锚点，但没有指出工程响应在哪里。

`docs/research/grounding-infrastructure.md` §2 建立了 2×2 矩阵（身份轴 × 通道轴），解释了自观测（左下格：自观测 + 记录-结构通道）为何不违反 H6，以及速度 / 稳健性权衡前沿（§2.1）和自观测需要隔离校准的论据（§2.2）。该文 §8 已有"接地基础设施 → 自指性分析"的单向说明，但 §2 / §4.3 尚未把 premise-ledger 明确定位为 2×2 左下格的典型实例。两篇文档的**关联**元数据头也未互相列入。

## Goals

1. self-reference-analysis §3 增加 forward reference → grounding-infrastructure §2（2×2 矩阵：自观测不违反 H6 的机制）
2. self-reference-analysis §挑战 / 接地问题 增加 forward reference → grounding-infrastructure §2.2（隔离校准是"纯自指脱离现实"风险的工程响应）
3. grounding-infrastructure §2.1 或 §4.3 明确把 premise-ledger 定位为 2×2 左下格典型实例
4. 验证两篇文档**关联**元数据头互相包含对方

## Sketch（子任务）

**ST-1：self-reference-analysis 增加两处 forward reference**
- §3"观测即自观测"末尾添加 1-2 句：指向 grounding-infrastructure.md §2 的 2×2 矩阵，说明该矩阵解释了为何自观测可部分满足 H6 独立性。
- §挑战 / 接地问题末尾添加 1-2 句：指向 grounding-infrastructure.md §2.2，作为"纯自指脱离现实风险"的工程响应路径。

**ST-2：grounding-infrastructure §2.1 中明确 premise-ledger 为左下格典型实例**
- 在 §2.1 速度/稳健性表格或其描述段落中，补充 premise-ledger 是左下格（自观测 + 结构解耦）的典型实例，并加注 H 自报偏差数据（delta_H = -1.46）说明其局限性。

**ST-3：元数据头双向验证与修正**
- self-reference-analysis.md 的**关联**字段加入 `grounding-infrastructure.md`（若缺失）。
- grounding-infrastructure.md 的**关联**字段加入 `baime-self-reference-analysis.md`（若缺失）。
- 已存在则保持不变（只补缺失）。

## Trade-offs

- **范围极小**：每处修改 1-3 行，无结构性改动风险。
- **收益明确**：读者从两个方向进入都能找到对方，H6 / 左下格 / 接地问题三处论证变得完整。
- **无退路成本**：doc-only 任务，失败后直接 revert。

---

# Plan: baime-self-reference-analysis 与 grounding-infrastructure 双向交叉引用

## Sub-Task Decomposition

### TASK-184a：self-reference-analysis §3 + §挑战 增加 forward reference

**Kind**: basic
**Labels**: doc-only

**Description**:
修改 `docs/baime-self-reference-analysis.md`，在两处增加指向 grounding-infrastructure.md 的 forward reference：

1. §3"观测即自观测"末尾（当前结尾在"这是自指在 prompt 工程层面的直接应用——自指不只是结构特征，也是可用来压缩开销的工具。"之后）添加：
   > 自观测之所以能在不引入外部观察者的情况下满足（部分）H6 独立性要求，根本原因在于身份耦合与通道解耦正交——premise-ledger 和 meta-cc self-trace 在身份上是自观测，在通道上已解耦。详见 [`grounding-infrastructure.md §2`](research/grounding-infrastructure.md)（2×2 矩阵）。

2. §挑战 / 接地问题（"1. 接地问题（grounding）"段落末尾，当前结尾在"这个角色值得显式确认。"之后）添加：
   > "纯自指脱离现实"的工程响应已在 [`grounding-infrastructure.md §2.2`](research/grounding-infrastructure.md) 系统化：自观测做主力高频反馈，隔离校准做周期性低频纠偏（TASK-152 实证：delta_H = -1.46，13 个事件全部为负，正是此机制捕捉到的系统性偏差）。行为接地（§3.3）是最终的外部锚点。

**DoD**:
- [ ] self-reference-analysis.md §3 末尾新增段落，包含指向 grounding-infrastructure.md §2 的链接
- [ ] self-reference-analysis.md §挑战 / 接地问题 末尾新增段落，包含指向 grounding-infrastructure.md §2.2 的链接
- [ ] `bash scripts/validate-plugin.sh` 通过（文档校验）

---

### TASK-184b：grounding-infrastructure §2.1 明确 premise-ledger 为左下格典型实例

**Kind**: basic
**Labels**: doc-only

**Description**:
修改 `docs/research/grounding-infrastructure.md`，在 §2.1 速度/稳健性权衡前沿的说明文字中，明确把 premise-ledger 定位为 2×2 左下格（自观测 + 记录-结构通道）的典型实例。

在 §2.1 末尾段落（当前结尾在"`draftAndReview` 把 draft 与 review 合并进同一上下文窗口……就是这条前沿上"自观测换速度"的直接收益。"之后）添加：

> **典型实例**：premise-ledger 是左下格的规范案例——reviewer 对自己刚做的判断分类（身份上是自观测），但通过 E/C/H 结构化分类实现通道解耦；delta_H = -1.46（TASK-152，N=13）表明其仍有系统性偏差，需要 §2.2 的隔离校准来检测。

**DoD**:
- [ ] grounding-infrastructure.md §2.1 末尾新增"典型实例"段落，明确 premise-ledger 为左下格案例
- [ ] 新增段落引用 delta_H 数据和 TASK-152
- [ ] `bash scripts/validate-plugin.sh` 通过

---

### TASK-184c：两篇文档关联元数据头互相引用验证与修正

**Kind**: basic
**Labels**: doc-only

**Description**:
验证并补全两篇文档元数据头的**关联**字段：

1. `docs/baime-self-reference-analysis.md`：检查**关联**字段是否包含 `grounding-infrastructure.md`；若缺失，在现有关联列表末尾追加：
   `- [\`grounding-infrastructure.md\`](research/grounding-infrastructure.md) — 接地基础设施：2×2 矩阵解释自观测不违反 H6，以及隔离校准响应"纯自指脱离现实"风险`

2. `docs/research/grounding-infrastructure.md`：检查**关联**字段是否包含 `baime-self-reference-analysis.md`；当前 **关联** 行已有该引用（`docs/baime-self-reference-analysis.md（"观测即自观测"，自观测作为最快反馈机制）`），验证即可，无需修改。

**DoD**:
- [ ] self-reference-analysis.md 关联头包含指向 grounding-infrastructure.md 的条目
- [ ] grounding-infrastructure.md 关联头包含指向 baime-self-reference-analysis.md 的条目（已存在，验证）
- [ ] `bash scripts/validate-plugin.sh` 通过

---

## Execution Order

TASK-184c → TASK-184a → TASK-184b（可并行，但建议按此顺序以确保元数据先就位再读者验证）

实际上三个子任务均无依赖，可任意顺序独立执行。

## Risk Assessment

- 文档格式：markdown，无语法校验以外的风险
- 范围：每文件改动 < 5 行
- 回滚成本：git revert 单文件即可
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Epic proposal self-review: APPROVED
premise-ledger:
[E] background lines: 8 lines (3 substantive background paragraphs covering each document's gap)
[C] goal coverage: 4 goals × 3 sub-tasks — ST-1 covers Goals 1+2 (two forward refs), ST-2 covers Goal 3 (premise-ledger positioning), ST-3 covers Goal 4 (metadata head verification)
[H] epic 粒度: doc-only maintenance epic，3 子任务均为 1-3 行改动，粒度适当
GCL-self-report: E=1 C=2 H=1

Epic proposal approved. Starting epic plan draft.

cap:propose=approved
<!-- SECTION:NOTES:END -->
