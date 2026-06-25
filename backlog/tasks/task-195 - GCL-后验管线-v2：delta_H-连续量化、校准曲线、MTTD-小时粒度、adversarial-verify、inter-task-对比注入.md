---
id: TASK-195
title: GCL 后验管线 v2：delta_H 连续量化、校准曲线、MTTD 小时粒度、adversarial verify、inter-task 对比注入
status: 'Basic: Backlog'
assignee: []
created_date: '2026-06-24 17:11'
updated_date: '2026-06-24 17:23'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 122000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GCL 后验管线 v2：delta_H 连续量化、H vs escape_rate 校准曲线、MTTD 小时粒度、escape_signal adversarial verify、inter-task 对比注入反 stereotypy

背景：TASK-194 建立了 gcl-posterior-pipeline.py 三阶段管线（git 关联→用户意图分类→字段回填），首次将 GCL 自报与真实逃逸行为信号联接。当前管线存在五项已知局限：(1) delta_H 仅为 0/1 二元下界估计；(2) H_reported 与实际 escape_rate 的预测关系未验证；(3) MTTD days_to_detection=0（无区分度）；(4) escape_signal 基于关键词匹配、误报率未量化；(5) stereotypy 无干预机制。本任务系统性解决这五项局限，使 GCL 从描述性负载测量升级为可操作的风险预测工具。
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: GCL 后验管线 v2：delta_H 连续量化、校准曲线、MTTD 小时粒度、adversarial verify、inter-task 对比注入

## Background

The v1 posterior pipeline (TASK-194) established git-history + meta-cc session linkage to compute escape_rate and delta_H, but three structural measurement gaps remain. First, delta_H is hardcoded as a binary floor (0 or 1): a confirmed escape always yields delta_H=1 regardless of how many distinct hidden premises the corrective session reveals. This collapses qualitatively different escape magnitudes into a single point and prevents any regression analysis against H_reported. Second, the H_reported → escape_rate relationship is assumed monotonically negative but has never been empirically checked: without a calibration curve we cannot tell whether H=2 gates genuinely outperform H=1 gates or whether the self-report signal is noise. Third, MTTD is computed in days, which rounds intra-session corrections to 0.000 days — confirmed by the current analysis showing mean_MTTD=0.000d across all three observed events. Days granularity destroys the precision needed to distinguish "caught in the same session" from "caught the next day." Additionally, escape_signal classification depends entirely on keyword heuristics with no adversarial check, making the false-positive rate unquantified and potentially inflating escape_rate. Finally, the stereotypy diagnosis already confirmed that LLMs batch-scoring similar tasks converge to identical GCL scores (stdev≈0 across TASK-153~158), yet gate prompts carry no inter-task contrast signal to break this attractor.

## Goals

1. **delta_H 升级为连续量**：pipeline 对每个逃逸事件输出 delta_H 为整数（对应修正会话中可识别的独立 hidden premise 数量，下界为 1），而非固定为 1；非逃逸事件保持 delta_H=0。验证：delta_H 分布中至少一条逃逸记录出现 delta_H ≥ 2，或所有记录提取结果有书面记录，gcl-events-schema.md 中字段说明更新为"连续计数（整数）"。
2. **H vs escape_rate 校准曲线**：Phase C 输出的 gcl-posterior-analysis.md 中新增独立章节，按 H_reported 桶（H=0、H=1、H=2、H≥3）分别计算实际 escape_rate。验证：报告中出现校准表，每行包含桶标签、N 值和 escape_rate 数值，空桶标注 N=0 而非省略。
3. **MTTD 小时粒度**：`days_to_detection` 字段替换为 `hours_to_detection`（单位：小时，保留两位小数），Phase C 报告中对应表头改为"小时"列。验证：gcl-events.jsonl 中现有三条 days_to_detection=0.000 的记录迁移后显示为精确小时数（预期 < 1.00h），报告均值单位标注为"h"。
4. **escape_signal adversarial verify**：Phase B 对所有 escape_signal=1 分类增加 refuter 步骤，若检测到关键词出现在引号、代码块或日志行等非意图上下文中，将 escape_signal 降级为 null，新增 `intent_source_v2` 字段设为 "refuted"。验证：gcl-intent-classification.jsonl 中每条原 escape_signal=1 的记录均有 `intent_source_v2` 字段，至少一条记录的值为 "refuted" 或 "user_message"（表明 refuter 确实对每条记录执行过）。
5. **inter-task 对比注入**：新增 `build_gate_context(task_id, gate_type)` 函数，从 gcl-events.jsonl 检索同 gate_type 的最近历史记录，返回含 `contrast_task_id`、`contrast_GCL`、`contrast_gate_outcome` 的字典供 gate prompt 构造器使用；gcl-events-schema.md 新增可选字段 `contrast_task_id`。验证：函数在单元调用时对已有 23 条记录能成功返回非空字典，schema 文件中 `contrast_task_id` 字段定义可检索到。

