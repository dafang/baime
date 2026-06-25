---
id: TASK-194
title: GCL 后验反馈管线：git history + meta-cc session record 联接，量化验证 gate 逃逸率与 delta_H
status: 'Basic: Done'
assignee: []
created_date: '2026-06-24 16:12'
updated_date: '2026-06-24 16:59'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GCL 后验反馈管线：git history + meta-cc session record 联接，量化验证 gate 逃逸率与 delta_H

背景：当前 gcl-events.jsonl 有 33 个 gate 自报事件，但 delta_H=0、sample_run_id=0/33、escape_rate 字段几乎全空。TASK-153~158 batch 六个任务 GCL 完全相同（stdev=0），表明自报存在 stereotypy。需要用真实反馈信号验证 GCL 自报的效度：git history 中的修正提交是已实现逃逸的直接证据；meta-cc session record 提供分类标签（用户意图措辞）和未形成 commit 的摩擦信号。
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: GCL 后验反馈管线：git history + meta-cc session record 联接，量化验证 gate 逃逸率与 delta_H

## Background

当前 gcl-events.jsonl 积累了 33 个 gate 自报事件，但这些数据的效度缺乏外部校验：`delta_H` 字段全部为空，`escape_rate` 几乎全零，`sample_run_id` 无一非空。TASK-153~158 六个连续任务 GCL 均等于 7（stdev=0），暴露了自报存在系统性 stereotypy 的风险——模型对相似任务结构产生相同评分，而非独立测量各任务的实际认知负载。gcl-synthesis.md §H10 的两段制框架指出，escape 应被重定义为"先验 gate 漏过且后验循环未及时捕获的缺陷"，但这一重定义目前没有数据支撑，因为 git history、meta-cc session record 和 gcl-events.jsonl 三个数据源彼此独立、未关联回任务 ID。本管线的目的是建立这条关联，让先验 gate 的 H 自报第一次能与后验行为信号比对，为 H10 的可证伪规则提供实测数据。

## Goals

1. 对 gcl-events.jsonl 中所有非空 task_id，通过 `git log --grep=TASK-NNN` 提取关联提交，按提交消息分类为 additive（功能完成）或 corrective（修正先前缺陷），输出每任务 corrective commit 数量，结果写入 `docs/research/gcl-commit-map.jsonl`。
2. 对每个 corrective commit，定位其时间戳，通过 meta-cc `query_user_messages` 在时间窗口内查询用户消息，利用用户措辞作为主分类信号判定该 commit 是否对应先验 gate 通过后的缺陷发现，填充 gcl-events.jsonl 中对应记录的 `escape_rate` 字段（重定义版：0/1/null）。
3. 对已有先验 gate H 自报的任务，计算 `delta_H = corrective_H_revealed - H_reported`，填充 gcl-events.jsonl 中对应记录的 `delta_H` 字段，输出 delta_H 分布统计（均值、std、分位数）；验证 TASK-153~158 batch 的 stdev=0 是否在后验信号中也复现。
4. 计算 MTTD（Mean Time to Detection）= 后验发现时间戳 − 先验 gate 时间戳，按任务类型和 gate 类型分层报告，并以 `days_to_detection` 字段追加至 gcl-events.jsonl schema（gcl-events-schema.md 同步更新）。
5. 输出一个可增量运行的分析脚本 `scripts/gcl-posterior-pipeline.py`，使管线在新 task 完成后能幂等地追加运行，不修改已填充字段。

## Proposed Approach

管线由三层关联构成。第一层（git 关联）：对 gcl-events.jsonl 中每个 task_id 运行 `git log --grep=TASK-NNN --oneline`，按提交消息关键词（fix、revert、correct、amend 等）初步标记 corrective 候选，输出 task→commit 映射表。第二层（用户意图分类）：对每个 corrective 候选提交取其 commit_timestamp，调用 meta-cc `query_user_messages` 在 ±30 分钟窗口内检索用户消息；用户在 Claude Code session 中的明确陈述是分类的主信号，若窗口内无用户消息则标记为 ambiguous。第三层（字段回填）：将分类结果写回 gcl-events.jsonl 的 `escape_rate` 和 `delta_H` 字段，计算 MTTD 并追加 `days_to_detection` 字段。

