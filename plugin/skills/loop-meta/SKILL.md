---
name: loop-meta
description: "Autonomous L1 Meta-planner for the backlog Meta lane. Responds to meta-ready events, decomposes meta-tasks into backlog sub-tasks via decomposer subagent (using task-to-backlog / feature-to-backlog), and idempotently reconciles desired vs actual sub-task state. Sub-tasks are created in Backlog status for human promotion to Ready. Escalates on budget, noProgress, or diverging conditions."
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Monitor, Agent
contracts:
  - grep: "idempotentReconcile"
    target: self
  - grep: "decomposer"
    target: self
  - grep: "Needs Human"
    target: self
  - grep: "meta-ready"
    target: self
  - not-grep: "git worktree add"
    target: self
  - grep: "evaluator"
    target: self
  - grep: "replanner"
    target: self
  - grep: "draftMetaProposal"
    target: self
  - grep: "Meta-Proposal"
    target: self
  - grep: "gateHuman"
    target: self
  - grep: "reviewLoop"
    target: self
  - grep: "WIP_CAP"
    target: self
  - grep: "setReady"
    target: self
  - grep: "budget exhausted"
    target: self
  - grep: "### draftDecomposition"
    target: self
  - grep: "metaWorkerLoop"
    target: self
  - grep: "Monitor(persistent=true"
    target: self
  - grep: "loop-meta-stop"
    target: self
  - grep: "catchUpScan"
    target: self
  - grep: "tail -f -n 0"
    target: self
  - grep: "children already exist"
    target: self
  - grep: "setReady.*unconditional"
    target: self
  - grep: "### createSubTask"
    target: self
  - grep: "verifySubTaskDod"
    target: self
  - not-grep: "backlog task create --title \"\\$TITLE\""
    target: self
  - grep: "Definition of Done"
    target: scripts/verify-subtask-dod.sh
  - grep: "GRACE_POLLS"
    target: scripts/loop-backlog-daemon.js
  - grep: "wipAbsentCount"
    target: scripts/loop-backlog-daemon.js
  - grep: "computeWip"
    target: scripts/loop-backlog-daemon.js
  - grep: "wipNotified"
    target: scripts/loop-backlog-daemon.js
---

λ() → metaWorkerLoop()

## Spec

data MetaStatus = MetaProposal | MetaPlan | MetaActive | MetaDone | NeedsHuman

data Outcome = Proposed | Reconciled | Escalated Reason | Idle | Stopped

-- metaWorkerLoop: top-level event loop. Ensures the shared daemon is running,
-- processes existing meta-tasks on startup (catch-up), then blocks on Monitor
-- for meta-ready events. Runs in its own Claude Code session, independent of
-- loop-backlog. Stop via backlog/.loop-meta-stop or the shared backlog/.loop-stop.
metaWorkerLoop :: () → Outcome
metaWorkerLoop() = {
  _:  daemonBootstrap(),
  _:  catchUpScan(),
  loop:
    if (stopSentinel()): return Stopped,
    event: Monitor(persistent=true, command="tail -f -n 0 DAEMON_LOG"),
    | stopSentinel()                → return Stopped
    | event matches "meta-ready:*" → metaLoop(extractId(event)); loop
    | otherwise                    → loop   -- ignore task-ready: and noise
}

-- catchUpScan: on startup, dispatch all existing meta-tasks immediately.
-- Prevents tasks created before this session started from being missed.
catchUpScan :: () → ()
catchUpScan() =
  ∀status ∈ {MetaProposal, MetaPlan, MetaActive}:
    ∀id ∈ tasksWithStatus(status):
      if (¬stopSentinel()): metaLoop(id)

-- stopSentinel: true if either stop file exists.
stopSentinel :: () → Bool
stopSentinel() =
  exists("backlog/.loop-meta-stop") ∨ exists("backlog/.loop-stop")

-- Entry point: invoked when a meta-ready event is received for a meta-task.
metaLoop :: TaskId → Outcome
metaLoop(id) =
  | stopSentinel()         → Stopped
  | status(id) == MetaProposal → draftMetaProposal(id)
  | status(id) == MetaPlan    → draftDecomposition(id)
  | status(id) == MetaActive  → idempotentReconcile(id)
  | otherwise              → Idle

-- draftMetaProposal: intake path for Meta-Proposal tasks. Drafts a structured
-- proposal doc from the description, then enters reviewLoop (max 4 iterations)
-- to collect human feedback before the human advances to Meta-Plan.
draftMetaProposal :: TaskId → Outcome
draftMetaProposal(id) = {
  goal:  readField(id, "description"),
  doc:   Agent(prompt=proposalPrompt(goal)),    -- subagent writes proposal to notes
  _:     reviewLoop(id, doc, maxIter=4),
  return: Proposed
}