## Proposed Approach

**改进 1 — delta_H 连续量化**：在 Phase B 的 `classify_escape` 之后增加 `count_hidden_premises(messages)` 函数。该函数扫描修正会话中 type=assistant 的消息，用正则识别 hidden-premise 认领句（"I missed…"、"assumption was…"、"forgot that…"、"should have checked…" 及中文对应模式），每句计为 delta_H +1，起点为 1（只要发生逃逸就至少 +1）。结果写入 intent-classification 记录的 `delta_H_count` 字段，Phase C 从该字段读取而非硬编码为 1。

**改进 2 — 校准曲线**：Phase C 在现有 escape_rate_by_gate 循环之后增加 `build_calibration_curve(events)` 函数，将 event 按 H 值分桶（0、1、2、≥3），计算每桶的 escape count 和 escape_rate，输出为 Markdown 表格追加到 gcl-posterior-analysis.md。桶边界固定，确保随数据增长结果可横向比较。

**改进 3 — MTTD 小时粒度**：将 `days_to_detection` 计算公式改为 `delta.total_seconds() / 3600`（保留两位小数），字段重命名为 `hours_to_detection`。Phase C 的 backfill 逻辑增加迁移步骤：若记录存在旧 `days_to_detection` 字段，则按 ×24 换算写入 `hours_to_detection` 并删除旧字段。gcl-events-schema.md 相应更新字段名称和单位说明。

**改进 4 — adversarial verify**：Phase B 在 `classify_escape` 之后增加 `refute_escape(messages)` 函数。该函数检查以下模式：(a) 关键词出现在引号内或 markdown 代码块内；(b) 关键词主语是外部系统而非当前任务；(c) 消息整体是日志输出（以 `[` 开头或含 `exit code 0`）。满足任一模式则降级 escape_signal 为 null，intent_source_v2 设为 "refuted"，否则保持 intent_source_v2 为 "user_message"。此逻辑为纯规则型，无需二次 LLM 调用，保持管线确定性。

**改进 5 — inter-task 对比注入**：新增独立函数 `build_gate_context(task_id, gate_type, events_path)` 读取 gcl-events.jsonl，过滤同 gate_type 的记录（排除当前 task_id），按 timestamp 降序取最近一条，返回对比字典。该函数供 gate prompt 构造器调用，将对比区块插入 premise-ledger 之前。gcl-events.jsonl 新增可选字段 `contrast_task_id` 记录本次 gate 注入的历史对比基准。

## Trade-offs and Risks

**未做之事**：改进 4 不引入 LLM-as-refuter，避免管线引入不确定性和推理成本；不修改 gcl-events.jsonl 的历史记录格式（字段重命名通过迁移步骤处理）；校准曲线不使用自适应桶边界，以保持时序可比性；不自动重新分类已有历史 delta_H=1 的记录（连续量提取仅对新运行生效）。

**已知风险**：
- delta_H 连续计数依赖助手自报式措辞识别，若修正会话未使用目标模式则提取为 0，连续量退化回二值（保守但不会引入虚高估计）。
- hours_to_detection 字段重命名是破坏性变更：所有依赖 `days_to_detection` 字段名的下游查询脚本需同步更新，否则静默产生 null。
- inter-task 对比注入基于时间戳最近而非语义相似度，当前仅 23 条记录可能注入相关性低的对比基准，效果随数据规模增长才能稳定。
- adversarial verify 的规则集覆盖有限，口语化"fix this bug"作为新需求描述的场景仍可能通过，假阳性率未量化。

---

# Plan: GCL 后验管线 v2：delta_H 连续量化、校准曲线、MTTD 小时粒度、adversarial verify、inter-task 对比注入

## Phase A: delta_H 连续量化（--extract-hidden-premises）

### Tests (write first)

