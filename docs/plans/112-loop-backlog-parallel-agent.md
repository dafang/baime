# Plan: loop-backlog 并行 background agent 执行 task（主循环控制 merge）

Proposal: docs/proposals/proposal-loop-backlog-parallel-agent.md

## Phase A: Config 扩展 — 解析 max-parallel 并更新 allowed-tools

### Tests (write first)

These grep checks must FAIL before implementation (i.e., the strings do not yet exist in SKILL.md):

```bash
# Must fail before Phase A:
grep -q "Agent" plugin/skills/loop-backlog/SKILL.md          # exits 1 — Agent not in allowed-tools
grep -q "maxParallel" plugin/skills/loop-backlog/SKILL.md    # exits 1 — not in Spec Config type
grep -q "max-parallel" plugin/skills/loop-backlog/SKILL.md   # exits 1 — not in loadConfig bash
grep -q "CFG_MAX_PARALLEL" plugin/skills/loop-backlog/SKILL.md  # exits 1 — not in Implementation
```

### Implementation

**Edit 1** — frontmatter `allowed-tools`: add `Agent` to the existing line.

In `plugin/skills/loop-backlog/SKILL.md`, change:

```
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Monitor
```

to:

```
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Monitor, Agent
```

**Edit 2** — `Config` type in `## Spec`: add `maxParallel` field.

Change:

```
Config :: {
  symlinks : [Path]   -- dirs to symlink into worktree ([] = none)
}
```

to:

```
Config :: {
  symlinks    : [Path]   -- dirs to symlink into worktree ([] = none)
  maxParallel : Int      -- max concurrent background agents (default 2)
}
```

**Edit 3** — `loadConfig` spec: mention `max-parallel` parsing.

After the existing `loadConfig` definition:

```
loadConfig :: () → Config
loadConfig() =
  | fromClaudeMd()   -- explicit: "## L0 Config" section in CLAUDE.md
  | autoDetect()     -- implicit: probe package.json, go.mod, Cargo.toml, etc.
```

Change to:

```
loadConfig :: () → Config
loadConfig() =
  | fromClaudeMd()   -- explicit: "## L0 Config" section in CLAUDE.md
                     -- reads: worktree-symlinks, max-parallel (default 2)
  | autoDetect()     -- implicit: probe package.json, go.mod, Cargo.toml, etc.
```

**Edit 4** — `### loadConfig` bash block: add `CFG_MAX_PARALLEL` parsing after the existing `CFG_SYMLINKS` line.

Change:

```bash
CFG_SYMLINKS=$(parse_cfg "worktree-symlinks")
```

to:

```bash
CFG_SYMLINKS=$(parse_cfg "worktree-symlinks")
CFG_MAX_PARALLEL=$(parse_cfg "max-parallel")
CFG_MAX_PARALLEL=${CFG_MAX_PARALLEL:-2}
```

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "Agent" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "maxParallel" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "max-parallel" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "CFG_MAX_PARALLEL" plugin/skills/loop-backlog/SKILL.md`

---

## Phase B: Spec 更新 — claimBatch、spawnAgent、waitForAgents 函数定义

### Tests (write first)

These grep checks must FAIL before Phase B (i.e., do not yet exist after Phase A):

```bash
# Must fail before Phase B:
grep -q "claimBatch" plugin/skills/loop-backlog/SKILL.md     # exits 1
grep -q "spawnAgent" plugin/skills/loop-backlog/SKILL.md     # exits 1
grep -q "waitForAgents" plugin/skills/loop-backlog/SKILL.md  # exits 1
grep -q "agent-done-TASK" plugin/skills/loop-backlog/SKILL.md  # exits 1 (signal file path)
```

### Implementation

**Edit 1** — replace `claim` spec definition with `claimBatch`, and update `workerLoop` to use the new parallel flow.

In `## Spec`, replace the existing `claim` definition:

```
claim :: () → Maybe Task
claim() = {
  t: head(readyTasks()),
  if (empty(t)): return Nothing,
  atomically: {
    setStatus(t, "In Progress"),
    appendNote(t, "claimed: " + now())
  },
  return: Just(t)
}
```