-- gateHuman: append a note requesting human action and halt.
-- Never auto-advances status — the human must set the next status.
-- Returns after appending; control resumes only on the next meta-ready event.
gateHuman :: (TaskId, Message) → ()
gateHuman(id, msg) = {
  appendNote(id, msg)
  -- loop-meta halts here; daemon will emit meta-ready again on next poll
}

-- reviewLoop: iterative human-review gate for Meta-Proposal tasks.
-- Calls gateHuman each iteration. If the human advances status beyond
-- Meta-Proposal before maxIter is reached, the next meta-ready event will
-- dispatch to draftDecomposition or idempotentReconcile — reviewLoop is
-- not re-entered. If maxIter is exhausted without approval, escalates.
reviewLoop :: (TaskId, Doc, Int) → Outcome
reviewLoop(id, doc, maxIter) = {
  iter: countNotes(id, "reviewLoop:"),

  if (iter >= maxIter):
    return: escalate(id, "reviewLoop exhausted: " + maxIter
                       + " iterations without human approval"),

  gateHuman(id, "reviewLoop: iteration " + (iter+1) + "/" + maxIter
               + " — review proposal and set status → Meta-Plan to approve,"
               + " or add feedback note and leave status unchanged for revision."),
  appendNote(id, "reviewLoop: iteration " + str(iter+1) + " of " + str(maxIter)),
  return: Proposed
}

-- draftDecomposition: for Meta-Plan tasks, call decomposer subagent to produce
-- the canonical desired sub-task list, create each as a Backlog child task,
-- then gate for human review before activating (status stays Meta-Plan until
-- human sets Meta-Active).
draftDecomposition :: TaskId → Outcome
draftDecomposition(id) = {
  -- Idempotency guard: skip creation if children already exist
  if (¬empty(listChildren(id))):
    appendNote(id, "draftDecomposition: children already exist — skipping creation"),
    return: Proposed,

  plan:  readField(id, "implementationPlan"),
  subs:  decomposer(id, plan),
  _:     ∀t ∈ subs: createSubTask(id, t),   -- create all children in Backlog status
  _:     appendNote(id, "Decomposition complete: " + length(subs) + " sub-tasks in Backlog. "
                     + "Review sub-tasks, then set status → Meta-Active to start reconcile loop."),
  return: Proposed
}

-- idempotentReconcile: desired ⊖ actual diff — only creates sub-tasks that do
-- not already exist. Running reconcile twice on the same meta-task produces the
-- same result as running it once (no duplicate sub-tasks).
idempotentReconcile :: TaskId → Outcome
idempotentReconcile(id) = {
  desired: decomposer(id, readField(id, "implementationPlan")),
  actual:  listChildren(id),
  gap:     desired ⊖ actual,    -- set diff by normalised title

  if (empty(gap)):
    appendNote(id, "idempotentReconcile: no gap — all " + length(desired) + " sub-tasks present"),
    return: Reconciled,

  if (noProgress(id)):
    return: escalate(id, "noProgress: sub-tasks have been in Backlog too long without promotion"),

  if (diverging(id)):
    return: escalate(id, "diverging: actual sub-task set has grown beyond desired — manual review needed"),

  if (budgetExceeded(id)):
    return: escalate(id, "budget exhausted: reconcile loop exceeded cycle limit"),

  ∀t ∈ gap: createSubTask(id, t),
  appendNote(id, "idempotentReconcile: created " + length(gap) + " sub-task(s)"),

  -- Auto-schedule: promote Backlog children up to WIP_CAP (Meta-Active only)
  setReady(id, filter(c → status(c) == Backlog, listChildren(id))),
  return: Reconciled
}

-- decomposer: subagent that reads meta-plan text and returns a canonical list
-- of desired sub-tasks. Each sub-task is produced via task-to-backlog or
-- feature-to-backlog to ensure shell-gate DoD is present. Returns a list of
-- SubTaskSpec records (title, description, dodCommands).
decomposer :: (TaskId, PlanText) → [SubTaskSpec]
decomposer(id, plan) =
  Agent(
    prompt = decomposerPrompt(id, plan),
    schema = SubTaskListSchema
  )

-- listChildren: scan backlog for tasks whose notes contain "parentTask: <id>".
listChildren :: TaskId → [SubTaskSpec]
listChildren(id) =
  filter(t → hasNote(t, "parentTask: " + id), allTasks())

