# Dyad 实验设计：LLM-boss Gate 与 H7 首次测量

**日期**：2026-06-24  
**状态**：设计完成，待数据积累  
**依赖**：docs/research/cc-actor-network.md §3, docs/research/gcl-complete-observation-mechanism.md §5  
**关联任务**：TASK-185 (实现), TASK-176 (gcl-events.jsonl schema)

---

## §1 Boss CC 架构：信号流与证据通道

### 1.1 信号流（文本图）

```
┌─────────────────────────────────────────────────────────────┐
│                    loop-backlog worker                       │
│                                                             │
│  [basic-daemon.js]                                          │
│       │ child-done:EPIC-N                                   │
│       ▼                                                     │
│  onChildDone(EPIC-N)                                        │
│       │ all children Basic: Done                            │
│       ▼                                                     │
│  setStatus(EPIC-N, "Epic: Evaluating")                      │
│       │                                                     │
│       ▼                                                     │
│  epicEvaluate(EPIC-N)                                       │
│       │                                                     │
│       ├──► [BOSS CC CHANNEL] ◄─── 独立证据                   │
│       │         │                  ├─ archguard change_risk  │
│       │         │                  └─ meta-cc session_signals│
│       │         │ (NOT worker Notes/summary)                 │
│       │         ▼                                           │
│       │    boss-evidence-pack.sh $EPIC_ID                   │
│       │         │ JSON evidence pack                        │
│       │         ▼                                           │
│       │    LLM boss verdict: FINISH | ITERATE               │
│       │    gate_actor_type = "llm"                          │
│       │         │                                           │
│       │         ▼                                           │
│       │    Write to epic Notes + gcl-events.jsonl           │
│       │                                                     │
│       ▼                                                     │
│  cap:evaluate=recommendation:<verdict>                      │
│  RECOMMENDATION: <FINISH|ITERATE>  ← soft-halt             │
│  (状态保持 Epic: Evaluating，等待人类确认)                   │
│                                                             │
│  [人类确认] ──► Epic: Done                                  │
│                gate_actor_type = "human" (confirmation gate) │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 证据通道

Boss CC 使用两条独立于 worker 的证据通道：

| 通道 | 来源 | 字段 | 独立性 |
|------|------|------|--------|
| archguard change_risk | `.archguard/query/git-history/file-metrics.json` | 文件变更风险分数、hot-spot 文件 | 高：来自版本控制历史，与任务 Notes 完全独立 |
| meta-cc session_signals | meta-cc MCP 工具 | 工具调用频率、error 分布、edit 振荡 | 中：来自 session 日志，而非 worker 自述摘要 |

**关键约束**：boss 不读取 worker Notes。worker 在任务 Notes 中写的自评摘要（`## Gate Evidence Pack`）**不进入** boss 的证据包。这是 cc-actor-network.md §4.1 的直接实现：避免 boss 只是 worker 的回声。

### 1.3 soft-halt 接入点

Boss CC 通道接入 `epicEvaluate` 函数，位于 `cap:evaluate` 写入**之前**：

```
epicEvaluate(id) {
  if hasCap(id, "evaluate"): return Idle   ← 幂等检查（不改变）

  [NEW] evidencePack = bossEvidenceCollect(id)
  [NEW] bossVerdict  = bossEvaluate(evidencePack, id)
  [NEW] writeGclEvent(id, gate_actor_type="llm")

  verdict = aggregate(childOutcomes, bossVerdict)

  appendNote("cap:evaluate=recommendation:...")  ← 原有逻辑
  appendNote("RECOMMENDATION: ...")              ← 原有逻辑
  -- soft-halt: 状态留在 Epic: Evaluating      ← 不改变
}
```

**不改变的内容**：soft-halt 状态机、`cap:evaluate` 写入时机、`RECOMMENDATION` note 格式。

---

## §2 证据独立性操作化

### 2.1 最小证据包字段

Boss 的 JSON 证据包（由 `boss-evidence-pack.sh` 生成）必须包含以下字段：

```json
{
  "task_id": "EPIC-N",
  "change_risk": {
    "hot_files": ["file1.sh", "file2.md"],
    "max_risk_score": 0.72,
    "churn_files": 3,
    "source": "archguard-file-metrics"
  },
  "session_signals": {
    "error_count": 2,
    "edit_oscillation": "low",
    "tool_call_count": 47,
    "source": "meta-cc-session"
  },
  "evidence_source": "archguard+meta-cc",
  "worker_notes_included": false,
  "collected_at": "2026-06-24T12:00:00Z"
}
```

**硬约束**：`worker_notes_included` 必须为 `false`。如果脚本意外读取了 worker Notes，输出应包含 `"worker_notes_included_violation": true` 并降级为 `"evidence_source": "unavailable"`。

### 2.2 evidence_independence 分级

| 等级 | 定义 | 此实验中适用于 |
|------|------|---------------|
| `high` | 证据来自完全独立通道（archguard git-history + meta-cc session log），boss 未读 worker Notes | 成功调用两条通道的 boss gate |
| `medium` | 证据来自部分独立通道（仅 meta-cc 或仅 archguard 之一可用） | 仅一条通道降级的 boss gate |
| `low` | 证据来自 worker 自述（含 Notes 摘要），循环证据 | 禁止此实验出现；若出现则标记并排除 |
| `unknown` | 证据来源未记录 | 历史回填记录；此实验不产生 unknown |