with:

```
claimBatch :: Int → [Task]
claimBatch(n) = {
  tasks: take(n, readyTasks()),
  if (empty(tasks)): return [],
  ∀t ∈ tasks: atomically: {
    setStatus(t, "In Progress"),
    appendNote(t, "claimed: " + now())
  },
  return: tasks        -- actual list; may be fewer than n if fewer Ready tasks exist
}
```

**Edit 2** — add `spawnAgent` and `waitForAgents` spec definitions after `claimBatch`.

Insert after `claimBatch`:

```
-- spawnAgent: launch a background agent for a single task in its worktree.
-- The agent works only inside wt, commits if changed, then writes a signal file.
-- Agent's allowed-tools explicitly excludes Agent to prevent recursive spawn.
spawnAgent :: (Task, Worktree) → ()
spawnAgent(T, wt) =
  Agent(run_in_background=true, prompt=executePrompt(T, wt))

-- waitForAgents: poll signal files until all agents in the batch have reported.
-- Signal file path: backlog/.agent-done-TASK-N
-- Content: "done" | "needs-human: <reason>"
-- Polls every 5 seconds; no external dependencies beyond bash.
waitForAgents :: [Task] → Map Task SignalContent
waitForAgents(tasks) = {
  remaining: tasks,
  results:   {},
  loop while (nonEmpty(remaining)): {
    sleep(5),
    ∀t ∈ remaining:
      if (exists("backlog/.agent-done-" + t.id)):
        content: read("backlog/.agent-done-" + t.id),
        results[t]: content,
        remaining:  remaining \ {t}
  },
  return: results
}
```

**Edit 3** — replace `workerLoop` spec to use `claimBatch` / `spawnAgent` / `waitForAgents`.

Replace the existing `workerLoop` spec body:

```
workerLoop :: () → Outcome
workerLoop() = {
  cfg:    loadConfig(),
  _:      ensureDaemonScript(),
  _:      daemonBootstrap(),
  _:      reap(inProgressTasks()),
  task:   claim(),

  if (stopSentinel()):
    return: Stopped,

  if (empty(task)):
    -- No task yet; block persistently until daemon emits a task-ready line
    -- Monitor(persistent=true) never times out — daemon runs until .loop-stop written
    event: Monitor(persistent=true),
    if (event matches "task-ready:TASK-*"):
      return: workerLoop(),      -- re-enter to claim the announced task
    if (stopSentinel()):
      return: Stopped,

  result: withWorktree(task, cfg, execute),
  return: result
}
```

with:

```
workerLoop :: () → Outcome
workerLoop() = {
  cfg:    loadConfig(),
  _:      ensureDaemonScript(),
  _:      daemonBootstrap(),
  _:      reap(inProgressTasks()),
  tasks:  claimBatch(cfg.maxParallel),

  if (stopSentinel()):
    return: Stopped,

  if (empty(tasks)):
    -- No task yet; block persistently until daemon emits a task-ready line
    event: Monitor(persistent=true),
    if (event matches "task-ready:TASK-*"):
      return: workerLoop(),
    if (stopSentinel()):
      return: Stopped,

  -- Parallel: create worktrees and spawn one background agent per task
  worktrees: ∀t ∈ tasks: withWorktree(t, cfg),
  _:         ∀(t, wt) ∈ zip(tasks, worktrees): spawnAgent(t, wt),

  -- Wait for all agents to signal completion
  results: waitForAgents(tasks),

  -- Serial: merge each branch in order; read signal file to decide merge vs. escalate
  ∀t ∈ tasks: {
    sig: results[t],
    _:   deleteSignalFile("backlog/.agent-done-" + t.id),
    if (sig == "done"):
      merge(t, t.branch)
    else:
      escalate(t, stripPrefix("needs-human: ", sig))
  },

  return: Done
}
```

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "claimBatch" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "spawnAgent" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "waitForAgents" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "agent-done-TASK" plugin/skills/loop-backlog/SKILL.md`

---

## Phase C: Implementation 更新 — bash 实现 claimBatch、waitForAgents、executePrompt、workerLoop

### Tests (write first)

These grep checks must FAIL before Phase C (i.e., do not yet exist after Phase B):

```bash
# Must fail before Phase C:
grep -q "run_in_background" plugin/skills/loop-backlog/SKILL.md   # exits 1 — Agent call not yet in Implementation
grep -q "executePrompt" plugin/skills/loop-backlog/SKILL.md       # exits 1
grep -q "CFG_MAX_PARALLEL" plugin/skills/loop-backlog/SKILL.md    # still exits 1 if Phase A not done (dependency)
# After Phase A this one passes; Phase C introduces the others below:
grep -q "agent-done-TASK" plugin/skills/loop-backlog/SKILL.md     # exits 1 in signal-file bash block
```

### Implementation

**Edit 1** — replace `### claim` bash section with `### claimBatch`.