-- createSubTask: create a new backlog task in Backlog status with parentTask link.
-- MUST delegate to task-to-backlog (or feature-to-backlog) so the child carries a
-- shell-gate Definition of Done. A child created by a bare `backlog task create
-- --title` (no DoD) is FORBIDDEN: loop-backlog cannot verifyDod it, so it can be
-- rubber-stamped Done without the work being done (TASK-93 post-mortem, root cause R1).
-- After creation, verifySubTaskDod asserts the DoD shell-gate is present; if absent,
-- the child is reset and the meta-task escalates rather than proceeding with an
-- unverifiable sub-task.
createSubTask :: (TaskId, SubTaskSpec) → ()
createSubTask(parent, spec) = {
  child: invoke("task-to-backlog", spec),   -- produces ## Definition of Done with ≥1 shell-gate
  appendNote(child, "parentTask: " + parent),
  setParentTaskId(child, parent),           -- frontmatter parent_task_id for daemon/listChildren
  setStatus(child, "Backlog"),
  assert: hasDod(child)                      -- enforced by verify-subtask-dod.sh — no DoD-less children
}

-- verifySubTaskDod: gate run after decomposition/reconcile. Asserts every child of
-- the meta-task carries a Definition of Done shell-gate (scripts/verify-subtask-dod.sh).
-- Exit 1 (DoD-less child found) → escalate; never allow a rubber-stampable child to
-- enter the Ready lane.
verifySubTaskDod :: TaskId → Bool
verifySubTaskDod(id) =
  shell("bash scripts/verify-subtask-dod.sh " + id) == 0

-- escalation conditions
noProgress :: TaskId → Bool
noProgress(id) =
  allChildrenInBacklogForDays(id, threshold=7)

diverging :: TaskId → Bool
diverging(id) =
  length(listChildren(id)) > 2 * length(desired(id))

budgetExceeded :: TaskId → Bool
budgetExceeded(id) =
  reconcileAttempts(id) > 5

escalate :: (TaskId, Reason) → Outcome
escalate(id, r) = {
  setStatus(id, "Needs Human"),
  appendNote(id, "Escalated: " + r
               + "\nTo continue: answer in notes and set status → Meta-Active."),
  return: Escalated(r)
}


-- WIP_CAP: maximum number of sub-tasks in Ready or In Progress at any time.
-- Conservative initial value; adjustable after validation data accumulates.
WIP_CAP :: Int
WIP_CAP = 2

-- setReady: promote Backlog sub-tasks to Ready while wip(id) < WIP_CAP.
-- Called inside idempotentReconcile when Meta-Active and human gate has passed.
-- Never auto-schedules from Meta-Plan — that gate is preserved unconditionally.
setReady :: (TaskId, [SubTaskSpec]) → ()
setReady(parent, backlogChildren) = {
  ∀t ∈ backlogChildren:
    if (wip(parent) < WIP_CAP):
      setStatus(t, "Ready"),
      appendNote(parent, "setReady: promoted " + t.title)
}

-- wip: count of children currently in Ready or In Progress status.
wip :: TaskId → Int
wip(id) =
  length(filter(c → status(c) ∈ {Ready, InProgress}, listChildren(id)))


-- evaluator: slice-aggregate quality assessor. Takes a meta-task and its Done
-- children; produces a Met/NotMet verdict from three independent slices.
-- Each slice MUST carry data_source: measured — no estimated inputs accepted.
-- Slice types:
--   layer25_oracle : run Class A/B oracle from experiments/skill-quality/artifacts/
--   dod_aggregate  : check all child DoD shell-gate pass counts from task notes
--   trace_replay   : replay execution log patterns against acceptance specs
evaluator :: (TaskId, [TaskId]) → EvalResult
evaluator(metaId, doneChildren) = {
  oracle_slice : runLayer25Oracle(doneChildren),    -- data_source: measured
  dod_slice    : aggregateDodResults(doneChildren), -- data_source: measured
  trace_slice  : replayTraces(metaId),              -- data_source: measured

  if (any(s → s.data_source ≠ "measured", [oracle_slice, dod_slice, trace_slice])):
    raise InvalidEvidenceError("estimated slices not permitted in evaluator"),

  verdict: if (all(slicePassed, [oracle_slice, dod_slice, trace_slice])): Met
           else: NotMet(reasons=[s.reason | s ← slices, ¬slicePassed(s)]),

  _: appendNote(metaId, "evaluator: " + verdict.label
               + " | oracle=" + oracle_slice.label
               + " | dod=" + dod_slice.label
               + " | trace=" + trace_slice.label
               + " | data_source: measured"),
  return: verdict
}