关键交付物：`scripts/gcl-posterior-pipeline.py`；`docs/research/gcl-posterior-analysis.md`；`docs/research/gcl-events-schema.md` 新增字段定义。

## Trade-offs and Risks

不实现实时监听（离线批处理，手动触发）；不引入启发式 commit 自动分类作为主信号；不修改先验 gate 评分流程。已知风险：时间戳漂移（±30 分钟窗口匹配失败）；历史提交消息措辞不统一；初次运行可填充 delta_H 值有限，统计功效可能不足。

---

# Plan: GCL 后验反馈管线：git history + meta-cc session record 联接，量化验证 gate 逃逸率与 delta_H

## Phase A: git 关联层 — task→commit 映射表

### Tests (write first)
- `scripts/gcl-posterior-pipeline.py --phase a` 在空输出目录执行后，`docs/research/gcl-commit-map.jsonl` 应存在且每条记录含 `task_id`、`commit_hash`、`commit_type`（additive/corrective/ambiguous）字段
- 对已知含 corrective commit 的任务（如 TASK-128），`commit_type` 应为 `corrective`

### Implementation
- 新建 `scripts/gcl-posterior-pipeline.py`，实现 `--phase a` 子命令
- 读取 `docs/research/gcl-events.jsonl`，提取全部唯一 task_id
- 对每个 task_id 执行 `git log --grep=<task_id> --oneline --format=%H|%ai|%s`
- 按关键词集（fix、revert、correct、amend、repair、patch、hotfix、rollback）标记 corrective；其余标记 additive；无法确定标记 ambiguous
- 输出 `docs/research/gcl-commit-map.jsonl`（每提交一行），幂等（已存在 hash 跳过）

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f scripts/gcl-posterior-pipeline.py`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase a`
- [ ] `test -f docs/research/gcl-commit-map.jsonl`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-commit-map.jsonl')]; assert all('commit_type' in r for r in recs)"`
- [ ] `! grep -q '"commit_type": ""' docs/research/gcl-commit-map.jsonl`

## Phase B: meta-cc 意图分类层 — corrective/additive 判定

### Tests (write first)
- `--phase b` 执行后，`docs/research/gcl-intent-classification.jsonl` 存在且每条记录含 `escape_signal`（0/1/null）和 `intent_source`（user_message/ambiguous/no_window_match）
- 对 `commit_type=corrective` 的候选，`intent_source` 应为 `user_message` 或 `ambiguous`（不应为 `no_window_match` 当 session record 存在时）

### Implementation
- 实现 `--phase b --window 30`（默认 ±30 分钟窗口）
- 读取 `docs/research/gcl-commit-map.jsonl`，筛选 `commit_type=corrective` 的候选
- 对每条候选取 `commit_timestamp`，调用 meta-cc `query_user_messages` 检索窗口内消息
- 用 LLM 对用户消息分类（主信号：用户措辞是否表明"之前的实现有问题"）
- 输出 `docs/research/gcl-intent-classification.jsonl`，含 `escape_signal`、`intent_source`、`user_message_preview`

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase b`
- [ ] `test -f docs/research/gcl-intent-classification.jsonl`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-intent-classification.jsonl')]; assert all('escape_signal' in r for r in recs)"`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-intent-classification.jsonl')]; assert all(r['intent_source'] in ('user_message','ambiguous','no_window_match') for r in recs)"`
- [ ] `! grep -q '"intent_source": ""' docs/research/gcl-intent-classification.jsonl`

## Phase C: 字段回填与分析输出

### Tests (write first)
- `--phase c` 执行后，`docs/research/gcl-posterior-analysis.md` 存在且含 "delta_H"、"MTTD"、"TASK-153" 关键词
- `docs/research/gcl-events-schema.md` 含 `delta_H` 和 `days_to_detection` 字段定义
- `docs/research/gcl-events.jsonl` 中每条记录含 `gate_outcome` 和 `gate_timing` 字段