Replace:

```
### claim

\`\`\`bash
TASK_ID=$(backlog task list --status "Ready" --plain | grep -oP 'TASK-\d+' | head -1)
\`\`\`

If empty and no stop sentinel: use Monitor (persistent) to wait for the next `task-ready` event.
The daemon writes `task-ready:TASK-N` lines to `$DAEMON_LOG`; Monitor tails that file:

\`\`\`bash
# Foreground tail — Monitor reads its stdout as the event stream.
# No background subshell, no --pid, no pipeline.
Monitor(persistent=true, command="tail -f \"$DAEMON_LOG\"")
\`\`\`

Any output line matching `task-ready:TASK-*` is the wake-up signal; re-enter `workerLoop()`.

\`\`\`bash
backlog task edit "$TASK_ID" --status "In Progress" \
  --append-notes "claimed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
\`\`\`
```

with:

```
### claimBatch

Claim up to `CFG_MAX_PARALLEL` Ready tasks atomically. Returns the list of claimed task IDs
in `CLAIMED_TASK_IDS` (space-separated). If fewer Ready tasks exist, claims only those.

\`\`\`bash
CLAIMED_TASK_IDS=""
CLAIM_COUNT=0
while IFS= read -r CANDIDATE_ID; do
  [ -z "$CANDIDATE_ID" ] && continue
  [ "$CLAIM_COUNT" -ge "$CFG_MAX_PARALLEL" ] && break
  backlog task edit "$CANDIDATE_ID" --status "In Progress" \
    --append-notes "claimed: $(date -u +%Y-%m-%dT%H:%M:%SZ)" 2>/dev/null || continue
  CLAIMED_TASK_IDS="${CLAIMED_TASK_IDS} ${CANDIDATE_ID}"
  CLAIM_COUNT=$((CLAIM_COUNT + 1))
done < <(backlog task list --status "Ready" --plain | grep -oP 'TASK-\d+')
CLAIMED_TASK_IDS=$(echo "$CLAIMED_TASK_IDS" | xargs)  # trim whitespace
\`\`\`

If `CLAIMED_TASK_IDS` is empty and no stop sentinel: use Monitor (persistent) to wait for
the next `task-ready` event. The daemon writes `task-ready:TASK-N` lines to `$DAEMON_LOG`;
Monitor tails that file:

\`\`\`bash
# Foreground tail — Monitor reads its stdout as the event stream.
Monitor(persistent=true, command="tail -f \"$DAEMON_LOG\"")
\`\`\`

Any output line matching `task-ready:TASK-*` is the wake-up signal; re-enter `workerLoop()`.
```

**Edit 2** — add `### waitForAgents` bash section after `### claimBatch`.

Insert immediately after the claimBatch section (before `### withWorktree`):

