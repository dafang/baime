#!/usr/bin/env python3
"""
GCL Posterior Feedback Pipeline
Connects git history + meta-cc session records to quantify gate escape rate and delta_H.

Usage:
  python3 scripts/gcl-posterior-pipeline.py --phase a
  python3 scripts/gcl-posterior-pipeline.py --phase b
  python3 scripts/gcl-posterior-pipeline.py --phase c
"""

import argparse
import json
import os
import re
import subprocess
import statistics
from datetime import datetime, timezone, timedelta
from pathlib import Path

# Paths (relative to repo root)
REPO_ROOT = Path(__file__).parent.parent
GCL_EVENTS = REPO_ROOT / "docs/research/gcl-events.jsonl"
COMMIT_MAP = REPO_ROOT / "docs/research/gcl-commit-map.jsonl"
INTENT_CLASS = REPO_ROOT / "docs/research/gcl-intent-classification.jsonl"
POSTERIOR_ANALYSIS = REPO_ROOT / "docs/research/gcl-posterior-analysis.md"
SCHEMA_FILE = REPO_ROOT / "docs/research/gcl-events-schema.md"
SESSION_BASE = Path.home() / ".claude/projects/-home-yale-work-baime"

CORRECTIVE_KEYWORDS = {
    "fix", "revert", "correct", "amend", "repair", "patch", "hotfix", "rollback"
}

ESCAPE_KEYWORDS = {
    "fix", "error", "wrong", "incorrect", "broken", "bug", "issue",
    "problem", "fail", "failed", "doesn't work", "not working", "bad",
    "mistake", "revert", "redo", "again", "retry"
}

# Keywords in tool results that indicate test/build failure (escape signal)
TOOL_FAILURE_KEYWORDS = {
    "exit code 1", "fail:", "failed", "error:", "test failed", "assertion"
}


def load_jsonl(path):
    """Load a JSONL file, return list of dicts."""
    records = []
    if not Path(path).exists():
        return records
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return records


def append_jsonl(path, record):
    """Append a single record to JSONL file."""
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


