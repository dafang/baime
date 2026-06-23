# ADR-002: Monitor 生命周期 — 启动前必须清理旧进程

**Status**: Accepted
**Date**: 2026-06-23
**Deciders**: Yale Huang
**Related tasks**: TASK-169, fix: use tail -f -n 0 in loop-backlog Monitor

## Context

loop-backlog skill 使用 Claude Code 的 Monitor 工具监听 daemon 日志文件。每次调用 `/loop-backlog` 或 skill 重启时，都会创建一个新的 Monitor。

旧的 Monitor 进程不会自动终止，导致：
- 多个 Monitor 同时监听同一日志文件
- 相同事件被多个 Monitor 触发，产生重复任务处理
- 用户看到 "2 个 Monitor" 的混乱状态
- 游离 Monitor 消耗资源且行为不可预测

## Decision

loop-backlog skill 在创建新 Monitor 之前，**必须**调用 `stopStaleMon()` 清理所有已存在的同类 Monitor。

守护顺序：
1. 调用 `stopStaleMon()` 停止旧 Monitor
2. 验证旧进程已终止
3. 创建新 Monitor

任意时刻，针对同一目标项目，最多只能有一个 loop-backlog Monitor 存在。

## Consequences

- 单 Monitor 不变量（invariant）得到强制保证
- 重启 loop-backlog 是安全的幂等操作
- skill 启动逻辑增加了 stopStaleMon() 调用开销（可忽略）

## Rejected alternatives

**检测到 Monitor 存在则跳过创建**：无法处理僵尸进程（进程存在但不响应）；且用户显式重启时期望刷新 Monitor 行为。

**依赖 Monitor 自然超时退出**：Monitor 没有内置超时机制，旧进程会无限期存在。
