---
id: TASK-184
title: baime-self-reference-analysis 与 grounding-infrastructure 双向交叉引用
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 05:50'
updated_date: '2026-06-24 09:12'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add bidirectional cross-references between `docs/baime-self-reference-analysis.md` and `docs/research/grounding-infrastructure.md` to complete the argumentative links between the two documents. Change 1: in self-reference-analysis §3 ("观测即自观测"), add 1-2 sentences pointing to grounding-infrastructure §2 (2×2 matrix explaining why self-observation partially satisfies H6 independence). Change 2: in self-reference-analysis §挑战/接地问题, add 1-2 sentences pointing to grounding-infrastructure §2.2 (isolation calibration as the engineering response to "pure self-reference loses grip on reality"). Change 3: in grounding-infrastructure §2.1, add a "典型实例" paragraph explicitly positioning premise-ledger as the canonical left-bottom-cell case, citing delta_H = -1.46 (TASK-152, N=13). Change 4: verify/add mutual 关联 metadata headers in both documents. All changes are doc-only; each file change < 10 lines.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: baime-self-reference-analysis 与 grounding-infrastructure 双向交叉引用

## Background
`docs/baime-self-reference-analysis.md` §3 "观测即自观测" establishes self-observation as BAIME's fastest feedback mechanism, but does not connect it to the H6/evidence independence framework, leaving readers without the mechanism explaining why self-observation can partially satisfy independence. Its §"挑战/接地问题" identifies the "pure self-reference loses grip on reality" risk but does not point to the engineering response. `docs/research/grounding-infrastructure.md` §2 provides the 2×2 matrix (identity axis × channel axis) and §2.2 the isolation calibration rationale, but §2.1 has not explicitly positioned premise-ledger as the canonical left-bottom-cell case. The 关联 metadata headers in both documents also do not yet cross-reference each other.

## Goals
1. `docs/baime-self-reference-analysis.md` §3 末尾 adds 1-2 sentences pointing to grounding-infrastructure.md §2 (2×2 matrix explaining H6 partial independence). `grep -q 'grounding-infrastructure' docs/baime-self-reference-analysis.md` exits 0.
2. `docs/baime-self-reference-analysis.md` §挑战/接地问题 adds 1-2 sentences pointing to grounding-infrastructure.md §2.2 (isolation calibration as engineering response to pure-self-reference risk).
3. `docs/research/grounding-infrastructure.md` §2.1 adds a "典型实例" paragraph explicitly positioning premise-ledger as left-bottom-cell canonical case, citing delta_H = -1.46 (TASK-152, N=13). `grep -q '典型实例' docs/research/grounding-infrastructure.md` exits 0.
4. Both documents' 关联 metadata headers include cross-references to each other. `grep -q 'grounding-infrastructure' docs/baime-self-reference-analysis.md && grep -q 'baime-self-reference-analysis' docs/research/grounding-infrastructure.md` exits 0.
5. `bash scripts/validate-plugin.sh` passes. All changes are doc-only; each file change < 10 lines total.

## Proposed Approach
Read both documents to find exact insertion points. Phase 1: add two forward references in self-reference-analysis.md (§3 and §挑战). Phase 2: add 典型实例 paragraph in grounding-infrastructure.md §2.1. Phase 3: verify/patch 关联 metadata headers in both files. Each phase is independent; total diff < 20 lines across both files.

## Trade-offs and Risks
- Scope is extremely small (1-3 lines per insertion), no structural change risk.
- Doc-only: validate-plugin.sh is satisfied by existing contracts; no new contracts needed.
- If existing 关联 headers already contain the cross-reference, Phase 3 is a no-op (verify only).

---

# Plan: baime-self-reference-analysis 与 grounding-infrastructure 双向交叉引用

## Phase 1: Add forward references in self-reference-analysis.md
### Tests (write first)
- `! grep -q 'grounding-infrastructure' docs/baime-self-reference-analysis.md` — cross-ref not yet present