```python
# test_phase_a_delta_H.py  (write before implementing)
# T1: count_hidden_premises returns int >= 1 when messages contain admission pattern
# T2: count_hidden_premises returns 0 when no escape (caller must pass is_escape=False)
# T3: "I missed the constraint" → delta_H_count = 1
# T4: two distinct admission sentences → delta_H_count = 2
# T5: admission inside markdown code block → NOT counted (Phase D concerns; here just baseline patterns)
# T6: delta_H_count field present in every intent-classification record after --extract-hidden-premises
# T7: non-escape record has delta_H_count = 0
```

### Implementation

Files to modify: `scripts/gcl-posterior-pipeline.py`

- Add `count_hidden_premises(messages)` function: scans `type=assistant` session messages within the commit-window, applies regex for admission phrases ("I missed", "assumption was", "forgot that", "should have checked", "我忽略了", "未考虑到"), returns count (floor 1 if escape).
- Add `--extract-hidden-premises` flag to `main()` parser (additive; default False).
- In `phase_b()`: when `--extract-hidden-premises` is set and `escape_signal == 1`, call `count_hidden_premises()` and write `delta_H_count` (int) into the intent-classification record.
- In `phase_c()`: read `delta_H_count` from intent-classification records (fall back to legacy value 1 if field absent) instead of hardcoded 1; write `delta_H_continuous` into each updated event.

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase b --extract-hidden-premises && python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-intent-classification.jsonl')]; assert any(isinstance(r.get('delta_H_count'), (int,float)) for r in recs), 'No delta_H_count found'"`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase c && python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert all('delta_H_continuous' in r or r.get('gate_outcome') != 'escape' for r in recs), 'escape record missing delta_H_continuous'"`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase b && python3 -c "print('backward compat ok')"`

---

## Phase B: H vs escape_rate 校准曲线（--calibration）

### Tests (write first)

```python
# test_phase_b_calibration.py  (write before implementing)
# T1: build_calibration_curve([]) returns table with all 4 buckets, each N=0
# T2: event with H=0 and gate_outcome="escape" → bucket H=0 escape_count += 1
# T3: event with H=3 → assigned to bucket "≥3"
# T4: event with H=2 → assigned to bucket "H=2"
# T5: output markdown contains "calibration_curve" header
# T6: empty bucket is present in output with N=0 (not omitted)
# T7: --calibration flag is additive; --phase c without it still runs successfully
```

### Implementation

Files to modify: `scripts/gcl-posterior-pipeline.py`

- Add `build_calibration_curve(events)` function: buckets H=0, H=1, H=2, H≥3; computes escape count and escape_rate per bucket; returns markdown table rows.
- Add `--calibration` flag to `main()` parser (additive; default False).
- In `phase_c()`: when `--calibration` is set, call `build_calibration_curve(updated_events)` and append a new `## 7. H vs escape_rate 校准曲线` section to the analysis markdown with the literal anchor text `calibration_curve`.

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase c --calibration && grep -q "calibration_curve" docs/research/gcl-posterior-analysis.md`
- [ ] `python3 -c "import json; data=open('docs/research/gcl-posterior-analysis.md').read(); assert 'N=0' in data or 'N=' in data, 'calibration table missing N column'"`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase c && python3 -c "print('backward compat ok')"`

---

## Phase C: MTTD 小时粒度（hours_to_detection）

### Tests (write first)

```python
# test_phase_c_mttd_hours.py  (write before implementing)
# T1: delta of 30 minutes → hours_to_detection = 0.50
# T2: delta of 0 seconds → hours_to_detection = 0.00
# T3: delta of 25 hours → hours_to_detection = 25.00
# T4: existing record with days_to_detection=0.000 migrates to hours_to_detection=0.00 and old field removed
# T5: after --phase c, no record in gcl-events.jsonl contains "days_to_detection" key
# T6: report MTTD section header changes to "小时" unit label
# T7: hours_to_detection field present in gcl-events-schema.md
```

### Implementation

Files to modify: `scripts/gcl-posterior-pipeline.py`

- In `phase_c()` computation: replace `delta.total_seconds() / 86400` with `delta.total_seconds() / 3600`; rename field from `days_to_detection` to `hours_to_detection` (round to 2 decimal places).
- Add migration step: if event has `days_to_detection` key (not None), convert via `× 24` → `hours_to_detection`, then `del event["days_to_detection"]`.
- Update all analysis report MTTD sections: change column headers from `mean_MTTD (d)` to `mean_MTTD (h)`, change unit labels in prose to "小时 (h)".

