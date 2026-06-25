---
id: TASK-181
title: grounding-infrastructure.md 补全：缺口再分析、改进方案与过程展望
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 05:48'
updated_date: '2026-06-24 07:03'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Supplement §9 of `docs/research/grounding-infrastructure.md` with three sections that complete the document from analysis to action guidance: (1) §9.1 gap re-analysis — identify gcl-events.jsonl as the architectural spine (the only join key across all three grounding layers) and rank the remaining three gaps by leverage: escape rate > pre-dispatch enrichment > gate evidence pack; (2) §9.2 four improvement proposals — expand proposals 1–4 with trigger point, tools called, artifact produced, and implementation sequence (spine → proposal 3+1 → proposal 2 → proposal 4); (3) §9.3 process outlook — describe the four-stage closed loop (intake → execution → gate → outcome) using real project artifacts, derive three progressive consequences and two operational disciplines. All changes are doc-only, limited to `docs/research/grounding-infrastructure.md`.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: grounding-infrastructure.md §9 补全

## Background
`docs/research/grounding-infrastructure.md` covers grounding concepts through §8 but §9 "Current Status and Next Steps" only has a three-row status table and a short priority list. It does not complete three closing tasks: (1) gap re-analysis (the four gaps are architecturally non-equivalent — gcl-events.jsonl is the spine/join-key, not just another gap); (2) four actionable improvement proposals with trigger points, tools, artifacts, and sequencing; (3) a process outlook describing what the development workflow looks like once the infrastructure is built. Without these, §9 stays at "analysis" level and never reaches "action guidance" level.

## Goals
1. §9.1 gap re-analysis: gcl-events.jsonl identified as the architectural spine (only join key across all three grounding layers); remaining three gaps ranked by leverage: escape rate > pre-dispatch enrichment > gate evidence pack. Verifiable by reading the document's analysis logic.
2. §9.2 four improvement proposals: proposals 1–4 each expanded with trigger point, tools called, artifact produced, and implementation sequence (spine → proposal 3+1 → proposal 2 → proposal 4). Verifiable by cross-checking against §3–§5.
3. §9.3 process outlook: four-stage closed loop (intake → execution → gate → outcome) traced through real project artifacts, three progressive consequences, and two operational disciplines. Verifiable by internal logical consistency.
4. All changes are doc-only, limited to `docs/research/grounding-infrastructure.md`.

## Proposed Approach
Read the existing §9, then append three subsections in sequence. §9.1 re-ranks the four gaps architecturally. §9.2 expands each proposal with actionable detail, cross-referenced against the existing §4 tool table. §9.3 traces the full closed loop using real artifacts (loop-backlog SKILL.md, archguard local cache, gcl-events.jsonl) to derive consequences and disciplines.

## Trade-offs and Risks
- Not doing: modifying §1–§8 — only appending to §9 to avoid introducing contradictions with existing content.
- Risk: §9.3 process outlook may overlap with §7 (portable design principles); mitigated by focusing §9.3 on "how the workflow changes post-build" while §7 keeps its cross-project perspective.
- Not doing: creating runnable code; all output is documentation content relying on already-integrated tools.

---

# Plan: grounding-infrastructure.md §9 补全

## Phase 1: Write §9.1 gap re-analysis
### Tests (write first)
- `grep -q "脊梁\|spine\|join key" docs/research/grounding-infrastructure.md` — spine concept present
- `grep -q "escape rate" docs/research/grounding-infrastructure.md` — leverage ranking present

### Implementation
- Read existing `docs/research/grounding-infrastructure.md` §9 to find insertion point after the current status table.
- Append §9.1 (~200 words + leverage ranking table) identifying gcl-events.jsonl as the spine and ranking the other three gaps: escape rate (highest leverage: prerequisite for GCL to measure supervision quality and unlocks H5) → pre-dispatch enrichment (directly reduces C-component) → gate evidence pack (improves evidence independence at gate time).

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "脊梁\|spine\|join key" docs/research/grounding-infrastructure.md`
- [ ] `grep -q "escape rate" docs/research/grounding-infrastructure.md`

## Phase 2: Write §9.2 four improvement proposals
### Tests (write first)
- `grep -q "gate evidence pack\|pre-dispatch\|escape rate linkage" docs/research/grounding-infrastructure.md` — all four proposals present
- `grep -q "触发点\|trigger\|产出物\|artifact" docs/research/grounding-infrastructure.md` — actionable format present

### Implementation
- Append §9.2 (~400 words + proposal table + sequencing description) with four proposals:
  - Proposal 1 (gate evidence pack): trigger=verifyDod/epicEvaluate; tools=meta-cc query_file_activity + analyze_errors; artifact=actual-vs-declared file diff written to gate evidence pack in task Notes.
  - Proposal 2 (pre-dispatch enrichment): trigger=claimBatch; tools=archguard_get_change_risk + archguard_get_cochange; artifact=risk summary inlined into worker context.
  - Proposal 3 (escape rate linkage, TASK-176d): trigger=task reaches Needs Human or reaper requeue; tools=gcl-events.jsonl append; artifact=queryable link between gate decision and downstream escape event.
  - Proposal 4 (behavioral grounding to production): trigger=external product telemetry available; tools=TBD; artifact=real delivery metrics linked back to gate decisions.
  - Implementation sequence: spine (TASK-176a) → proposals 3+1 → proposal 2 → proposal 4.

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "gate evidence pack" docs/research/grounding-infrastructure.md`
- [ ] `grep -q "pre-dispatch" docs/research/grounding-infrastructure.md`