```
### waitForAgents

Poll `backlog/.agent-done-TASK-N` signal files for every task in `CLAIMED_TASK_IDS`.
Loops with `sleep 5` until all signal files are present.

\`\`\`bash
# $1: space-separated list of TASK-IDs to wait for
waitForAgents() {
  local REMAINING="$1"
  local ALL_DONE=false
  while [ "$ALL_DONE" = "false" ]; do
    ALL_DONE=true
    local STILL_WAITING=""
    for TID in $REMAINING; do
      SIGNAL_FILE="${REPO_ROOT}/backlog/.agent-done-${TID}"
      if [ ! -f "$SIGNAL_FILE" ]; then
        ALL_DONE=false
        STILL_WAITING="${STILL_WAITING} ${TID}"
      fi
    done
    REMAINING=$(echo "$STILL_WAITING" | xargs)
    if [ "$ALL_DONE" = "false" ]; then
      echo "waitForAgents: still waiting for:${REMAINING}"
      sleep 5
    fi
  done
  echo "waitForAgents: all agents done"
}
\`\`\`
```

**Edit 3** — add `### executePrompt` bash section after `### waitForAgents`.

Insert after `### waitForAgents`:

```
### executePrompt

Build a self-contained prompt string for a background agent executing one task.
The prompt must not depend on external bash variables at call time — all values
are interpolated into the string before passing to the Agent tool.
The agent's allowed-tools list explicitly excludes `Agent` to prevent recursive spawn.

\`\`\`bash
# Usage: PROMPT=$(buildExecutePrompt "$TASK_ID" "$TASK_TITLE" "$TASK_DESC" "$WORKTREE" "$BRANCH" "$SIGNAL_FILE")
buildExecutePrompt() {
  local TID="$1"
  local TTITLE="$2"
  local TDESC="$3"
  local TWT="$4"
  local TBRANCH="$5"
  local TSIGNAL="$6"

  cat <<PROMPT_EOF
You are a background task agent. Your only job is to execute the task described below.

## Task
ID: ${TID}
Title: ${TTITLE}
Branch: ${TBRANCH}
Worktree: ${TWT}
Signal file: ${TSIGNAL}

## Description
${TDESC}

## Constraints
- Work exclusively inside the worktree at: ${TWT}
- Do NOT run git merge or git push
- Do NOT spawn sub-agents (Agent tool is not available to you)
- After all work is complete, run git add -A && git commit if there are changes
- Write the signal file as the LAST action before exiting

## Completing the task
When done (success):
  Write file ${TSIGNAL} with content: done

If you cannot continue without human input (escalation):
  Write file ${TSIGNAL} with content: needs-human: <one-line reason>

allowed-tools: Bash, Read, Write, Edit, Glob, Grep
PROMPT_EOF
}
\`\`\`
```

**Edit 4** — replace the main `workerLoop` orchestration in the implementation to use `claimBatch`, `spawnAgent` (Agent call), `waitForAgents`, and serial merge.

After the `### merge` section, add a `### workerLoop (parallel)` section that documents the full orchestration flow:

```
### workerLoop (parallel)

The top-level orchestration using claimBatch, background Agent spawning, and serial merge.

\`\`\`bash
# After loadConfig, ensureDaemonScript, daemonBootstrap, and reap have run:

# 1. Claim a batch of up to CFG_MAX_PARALLEL Ready tasks
# (claimBatch sets CLAIMED_TASK_IDS)

if [ -z "$CLAIMED_TASK_IDS" ]; then
  # No ready tasks — block on daemon event
  # Monitor(persistent=true, command="tail -f \"$DAEMON_LOG\"")
  # On task-ready event: re-enter workerLoop
  exit 0
fi

# 2. Create worktrees and spawn one background agent per task
declare -A TASK_WORKTREES
declare -A TASK_BRANCHES
for TASK_ID in $CLAIMED_TASK_IDS; do
  BRANCH="task/${TASK_ID}"
  PROJECT_NAME=$(basename "$REPO_ROOT")
  WORKTREE="${REPO_ROOT}/../${PROJECT_NAME}-${TASK_ID}"
  git worktree add "$WORKTREE" -b "$BRANCH"
  for SYM in $CFG_SYMLINKS; do
    [ -e "${REPO_ROOT}/${SYM}" ] && ln -sf "${REPO_ROOT}/${SYM}" "${WORKTREE}/${SYM}"
  done
  TASK_WORKTREES[$TASK_ID]="$WORKTREE"
  TASK_BRANCHES[$TASK_ID]="$BRANCH"

  TASK_VIEW=$(backlog task view "$TASK_ID" --plain)
  TASK_TITLE=$(echo "$TASK_VIEW" | grep -oP '(?<=Task TASK-\d+ - ).+' | head -1)
  TASK_DESC=$(echo "$TASK_VIEW" | awk '/^Description:/,/^(Status|Assignee|Labels|Priority|Due|Created|Updated|Notes):/' | tail -n +2)
  SIGNAL_FILE="${REPO_ROOT}/backlog/.agent-done-${TASK_ID}"

  AGENT_PROMPT=$(buildExecutePrompt \
    "$TASK_ID" "$TASK_TITLE" "$TASK_DESC" "$WORKTREE" "$BRANCH" "$SIGNAL_FILE")

  # Spawn background agent — run_in_background=true
  Agent(run_in_background=true, prompt="$AGENT_PROMPT")
done

# 3. Wait for all agents to write their signal files
waitForAgents "$CLAIMED_TASK_IDS"

# 4. Serial merge: read signal, merge or escalate, delete signal file
for TASK_ID in $CLAIMED_TASK_IDS; do
  SIGNAL_FILE="${REPO_ROOT}/backlog/.agent-done-${TASK_ID}"
  SIGNAL_CONTENT=$(cat "$SIGNAL_FILE" 2>/dev/null || echo "needs-human: signal file missing")
  rm -f "$SIGNAL_FILE"

  BRANCH="${TASK_BRANCHES[$TASK_ID]}"
  WORKTREE="${TASK_WORKTREES[$TASK_ID]}"
  TASK_VIEW=$(backlog task view "$TASK_ID" --plain)
  TITLE=$(echo "$TASK_VIEW" | grep -oP '(?<=Task TASK-\d+ - ).+' | head -1)

  cd "$REPO_ROOT"
  if [ "$SIGNAL_CONTENT" = "done" ]; then
    # Standard merge path (same as existing merge section)
    if git merge --no-ff "$BRANCH" -m "merge: ${TITLE} (${TASK_ID})"; then
      backlog task edit "$TASK_ID" \
        --status "Done" \
        --append-notes "Completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      git worktree remove "$WORKTREE"
      git branch -d "$BRANCH"
    else
      backlog task edit "$TASK_ID" \
        --status "Needs Human" \
        --append-notes "Merge conflict: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi
  else
    REASON=$(echo "$SIGNAL_CONTENT" | sed 's/^needs-human: //')
    backlog task edit "$TASK_ID" \
      --status "Needs Human" \
      --append-notes "Escalated: ${REASON}
To continue: answer in Implementation Notes, then set status → Ready."
  fi
done
\`\`\`
```

### DoD

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "agent-done-TASK" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "run_in_background" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "executePrompt\|buildExecutePrompt" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "waitForAgents" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "claimBatch" plugin/skills/loop-backlog/SKILL.md`

---

## Constraints

- 只修改 `plugin/skills/loop-backlog/SKILL.md`，不新建文件，不修改其他 skill
- `buildExecutePrompt` 输出须为自包含字符串，所有变量在调用时插值，不依赖 Agent 运行时外部 bash 变量
- task agent 的 `allowed-tools` 在 `executePrompt` 的 prompt 文本中须显式列出并排除 `Agent`（防止递归）
- `waitForAgents` 使用 `sleep 5` 轮询，不引入新的外部依赖
- 每个 Phase 的 DoD 第一项必须是 `bash scripts/validate-plugin.sh`
- `claimBatch` 以实际返回列表为准，不假设数量等于 `maxParallel`（另一 loop-backlog 实例可能并发 claim）
- 信号文件写入是 agent 的最后一个动作；主循环读取后立即删除

## Acceptance Gate

- [ ] `bash scripts/validate-plugin.sh`
- [ ] `grep -q "Agent" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "claimBatch" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "waitForAgents" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "agent-done-TASK" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "executePrompt\|buildExecutePrompt" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "max-parallel" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "run_in_background" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "maxParallel" plugin/skills/loop-backlog/SKILL.md`
- [ ] `grep -q "CFG_MAX_PARALLEL" plugin/skills/loop-backlog/SKILL.md`