### 2.3 与 cc-actor-network.md §4.1 的对应

cc-actor-network.md §4.1 的核心论断：

> 一个"boss 和 worker 是同一个模型 + 共享同一份 context"的 dyad，在 H6 意义下监督质量接近于零——boss 只是 worker 的回声。**dyad 实验必须让 boss 持有 worker 没有的独立证据**。

本实验的落点：
- Boss 与 worker 可能是同一个基础模型（claude-sonnet-4-6），这是不可避免的现实条件
- 但 boss 的**证据通道**与 worker 的**上下文**正交：archguard 读 git-history，meta-cc 读 session log，两者均不经过 worker 的主要 context window
- 通过 `worker_notes_included: false` 约束强制执行这一点

---

## §3 H7 统计检验设计

### 3.1 零假设

**H7**（来自 gcl-h5-h6-h7-validation.md §1.1）：

> 在控制 evidence_independence 的情况下，gate_actor_type（human vs llm）对 escape_rate 无显著差异（routine gate 子集）。

等价写法：

```
H0: P(escape_rate=1 | gate_actor_type=llm, evidence_independence) 
  = P(escape_rate=1 | gate_actor_type=human, evidence_independence)

H1: 上述两者有显著差异
```

### 3.2 控制变量

| 控制变量 | 类型 | 用途 |
|---------|------|------|
| `evidence_independence` | 分类 (`high`/`medium`/`low`/`unknown`) | 主要协变量；H7 在"分层控制 evidence_independence"下检验 |
| `task_kind` | 分类 (`basic`/`epic`) | 分层变量；此实验仅产生 `epic` 类型 gate |
| `gate_type` | 分类 (`epic-evaluate`/`plan`/`proposal`) | 此实验仅产生 `epic-evaluate` 类型 |

### 3.3 效应量估计与样本规划

**初始测量目标**：N_llm ≥ 10 个 `epic-evaluate` gate 事件（`gate_actor_type=llm`）

**长期统计检验要求**：

| 检验 | 所需最小样本 | 依据 |
|------|------------|------|
| Fisher exact (H7, 2×2) | N_llm ≥ 10, N_human ≥ 10 | 两类各 10 事件可检测 OR ≈ 5 |
| Mann-Whitney U (若 escape_rate 连续化) | 各组 N ≥ 20 | 80% power at medium effect |
| 分层 Fisher (控制 evidence_independence) | 各层 N ≥ 5 | 避免稀疏格 |

**样本规划**：
- Phase 1（当前）：收集 ≥10 个 `llm` gate 事件（此实验将每次 epic 评估自动产生 1 个）
- Phase 2：引入至少 10 个 human gate 事件（人类手动审核部分 epic）
- Phase 3：当 N_llm ≥ 10 且 N_human ≥ 10 时，运行 Fisher exact 检验

### 3.4 检验选择

**主检验**：Fisher exact test

适用条件：
- 两个二元变量（`gate_actor_type` × `escape_rate`）
- N 较小时精确 p 值优于卡方近似
- 分层后各层可独立执行 Fisher exact

**备选检验**：Mann-Whitney U

适用条件：若 escape_rate 被扩展为连续变量（如 re-work 工作量），或当 N 足够大时替代 Fisher。

### 3.5 可证伪规则

- **H7 成立的证据**：Fisher exact p > 0.05，OR 置信区间包含 1.0，在 evidence_independence 分层后差异仍不显著
- **H7 被否定的证据**：Fisher exact p ≤ 0.05，且 evidence_independence 受控情况下 llm gate 显著高于或低于 human gate 的 escape_rate
- **无法检验**：N_llm < 10 或 N_human < 10，或 escape_rate 方差为 0（所有 escape_rate=0）

---

## §4 实验局限性预声明

1. **同质化风险**：Boss 和 worker 使用相同基础模型。即使证据独立，推理模式仍可能相关。若 H7 在 `evidence_independence=high` 下成立，这更强烈支持证据独立性而非 actor 多样性的贡献。
2. **Human gate 样本稀缺**：收集 ≥10 个 human gate 事件需要主动设计人类审核流程，而非仅依赖现有 soft-halt。
3. **Escape rate 定义稳定性**：当前 escape_rate 定义（Needs Human 状态或 reaper 重排）仅是近似。真正的"逃逸"应指 gate 通过后发现的质量问题，现有代理指标可能存在误测。
4. **小样本期间的 I 类错误风险**：Fisher exact 在小 N 时保守（欠检验），但这是合理的科学谨慎。

---

## §5 参考文献

| 来源 | 关联 |
|------|------|
| docs/research/cc-actor-network.md §3, §4.1 | Dyad 设计原则，证据独立性约束 |
| docs/research/gcl-complete-observation-mechanism.md §5 | H7 可证伪规则 |
| docs/research/gcl-events-schema.md | gate_actor_type, evidence_independence 字段定义 |
| docs/research/gcl-h5-h6-h7-validation.md | 当前数据集状态，H7 UNTESTABLE 现状 |
| plugin/skills/loop-backlog/SKILL.md (epicEvaluate) | Boss CC 通道接入点 |
| plugin/skills/loop-backlog/boss-evidence-pack.sh | 证据收集脚本 |
