# Proposal: loop-backlog 并行 background agent 执行 task（主循环控制 merge）

## Background

当前 loop-backlog skill 串行执行：claim → execute → merge → claim → ...
每次只处理一个 task，execute 全程阻塞主 Claude session。当 backlog 中有多个
Ready task 时，后续 task 必须等待前一个完整执行周期结束才能开始，吞吐量受限于
单个 task 的执行时间。

本提案将 execute 阶段改为 background agent 并行执行，主循环保留 worktree 创建
和 merge 的串行控制权，从而在不引入 merge conflict 风险的前提下提升并发吞吐。

## Goals

1. 主循环能同时 spawn 多个 background agent，每个 agent 独立执行一个 task
2. task agent 只写自己的 worktree 和 branch，不操作其他路径，不执行 git merge
3. 主循环在所有 agent 完成后串行 merge 各 branch，消除 merge conflict 风险
4. max-parallel 并发数可通过 CLAUDE.md 的 `## L0 Config` 段落配置（默认 2）
5. agent 通过信号文件向主循环报告完成状态（done 或 needs-human: reason）

## Proposed Approach

**allowed-tools 变更**：当前 SKILL.md 的 `allowed-tools` 为
`Bash, Read, Write, Edit, Glob, Grep, Monitor`，不含 Agent 工具。
实现本提案需在 SKILL.md frontmatter 中新增 `Agent` 到 `allowed-tools`，
并在 `executePrompt` 契约中明确禁止 task agent 递归调用 Agent，
以防止无界递归。

**Config 扩展**：在 `CLAUDE.md` 的 `## L0 Config` 段落新增 `max-parallel: N`
字段（整数，默认 2），由 `loadConfig` 解析后存入 `cfg.maxParallel`。
`loadConfig` 的 bash 实现需在现有 `parse_cfg "worktree-symlinks"` 之后
补充一行：`CFG_MAX_PARALLEL=$(parse_cfg "max-parallel")`，
并设置 `CFG_MAX_PARALLEL=${CFG_MAX_PARALLEL:-2}` 作为默认值。

**claim 函数签名变更**：当前 SKILL.md 的 `claim :: () → Maybe Task` 仅返回单个
task。本提案需将其扩展为 `claimBatch :: Int → [Task]`，一次性 claim 最多
`maxParallel` 个 Ready task（每个均原子地设为 In Progress），
返回实际 claimed 的 task 列表（可能少于 maxParallel）。

**新 workerLoop 流程**：
1. 主循环调用 `claimBatch(cfg.maxParallel)`，为每个 task 调用 `withWorktree` 建立 worktree
2. 对每个 claimed task，spawn 一个 background agent（`run_in_background=true`），
   传入自包含 prompt（含 task ID、title、description、DoD commands、worktree 路径、branch 名）
3. 调用 `waitForAgents`：轮询 `backlog/.agent-done-TASK-N` 信号文件，全部出现后继续
4. 串行遍历 claimed tasks，读取信号文件内容：`done` → 执行 merge；`needs-human: <reason>` → escalate
5. 删除信号文件，进入下一轮

**executePrompt 契约**：agent 只被允许在其 worktree 内工作，commit 如有变更，
完成后写 `backlog/.agent-done-TASK-N`（内容 `done` 或 `needs-human: <reason>`），
不执行 git merge，escalation 时写信号文件后立即退出。
Agent 的 allowed-tools 须显式排除 Agent 工具本身，防止递归 spawn。
executePrompt 须为自包含 prompt（含 task ID、title、description、DoD commands、
worktree 路径、branch 名、信号文件路径），不依赖外部变量。

**信号协议**：
- 文件路径：`backlog/.agent-done-TASK-N`
- 内容格式：`done` 或 `needs-human: <reason>`
- 生命周期：agent 写入，主循环读取后删除

## Trade-offs and Risks

**不做的事**：不引入跨 agent 通信；不实现动态并发调度（固定 max-parallel 上限）；
不修改 merge 策略（仍为 no-ff）；不改变 reaper 逻辑。

**已知风险**：
- 若多个 agent 同时修改相同文件，merge 时仍可能产生 conflict → 由现有 merge conflict
  escalation 路径处理，无需新增逻辑
- waitForAgents 使用轮询（sleep 5s），agent 意外挂起时需依赖 reaper（30min timeout）
  兜底；agent 崩溃（非挂起）时信号文件永不写入，waitForAgents 同样会阻塞直至 reaper
  超时触发——两种失败模式均由同一 30min reaper 路径兜底，无需额外机制
- allowed-tools 新增 Agent 后，skill 可递归 spawn agent，需在 executePrompt 中
  明确禁止 task agent 再次 spawn agent（已在 executePrompt 契约中明确）
- claimBatch 需原子性逐一 claim，不保证批次内所有 claim 均成功（另一个 loop-backlog
  实例可能并发 claim）；主循环应以实际返回列表为准，而非假设数量等于 maxParallel
- 并行执行增加了每轮对 backlog CLI（`backlog task edit`）的并发写入频率；
  若 backlog CLI 不支持并发写入，需在主循环的串行 merge 阶段集中执行状态更新