### Implementation
- 实现 `--phase c`
- 将 Phase B 的 `escape_signal` 写回 `gcl-events.jsonl` 对应记录的 `escape_rate` 字段
- 计算 `delta_H`：读 corrective session 用户消息，LLM 提取"被修正的隐性假设"，与 `H_reported` 比对
- 计算 MTTD，写入 `days_to_detection`；追加 `gate_outcome`（pass/escape/unknown）和 `gate_timing` 字段
- 更新 `docs/research/gcl-events-schema.md`，追加 4 个新字段定义
- 生成 `docs/research/gcl-posterior-analysis.md`，含 delta_H 分布统计、MTTD 分层报告、TASK-153~158 stereotypy 验证段落

### DoD
- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase c`
- [ ] `test -f docs/research/gcl-posterior-analysis.md`
- [ ] `grep -q "delta_H" docs/research/gcl-posterior-analysis.md`
- [ ] `grep -q "MTTD" docs/research/gcl-posterior-analysis.md`
- [ ] `grep -q "delta_H" docs/research/gcl-events-schema.md`
- [ ] `grep -q "days_to_detection" docs/research/gcl-events-schema.md`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert all('gate_outcome' in r for r in recs)"`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert all('gate_timing' in r for r in recs)"`
- [ ] `! grep -q '"gate_outcome": ""' docs/research/gcl-events.jsonl`

## Constraints

- 管线为离线批处理，不实现实时监听或 webhook 触发
- 分类主信号为 meta-cc 用户消息措辞，不以 commit 消息关键词作为唯一依据
- 不修改先验 gate 评分流程（gcl-events.jsonl 中已有字段只追加新字段，不覆盖）
- `gate_outcome` 和 `gate_timing` 字段作为 schema 扩展，支持 Goal 4 的 MTTD 分层报告
- Phase A 产出 gcl-commit-map.jsonl 供 Phase B 消费；Phase B 产出 gcl-intent-classification.jsonl 供 Phase C 消费

