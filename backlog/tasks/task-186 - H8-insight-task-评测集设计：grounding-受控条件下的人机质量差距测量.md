---
id: TASK-186
title: H8 insight-task 评测集设计：grounding 受控条件下的人机质量差距测量
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 05:50'
updated_date: '2026-06-24 09:37'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design the H8 insight-task evaluation set (doc-only) to bring H8 into falsifiable phase. Five new documents to create in `docs/research/`: (1) `h8-insight-task-taxonomy.md` — classification framework covering ≥3 insight task types (architecture comparison, problem definition review, product variant pre-screening), each with definition, boundary conditions, and example scenario template; (2) `h8-grounding-controlled-operationalization.md` — define "equal real-world observation evidence pack" (evidence types, cutoff rules, format spec, explicit handling of human implicit grounding, maturity annotations); (3) `h8-scoring-rubric.md` — multi-dimension quality rubric with ≥3 dimensions (solution completeness, trade-off identification, decision justifiability, evidence utilization), inter-rater consistency procedure (Cohen's kappa ≥ 0.6), proxy metrics (escape rate, rework rate); (4) `h8-evaluation-material-candidates.md` — ≥5 real judgment cases from `docs/adr/`, `docs/research/`, backlog history, each with metadata (task type, grounding sources, availability, difficulty estimate); (5) `h8-statistical-design.md` — null hypothesis, permutation test + Wilcoxon method, minimum sample size estimation, longitudinal retest procedure with grounding milestone triggers. DoD: all five `docs/research/h8-*.md` files exist.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: H8 insight-task 评测集设计 — grounding 受控条件下的人机质量差距测量

## Background
H8 假设（gcl-synthesis.md §新增假设、gcl-complete-observation-mechanism.md §5）主张：在 insight 任务（设计取舍、架构判断、产品品味、问题定义）上，控制 grounding 接入后，人机质量差距不显著；随接地基础设施建设，残差差距随时间收窄。H7 已在 routine gate 建立"无差异"，H8 把该结论推广到 insight 任务。当前缺少可实施的评测集：没有操作化的"grounding 受控"定义，没有覆盖多类 insight 任务的评分标准，没有明确的统计检验设计。gcl-complete §5 H8 可证伪规则明确要求该评测集存在。本任务是评测集的设计阶段（doc-only），不包含数据收集。

## Goals
1. `docs/research/h8-insight-task-taxonomy.md` 存在：≥3 种 insight 任务类别（架构方案对比、问题定义复审、产品 variant 取舍预筛），每类有定义、边界条件、示例场景模板。
2. `docs/research/h8-grounding-controlled-operationalization.md` 存在：同等真实世界观测证据包的构成要素、截止规则、格式规范、人类隐性 grounding 显式化方案、接地成熟度标注。
3. `docs/research/h8-scoring-rubric.md` 存在：≥3 个评分维度（方案完整性、关键权衡识别、决策可辩护性、信息利用率），评审者间一致性规程（Cohen's kappa ≥ 0.6），代理指标（escape rate、rework rate）。
4. `docs/research/h8-evaluation-material-candidates.md` 存在：≥5 个来自 docs/adr/、docs/research/、backlog/ 的真实判断案例候选，每条含任务类型、grounding 来源、可用性、难度估计。
5. `docs/research/h8-statistical-design.md` 存在：null hypothesis、置换检验 + Wilcoxon 方法、最小样本量估算、纵向重测规程（含 grounding 里程碑触发条件）。

## Proposed Approach
Five sequential phases, each creating one document. Phase 1 (taxonomy) first; Phases 2 (grounding operationalization) and 4 (material candidates) can follow immediately; Phase 3 (scoring rubric) depends on Phase 1+2; Phase 5 (statistical design) depends on Phase 3. All doc-only; no code changes.

## Trade-offs and Risks
- Design phase only: data collection and LLM/human comparison execution deferred until grounding infrastructure is ready.
- Scoring is partially subjective: rubric must separate measurable information-processing quality from B/C-class gates (preference, institutional responsibility) — latter are recorded but not scored.
- Phase 4 material candidates are limited to this project's own history; external expansion path documented as future work.
- TASK-176 dependency: gcl-events.jsonl schema fields (grounding_package_id) are annotated as "pending TASK-176" where they appear in the statistical design.

---

# Plan: H8 insight-task 评测集设计 — grounding 受控条件下的人机质量差距测量

## Phase 1: Create h8-insight-task-taxonomy.md
### Tests (write first)
- `! test -f docs/research/h8-insight-task-taxonomy.md` — file does not exist yet

### Implementation
- Create `docs/research/h8-insight-task-taxonomy.md` with:
  - Classification framework (based on cc-actor-network.md §4.6): architecture comparison, problem definition review, product variant pre-screening (≥3 types)
  - For each type: definition, boundary conditions, input/output description, example scenario template
  - Boundary with B/C-class gates: note that evaluation only covers measurable information-processing quality, not preference or institutional responsibility

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/h8-insight-task-taxonomy.md`
- [ ] `grep -q 'architecture\|架构\|insight' docs/research/h8-insight-task-taxonomy.md`

## Phase 2: Create h8-grounding-controlled-operationalization.md
### Tests (write first)
- `! test -f docs/research/h8-grounding-controlled-operationalization.md` — file does not exist yet

### Implementation
- Create `docs/research/h8-grounding-controlled-operationalization.md` with:
  - Evidence pack components: documentary (ADR, incident log, research excerpts), behavioral (runtime metrics — marked as "pending grounding infrastructure"), structural (codebase snapshot, architecture diagrams)
  - Information cutoff boundary rules: how to ensure human and machine receive equal and identically-bounded observations
  - Format spec: structured Markdown pack with frontmatter fields (evidence_type, cutoff_date, source_path)
  - Human implicit grounding externalization: interview/questionnaire procedure to identify and include raters' background knowledge
  - Grounding maturity annotations: "currently actionable" vs "pending behavioral grounding infrastructure"

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/h8-grounding-controlled-operationalization.md`
- [ ] `grep -q 'cutoff\|evidence_type\|implicit\|隐性' docs/research/h8-grounding-controlled-operationalization.md`

## Phase 3: Create h8-scoring-rubric.md
### Tests (write first)
- `! test -f docs/research/h8-scoring-rubric.md` — file does not exist yet

### Implementation
- Create `docs/research/h8-scoring-rubric.md` with:
  - Multi-dimensional quality rubric (Likert 5-scale or 0/1/2):
    - Solution completeness: are critical dimensions covered
    - Trade-off identification: are key trade-offs recognized and weighed
    - Decision justifiability: evidence-backed conclusion with traceable reasoning
    - Evidence utilization rate: does the output rely on the provided evidence pack vs. external implicit knowledge
  - Inter-rater consistency procedure: Cohen's kappa target ≥ 0.6, conflict resolution mechanism
  - Proxy metrics: escape rate (downstream rework/correction triggered), rework rate
  - Explicit note: B/C-class gates (preference origin, institutional responsibility) are recorded but not scored

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/h8-scoring-rubric.md`
- [ ] `grep -q "Cohen's kappa\|kappa" docs/research/h8-scoring-rubric.md`

## Phase 4: Create h8-evaluation-material-candidates.md
### Tests (write first)
- `! test -f docs/research/h8-evaluation-material-candidates.md` — file does not exist yet

### Implementation
- Scan `docs/adr/`, `docs/research/`, and recent backlog task history for real insight judgment cases
- Create `docs/research/h8-evaluation-material-candidates.md` with:
  - ≥5 candidate cases, each with: task type (from Phase 1 taxonomy), required grounding sources, current grounding availability, difficulty estimate
  - Selection criteria: real decision record (not invented), identifiable correct judgment (post-hoc validation or expert consensus), evidence pack reconstructible
  - External extension path: note domain coverage limitations of first batch

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/h8-evaluation-material-candidates.md`
- [ ] `grep -q 'grounding availability\|难度\|difficulty' docs/research/h8-evaluation-material-candidates.md`

## Phase 5: Create h8-statistical-design.md
### Tests (write first)
- `! test -f docs/research/h8-statistical-design.md` — file does not exist yet

### Implementation
- Create `docs/research/h8-statistical-design.md` with:
  - Null hypothesis: "Under grounding-controlled conditions (equal evidence packs), the distribution of quality scores for human vs. machine outputs shows no significant difference" (two-sided, α=0.05)
  - Test methods: permutation test (primary) + Wilcoxon signed-rank (secondary); rationale: non-normal small samples, matching gcl-complete §5 H8 falsifiability rule
  - Minimum sample size estimation: Cohen's d=0.5 (medium effect), power=0.8, α=0.05
  - Longitudinal retest procedure: grounding milestone triggers (infrastructure expansion checkpoints), retest criteria, "residual gap narrowing" judgment standard (two time-point comparison)
  - gcl-events.jsonl schema dependency: note `gate_actor_type`, `evidence_independence`, `grounding_package_id` fields required (pending TASK-176)

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/h8-statistical-design.md`
- [ ] `grep -q 'null hypothesis\|Wilcoxon\|permutation' docs/research/h8-statistical-design.md`

## Constraints
- All changes are doc-only; no modifications to `plugin/`, `scripts/`, or any runtime files.
- Scoring rubric must not score B/C-class gates (preference, institutional responsibility).
- Phase 4 material candidates must be real historical cases from the project, not invented scenarios.
- TASK-176 gcl-events.jsonl schema fields are annotated as "pending TASK-176" where they appear; Phase 5 is not blocked by TASK-176 completion.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/h8-insight-task-taxonomy.md`
- [ ] `test -f docs/research/h8-grounding-controlled-operationalization.md`
- [ ] `test -f docs/research/h8-scoring-rubric.md`
- [ ] `test -f docs/research/h8-evaluation-material-candidates.md`
- [ ] `test -f docs/research/h8-statistical-design.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Epic proposal self-review: APPROVED
premise-ledger:
[E] background lines: 8 行，涵盖 H8 来源、当前缺口、与 H7 的关系——直接可数
[C] goal coverage: Goals 1-5 对照 gcl-complete §5 H8 可证伪规则：「grounding 受控评测集存在」→ Goal 1+2；「独立评审+下游指标」→ Goal 3；「素材识别」→ Goal 4；「统计检验+纵向追踪」→ Goal 5；覆盖完整，需推断「Wilcoxon/置换检验」与 H8 统计要求的匹配，信心适中
[H] epic 粒度: 5 个 doc-only 子任务均为设计文档，无实现或数据收集，粒度一致；与背景知识判断相符
GCL-self-report: E=1 C=3 H=1

Epic proposal approved. Starting epic plan draft.

cap:propose=approved

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: G1→Phase 1 / G2→Phase 2 / G3→Phase 3 / G4→Phase 4 / G5→Phase 5 — direct read from plan phases
[E] TDD structure: all 5 phases have Tests → Implementation → DoD in correct order
[E] first DoD item: bash scripts/validate-plugin.sh confirmed in all 5 phases
[E] acceptance gate: first item is bash scripts/validate-plugin.sh
[E] DoD executability: all items are shell commands (test -f / grep -q / bash)
[C] file paths: docs/research/ confirmed to exist (grounding-infrastructure.md already there); all 5 h8-*.md files are new (correct)
[H] DoD sufficiency: grep -q spot checks adequate for doc-only creation tasks where the full content is authored by implementer — background knowledge
GCL-self-report: E=5 C=1 H=1

claimed: 2026-06-24T09:25:58Z

Phase 1 ✓ 2026-06-24T00:00:00Z: h8-insight-task-taxonomy.md created — 3 task types (arch comparison, problem definition review, product variant pre-screening), each with definition, boundary conditions, I/O description, scenario template, real case references

Phase 2 ✓ 2026-06-24T00:00:00Z: h8-grounding-controlled-operationalization.md created — EGEP 3-component spec (documentary/behavioral/structural), information cutoff rules (git hash preferred), frontmatter format spec, human implicit grounding externalization 4-step procedure, maturity annotation framework

Phase 3 ✓ 2026-06-24T00:00:00Z: h8-scoring-rubric.md created — 4 dimensions (SC/TI/DJ/EUR), Likert 5-scale + 0/1/2 for EUR, Cohen's kappa target ≥0.6 with conflict resolution procedure, escape_rate and rework_rate proxy metrics, B/C class gate recording-not-scoring rule

Phase 4 ✓ 2026-06-24T00:00:00Z: h8-evaluation-material-candidates.md created — 6 real cases from docs/adr/ and docs/proposals/ and docs/research/: ADR-001 (daemon script location), ADR-002 (Monitor lifecycle), proposal-daemon-monitor-event-driven, proposal-skill-layered-test, gcl-synthesis H4 ruling, grounding-infrastructure §1 revision. All with task type/sources/availability/difficulty metadata

Phase 5 ✓ 2026-06-24T00:00:00Z: h8-statistical-design.md created — two-sided H₀ (median equality), permutation test (primary) + Wilcoxon signed-rank (secondary), min sample N≈36 (d=0.5, power=0.8, α=0.05), 4-milestone longitudinal retest triggers, gcl-events.jsonl schema dependencies (grounding_package_id, h8_quality_score fields) marked pending TASK-176

DoD #1: PASS — bash scripts/validate-plugin.sh → Errors: 0, ALL CHECKS PASSED

DoD #2: PASS — test -f docs/research/h8-insight-task-taxonomy.md

DoD #3: PASS — test -f docs/research/h8-grounding-controlled-operationalization.md

DoD #4: PASS — test -f docs/research/h8-scoring-rubric.md

DoD #5: PASS — test -f docs/research/h8-evaluation-material-candidates.md

DoD #6: PASS — test -f docs/research/h8-statistical-design.md

## Execution Summary
Result: Done
Commit: be6c78d

Completed: 2026-06-24T09:37:32Z
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 test -f docs/research/h8-insight-task-taxonomy.md
- [ ] #3 test -f docs/research/h8-grounding-controlled-operationalization.md
- [ ] #4 test -f docs/research/h8-scoring-rubric.md
- [ ] #5 test -f docs/research/h8-evaluation-material-candidates.md
- [ ] #6 test -f docs/research/h8-statistical-design.md
<!-- DOD:END -->
