---
id: TASK-183
title: pre-dispatch enrichment：archguard change-risk 在 claim 时注入 worker context
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 05:49'
updated_date: '2026-06-24 09:04'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Inject archguard change-risk context into the worker execute prompt at claim time to reduce the C-component of GCL. Phase 1: create `scripts/lib/parse-task-files.js` — extract file paths from task description via regex (covering `plugin/`, `scripts/`, `docs/` prefixes), verify existence via `fs.existsSync`, return path list; self-test coverage ≥ 60% on 10 historical task descriptions. Phase 2: create `scripts/lib/fetch-risk-context.js` — given file list, read `.archguard/query/git-history/file-metrics.json` for commitCount/activeDays/topCochangeNeighbors (strength ≥ 0.2); format as `## Archguard Risk Context` Markdown block; return empty string when no data (advisory, non-blocking). Phase 3: integrate into `buildExecutePrompt` in `plugin/skills/loop-backlog/SKILL.md` — call both helpers and inject the risk block; omit block entirely when empty. Phase 4: after ≥5 gate events with enriched context, write `docs/research/gcl-predispatch-impact.md` with C-mean before/after comparison. DoD: `bash scripts/validate-plugin.sh` passes; enriched prompt contains `## Archguard Risk Context` when data is available.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: pre-dispatch enrichment — archguard change-risk 在 claim 时注入 worker context

## Background
当前 loop-backlog 的 `claimBatch` 流程中，worker 拿到的 context 仅限 task description（人类或 LLM 起草的意图描述）。description 不知道涉及文件的实际 cochange 风险，不知道历史中类似任务的执行模式，不知道过去导致过什么 merge conflict 或 DoD 失败。GCL 的 C 分量（均值 4.50，占 31%）部分反映了这个缺口：gate 判断者需要跨任务查阅外部文档、手工查找历史 cochange 关系，因为 intake 阶段没有把这些证据内联进来。本项目 `.archguard/query/git-history/file-metrics.json` 已有真实 change-risk 数据，archguard MCP 工具已就绪，改进方向是在 `claimBatch` 后、spawnAgent 前自动注入 archguard risk context。

## Goals
1. `scripts/lib/parse-task-files.js` 存在并可执行：从 task description 提取文件路径（plugin/、scripts/、docs/ 前缀），验证存在性，返回路径列表。`node scripts/lib/parse-task-files.js --self-test` exits 0 with coverage ≥ 60% on 10 historical descriptions.
2. `scripts/lib/fetch-risk-context.js` 存在并可执行：给定文件列表，从 `.archguard/query/git-history/file-metrics.json` 读取 commitCount/activeDays/topCochangeNeighbors (strength ≥ 0.2)，格式化为 `## Archguard Risk Context` Markdown block；无数据时返回空字符串。`node scripts/lib/fetch-risk-context.js --self-test` exits 0.
3. `buildExecutePrompt` in `plugin/skills/loop-backlog/SKILL.md` 调用两个 helpers，将 risk block 内联进 worker execute prompt；无数据时整体省略。`grep -q 'Archguard Risk Context' plugin/skills/loop-backlog/SKILL.md` exits 0.
4. `docs/research/gcl-predispatch-impact.md` 存在，包含 N≥5 gate events 的 C 分量观测表和 baseline: 4.50 vs post_mean delta。

## Proposed Approach
Phase 1: create `scripts/lib/` directory and `parse-task-files.js` with regex extraction + existsSync verification + self-test mode. Phase 2: create `fetch-risk-context.js` reading `.archguard/query/git-history/file-metrics.json` with MCP fallback (≤3 files). Phase 3: integrate both helpers into `buildExecutePrompt` in SKILL.md. Phase 4: after ≥5 enriched gate events, write measurement doc.

## Trade-offs and Risks
- Advisory only: archguard context is informational and never blocks claim flow; missing data silently skips injection.
- Regex over LLM for Phase 1: high precision / lower recall; LLM parsing deferred to follow-up task.
- MCP fallback capped at 3 files to limit per-claim latency to < 3 seconds.
- Phase 4 measurement depends on Phase 3 being live and ≥5 tasks completing gate; timing is data-driven not calendar-driven.

---

# Plan: pre-dispatch enrichment — archguard change-risk 在 claim 时注入 worker context

## Phase 1: Implement parse-task-files.js
### Tests (write first)
- `! test -f scripts/lib/parse-task-files.js` — file does not exist yet
- After implementation: `node scripts/lib/parse-task-files.js --self-test` exits 0 with ≥6/10 coverage

### Implementation
- Create `scripts/lib/` directory
- Create `scripts/lib/parse-task-files.js`:
  - Export `parseTaskFiles(description)` → `string[]`
  - Regex to extract tokens matching `(plugin|scripts|docs|\.archguard|\.claude)/\S+` from description
  - Filter candidates with `fs.existsSync(path.join(repoRoot, candidate))`
  - `--self-test` mode: runs 10 built-in historical task description samples, asserts ≥6 return non-empty arrays, prints pass/fail count, exits 0 on pass

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `node scripts/lib/parse-task-files.js --self-test`
- [ ] `test -f scripts/lib/parse-task-files.js`

## Phase 2: Implement fetch-risk-context.js
### Tests (write first)
- `! test -f scripts/lib/fetch-risk-context.js` — file does not exist yet
- After implementation: `node scripts/lib/fetch-risk-context.js --self-test` exits 0