### Implementation
- Read `docs/baime-self-reference-analysis.md` to find §3 "观测即自观测" end and §挑战/接地问题 end
- In §3 末尾, after the last sentence, add 1-2 sentences: explain that premise-ledger and meta-cc self-trace satisfy partial H6 independence via identity-coupling + channel-decoupling; link to `research/grounding-infrastructure.md §2` (2×2 矩阵)
- In §挑战/接地问题 "1. 接地问题" paragraph end, add 1-2 sentences: cite isolation calibration as the engineering response to "pure self-reference" risk; link to `research/grounding-infrastructure.md §2.2`; mention delta_H = -1.46 (TASK-152)

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'grounding-infrastructure' docs/baime-self-reference-analysis.md`

## Phase 2: Add 典型实例 paragraph in grounding-infrastructure.md §2.1
### Tests (write first)
- `! grep -q '典型实例' docs/research/grounding-infrastructure.md` — not yet present

### Implementation
- Read `docs/research/grounding-infrastructure.md` §2.1 to find the end of the speed/robustness trade-off discussion
- Append a **典型实例** paragraph: premise-ledger as left-bottom-cell canonical case (自观测 + 结构化通道); cite delta_H = -1.46, TASK-152, N=13; note this systematic bias is what §2.2 isolation calibration is designed to detect

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q '典型实例' docs/research/grounding-infrastructure.md`
- [ ] `grep -q 'delta_H.*-1.46\|-1.46.*delta_H' docs/research/grounding-infrastructure.md`

## Phase 3: Verify and patch 关联 metadata headers
### Tests (write first)
- Check both documents for cross-reference presence: if either is missing, it must be patched

### Implementation
- Read 关联 header sections in both documents
- In `docs/baime-self-reference-analysis.md`: if 关联 field does not already include grounding-infrastructure.md entry, add: `- [\`grounding-infrastructure.md\`](research/grounding-infrastructure.md) — 接地基础设施：2×2 矩阵、隔离校准`
- In `docs/research/grounding-infrastructure.md`: verify 关联 field includes baime-self-reference-analysis.md; patch if missing

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'grounding-infrastructure' docs/baime-self-reference-analysis.md`
- [ ] `grep -q 'baime-self-reference-analysis' docs/research/grounding-infrastructure.md`

## Constraints
- All changes are doc-only; no modifications to `plugin/`, `scripts/`, or runtime files.
- Each file's total change < 10 lines.
- Do not modify §1–§8 headings or structure in grounding-infrastructure.md; only append within §2.1.
- Do not modify overall document structure of self-reference-analysis.md; only append within existing sections.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'grounding-infrastructure' docs/baime-self-reference-analysis.md`
- [ ] `grep -q '典型实例' docs/research/grounding-infrastructure.md`
- [ ] `grep -q 'baime-self-reference-analysis' docs/research/grounding-infrastructure.md`
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

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: G1+G2→Phase 1 (two forward refs in self-reference-analysis) / G3→Phase 2 (典型实例 paragraph) / G4→Phase 3 (关联 metadata) / G5→all phases (validate-plugin.sh)
[E] TDD structure: all 3 phases have Tests → Implementation → DoD in correct order
[E] first DoD item: bash scripts/validate-plugin.sh confirmed in all 3 phases
[E] acceptance gate: first item is bash scripts/validate-plugin.sh
[E] DoD executability: all items are shell commands (grep -q / bash)
[C] file paths: docs/baime-self-reference-analysis.md and docs/research/grounding-infrastructure.md both verified to exist on disk
[H] DoD sufficiency: grep -q on 5 target strings is adequate coverage signal for doc-only insertion tasks — background knowledge
GCL-self-report: E=5 C=1 H=1

claimed: 2026-06-24T09:07:58Z

Phase 1 ✓ 2026-06-24T00:00:00Z: Added §3 forward ref (2×2 matrix, H6 partial independence) and §挑战/接地问题 forward ref (isolation calibration, delta_H=-1.46, TASK-152) in self-reference-analysis.md

Phase 2 ✓ 2026-06-24T00:00:00Z: Added 典型实例 paragraph in grounding-infrastructure.md §2.1 positioning premise-ledger as canonical left-bottom-cell case (N=13, delta_H=-1.46)

Phase 3 ✓ 2026-06-24T00:00:00Z: Added grounding-infrastructure.md entry to 关联文档 header in self-reference-analysis.md; grounding-infrastructure.md already referenced baime-self-reference-analysis.md

DoD #1: PASS — bash scripts/validate-plugin.sh → ALL CHECKS PASSED (Errors: 0)

DoD #2: PASS — grep -q 'grounding-infrastructure' docs/baime-self-reference-analysis.md

DoD #3: PASS — grep -q '典型实例' docs/research/grounding-infrastructure.md

DoD #4: PASS — grep -q 'baime-self-reference-analysis' docs/research/grounding-infrastructure.md

## Execution Summary
Result: Done
Commit: e65c5de

Merge conflict: 2026-06-24T09:11:58Z

Completed: 2026-06-24T09:12:27Z
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 grep -q 'grounding-infrastructure' docs/baime-self-reference-analysis.md
- [ ] #3 grep -q '典型实例' docs/research/grounding-infrastructure.md
- [ ] #4 grep -q 'baime-self-reference-analysis' docs/research/grounding-infrastructure.md
<!-- DOD:END -->