Files to modify: `docs/research/gcl-events-schema.md`

- Replace `days_to_detection` row with `hours_to_detection` row (type: float | null; unit: 小时, precision: 2 decimal places).
- Update `### days_to_detection 定义` section to `### hours_to_detection 定义` with updated unit description.

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "hours_to_detection" docs/research/gcl-events-schema.md`
- [ ] `! grep -q "days_to_detection" docs/research/gcl-events-schema.md`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase c && python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert not any('days_to_detection' in r for r in recs), 'old field still present'"`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; hrs=[r['hours_to_detection'] for r in recs if r.get('hours_to_detection') is not None]; assert all(h < 24 for h in hrs), 'expected intra-day corrections'"`

---

## Phase D: escape_signal adversarial verify（--adversarial）

### Tests (write first)

```python
# test_phase_d_adversarial.py  (write before implementing)
# T1: keyword inside backtick code block → escape_signal downgraded to null, intent_source_v2="refuted"
# T2: keyword inside quotation marks → escape_signal downgraded to null, intent_source_v2="refuted"
# T3: message starts with "[" (log output) → escape_signal downgraded to null, intent_source_v2="refuted"
# T4: message contains "exit code 0" → escape_signal downgraded to null, intent_source_v2="refuted"
# T5: clean human message "fix the bug" not in quotes/code → escape_signal preserved, intent_source_v2="user_message"
# T6: all original escape_signal=1 records get intent_source_v2 field after --adversarial
# T7: --adversarial is additive; --phase b without it produces records lacking intent_source_v2
```

### Implementation

Files to modify: `scripts/gcl-posterior-pipeline.py`

- Add `refute_escape(messages)` function: pure rule-based, no LLM call. Rules: (a) keyword appears only inside backtick spans or fenced code blocks; (b) message starts with `[` or contains `exit code 0` (log-line pattern); (c) keyword inside double/single quotes. Returns `("refuted", None)` or `("user_message", escape_signal)`.
- Add `--adversarial` flag to `main()` parser (additive; default False).
- In `phase_b()`: when `--adversarial` is set and `escape_signal == 1`, call `refute_escape(messages)`; overwrite `escape_signal` if refuted; write `intent_source_v2` field into intent-classification record regardless of verdict.