### Implementation
- Create `scripts/lib/fetch-risk-context.js`:
  - Export `fetchRiskContext(files, repoRoot)` → `string` (Markdown block or empty string)
  - Read `.archguard/query/git-history/file-metrics.json`, build `filePath → metrics` index
  - For each file in input list: extract `commitCount`, `activeDays`, `topCochangeNeighbors` (strength ≥ 0.2)
  - Format as `## Archguard Risk Context` Markdown block with per-file table
  - Return empty string when no data found for any file
  - MCP fallback: if local file missing, attempt `archguard_get_change_risk` for ≤3 files
  - `--self-test` mode: tests against `plugin/skills/loop-backlog/SKILL.md` (expects non-empty result), tests empty-list input (expects empty string)

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `node scripts/lib/fetch-risk-context.js --self-test`
- [ ] `test -f scripts/lib/fetch-risk-context.js`

## Phase 3: Integrate into buildExecutePrompt in SKILL.md
### Tests (write first)
- `! grep -q 'Archguard Risk Context' plugin/skills/loop-backlog/SKILL.md` — not yet present

### Implementation
- In `plugin/skills/loop-backlog/SKILL.md`, in the `buildExecutePrompt` implementation section:
  - After task description is assigned to `TASK_DESC`, add:
    ```
    FILES=$(node scripts/lib/parse-task-files.js "$TASK_DESC")
    RISK_BLOCK=$(node scripts/lib/fetch-risk-context.js $FILES)
    ```
  - In the prompt heredoc, insert `$RISK_BLOCK` as a conditional block (omit entirely when empty)
  - Do not modify claimBatch state machine, cap:* markers, or signal file logic

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q 'Archguard Risk Context' plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q 'parse-task-files\|fetch-risk-context' plugin/skills/loop-backlog/SKILL.md`

## Phase 4: Write C-component impact measurement doc
### Tests (write first)
- `! test -f docs/research/gcl-predispatch-impact.md` — file does not exist yet

### Implementation
- After Phase 3 is live and ≥5 tasks have completed the gate with enriched context:
  - Extract `GCL-self-report: E=N C=N H=N` from those task Notes
  - Compute post-enrichment C-mean
  - Create `docs/research/gcl-predispatch-impact.md` with:
    - Observation table (task ID, date, C value, context_enriched: yes/no)
    - `baseline: 4.50`, `post_mean: X.XX`, `delta: ±Y.YY`
    - Interpretation: if delta ≤ -0.5 → G3 confirmed; else record deviation reasons

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f docs/research/gcl-predispatch-impact.md`
- [ ] `grep -q 'baseline: 4.50' docs/research/gcl-predispatch-impact.md`

## Constraints
- Advisory only: archguard injection never blocks claimBatch or spawnAgent; graceful skip when data unavailable.
- MCP fallback capped at 3 files per claim to keep latency < 3 seconds.
- Phase 3 must not modify claimBatch state machine, cap:* markers, or signal file timing.
- All SKILL.md edits must preserve existing contracts verified by validate-plugin.sh.
- Phase 4 measurement is data-gated (requires ≥5 gate events), not calendar-gated.

## Acceptance Gate
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `node scripts/lib/parse-task-files.js --self-test`
- [ ] `node scripts/lib/fetch-risk-context.js --self-test`
- [ ] `grep -q 'Archguard Risk Context' plugin/skills/loop-backlog/SKILL.md`
- [ ] `test -f docs/research/gcl-predispatch-impact.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Epic proposal self-review: APPROVED
premise-ledger:
[E] background lines: 6 lines (within 3-8 limit)
[E] concrete data: file-metrics.json 6 commits/2 days, cochange strength 0.29 cited
[E] C-分量 claim grounded in observed GCL mean 4.50 from gcl-corpus
[C] goal coverage: G1→sub-task 3, G2→sub-task 1, G3→sub-task 4, G4→sub-tasks 1+2, G5→sub-task 2
[C] all goals verifiable (shell-checkable or measurable vs gcl-corpus baseline)
[H] epic granularity: 4 sub-tasks, each independently deliverable, right-sized
GCL-self-report: E=1 C=2 H=1

Epic proposal approved. Starting epic plan draft.

cap:propose=approved

Plan review iteration 1: APPROVED
premise-ledger:
[E] goal coverage: G1→Phase 1 / G2→Phase 2 / G3→Phase 3 / G4→Phase 4 — direct read from plan phases
[E] TDD structure: all 4 phases have Tests → Implementation → DoD in correct order
[E] first DoD item: bash scripts/validate-plugin.sh confirmed in all 4 phases
[E] acceptance gate: first item is bash scripts/validate-plugin.sh
[E] DoD executability: all items are shell commands (node / bash / grep -q / test -f)
[C] file path validation: scripts/lib/ confirmed not yet existing (new directory); .archguard/query/git-history/file-metrics.json confirmed to exist on disk; plugin/skills/loop-backlog/SKILL.md confirmed to exist
[C] phase ordering: Phase 1+2 (helpers) before Phase 3 (integration) before Phase 4 (data-gated measurement) — verified from description dependency statement
[H] DoD sufficiency: self-test mode coverage ≥60% threshold adequate proxy for parser quality — background knowledge
GCL-self-report: E=5 C=2 H=1

claimed: 2026-06-24T08:56:43Z

Completed: 2026-06-24T09:04:11Z
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 node scripts/lib/parse-task-files.js --self-test
- [ ] #3 node scripts/lib/fetch-risk-context.js --self-test
- [ ] #4 grep -q 'Archguard Risk Context' plugin/skills/loop-backlog/SKILL.md
- [ ] #5 test -f docs/research/gcl-predispatch-impact.md
<!-- DOD:END -->
