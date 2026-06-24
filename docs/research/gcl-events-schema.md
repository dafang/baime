# gcl-events.jsonl Schema

**文件**：`docs/research/gcl-events.jsonl`  
**格式**：每行一个 JSON 对象（JSONL），append-only。  
**用途**：结构化 GCL gate 事件日志，支持 H5/H6/H7 假设验证和 drift 告警。

## 字段表

| 字段 | 类型 | 说明 | 允许值 |
|------|------|------|--------|
| task_id | string | 任务 ID | 如 "TASK-123"、"TASK-176.1" |
| gate_type | string | gate 类型 | "plan" \| "proposal" \| "epic-evaluate" |
| task_kind | string | 任务种类 | "basic" \| "epic" |
| timestamp | string | ISO 8601 UTC 时间戳 | 如 "2026-06-23T16:45:00Z" |
| E | integer | Explicit 分量（可从任务文件直接读到的前提数） | ≥ 0 |
| C | integer | Cross-boundary 分量（需跳转外部任务/文档才能确认的前提数） | ≥ 0 |
| H | integer | Hidden 分量（靠背景知识推断、无 artifact 支撑的前提数） | ≥ 0 |
| GCL | integer | 总认知负载，等于 E+C+H | ≥ 0 |
| reviewer_model | string | 执行 gate 的模型或 actor | 如 "claude-sonnet-4-6"、"human" |
| sample_run_id | string \| null | 可靠性采样的第二次运行 ID（176e 填充）；非采样 event 为 null | null 或 "TASK-N-r2" |
| evidence_independence | string | gate 证据来源与被审系统的独立程度（H6 字段） | "high" \| "low" \| "unknown" |
| gate_actor_type | string | gate 执行者类型（H7 字段） | "human" \| "llm" \| "hybrid" \| "tool" |
| premise_lines | integer \| null | premise-ledger 中的前提条目总数；未记录时为 null | null 或 ≥ 0 |
| escape_rate | integer | gate 通过后该任务是否发生逃逸（0=无逃逸，1=逃逸） | 0 \| 1 |

## escape_rate 定义

**逃逸（escape_rate=1）**：gate 通过后，任务满足以下任一条件：

1. 任务状态曾到达 `Basic: Needs Human`（reaper 触发的人工干预）
2. 任务 Notes 中出现 `Requeued by reaper` 或等效的 reaper 重新排队记录

**无逃逸（escape_rate=0）**：gate 通过后任务成功完成，无上述逃逸迹象。保守原则：无明确逃逸证据的记录默认为 0。

**提取方法**：

```bash
# 检查任务是否曾处于 Needs Human 状态或被 reaper 重新排队
backlog task view TASK-N --plain | grep -iE 'Needs Human|Requeued by reaper'

# 批量检查所有 gcl-events.jsonl 中的任务
python3 -c "
import json, subprocess
recs = [json.loads(l) for l in open('docs/research/gcl-events.jsonl')]
task_ids = sorted(set(r['task_id'] for r in recs))
for tid in task_ids:
    out = subprocess.run(['backlog', 'task', 'view', tid, '--plain'],
                        capture_output=True, text=True).stdout
    escaped = 1 if any(kw in out for kw in ['Needs Human', 'Requeued by reaper']) else 0
    print(f'{tid}: escape_rate={escaped}')
"
```

## 说明

- **evidence_independence**：若 gate 证据完全来自被审任务自身摘要（如 LLM 只读自己写的 plan），则为 "low"。若有独立测试输出、archguard 分析、meta-cc trace 等独立通道，则为 "high"。历史回填记录置 "unknown"。
- **gate_actor_type**：历史回填记录中 premise-ledger 由 LLM 执行，置 "llm"。未来若由人工审核，置 "human"。
- **sample_run_id**：176e 实现可靠性采样后，对同一 gate 内容做第二次 self-report，第二条记录的 sample_run_id 为 "TASK-N-r2"，与原始记录共享 task_id。

## 查询示例

```bash
# 统计各 gate_type 的 GCL 均值
python3 -c "
import json, statistics
recs = [json.loads(l) for l in open('docs/research/gcl-events.jsonl')]
by_type = {}
for r in recs:
    by_type.setdefault(r['gate_type'], []).append(r['GCL'])
for t, vals in sorted(by_type.items()):
    print(f'{t}: mean={statistics.mean(vals):.1f} n={len(vals)}')
"
```

## 后验反馈字段（Phase C 回填）

以下字段由 `scripts/gcl-posterior-pipeline.py --phase c` 非破坏性地回填到 gcl-events.jsonl，
仅在字段为 null 时写入（不覆盖已有非空值）。

| 字段 | 类型 | 说明 | 允许值 |
|------|------|------|--------|
| gate_outcome | string | gate 后验结果 | "pass" \| "escape" \| "unknown" |
| gate_timing | string | gate 在任务流程中的位置 | "pre-plan" \| "pre-execution" \| "post-execution" \| "unknown" |
| days_to_detection | float \| null | 从 gate timestamp 到最早后续修正提交的天数差（MTTD 代理指标） | null 或 ≥ 0 |
| delta_H | float \| null | 后验 H - 自报 H（逃逸事件的 hidden premise 低估量）；无逃逸时为 0 | null 或任意实数 |

### delta_H 定义

**delta_H**（Hidden premise delta）= 后验观测的 H 分量 − 自报的 H 分量。

- 逃逸事件（gate_outcome=escape）：delta_H ≥ 1，表明至少 1 个隐藏前提在 gate 阶段未被识别
- 无逃逸事件（gate_outcome=pass）：delta_H = 0（无后验证据表明低估）
- 当前为保守下界估计，基于"逃逸=至少 1 个 hidden premise 被遗漏"的假设

### days_to_detection 定义

**days_to_detection**（MTTD 代理）= 修正提交 timestamp − gate timestamp，单位为天。

- 仅对有后续修正提交（commit_type=corrective）的任务记录非 null 值
- 修正提交须在 gate timestamp 之后（否则视为历史修正，不计入 MTTD）
- 多个修正提交时取最早一条

### gate_outcome 定义

- **pass**：gate 通过后无修正提交记录（无逃逸证据）
- **escape**：git history 中有修正提交且 meta-cc 会话确认用户问题意图（escape_signal=1）
- **unknown**：有修正提交但 meta-cc 信号模糊（ambiguous）或无窗口匹配（no_window_match）

### gate_timing 定义

- **pre-plan**：proposal gate，在正式 plan 制定前执行
- **pre-execution**：plan gate，在任务执行前执行
- **post-execution**：epic-evaluate gate，在执行完成后评估