-- replanner: root-cause diagnostician. Invoked only when evaluator returns NotMet.
-- Classifies root cause and rewrites the meta-plan path to resolve it.
-- MUST NOT modify acceptance criteria — only the path to meet them.
-- Root cause taxonomy: impl | sub-plan | meta-plan | harness | infeasible
replanner :: (TaskId, NotMet) → ReplanResult
replanner(metaId, notMet) = {
  evidence: readNotes(metaId) ++ notMet.reasons,
  rootCause: classify(evidence),   -- impl | sub-plan | meta-plan | harness | infeasible

  if (rootCause == infeasible):
    return: escalate(metaId, "infeasible: acceptance criteria cannot be met by any known path"),

  updatedPlan: patchPath(readField(metaId, "implementationPlan"), rootCause, evidence),
  _: appendNote(metaId, "replan: " + rootCause + " — " + summarise(evidence)),
  _: updateField(metaId, "implementationPlan", updatedPlan),
  return: Replanned(rootCause, updatedPlan)
}

-- evaluateAndReplan: integrate evaluate→replan branch into reconcile.
-- Triggered only when Meta-Active and at least one child is Done.
evaluateAndReplan :: TaskId → ()
evaluateAndReplan(metaId) = {
  doneChildren: filter(c → status(c) == Done, listChildren(metaId)),
  if (empty(doneChildren)): return,

  result: evaluator(metaId, doneChildren),
  if (result == Met): return,

  -- NotMet: diagnose and replan
  replanResult: replanner(metaId, result),
  if (replanResult == Escalated): return   -- handled by escalate()
  -- otherwise: idempotentReconcile will pick up the patched plan on next cycle
}

## Implementation

### metaLoop

```bash
# Read meta-task status and dispatch
TASK_VIEW=$(backlog task view "$META_TASK_ID" --plain)
META_STATUS=$(echo "$TASK_VIEW" | grep -oP '(?i)(?<=status: )\S.*' | head -1 | xargs)

case "$META_STATUS" in
  "Meta-Proposal")
    # draftProposal: generate proposal doc, append note, stay in Meta-Proposal
    ;;
  "Meta-Plan")
    # draftDecomposition: call decomposer, create sub-tasks in Backlog
    ;;
  "Meta-Active")
    # idempotentReconcile: diff desired vs actual, fill gap
    ;;
  *)
    echo "metaLoop: status '$META_STATUS' requires no action"
    exit 0
    ;;
esac
```

### metaWorkerLoop

Top-level event loop. Call once per Claude Code session — runs until a stop
sentinel is written. Stop loop-meta only: `touch backlog/.loop-meta-stop`.
Stop both workers: `touch backlog/.loop-stop`.

```bash
metaWorkerLoop() {
  BACKLOG_DIR="${REPO_ROOT}/backlog"
  DAEMON_LOG="${BACKLOG_DIR}/.daemon.log"
  STOP_FILE="${BACKLOG_DIR}/.loop-stop"
  META_STOP_FILE="${BACKLOG_DIR}/.loop-meta-stop"

  # 1. Ensure the shared daemon is running (idempotent — safe if loop-backlog already started it)
  daemonBootstrap

  # 2. Catch-up: process meta-tasks that existed before this session started
  catchUpScan

  # 3. Stop check before entering event loop
  [ -f "$STOP_FILE" ] || [ -f "$META_STOP_FILE" ] && return 0

  # 4. Block on daemon log; dispatch meta-ready events, ignore everything else
  Monitor(persistent=true, command="tail -f -n 0 \"$DAEMON_LOG\"")
  # -n 0: start from EOF, only follow NEW lines — prevents replaying history on restart
  # For each output line from Monitor:
  #   - Matches meta-ready:TASK-N  → metaLoop "$TASK_ID"
  #   - Stop sentinel present      → exit 0
  #   - Otherwise (task-ready:*, noise) → ignore, continue loop
}
```

### catchUpScan

On startup, processes any meta-tasks already in the backlog before the Monitor
starts. Prevents tasks created before this session from being missed.

```bash
catchUpScan() {
  BACKLOG_DIR="${REPO_ROOT}/backlog"
  STOP_FILE="${BACKLOG_DIR}/.loop-stop"
  META_STOP_FILE="${BACKLOG_DIR}/.loop-meta-stop"

  for STATUS in "Meta-Proposal" "Meta-Plan" "Meta-Active"; do
    backlog task list --status "$STATUS" --plain \
      | grep -oP 'TASK-\d+' \
      | while read -r TID; do
          [ -f "$STOP_FILE" ] || [ -f "$META_STOP_FILE" ] && return 0
          metaLoop "$TID"
        done
  done
}
```

### draftDecomposition

Runs the decomposer subagent, then creates each sub-task as a Backlog child task
with a `parentTask:` note linking it back to the meta-task. Finally appends a
human-review gate note; status stays Meta-Plan until the human sets Meta-Active.