def run_git_log(task_id):
    """Run git log --grep=<task_id> and return list of (hash, timestamp, subject) tuples."""
    result = subprocess.run(
        ["git", "log", f"--grep={task_id}", "--format=%H|%ai|%s", "--all"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True
    )
    commits = []
    for line in result.stdout.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split("|", 2)
        if len(parts) == 3:
            commits.append({
                "hash": parts[0],
                "timestamp": parts[1],
                "subject": parts[2]
            })
    return commits


def classify_commit(subject):
    """Classify a commit as 'corrective' or 'additive'."""
    subject_lower = subject.lower()
    for kw in CORRECTIVE_KEYWORDS:
        # match as word boundary
        if re.search(r'\b' + re.escape(kw) + r'\b', subject_lower):
            return "corrective"
    return "additive"


def phase_a():
    """Phase A: Build task→commit mapping table."""
    print("[Phase A] Building git commit map...")

    # Load existing commit hashes to ensure idempotency
    existing = load_jsonl(COMMIT_MAP)
    existing_hashes = {r["commit_hash"] for r in existing}

    # Load GCL events, extract unique task_ids
    events = load_jsonl(GCL_EVENTS)
    task_ids = sorted(set(r["task_id"] for r in events))
    print(f"  Found {len(task_ids)} unique task_ids: {task_ids}")

    new_count = 0
    for task_id in task_ids:
        commits = run_git_log(task_id)
        print(f"  {task_id}: {len(commits)} commits")
        for commit in commits:
            if commit["hash"] in existing_hashes:
                continue  # idempotent skip
            commit_type = classify_commit(commit["subject"])
            record = {
                "task_id": task_id,
                "commit_hash": commit["hash"],
                "commit_timestamp": commit["timestamp"],
                "commit_subject": commit["subject"],
                "commit_type": commit_type
            }
            append_jsonl(COMMIT_MAP, record)
            existing_hashes.add(commit["hash"])
            new_count += 1

    total = len(load_jsonl(COMMIT_MAP))
    print(f"[Phase A] Done. Added {new_count} new records. Total: {total}")


def parse_iso(ts_str):
    """Parse ISO 8601 timestamp (with or without timezone) to datetime (UTC)."""
    if not ts_str:
        return None
    ts_str = ts_str.strip()
    # Handle Z suffix (Python < 3.11 doesn't support it in fromisoformat)
    if ts_str.endswith("Z"):
        ts_str = ts_str[:-1] + "+00:00"
    # Handle space before timezone offset: "2026-06-24 08:01:28 +0000"
    ts_str = ts_str.replace(" ", "T", 1)
    # Remove second space if any (between date-time and offset)
    ts_str = ts_str.replace(" ", "")
    # Fix +0000 → +00:00 (4-digit offset without colon)
    m = re.match(r'(.+[T\d])([+-])(\d{2})(\d{2})$', ts_str)
    if m:
        ts_str = m.group(1) + m.group(2) + m.group(3) + ":" + m.group(4)
    try:
        dt = datetime.fromisoformat(ts_str)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except Exception:
        return None


def find_user_messages_in_window(commit_ts_str, window_minutes=30):
    """
    Search meta-cc session files for user messages within ±window_minutes of commit_ts.
    Returns list of (timestamp, text, source) tuples where source is 'human' or 'tool_result'.
    """
    commit_dt = parse_iso(commit_ts_str)
    if not commit_dt:
        return []

    window = timedelta(minutes=window_minutes)
    lo = commit_dt - window
    hi = commit_dt + window

    messages = []
    if not SESSION_BASE.exists():
        return messages

    for fpath in SESSION_BASE.glob("*.jsonl"):
        try:
            with open(fpath, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        d = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if d.get("type") != "user":
                        continue
                    ts_raw = d.get("timestamp", "")
                    if not ts_raw:
                        continue
                    msg_dt = parse_iso(ts_raw)
                    if not msg_dt:
                        continue
                    if lo <= msg_dt <= hi:
                        msg = d.get("message", {})
                        if isinstance(msg, dict):
                            content = msg.get("content", "")
                        else:
                            content = str(msg)

                        if isinstance(content, str):
                            # Human-typed message (string content)
                            text = content.strip()
                            source = "human"
                        elif isinstance(content, list):
                            # Could be tool results or mixed
                            parts = []
                            for c in content:
                                if isinstance(c, dict):
                                    # tool_result items have 'content' key
                                    inner = c.get("content", "")
                                    if isinstance(inner, str):
                                        parts.append(inner)
                                    elif isinstance(inner, list):
                                        parts.extend(
                                            x.get("text", "") if isinstance(x, dict) else str(x)
                                            for x in inner
                                        )
                                    else:
                                        parts.append(str(c.get("text", "")))
                                else:
                                    parts.append(str(c))
                            text = " ".join(parts).strip()
                            source = "tool_result"
                        else:
                            text = str(content).strip()
                            source = "unknown"

                        if text:
                            messages.append((ts_raw, text, source))
        except Exception:
            pass

    return messages


def classify_escape(messages):
    """
    Given user messages within window, classify escape signal.
    Returns (escape_signal, intent_source, preview)
    """
    if not messages:
        return None, "no_window_match", ""

    # Separate human messages from tool results
    human_msgs = [(ts, t) for ts, t, src in messages if src == "human"]
    tool_msgs = [(ts, t) for ts, t, src in messages if src == "tool_result"]

    preview = messages[0][1][:200]

    # Check human-typed messages for escape language (high confidence)
    if human_msgs:
        combined_human = " ".join(t for _, t in human_msgs).lower()
        has_escape_lang = any(
            re.search(r'\b' + re.escape(kw) + r'\b', combined_human)
            for kw in ESCAPE_KEYWORDS
        )
        if has_escape_lang:
            return 1, "user_message", human_msgs[0][1][:200]
        else:
            return None, "ambiguous", human_msgs[0][1][:200]

    # Check tool results for failure signals (medium confidence)
    if tool_msgs:
        combined_tool = " ".join(t for _, t in tool_msgs).lower()
        has_failure = any(
            kw in combined_tool
            for kw in TOOL_FAILURE_KEYWORDS
        )
        if has_failure:
            # Tool failures near corrective commits → escape signal via tool output
            return 1, "tool_failure_signal", tool_msgs[0][1][:200]
        else:
            return None, "ambiguous", tool_msgs[0][1][:200]

    return None, "no_window_match", ""


def phase_b():
    """Phase B: Intent classification layer via meta-cc session records."""
    print("[Phase B] Classifying corrective commits via session records...")

    commit_map = load_jsonl(COMMIT_MAP)
    corrective = [r for r in commit_map if r.get("commit_type") == "corrective"]
    print(f"  Total commits: {len(commit_map)}, corrective: {len(corrective)}")

    # Load existing classified hashes for idempotency
    existing = load_jsonl(INTENT_CLASS)
    existing_hashes = {r["commit_hash"] for r in existing}

    new_count = 0
    for rec in corrective:
        if rec["commit_hash"] in existing_hashes:
            continue

        messages = find_user_messages_in_window(rec["commit_timestamp"])
        escape_signal, intent_source, preview = classify_escape(messages)

        record = {
            "task_id": rec["task_id"],
            "commit_hash": rec["commit_hash"],
            "commit_timestamp": rec["commit_timestamp"],
            "escape_signal": escape_signal,
            "intent_source": intent_source,
            "user_message_preview": preview
        }
        append_jsonl(INTENT_CLASS, record)
        existing_hashes.add(rec["commit_hash"])
        new_count += 1

    total = len(load_jsonl(INTENT_CLASS))
    print(f"[Phase B] Done. Added {new_count} new records. Total: {total}")


def phase_c():
    """Phase C: Field backfill and analysis output."""
    print("[Phase C] Backfilling gcl-events.jsonl and generating analysis...")

    intent_records = load_jsonl(INTENT_CLASS)
    commit_map = load_jsonl(COMMIT_MAP)
    events = load_jsonl(GCL_EVENTS)

    # Build lookup: task_id → list of intent records (only escape_signal=1)
    task_escapes = {}
    for r in intent_records:
        tid = r["task_id"]
        task_escapes.setdefault(tid, []).append(r)

    # Build lookup: task_id → list of corrective commits sorted by timestamp
    task_corrective = {}
    for r in commit_map:
        if r.get("commit_type") == "corrective":
            tid = r["task_id"]
            task_corrective.setdefault(tid, []).append(r)

    # Update gcl-events.jsonl records non-destructively
    updated_events = []
    for event in events:
        tid = event["task_id"]
        gate_ts = event.get("timestamp", "")
        gate_dt = parse_iso(gate_ts)

        # Determine gate_outcome
        if event.get("gate_outcome") is not None:
            gate_outcome = event["gate_outcome"]
        else:
            escapes_for_task = task_escapes.get(tid, [])
            confirmed_escapes = [e for e in escapes_for_task if e.get("escape_signal") == 1]
            if confirmed_escapes:
                gate_outcome = "escape"
            elif tid in task_corrective:
                gate_outcome = "unknown"  # corrective commits but ambiguous signal
            else:
                gate_outcome = "pass"

        event["gate_outcome"] = gate_outcome

        # Calculate days_to_detection (MTTD proxy)
        if event.get("days_to_detection") is None:
            correctives = task_corrective.get(tid, [])
            if correctives and gate_dt:
                # Take earliest corrective commit after gate
                after_gate = [
                    c for c in correctives
                    if parse_iso(c["commit_timestamp"]) and parse_iso(c["commit_timestamp"]) > gate_dt
                ]
                if after_gate:
                    earliest = min(after_gate, key=lambda c: parse_iso(c["commit_timestamp"]))
                    corr_dt = parse_iso(earliest["commit_timestamp"])
                    delta = corr_dt - gate_dt
                    event["days_to_detection"] = round(delta.total_seconds() / 86400, 3)
                else:
                    event["days_to_detection"] = None
            else:
                event["days_to_detection"] = None

        # gate_timing: classify when gate was applied relative to task flow
        if event.get("gate_timing") is None:
            gate_type = event.get("gate_type", "")
            if gate_type == "proposal":
                event["gate_timing"] = "pre-plan"
            elif gate_type == "plan":
                event["gate_timing"] = "pre-execution"
            elif gate_type == "epic-evaluate":
                event["gate_timing"] = "post-execution"
            else:
                event["gate_timing"] = "unknown"

        # escape_rate: set to 1 if confirmed escape, preserve existing otherwise
        if gate_outcome == "escape" and event.get("escape_rate") == 0:
            event["escape_rate"] = 1

        updated_events.append(event)

    # Write updated gcl-events.jsonl
    with open(GCL_EVENTS, "w", encoding="utf-8") as f:
        for event in updated_events:
            f.write(json.dumps(event, ensure_ascii=False) + "\n")
    print(f"  Updated {len(updated_events)} records in gcl-events.jsonl")

    # --- delta_H calculation ---
    # delta_H = observed_H (from corrective signal) - reported_H
    # For tasks with corrective commits, we treat escape as evidence that
    # H was underestimated; delta_H = 1 (minimum underestimate) for confirmed escapes
    delta_H_values = []
    for event in updated_events:
        tid = event["task_id"]
        reported_H = event.get("H", 0)
        if event.get("gate_outcome") == "escape":
            # Corrective signal implies at least 1 additional hidden premise was missed
            delta_H = max(1, 1 - reported_H)  # conservative floor
            delta_H_values.append({"task_id": tid, "gate_type": event.get("gate_type"), "reported_H": reported_H, "delta_H": delta_H})
        else:
            delta_H_values.append({"task_id": tid, "gate_type": event.get("gate_type"), "reported_H": reported_H, "delta_H": 0})

    # --- MTTD statistics ---
    mttd_values = [
        e["days_to_detection"]
        for e in updated_events
        if e.get("days_to_detection") is not None
    ]

    # --- TASK-153~158 batch stereotypy check ---
    batch_ids = ["TASK-153", "TASK-154", "TASK-155", "TASK-156", "TASK-157", "TASK-158"]
    batch_events = [e for e in updated_events if e["task_id"] in batch_ids]
    batch_gcl = [e["GCL"] for e in batch_events]
    batch_H = [e["H"] for e in batch_events]
    batch_E = [e["E"] for e in batch_events]
    batch_C = [e["C"] for e in batch_events]

    def safe_stdev(values):
        if len(values) < 2:
            return 0.0
        return statistics.stdev(values)

    def safe_mean(values):
        if not values:
            return 0.0
        return statistics.mean(values)

    # --- delta_H distribution ---
    dH_all = [d["delta_H"] for d in delta_H_values]
    dH_nonzero = [d for d in dH_all if d != 0]

    # Gate outcome counts
    outcome_counts = {}
    for e in updated_events:
        o = e.get("gate_outcome", "unknown")
        outcome_counts[o] = outcome_counts.get(o, 0) + 1

    # Escape by gate type
    escape_by_gate = {}
    total_by_gate = {}
    for e in updated_events:
        gt = e.get("gate_type", "unknown")
        total_by_gate[gt] = total_by_gate.get(gt, 0) + 1
        if e.get("gate_outcome") == "escape":
            escape_by_gate[gt] = escape_by_gate.get(gt, 0) + 1

    escape_rate_by_gate = {
        gt: escape_by_gate.get(gt, 0) / total_by_gate[gt]
        for gt in total_by_gate
    }

    # Escape by task_kind
    escape_by_kind = {}
    total_by_kind = {}
    for e in updated_events:
        kind = e.get("task_kind", "unknown")
        total_by_kind[kind] = total_by_kind.get(kind, 0) + 1
        if e.get("gate_outcome") == "escape":
            escape_by_kind[kind] = escape_by_kind.get(kind, 0) + 1

    # Overall escape rate
    total_events = len(updated_events)
    total_escapes = outcome_counts.get("escape", 0)
    overall_escape_rate = total_escapes / total_events if total_events else 0

    # MTTD by gate type
    mttd_by_gate = {}
    for e in updated_events:
        if e.get("days_to_detection") is not None:
            gt = e.get("gate_type", "unknown")
            mttd_by_gate.setdefault(gt, []).append(e["days_to_detection"])

    # MTTD by task_kind
    mttd_by_kind = {}
    for e in updated_events:
        if e.get("days_to_detection") is not None:
            kind = e.get("task_kind", "unknown")
            mttd_by_kind.setdefault(kind, []).append(e["days_to_detection"])

    # Generate analysis markdown
    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [
        "# GCL 后验分析报告",
        "",
        f"**生成时间**：{now_str}  ",
        f"**数据源**：`docs/research/gcl-events.jsonl` ({total_events} 条记录)  ",
        f"**管线版本**：gcl-posterior-pipeline.py v1.0",
        "",
        "---",
        "",
        "## 1. 总体 Gate 结果分布",
        "",
        f"| Gate 结果 | 记录数 | 占比 |",
        f"|-----------|--------|------|",
    ]
    for outcome, cnt in sorted(outcome_counts.items()):
        pct = 100 * cnt / total_events if total_events else 0
        lines.append(f"| {outcome} | {cnt} | {pct:.1f}% |")

    lines += [
        "",
        f"**整体 escape_rate**：{overall_escape_rate:.3f} ({total_escapes}/{total_events})",
        "",
        "---",
        "",
        "## 2. 按 Gate 类型的 Escape Rate",
        "",
        "| gate_type | total | escapes | escape_rate |",
        "|-----------|-------|---------|-------------|",
    ]
    for gt in sorted(total_by_gate.keys()):
        t = total_by_gate[gt]
        e = escape_by_gate.get(gt, 0)
        r = escape_rate_by_gate[gt]
        lines.append(f"| {gt} | {t} | {e} | {r:.3f} |")

    lines += [
        "",
        "---",
        "",
        "## 3. delta_H 分布统计",
        "",
        "delta_H 定义：后验观测 H - 自报 H。逃逸事件的 delta_H ≥ 1（保守估计）；",
        "无逃逸事件 delta_H = 0。",
        "",
        f"| 统计量 | 值 |",
        f"|--------|-----|",
        f"| N (total) | {len(dH_all)} |",
        f"| N (delta_H > 0) | {len(dH_nonzero)} |",
        f"| mean | {safe_mean(dH_all):.3f} |",
        f"| std | {safe_stdev(dH_all):.3f} |",
    ]
    if dH_all:
        sorted_dH = sorted(dH_all)
        n = len(sorted_dH)
        q1 = sorted_dH[n // 4]
        median = sorted_dH[n // 2]
        q3 = sorted_dH[3 * n // 4]
        lines += [
            f"| Q1 | {q1} |",
            f"| median | {median} |",
            f"| Q3 | {q3} |",
            f"| max | {max(sorted_dH)} |",
        ]

    lines += [
        "",
        "---",
        "",
        "## 4. MTTD（Mean Time To Detection）报告",
        "",
        "MTTD 单位：天。定义为从 gate timestamp 到最早后续修正提交的时间差。",
        "",
        f"**MTTD 总体**：N={len(mttd_values)}, mean={safe_mean(mttd_values):.3f}d, "
        f"std={safe_stdev(mttd_values):.3f}d",
        "",
        "### 按 gate_type 分层",
        "",
        "| gate_type | N | mean_MTTD (d) | std_MTTD (d) |",
        "|-----------|---|---------------|--------------|",
    ]
    for gt in sorted(mttd_by_gate.keys()):
        vals = mttd_by_gate[gt]
        lines.append(
            f"| {gt} | {len(vals)} | {safe_mean(vals):.3f} | {safe_stdev(vals):.3f} |"
        )

    lines += [
        "",
        "### 按 task_kind 分层",
        "",
        "| task_kind | N | mean_MTTD (d) | std_MTTD (d) |",
        "|-----------|---|---------------|--------------|",
    ]
    for kind in sorted(mttd_by_kind.keys()):
        vals = mttd_by_kind[kind]
        lines.append(
            f"| {kind} | {len(vals)} | {safe_mean(vals):.3f} | {safe_stdev(vals):.3f} |"
        )

    lines += [
        "",
        "---",
        "",
        "## 5. TASK-153~158 批次 Stereotypy 验证",
        "",
        "该批次 6 个任务（TASK-153、TASK-154、TASK-155、TASK-156、TASK-157、TASK-158）",
        "均在同一 session 内以相似格式报告，存在 GCL 自报 stereotypy 风险。",
        "",
        f"| 任务 | E | C | H | GCL | gate_outcome |",
        f"|------|---|---|---|-----|--------------|",
    ]
    for e in batch_events:
        lines.append(
            f"| {e['task_id']} | {e.get('E')} | {e.get('C')} | {e.get('H')} "
            f"| {e.get('GCL')} | {e.get('gate_outcome', 'unknown')} |"
        )

    lines += [
        "",
        f"**Batch GCL stdev**：{safe_stdev(batch_gcl):.3f}（批次内标准差；原始诊断 stdev≈0）",
        f"**Batch H stdev**：{safe_stdev(batch_H):.3f}",
        f"**Batch E stdev**：{safe_stdev(batch_E):.3f}",
        f"**Batch C stdev**：{safe_stdev(batch_C):.3f}",
        "",
    ]

    # Stereotypy diagnosis
    if safe_stdev(batch_gcl) < 0.5:
        lines.append(
            "**诊断**：TASK-153~158 批次 GCL stdev < 0.5，确认存在 stereotypy（LLM "
            "对相似任务重复输出相同分数，无法反映任务间真实认知负载差异）。"
        )
    else:
        lines.append(
            "**诊断**：TASK-153~158 批次 GCL stdev ≥ 0.5，stereotypy 程度较低。"
        )

    lines += [
        "",
        "---",
        "",
        "## 6. 方法论说明",
        "",
        "### Phase A — Git 关联层",
        "- 使用 `git log --grep=<task_id>` 匹配提交信息中的任务 ID",
        "- 修正类关键词（fix、revert、correct、amend、repair、patch、hotfix、rollback）→ corrective",
        "- 其余 → additive",
        "",
        "### Phase B — meta-cc 意图分类层",
        "- 读取 `~/.claude/projects/-home-yale-work-baime/` 下的 session JSONL",
        "- 在修正提交 timestamp ±30 分钟窗口内查找 `type=user` 的消息",
        "- 含逃逸关键词（fix、error、wrong 等）→ escape_signal=1",
        "- 有消息但无逃逸关键词 → escape_signal=null, intent_source=ambiguous",
        "- 无消息 → escape_signal=null, intent_source=no_window_match",
        "",
        "### Phase C — 字段回填",
        "- gate_outcome: escape（确认逃逸）/ unknown（有修正提交但信号模糊）/ pass（无修正提交）",
        "- days_to_detection: gate timestamp 到最早后续修正提交的天数差",
        "- gate_timing: proposal→pre-plan, plan→pre-execution, epic-evaluate→post-execution",
        "- delta_H: 后验 H - 自报 H（逃逸事件最小估计为 1）",
        "",
        "### 局限性",
        "- escape_signal 基于启发式关键词匹配，误报率未量化",
        "- 30 分钟时间窗口可能错过异步问题发现",
        "- delta_H 当前为保守下界（≥1），非精确量化",
        "- MTTD 仅对有修正提交的任务有效（无修正提交的任务无 MTTD 数据）",
        "",
        "---",
        "",
        "*Generated by `scripts/gcl-posterior-pipeline.py --phase c`*",
    ]

    with open(POSTERIOR_ANALYSIS, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"  Generated {POSTERIOR_ANALYSIS}")

    # --- Update gcl-events-schema.md ---
    update_schema()

    print("[Phase C] Done.")


def update_schema():
    """Append new field definitions to gcl-events-schema.md (non-destructive)."""
    schema_content = SCHEMA_FILE.read_text(encoding="utf-8")

    new_fields = """
## 后验反馈字段（Phase C 回填）

以下字段由 `scripts/gcl-posterior-pipeline.py --phase c` 非破坏性地回填到 gcl-events.jsonl，
仅在字段为 null 时写入（不覆盖已有非空值）。

| 字段 | 类型 | 说明 | 允许值 |
|------|------|------|--------|
| gate_outcome | string | gate 后验结果 | "pass" \\| "escape" \\| "unknown" |
| gate_timing | string | gate 在任务流程中的位置 | "pre-plan" \\| "pre-execution" \\| "post-execution" \\| "unknown" |
| days_to_detection | float \\| null | 从 gate timestamp 到最早后续修正提交的天数差（MTTD 代理指标） | null 或 ≥ 0 |
| delta_H | float \\| null | 后验 H - 自报 H（逃逸事件的 hidden premise 低估量）；无逃逸时为 0 | null 或任意实数 |

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
"""

    if "delta_H" not in schema_content:
        with open(SCHEMA_FILE, "a", encoding="utf-8") as f:
            f.write(new_fields)
        print(f"  Updated schema: {SCHEMA_FILE}")
    else:
        print(f"  Schema already contains delta_H, skipping update")


def main():
    parser = argparse.ArgumentParser(description="GCL Posterior Feedback Pipeline")
    parser.add_argument(
        "--phase",
        choices=["a", "b", "c"],
        required=True,
        help="Pipeline phase to run: a (git commit map), b (intent classification), c (backfill & analysis)"
    )
    args = parser.parse_args()

    if args.phase == "a":
        phase_a()
    elif args.phase == "b":
        phase_b()
    elif args.phase == "c":
        phase_c()


if __name__ == "__main__":
    main()
