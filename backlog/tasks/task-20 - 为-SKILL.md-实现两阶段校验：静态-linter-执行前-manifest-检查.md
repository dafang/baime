---
id: TASK-20
title: 为 SKILL.md 实现两阶段校验：静态 linter + 执行前 manifest 检查
status: Proposal
assignee: []
created_date: '2026-06-17 22:25'
updated_date: '2026-06-18 02:27'
labels:
  - toolchain
  - skill-quality
  - linting
dependencies:
  - TASK-19
priority: medium
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

上下文压缩前发现的两类 bug 的共同根源：
- **author-time 缺陷**（Config 类型冲突、undefined ref）：写 SKILL.md 时没有机械化校验
- **execution-time 缺陷**（`--description` 覆盖原始描述、resolveOrCreate 缺失）：Claude 执行 skill 时偏离 spec，且 spec 本身不完整

TASK-19 覆盖了 author-time 静态检查。本任务覆盖 execution-time 校验，并明确两阶段的架构分工。

---

## 核心设计

### 两阶段分工

```
author-time  (写 SKILL.md 时)
  → skill-lint.sh --static plugin/skills/*/SKILL.md
  → 捕获：类型冲突、undefined ref、field 写法、clone

execution-time (Claude 运行 skill 前)
  → Claude 在 Phase 0 生成 manifest.json（CoT 展开为结构化输出）
  → skill-lint.sh --manifest $TMPDIR/<skill>-manifest.json
  → 捕获：field 写法错误、phase 跳过逻辑不一致、entry_point 非法
```

### LLM 承担"展开"，linter 承担"校验"

不实现 DSL 解释器。Claude 自行将 SKILL.md spec 展开为执行计划（即 CoT），最终物化为一个结构化 manifest，linter 对 manifest 做机械化检查。

这是 compiler 方案的简化替代：保留"形式校验"，放弃"确定性展开"。

---

## Manifest 格式（Phase 0 输出）

```json
{
  "skill": "task-to-backlog",
  "task_id": "TASK-12 | null",
  "entry_point": "resolveOrCreate | createTask",
  "skip_draft": true,
  "field_writes": [
    { "tool": "backlog task edit", "field": "planSet",  "source": "$TMPDIR/ttb-plan.md" },
    { "tool": "backlog task edit", "field": "status",   "value": "Plan Review" }
  ],
  "phases_to_execute": ["resolveOrCreate", "reviewLoop", "finalise"]
}
```

Linter 规则（manifest 层）：
- `field_writes[*].field` ≠ `"description"`（task create 除外）
- `phases_to_execute` 中的每项必须对应 SKILL.md spec 中已定义的函数
- `entry_point` 必须是 spec 中 resolveOrCreate 的合法返回构造子
- `skip_draft == true` iff `entry_point == "resolveOrCreate"`

---

## 与 TASK-19 的关系

| | TASK-19 | 本任务 |
|---|---|---|
| 检查时机 | author-time | execution-time |
| 检查对象 | SKILL.md 文件本身 | manifest JSON（Claude 生成） |
| 主要发现 | 类型冲突、undefined ref | field 写法错误、phase 逻辑偏离 |
| 实现复杂度 | grep + diff | JSON Schema + 业务规则 |
| 依赖关系 | 独立 | 可复用 TASK-19 的 skill-lint.sh |

两者共用同一工具入口：`bash scripts/skill-lint.sh`，通过子命令区分。

---

## 遗留缺口（本方案不覆盖）

- Claude 写了正确的 manifest 但实际执行时调用了不同的字段（manifest 与实现解耦）
- Manifest 格式被 Claude 写错（需 JSON Schema 校验兜底，已含在 linter 规则中）

如需完全消除第一项缺口，需实现 compiler 方案（Phase 3，可选，见 TASK-19 讨论）。

---

## 目标交付物

1. `scripts/skill-lint.sh --manifest <path>` 子命令：manifest 规则校验
2. `plugin/skills/task-to-backlog/SKILL.md` Phase 0 节：manifest 生成 + lint 步骤
3. `plugin/skills/feature-to-backlog/SKILL.md` Phase 0 节：同上
4. 集成到 `scripts/validate-plugin.sh`（可选：用示例 manifest fixture 做 smoke test）
<!-- SECTION:DESCRIPTION:END -->