```bash
draftDecomposition() {
  local META_ID="$1"
  local STOP_FILE="${REPO_ROOT}/backlog/.loop-stop"
  local META_STOP_FILE="${REPO_ROOT}/backlog/.loop-meta-stop"

  # 0. Idempotency guard: skip if children already exist
  EXISTING=$(backlog task list --plain | grep -oP 'TASK-\d+' | while read -r TID; do
    backlog task view "$TID" --plain | grep -q "parentTask: ${META_ID}" && echo "$TID"
  done | wc -l)
  if [ "$EXISTING" -gt 0 ]; then
    backlog task edit "$META_ID" --append-notes \
      "draftDecomposition: children already exist (${EXISTING}) — skipping creation"
    return 0
  fi

  # 1. Run decomposer — returns one sub-task title per line
  TITLES=$(callDecomposer "$META_ID")

  if [ -z "$(echo "$TITLES" | xargs)" ]; then
    backlog task edit "$META_ID" --append-notes \
      "draftDecomposition: decomposer returned empty list — no sub-tasks created"
    return 1
  fi

  # 2. Create each sub-task via createSubTask (task-to-backlog → shell-gate DoD)
  COUNT=0
  while IFS= read -r TITLE; do
    [ -z "$TITLE" ] && continue
    [ -f "$STOP_FILE" ] || [ -f "$META_STOP_FILE" ] && return 0
    NEW_ID=$(createSubTask "$META_ID" "$TITLE")
    [ -n "$NEW_ID" ] && COUNT=$((COUNT + 1))
  done <<< "$TITLES"

  # 3. DoD gate: every child MUST carry a shell-gate DoD (R1 — no rubber-stampable children)
  if ! verifySubTaskDod "$META_ID"; then
    backlog task edit "$META_ID" --status "Needs Human" --append-notes \
      "Escalated: draftDecomposition produced DoD-less sub-task(s). \
See verify-subtask-dod.sh output. Fix sub-task DoD before setting Meta-Active."
    return 1
  fi

  # 4. Human-review gate note — status stays Meta-Plan
  backlog task edit "$META_ID" --append-notes \
    "Decomposition complete: ${COUNT} sub-tasks in Backlog (all carry shell-gate DoD). Review sub-tasks, then set status → Meta-Active to start reconcile loop."
}
```

### createSubTask

Creates one child sub-task by invoking the `task-to-backlog` skill via an Agent, so the
child ends in `Backlog` status **with a full Implementation Plan and `## Definition of Done`
shell-gate**. A bare `backlog task create --title` (no DoD, no plan) is forbidden here —
it produces an unverifiable, content-free child that loop-backlog can rubber-stamp Done
(TASK-93 root cause R1). The child is linked to its parent both by a `parentTask:` note
and by the `parent_task_id:` frontmatter field that the daemon and `listChildren` rely on.

The agent prompt must supply:
- `TITLE` — the sub-task title
- `DESCRIPTION` — full context: what this sub-task is, why it exists, what it must achieve
- `PARENT_CONTEXT` — the parent meta-task's implementation plan excerpt relevant to this sub-task

This three-field prompt gives task-to-backlog enough context to draft a high-quality
multi-phase plan with specific shell-gate DoD items, without needing human interaction.

```bash
createSubTask() {
  local META_ID="$1"
  local TITLE="$2"
  local DESCRIPTION="$3"       # full context for this sub-task
  local PARENT_CONTEXT="$4"    # relevant excerpt from the meta-task's implementation plan

  # Invoke task-to-backlog via Agent — produces Backlog task with plan + shell-gate DoD.
  # FORBIDDEN: a bare title-only create with no plan/DoD (rubber-stampable child).
  NEW_ID=$(Agent(run_in_background=false, prompt="$(cat <<SUBTASK_EOF
You are creating a backlog sub-task for the meta-task ${META_ID}.

Use the Skill tool to invoke /task-to-backlog with the description below as the argument.
task-to-backlog will create a properly-formed Backlog task with a multi-phase
Implementation Plan and shell-verifiable DoD items. Do not skip the skill.

After task-to-backlog completes:
  1. Append a note line exactly: parentTask: ${META_ID}
  2. Confirm the YAML frontmatter field parent_task_id: ${META_ID} is set
     (task-to-backlog sets this if you pass --parent, otherwise edit it manually)
Output ONLY the created task id (e.g. TASK-123) as the last line.

--- Sub-task description ---
Title: ${TITLE}

${DESCRIPTION}

--- Parent meta-task context ---
${PARENT_CONTEXT}
SUBTASK_EOF
  )" | grep -oP 'TASK-\d+(\.\d+)*' | tail -1)

  if [ -z "$NEW_ID" ]; then
    backlog task edit "$META_ID" --append-notes "createSubTask: FAILED to create child for '${TITLE}'"
    return 1
  fi
  echo "$NEW_ID"
}
```