Files affected by pipeline run: `docs/research/gcl-intent-classification.jsonl` — `intent_source_v2` field added at runtime; no manual edits.

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase b --adversarial && python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-intent-classification.jsonl')]; assert all('intent_source_v2' in r for r in recs), 'missing intent_source_v2'"`
- [ ] `! grep -q '"intent_source_v2": ""' docs/research/gcl-intent-classification.jsonl`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase b && python3 -c "print('backward compat ok')"`

---

## Phase E: inter-task 对比注入（gate prompt template）

### Tests (write first)

```python
# test_phase_e_inter_task.py  (write before implementing)
# T1: build_gate_context("TASK-195", "plan", events_path) returns dict with key "contrast_task_id"
# T2: returned dict also contains "contrast_GCL" and "contrast_gate_outcome"
# T3: excludes current task_id from candidates
# T4: returns most recent record (highest timestamp) among same gate_type
# T5: returns None (not KeyError) when no same-gate_type history exists
# T6: gcl-gate-prompt-template.py --task-id X --dry-run outputs "prior_task_gcl" in stdout
# T7: script exits with code 0 on --dry-run even when task has no prior history
```

### Implementation

Files to create: `scripts/gcl-gate-prompt-template.py`

- `build_gate_context(task_id, gate_type, events_path=GCL_EVENTS)`: loads gcl-events.jsonl, filters to same gate_type excluding task_id, sorts by timestamp descending, returns first record's contrast dict (`contrast_task_id`, `contrast_GCL`, `contrast_gate_outcome`) or None.
- CLI: `--task-id`, `--gate-type` (default "plan"), `--dry-run` flag.
- `--dry-run` prints rendered prompt block containing `prior_task_gcl` key to stdout; no file writes.

Files to modify: `docs/research/gcl-events-schema.md`

- Add optional field `inter_task_context_injected` (boolean | null) to the schema field table under the posterior feedback section.
- Add optional field `contrast_task_id` (string | null) with definition.

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `test -f scripts/gcl-gate-prompt-template.py`
- [ ] `python3 scripts/gcl-gate-prompt-template.py --task-id TASK-195 --dry-run | grep -q "prior_task_gcl"`
- [ ] `grep -q "inter_task_context_injected" docs/research/gcl-events-schema.md`
- [ ] `grep -q "contrast_task_id" docs/research/gcl-events-schema.md`

---

## Constraints

- Phase A and Phase D both modify Phase B of the pipeline; implement sequentially (A before D) to avoid merge conflicts in `phase_b()`.
- Phase C renames `days_to_detection` → `hours_to_detection`; the code change and the `gcl-events-schema.md` update must land in the same commit (atomic).
- Phase E does not modify the existing gate flow — only adds `scripts/gcl-gate-prompt-template.py` as a standalone helper; no changes to `phase_a/b/c()`.
- All new `--flag` options must be additive: `python3 scripts/gcl-posterior-pipeline.py --phase a`, `--phase b`, and `--phase c` (without new flags) must continue to exit 0.
- `refute_escape()` in Phase D is pure-rule, no LLM calls — pipeline stays deterministic.
- Calibration bucket boundaries (H=0, H=1, H=2, H≥3) are fixed; do not use adaptive binning.
- Do not retroactively reprocess historical `delta_H=1` records with the continuous counter; new extraction applies only on fresh `--phase b` runs for new commits.

---

## Acceptance Gate

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase a && test -f docs/research/gcl-commit-map.jsonl`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase b --extract-hidden-premises --adversarial && test -f docs/research/gcl-intent-classification.jsonl`
- [ ] `python3 scripts/gcl-posterior-pipeline.py --phase c --calibration && grep -q "calibration_curve" docs/research/gcl-posterior-analysis.md`
- [ ] `grep -q "hours_to_detection" docs/research/gcl-events-schema.md`
- [ ] `! grep -q "days_to_detection" docs/research/gcl-events-schema.md`
- [ ] `test -f scripts/gcl-gate-prompt-template.py`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-intent-classification.jsonl')]; assert all('intent_source_v2' in r for r in recs), 'missing adversarial verdict'"`
- [ ] `python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert not any('days_to_detection' in r for r in recs), 'stale field present'"`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Proposal self-review: APPROVED
premise-ledger:
[E] Motivation: Background states WHY each gap matters — binary delta_H prevents regression analysis, missing calibration curve means signal may be noise, days granularity destroys intra-session precision, unquantified false-positive rate inflates escape_rate, no contrast signal means stereotypy attractor persists. 5 substantive lines, within 3-8 range.
[E] Goals: All 5 goals numbered with concrete verification criteria — specific field names, specific observable outputs (calibration table with N=0 rows, hours unit label, intent_source_v2 field present per record). No vague language.
[C] Feasibility: Approach maps to existing Phase A/B/C function structure; new functions follow load_jsonl/append_jsonl patterns already in codebase; adversarial verify mirrors existing CORRECTIVE_KEYWORDS rule pattern; migration step follows existing non-destructive backfill idiom.
[E] Completeness: Trade-offs section lists 4 explicit NOT-doing items and 4 specific risks with concrete failure modes (silent null on rename, regression to binary on pattern miss, low-relevance contrast on small dataset, unquantified FP on edge cases).
[H] Consistency: Initial draft had intent_source vs intent_source_v2 mismatch in Goal 4; caught and corrected in self-review round 1. Final version consistent across all sections.
GCL-self-report: E=5 C=3 H=2

Proposal approved. Starting plan draft.

