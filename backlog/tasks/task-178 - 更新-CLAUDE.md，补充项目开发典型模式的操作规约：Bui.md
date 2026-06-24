---
id: TASK-178
title: 更新 CLAUDE.md，补充项目开发典型模式的操作规约：Bui
status: 'Basic: Done'
assignee: []
created_date: '2026-06-23 23:26'
updated_date: '2026-06-23 23:31'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 116000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
更新 CLAUDE.md，补充项目开发典型模式的操作规约：Build & Install 构建安装流程、loop-backlog 交互规约（驻留模式/防重复启动）、ADR 检查范围精确化（含 CLI flag/Monitor 生命周期场景）、实验基础设施入口（experiments/skill-quality/ 和 run-quantitative-experiment）、meta-cc 自查入口。
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Plan: 更新 CLAUDE.md，补充项目开发典型模式的操作规约

## Context
当前 CLAUDE.md 仅 19 行，记录了项目简介、ADR 入口和 L0 Config。基于 meta-cc 会话模式分析（Bash 3982 次、Monitor 83 次、ScheduleWakeup 75 次、Skill 61 次），项目存在多个高频但无文档的操作模式：build-install-verify 循环、loop-backlog 驻留交互、ADR 触发场景、实验基础设施入口、meta-cc 自查。将这些模式固化到 CLAUDE.md 可降低每次会话的重新推理成本。

## Phase 1: 审查现状
读取 CLAUDE.md（`cat CLAUDE.md`）和 `scripts/install/install.sh` 前 20 行，确认：
- 构建安装命令是否为 `bash scripts/install/install.sh --user`
- loop-backlog 停止信号文件路径（`backlog/.loop-stop`）
- 实验目录路径（`experiments/skill-quality/`）
- 当前 ADR 列表（`ls docs/adr/`）覆盖的场景

### DoD
- `grep -q '## L0 Config' CLAUDE.md`
- `test -f scripts/install/install.sh`
- `test -d experiments/skill-quality`

## Phase 2: 更新 CLAUDE.md
使用 Edit 工具在 CLAUDE.md 现有内容末尾追加以下各节（不修改现有内容）：

**1. `## Build & Install`**
```
After modifying plugin skills or scripts, rebuild and reinstall:
  bash scripts/install/install.sh --user
Verify:
  bash scripts/validate-plugin.sh
```

**2. `## loop-backlog`**
```
Start the autonomous worker once per session:
  /loop-backlog
Check status: backlog task list --plain
Stop: touch backlog/.loop-stop
Do NOT start a second loop if one is already running — check for active Monitor before invoking.
```

**3. ADR 节扩写**（将现有 ADR 段落替换为更精确版本）：
```
ADRs live in `docs/adr/`. Read relevant ADRs before:
- modifying or creating skills/agents
- using backlog CLI flags (see ADR-006)
- touching Monitor lifecycle or daemon scripts (see ADR-001, ADR-002)
When a fix resolves a recurring architectural problem, capture it as a new ADR.
```

**4. `## Experiments`**
```
Quantitative skill experiments live in `experiments/skill-quality/`.
Use /run-quantitative-experiment to run a new experiment.
Pre-register hypotheses before execution (see docs/llm-capability-measurement-methodology.md).
```

**5. `## Session Analysis`**
```
Use meta-cc MCP tools to query Claude Code session history for self-analysis,
GCL measurement, or debugging session state:
  mcp__plugin_meta-cc_meta-cc__query_user_messages
  mcp__plugin_meta-cc_meta-cc__get_work_patterns
```

### DoD
- `grep -q '## Build & Install' CLAUDE.md`
- `grep -q 'install.sh' CLAUDE.md`
- `grep -q '## loop-backlog' CLAUDE.md`
- `grep -q 'loop-stop' CLAUDE.md`
- `grep -q '## Experiments' CLAUDE.md`
- `grep -q 'skill-quality' CLAUDE.md`
- `grep -q '## Session Analysis' CLAUDE.md`
- `grep -q 'meta-cc' CLAUDE.md`
- `grep -q 'ADR-006' CLAUDE.md`

## Phase 3: 验证
运行插件验证，确认 CLAUDE.md 变更未破坏任何 plugin 合规检查。

### DoD
- `bash scripts/validate-plugin.sh`
- `grep -q '## L0 Config' CLAUDE.md`

## Constraints
- 不删除或修改现有 CLAUDE.md 内容（ADR 段落除外，改写为更精确版本）
- 不修改任何 skill、agent 或脚本文件
- 不创建分支、不 push、不开 PR
- 各节内容保持简洁（≤8 行/节），避免把 CLAUDE.md 变成文档中心

## Acceptance Gate
- `grep -q '## Build & Install' CLAUDE.md`
- `grep -q '## loop-backlog' CLAUDE.md`
- `grep -q '## Experiments' CLAUDE.md`
- `grep -q '## Session Analysis' CLAUDE.md`
- `grep -q 'ADR-006' CLAUDE.md`
- `bash scripts/validate-plugin.sh`
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan review iteration 1: APPROVED

cap:propose=approved

claimed: 2026-06-23T15:45:00Z

## Execution Summary
Result: Done
Commit: c8d0fce (merged)
All 13 DoD checks passed. Expanded ADR section with ADR-006/001/002 triggers; added ## Build & Install, ## loop-backlog, ## Experiments, ## Session Analysis.
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 bash scripts/validate-plugin.sh
- [ ] #2 grep -q '## Build & Install' CLAUDE.md
- [ ] #3 grep -q '## Experiments' CLAUDE.md
- [ ] #4 grep -q '## L0 Config' CLAUDE.md
- [ ] #5 grep -q '## Session Analysis' CLAUDE.md
- [ ] #6 grep -q '## loop-backlog' CLAUDE.md
- [ ] #7 grep -q 'ADR-006' CLAUDE.md
- [ ] #8 grep -q 'install.sh' CLAUDE.md
- [ ] #9 grep -q 'loop-stop' CLAUDE.md
- [ ] #10 grep -q 'meta-cc' CLAUDE.md
- [ ] #11 grep -q 'skill-quality' CLAUDE.md
- [ ] #12 test -d experiments/skill-quality
- [ ] #13 test -f scripts/install/install.sh
<!-- DOD:END -->