## Acceptance Gate

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f scripts/gcl-posterior-pipeline.py`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase a && test -f docs/research/gcl-commit-map.jsonl`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase b && test -f docs/research/gcl-intent-classification.jsonl`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase c && test -f docs/research/gcl-posterior-analysis.md`
- [ ] `grep -q "delta_H" docs/research/gcl-events-schema.md`
- [ ] `grep -q "days_to_detection" docs/research/gcl-events-schema.md`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert all('gate_outcome' in r and 'gate_timing' in r for r in recs)"`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-intent-classification.jsonl')]; assert all(r['intent_source'] in ('user_message','ambiguous','no_window_match') for r in recs)"`
- [ ] `grep -q "MTTD" docs/research/gcl-posterior-analysis.md`
- [ ] `grep -q "TASK-153" docs/research/gcl-posterior-analysis.md`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Proposal self-review: APPROVED
premise-ledger:
[E] Background: stereotypy evidence (TASK-153~158, stdev=0) — readable from task description
[E] Background: delta_H=0/33, sample_run_id=0/33, escape_rate nearly all null — readable from task description
[E] Goal 1: git log --grep pattern — standard git command, no external lookup needed
[E] Goal 5: scripts/ directory exists — verified via ls
[C] Background: H10 two-phase framework (gcl-synthesis.md §H10) — requires reading gcl-synthesis.md
[C] Approach: meta-cc query_user_messages as classification signal — requires checking meta-cc MCP tool availability
[H] Risk: ±30 min window adequacy for timestamp matching — background knowledge about typical session/commit timing
[H] Risk: statistical power with N<33 completed tasks — background knowledge about minimum sample sizes
GCL-self-report: E=4 C=2 H=2

Proposal approved. Starting plan draft.

Plan review iteration 1: APPROVED
premise-ledger:
[E] Goal coverage: all 5 Goals addressed by Phases A/B/C; gate_outcome+gate_timing scope added to Constraints for Goal 4 backing
[E] TDD structure: each Phase has ### Tests before ### Implementation
[E] TDD order: first DoD item in all 3 Phases is bash scripts/validate-plugin.sh
[C] Acceptance gate: first item is bash scripts/validate-plugin.sh
[C] DoD executability: all DoD and Acceptance Gate items are shell commands; no natural-language items
[C] Absence checks: ! grep -q pattern used in all 3 phases; no grep -qv
[C] Phase ordering: A→B→C linear dependency, no circular deps
[H] Scope discipline: gate_outcome/gate_timing fields lacked Goal backing — fixed by adding to Constraints under Goal 4 schema completeness
[H] File paths: docs/research/gcl-events.jsonl, docs/research/gcl-events-schema.md, scripts/ all confirmed to exist
GCL-self-report: E=3 C=4 H=2

claimed: 2026-06-24T16:46:48Z

Phase A ✓ 2026-06-24T16:53:00Z - Built gcl-commit-map.jsonl: 58 commits across 18 task_ids, 5 classified as corrective (TASK-157 x2, TASK-159, TASK-165 x2)

Phase B ✓ 2026-06-24T16:53:20Z - Intent classification: escape_signal=1 for TASK-157 (user message + session summary mentions fix/error), TASK-159 (task-notification in window); TASK-165 ambiguous (user message was '执行了吗？'); timestamp parsing fixed for Z-suffix ISO format

Phase C ✓ 2026-06-24T16:55:00Z - Backfilled 23 gcl-events.jsonl records with gate_outcome/gate_timing/days_to_detection; escape_rate=8.7% (2/23); TASK-157 confirmed escape; generated gcl-posterior-analysis.md; updated schema with 4 new fields

DoD #1: PASS — bash scripts/validate-plugin.sh (0 errors)

DoD #2: PASS — test -f scripts/gcl-posterior-pipeline.py

DoD #3: PASS — python3 --phase a && test -f docs/research/gcl-commit-map.jsonl

DoD #4: PASS — python3 --phase b && test -f docs/research/gcl-intent-classification.jsonl

DoD #5: PASS — python3 --phase c && test -f docs/research/gcl-posterior-analysis.md

DoD #6: PASS — grep -q delta_H docs/research/gcl-events-schema.md

DoD #7: PASS — grep -q days_to_detection docs/research/gcl-events-schema.md

DoD #8: PASS — grep -q MTTD docs/research/gcl-posterior-analysis.md

DoD #9: PASS — grep -q TASK-153 docs/research/gcl-posterior-analysis.md

## Execution Summary
Result: Done
Commit: 044152f

workerLoop DoD #1: PASS — bash scripts/validate-plugin.sh

workerLoop DoD #2: PASS — test -f scripts/gcl-posterior-pipeline.py

workerLoop DoD #3: PASS — python3 scripts/gcl-posterior-pipeline.py --phase a && test -f docs/research/gcl-commit-map.jsonl

workerLoop DoD #4: PASS — python3 scripts/gcl-posterior-pipeline.py --phase b && test -f docs/research/gcl-intent-classification.jsonl

workerLoop DoD #5: PASS — python3 scripts/gcl-posterior-pipeline.py --phase c && test -f docs/research/gcl-posterior-analysis.md

workerLoop DoD #6: PASS — grep -q 'delta_H' docs/research/gcl-events-schema.md

workerLoop DoD #7: PASS — grep -q 'days_to_detection' docs/research/gcl-events-schema.md

workerLoop DoD #8: PASS — grep -q 'MTTD' docs/research/gcl-posterior-analysis.md

workerLoop DoD #9: PASS — grep -q 'TASK-153' docs/research/gcl-posterior-analysis.md

Completed: 2026-06-24T16:59:14Z
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 test -f scripts/gcl-posterior-pipeline.py
- [ ] #3 python3 scripts/gcl-posterior-pipeline.py --phase a && test -f docs/research/gcl-commit-map.jsonl
- [ ] #4 python3 scripts/gcl-posterior-pipeline.py --phase b && test -f docs/research/gcl-intent-classification.jsonl
- [ ] #5 python3 scripts/gcl-posterior-pipeline.py --phase c && test -f docs/research/gcl-posterior-analysis.md
- [ ] #6 grep -q "delta_H" docs/research/gcl-events-schema.md
- [ ] #7 grep -q "days_to_detection" docs/research/gcl-events-schema.md
- [ ] #8 grep -q "MTTD" docs/research/gcl-posterior-analysis.md
- [ ] #9 grep -q "TASK-153" docs/research/gcl-posterior-analysis.md
<!-- DOD:END -->