Plan review iteration 1: APPROVED
premise-ledger:
[E] Goal coverage: all 5 Goals map 1:1 to Phases A–E with no gaps
[E] TDD structure: every Phase has ### Tests before ### Implementation
[E] TDD order: first DoD item in each Phase is `bash scripts/validate-plugin.sh`
[E] Acceptance gate: first item is `bash scripts/validate-plugin.sh`
[E] DoD executability: all DoD and Acceptance Gate items are shell commands; no natural-language items
[E] Absence checks: `! grep -q` pattern used correctly in Phase C DoD and Acceptance Gate; Phase D uses `! grep -q` for empty-string check
[E] Phase ordering: A→B→C→D→E; Constraints explicitly order A before D; no circular deps
[E] Scope discipline: no Phase implements anything not backed by a Goal
[E] File paths: scripts/gcl-posterior-pipeline.py, docs/research/gcl-events-schema.md, docs/research/gcl-intent-classification.jsonl, docs/research/gcl-events.jsonl — all confirmed present
[C] All criteria independently verifiable from plan text and filesystem state
[H] Plan is well-structured; phases are cleanly separated with additive flags; migration step for days→hours is atomic as required
GCL-self-report: E=9 C=1 H=1
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 python3 scripts/gcl-posterior-pipeline.py --phase b --extract-hidden-premises && python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-intent-classification.jsonl')]; assert any(isinstance(r.get('delta_H_count'), (int,float)) for r in recs), 'No delta_H_count found'"
- [ ] #3 python3 scripts/gcl-posterior-pipeline.py --phase c && python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert all('delta_H_continuous' in r or r.get('gate_outcome') != 'escape' for r in recs), 'escape record missing delta_H_continuous'"
- [ ] #4 python3 scripts/gcl-posterior-pipeline.py --phase b && python3 -c "print('backward compat ok')"
- [ ] #5 bash scripts/validate-plugin.sh
- [ ] #6 python3 scripts/gcl-posterior-pipeline.py --phase c --calibration && grep -q "calibration_curve" docs/research/gcl-posterior-analysis.md
- [ ] #7 python3 -c "import json; data=open('docs/research/gcl-posterior-analysis.md').read(); assert 'N=0' in data or 'N=' in data, 'calibration table missing N column'"
- [ ] #8 python3 scripts/gcl-posterior-pipeline.py --phase c && python3 -c "print('backward compat ok')"
- [ ] #9 bash scripts/validate-plugin.sh
- [ ] #10 grep -q "hours_to_detection" docs/research/gcl-events-schema.md
- [ ] #11 ! grep -q "days_to_detection" docs/research/gcl-events-schema.md
- [ ] #12 python3 scripts/gcl-posterior-pipeline.py --phase c && python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert not any('days_to_detection' in r for r in recs), 'old field still present'"
- [ ] #13 python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; hrs=[r['hours_to_detection'] for r in recs if r.get('hours_to_detection') is not None]; assert all(h < 24 for h in hrs), 'expected intra-day corrections'"
- [ ] #14 bash scripts/validate-plugin.sh
- [ ] #15 python3 scripts/gcl-posterior-pipeline.py --phase b --adversarial && python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-intent-classification.jsonl')]; assert all('intent_source_v2' in r for r in recs), 'missing intent_source_v2'"
- [ ] #16 ! grep -q '"intent_source_v2": ""' docs/research/gcl-intent-classification.jsonl
- [ ] #17 python3 scripts/gcl-posterior-pipeline.py --phase b && python3 -c "print('backward compat ok')"
- [ ] #18 bash scripts/validate-plugin.sh
- [ ] #19 test -f scripts/gcl-gate-prompt-template.py
- [ ] #20 python3 scripts/gcl-gate-prompt-template.py --task-id TASK-195 --dry-run | grep -q "prior_task_gcl"
- [ ] #21 grep -q "inter_task_context_injected" docs/research/gcl-events-schema.md
- [ ] #22 grep -q "contrast_task_id" docs/research/gcl-events-schema.md
- [ ] #23 bash scripts/validate-plugin.sh
- [ ] #24 python3 scripts/gcl-posterior-pipeline.py --phase a && test -f docs/research/gcl-commit-map.jsonl
- [ ] #25 python3 scripts/gcl-posterior-pipeline.py --phase b --extract-hidden-premises --adversarial && test -f docs/research/gcl-intent-classification.jsonl
- [ ] #26 python3 scripts/gcl-posterior-pipeline.py --phase c --calibration && grep -q "calibration_curve" docs/research/gcl-posterior-analysis.md
- [ ] #27 grep -q "hours_to_detection" docs/research/gcl-events-schema.md
- [ ] #28 ! grep -q "days_to_detection" docs/research/gcl-events-schema.md
- [ ] #29 test -f scripts/gcl-gate-prompt-template.py
- [ ] #30 python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-intent-classification.jsonl')]; assert all('intent_source_v2' in r for r in recs), 'missing adversarial verdict'"
- [ ] #31 python3 -c "import json; recs=[json.loads(l) for l in open('docs/research/gcl-events.jsonl')]; assert not any('days_to_detection' in r for r in recs), 'stale field present'"
<!-- DOD:END -->