## Phase 3: Write §9.3 process outlook
### Tests (write first)
- `grep -q "四阶段\|four-stage\|intake.*execution\|execution.*gate" docs/research/grounding-infrastructure.md` — closed loop present
- `grep -q "操作纪律\|operational discipline" docs/research/grounding-infrastructure.md` — disciplines present

### Implementation
- Append §9.3 (~500 words) tracing the four-stage closed loop using real project artifacts:
  - Intake (system grounding): claimBatch auto-attaches archguard change-risk summary.
  - Execution (process grounding): meta-cc session trace records actual touched files, retry count.
  - Gate (decision grounding): verifyDod reads independent evidence pack, not worker self-report.
  - Outcome (behavioral grounding): escape events appended to gcl-events.jsonl, linked back to original gate decision.
  - Three progressive consequences: meta-cc+archguard become portable infrastructure; GCL hypotheses become data-queryable; escape rate patterns become answerable questions.
  - Two operational disciplines: (1) observation cost thermodynamic constraint (grounding depth should match task nature; doc-only tasks may have exemption logic); (2) D-pillar risk (escape rate is proxy for behavioral grounding until proposal 4 is built; all "supervision quality sufficient" conclusions must note this).

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "四阶段\|four-stage" docs/research/grounding-infrastructure.md`
- [ ] `grep -q "操作纪律\|operational discipline" docs/research/grounding-infrastructure.md`

## Constraints
- Only modify `docs/research/grounding-infrastructure.md`; no changes to `plugin/`, `scripts/`, `backlog/`, or any runtime file.
- Append after existing §9 content only; do not modify §1–§8.
- Cross-check §9.2 proposal tool details against existing §4 tool table for consistency.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "脊梁\|spine\|join key" docs/research/grounding-infrastructure.md`
- [ ] `grep -q "gate evidence pack" docs/research/grounding-infrastructure.md`
- [ ] `grep -q "四阶段\|four-stage" docs/research/grounding-infrastructure.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Epic proposal self-review: APPROVED
premise-ledger:
[E] background lines: 6 lines in Background section (直接计数)
[C] goal coverage: G1~G4 逐条对照 Decomposition Sketch A/B/C 验证覆盖（A→G1，B→G2，C→G3，doc-only→G4）
[H] epic 粒度: 三个子任务规模均匀，§9 补全不需要跨越 plugin/ 边界，粒度合理靠背景知识判断
GCL-self-report: E=1 C=2 H=1

Epic plan review iteration 1: APPROVED
premise-ledger:
[E] sub-task count: 3 子任务（181a / 181b / 181c），直接计数
[C] goal coverage: G1→1bc，G2→181b，G3→181c，G4→Constraints — 逆向验证每个 Goal 均有子任务对应
[H] sequencing 合理性: A→B→C 的依赖理由（杠杆识别先于方案详情，方案详情先于过程展望）靠背景知识判断
GCL-self-report: E=1 C=2 H=1

cap:propose=approved

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: 4 goals mapped to Phase 1 (§9.1) / Phase 2 (§9.2) / Phase 3 (§9.3) / Constraints (doc-only)
[E] TDD structure: each phase has Tests → Implementation → DoD in correct order
[E] first DoD item: bash scripts/validate-plugin.sh confirmed in all three phases
[E] acceptance gate: first item is bash scripts/validate-plugin.sh
[E] DoD executability: all DoD items are shell commands (grep -q / bash)
[C] file path: docs/research/grounding-infrastructure.md verified to exist on disk
[C] tool cross-ref: §9.2 proposal tools (meta-cc, archguard) consistent with §4 table per task description
[H] DoD sufficiency baseline: adequacy of grep checks as implementation proof relies on background knowledge of doc-append task norms
GCL-self-report: E=5 C=2 H=1

claimed: 2026-06-24T06:58:46Z

All three phases complete. §9.1 identifies gcl-events.jsonl as spine/join key across all three grounding layers; ranks escape-rate > pre-dispatch > gate-evidence-pack by leverage. §9.2 expands four proposals with trigger point, tools called, artifact produced, and implementation sequence (spine → P3+P1 → P2 → P4). §9.3 describes four-stage closed loop (intake→execution→gate→outcome) using real project artifacts, derives three progressive consequences and two operational disciplines. All DoD checks pass (validate-plugin.sh, spine/join key, gate evidence pack, four-stage). Committed as c635ef5.

Phase 1 ✓ 2026-06-24T00:00:00Z
§9.1 written: gcl-events.jsonl identified as spine/join key; three gaps ranked escape-rate > pre-dispatch > gate-evidence-pack
Phase 2 ✓ 2026-06-24T00:00:01Z
§9.2 written: four proposals with trigger/tools/artifact/sequence table; spine→P3+P1→P2→P4 ordering
Phase 3 ✓ 2026-06-24T00:00:02Z
§9.3 written: four-stage closed loop (intake→execution→gate→outcome), three recursive consequences, two operational disciplines

Completed: 2026-06-24T07:03:22Z
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 grep -q "脊梁\\|spine\\|join key" docs/research/grounding-infrastructure.md
- [ ] #3 grep -q "gate evidence pack" docs/research/grounding-infrastructure.md
- [ ] #4 grep -q "四阶段\\|four-stage" docs/research/grounding-infrastructure.md
<!-- DOD:END -->
