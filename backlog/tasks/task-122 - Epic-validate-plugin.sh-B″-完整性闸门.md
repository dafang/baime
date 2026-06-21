---
id: TASK-122
title: 'Epic: validate-plugin.sh B″ 完整性闸门'
status: 'Epic: Proposal'
assignee: []
created_date: '2026-06-21 09:16'
labels:
  - 'kind:epic'
dependencies: []
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Epic 目标
原 B″ 计划的 config.yml 状态校验用 grep 行数检查,与现行 inline 数组格式不兼容(会返回 0);且缺少防裸状态回归的守卫。本 Epic 把校验改为格式无关的 YAML parse,并补齐回归守卫。

## 拟拆分的 Basic 子任务(decompose 阶段细化)
1. 用 Python YAML parse 替换行数检查,断言 config.yml 恰含 14 个 Epic:/Basic: 状态(兼容 inline)
2. 加守卫:任何 SKILL.md body 含裸遗留状态串即 FAIL
3. (可选) 把 daemon pid/存活检查纳入 validate-plugin.sh

## 验收信号
bash scripts/validate-plugin.sh
python3 -c "import yaml;c=yaml.safe_load(open('backlog/config.yml'));assert len([s for s in c['statuses'] if s.startswith(('Epic:','Basic:')))==14"
<!-- SECTION:DESCRIPTION:END -->