### verifySubTaskDod

Runs `scripts/verify-subtask-dod.sh <META_ID>` — the R1 guard. Exit 0 iff every
child of the meta-task carries a `## Definition of Done` with ≥1 checkbox shell-gate.
Both `draftDecomposition` and `idempotentReconcile` call this before promoting any
child to Ready, so a DoD-less (rubber-stampable) child can never enter the work lane.

```bash
verifySubTaskDod() {
  local META_ID="$1"
  bash scripts/verify-subtask-dod.sh "$META_ID"
}
```

### idempotentReconcile

```bash
idempotentReconcile() {
  local META_ID="$1"

  # 1. Get desired sub-tasks from decomposer (list of titles, one per line)
  DESIRED=$(callDecomposer "$META_ID")

  # 2. Get actual sub-tasks: scan for children with parent_task_id: META_ID
  ACTUAL=$(backlog task list --plain \
    | grep -oP 'TASK-\d+(\.\d+)*' \
    | while read TID; do
        NOTE=$(backlog task view "$TID" --plain)
        echo "$NOTE" | grep -qiP "parent.task.id:\s*${META_ID}" && \
          echo "$NOTE" | grep -oP '(?<=Task TASK-[\d.]+ - ).+' | head -1
      done)

  # 3. Compute gap: desired titles not in actual
  GAP=""
  while IFS= read -r TITLE; do
    [ -z "$TITLE" ] && continue
    if ! echo "$ACTUAL" | grep -qxF "$TITLE"; then
      GAP="${GAP}${TITLE}\n"
    fi
  done <<< "$DESIRED"

  if [ -z "$(echo -e "$GAP" | xargs)" ]; then
    backlog task edit "$META_ID" --append-notes \
      "idempotentReconcile: no gap — all sub-tasks present"
  else
    # 4. Create missing sub-tasks via createSubTask (task-to-backlog → shell-gate DoD)
    COUNT=0
    while IFS= read -r TITLE; do
      [ -z "$TITLE" ] && continue
      NEW_ID=$(createSubTask "$META_ID" "$TITLE")
      [ -n "$NEW_ID" ] && COUNT=$((COUNT + 1))
    done <<< "$(echo -e "$GAP")"
    backlog task edit "$META_ID" --append-notes \
      "idempotentReconcile: created ${COUNT} sub-task(s)"
  fi

  # R1 DoD gate: refuse to promote a DoD-less (rubber-stampable) child to Ready.
  # Must pass before setReady — a child with no shell-gate cannot be verified by loop-backlog.
  if ! verifySubTaskDod "$META_ID"; then
    backlog task edit "$META_ID" --status "Needs Human" --append-notes \
      "Escalated: idempotentReconcile found DoD-less sub-task(s) — see verify-subtask-dod.sh. \
Not promoting to Ready until every child carries a shell-gate DoD."
    return 1
  fi

  # Fix-A: always call setReady — unconditional; must compute fresh wip via
  # listChildren, NEVER assume wip from prior context.
  setReady "$META_ID"  # unconditional — promotes Backlog→Ready up to WIP_CAP
}
```

### decomposer

The decomposer subagent reads the meta-task's Implementation Plan and returns a
newline-separated list of sub-task titles. Each title corresponds to one leaf
deliverable that `task-to-backlog` or `feature-to-backlog` will turn into a
fully-specified backlog task with shell-gate DoD.

```bash
callDecomposer() {
  local META_ID="$1"
  local PLAN
  PLAN=$(backlog task view "$META_ID" --plain \
    | awk '/^Implementation Plan:/,/^[A-Z]/' | tail -n +2)

  # Subagent prompt instructs the agent to output one sub-task title per line
  Agent(run_in_background=false, prompt="$(cat <<DECOMP_EOF
You are a decomposer agent. Read the meta-plan below and output a newline-separated
list of sub-task titles. Each title should be a self-contained unit of work
suitable for task-to-backlog or feature-to-backlog. Output ONLY the titles,
one per line, no numbering, no explanation.

Meta-task: ${META_ID}
Plan:
${PLAN}
DECOMP_EOF
  )")
}
```

### draftMetaProposal

Intake entry-point: when `loop-meta` receives a bare macro-goal (via `/loop-meta <goal>`
or finds a task already at `Meta-Proposal` status), it calls `draftMetaProposal` to:

1. Create a `Meta-Proposal`-status meta-task if one does not yet exist.
2. Call the `proposalPrompt` subagent to produce a structured proposal document containing:
   - **Background** (3-8 lines, WHY this goal matters)
   - **Frozen Acceptance Criteria** (numbered, shell-verifiable where possible)
   - **Sub-Goal Tree** (bullet hierarchy, max 2 levels, one line per sub-goal)
3. Write the proposal document to the meta-task's Implementation Plan field.
4. Enter `reviewLoop` (max 4 iterations) for human-feedback iteration.

```bash
draftMetaProposal() {
  local META_ID="$1"

  GOAL=$(backlog task view "$META_ID" --plain | grep -oP '(?<=Description: ).+' | head -1)

  # proposalPrompt: produces Background + Frozen Acceptance Criteria + Sub-Goal Tree
  DOC=$(Agent(run_in_background=false, prompt="$(cat <<PROPOSAL_EOF
You are a meta-proposal drafter. Given the macro goal below, produce a structured
Meta-Proposal document with exactly three sections:

## Background
(3-8 lines explaining WHY this goal matters, the problem it solves, and context)

## Frozen Acceptance Criteria
(numbered list; each criterion must be a concrete, verifiable outcome;
use shell-verifiable conditions where possible, e.g.: bash <command> exits 0)

## Sub-Goal Tree
(bullet hierarchy, max 2 levels; each leaf is a self-contained unit of work)

Macro goal: ${GOAL}

Output ONLY the three-section document. No preamble, no explanation.
PROPOSAL_EOF
  )"))

  # Write proposal to Implementation Plan field
  backlog task edit "$META_ID" --plan "$DOC"

  # Intake entry-point note for traceability
  backlog task edit "$META_ID" --append-notes     "draftMetaProposal: proposal drafted for goal: ${GOAL}"

  reviewLoop "$META_ID" "$DOC" 4
}
```

### gateHuman

`gateHuman` is a **soft halt**: it appends a note to the meta-task and then exits.
It never sets the status automatically — the human must advance the status themselves.
After exit, the daemon re-emits `meta-ready:<id>` on its next poll cycle, which
re-enters `metaLoop`. If the status is still `Meta-Proposal`, the reconcile branch
calls `reviewLoop` again (incrementing the iteration counter). When the human sets
the status to `Meta-Plan`, `metaLoop` dispatches to `draftDecomposition` instead —
this is the **approval path** that exits the intake loop and begins formal planning.

```bash
gateHuman() {
  local META_ID="$1"
  local MSG="$2"
  # Soft halt: append note, then exit — do NOT change status
  backlog task edit "$META_ID" --append-notes "$MSG"
  # loop-meta process exits here; daemon re-emits meta-ready on next poll cycle
  exit 0
}
```

### reviewLoop

`reviewLoop` drives the iterative human-feedback gate for `Meta-Proposal` intake:

- **Iteration counting**: reads `grep -c "reviewLoop:"` from task notes. Each call
  appends one `reviewLoop:` note line, so the count monotonically increases.
- **Cap**: MAX_ITER = 4 (matches `task-to-backlog` and `feature-to-backlog`). On
  exhaustion, status is set to `Needs Human` and the loop exits permanently.
- **Human approval path**: the human sets `status → Meta-Plan`. The daemon emits
  `meta-ready`, `metaLoop` dispatches to `draftDecomposition` (not `draftMetaProposal`),
  and the intake reviewLoop is never re-entered. This is the intended approval path.
- **Revision path**: the human adds a feedback note but leaves status at `Meta-Proposal`.
  The daemon re-emits `meta-ready`, `metaLoop` calls `draftMetaProposal` again
  (which calls `reviewLoop`), the ITER count has already incremented, so the next
  iteration message is shown automatically.

```bash
reviewLoop() {
  local META_ID="$1"
  local DOC="$2"
  local MAX_ITER="$3"

  # Iteration counting: each reviewLoop call appends one "reviewLoop:" note line
  ITER=$(backlog task view "$META_ID" --plain | grep -c "reviewLoop:" || true)

  if [ "$ITER" -ge "$MAX_ITER" ]; then
    backlog task edit "$META_ID" \
      --status "Needs Human" \
      --append-notes "Escalated: reviewLoop exhausted — ${MAX_ITER} iterations without human approval"
    return 1
  fi

  ITER_NEXT=$((ITER + 1))

  # Soft halt via gateHuman — re-enters on next meta-ready event
  gateHuman "$META_ID" \
    "reviewLoop: iteration ${ITER_NEXT}/${MAX_ITER} — review proposal and set status → Meta-Plan to approve (approval path), or add feedback note and leave status unchanged for revision."

  # Note written before gateHuman exits the process
  backlog task edit "$META_ID" --append-notes \
    "reviewLoop: iteration ${ITER_NEXT} of ${MAX_ITER}"
}
```

### setReady (auto-schedule)

```bash
setReady() {
  local META_ID="$1"

  # Count current WIP (Ready + In Progress children)
  WIP=$(backlog task list --plain     | grep -oP 'TASK-\d+'     | while read TID; do
        NOTE=$(backlog task view "$TID" --plain)
        if echo "$NOTE" | grep -q "parentTask: ${META_ID}"; then
          STATUS=$(echo "$NOTE" | grep -oP '(?<=status: )\S.*' | head -1 | xargs)
          case "$STATUS" in Ready|"In Progress") echo "$TID" ;; esac
        fi
      done | wc -l)

  if [ "$WIP" -ge "$WIP_CAP" ]; then
    return 0
  fi

  # Promote Backlog children up to WIP_CAP
  backlog task list --plain     | grep -oP 'TASK-\d+'     | while read TID; do
        NOTE=$(backlog task view "$TID" --plain)
        if echo "$NOTE" | grep -q "parentTask: ${META_ID}"; then
          STATUS=$(echo "$NOTE" | grep -oP '(?<=status: )\S.*' | head -1 | xargs)
          if [ "$STATUS" = "Backlog" ]; then
            CURRENT_WIP=$(backlog task list --plain | grep -oP 'TASK-\d+' | while read T; do
              N=$(backlog task view "$T" --plain)
              echo "$N" | grep -q "parentTask: ${META_ID}" &&                 echo "$N" | grep -qP 'status: (Ready|In Progress)' && echo "$T"
            done | wc -l)
            if [ "$CURRENT_WIP" -lt "$WIP_CAP" ]; then
              TITLE=$(echo "$NOTE" | grep -oP '(?<=Task TASK-\d+ - ).+' | head -1)
              backlog task edit "$TID" --status "Ready"
              backlog task edit "$META_ID" --append-notes "setReady: promoted ${TITLE}"
            fi
          fi
        fi
      done
}
```

### escalation checks

```bash
checkEscalation() {
  local META_ID="$1"

  # budget: too many reconcile attempts
  ATTEMPTS=$(backlog task view "$META_ID" --plain \
    | grep -c "idempotentReconcile:" || true)
  if [ "$ATTEMPTS" -gt 5 ]; then
    backlog task edit "$META_ID" \
      --status "Needs Human" \
      --append-notes "Escalated: budget — reconcile loop exceeded 5 attempts"
    return 1
  fi

  # noProgress: all children stuck in Backlog for ≥7 days
  FIRST_RECONCILE_DATE=$(backlog task view "$META_ID" --plain \
    | grep 'idempotentReconcile:' | head -1 \
    | grep -oP '\d{4}-\d{2}-\d{2}' | head -1 || true)
  if [ -n "$FIRST_RECONCILE_DATE" ]; then
    DAYS_SINCE=$(( ( $(date -u +%s) - $(date -u -d "$FIRST_RECONCILE_DATE" +%s) ) / 86400 ))
    ALL_IN_BACKLOG=true
    while IFS= read -r TID; do
      STATUS=$(backlog task view "$TID" --plain \
        | grep -oP '(?<=status: )\S.*' | head -1 | xargs)
      [ "$STATUS" != "Backlog" ] && ALL_IN_BACKLOG=false && break
    done < <(backlog task list --plain | grep -oP 'TASK-\d+' | while read T; do
      backlog task view "$T" --plain | grep -q "parentTask: ${META_ID}" && echo "$T"
    done)
    if $ALL_IN_BACKLOG && [ "$DAYS_SINCE" -ge 7 ]; then
      backlog task edit "$META_ID" \
        --status "Needs Human" \
        --append-notes "noProgress: all children in Backlog for ${DAYS_SINCE} days (threshold: 7)"
      return 1
    fi
  fi

  # diverging: actual child count > 2× desired (decomposer line count)
  DESIRED_COUNT=$(backlog task view "$META_ID" --plain \
    | awk '/^Implementation Plan:/,/^[A-Z][a-z]/' \
    | grep -c '^\s*[-*]' || true)
  ACTUAL_COUNT=$(backlog task list --plain | grep -oP 'TASK-\d+' | while read T; do
    backlog task view "$T" --plain | grep -q "parentTask: ${META_ID}" && echo "$T"
  done | wc -l)
  if [ "$DESIRED_COUNT" -gt 0 ] && [ "$ACTUAL_COUNT" -gt $((DESIRED_COUNT * 2)) ]; then
    backlog task edit "$META_ID" \
      --status "Needs Human" \
      --append-notes "diverging: actual=${ACTUAL_COUNT} > 2×desired=${DESIRED_COUNT} — manual review needed"
    return 1
  fi

  return 0
}
```
