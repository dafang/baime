---
id: TASK-198
title: loop-backlog 前缀无关 task ID 提取：移除硬编码 TASK-，靠路径约束+位置/字段锚定支持任意前缀项目
status: 'Basic: Done'
assignee: []
created_date: '2026-06-25 08:43'
updated_date: '2026-06-25 09:43'
labels:
  - 'kind:basic'
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 问题

loop-backlog 在 basic-daemon.js 的 parseTaskId 与 SKILL.md 的 ~11 处 grep 中硬编码了 `TASK-` 任务 ID 前缀。backlog CLI 的前缀可配置（config.yml 的 task_prefix）：baime=task → TASK-N，Backlog.md=back → back-NNN（BACK-511）。

后果：parseTaskId("BACK-511 ...") 返回 null → daemon 的 scanIds 跳过所有 back-* 文件 → daemon 对该项目永远发射 0 事件 → BACK-511 从未被处理。这是 Backlog.md 卡死的真正根因，与 Monitor 生命周期/heartbeat/pulse（TASK-196/197）正交。

## 方案：前缀无关提取（不读 config、不串前缀）

不靠"匹配前缀"识别 task —— `backlog/tasks/*.md` 路径已保证每个文件都是 task。只需提取 ID，而 ID 恒为文件名第一个 token（`<prefix>-<n> - 标题.md`）。CLI 文本输出靠位置/字段锚定而非前缀，避免标题里 ID 形噪音（如 UTF-8、JIRA-123）被误吞。

- basic-daemon.js：parseTaskId 改为提取文件名首 token（`^([A-Za-z][A-Za-z0-9]*-\d+(\.\d+)*)` 大写归一），不再需要前缀参数；scanIds/predicate 不变。
- SKILL.md ~11 处去硬编码：
  - extractId：从事件行 `basic-ready:BACK-511` 剥冒号前缀（`${EVENT#*:}`），无需正则。
  - claimBatch/reap 的 `task list --plain | grep`：锚定缩进行首 ` - ` 之前的 token（`^\s+\K[A-Za-z][A-Za-z0-9]*-\d+(\.\d+)*(?= - )`），排除标题噪音。
  - parent 提取：字段锚定 `(?<=parent_task_id: )\S+`。
  - title 提取：`^Task \S+ - \K.+` 用 ID 做地标取标题。
  - childrenOf/epic parent：用已知 epic ID 字符串，无需解析。

## 为什么不读 config.yml 配前缀
路径约束 + 位置/字段锚定即可唯一锁定真 ID，比"读配置串精确前缀到 11 处"更简单、零配置、对任意项目都对，且顺手消除现有 TASK-\d+ 硬编码本就有的标题误吞隐患。号码只作为唯一句柄的一部分被原样传递，其数值从不被解释。

## 影响文件
- plugin/scripts/basic-daemon.js
- plugin/skills/loop-backlog/SKILL.md
- scripts/basic-daemon.test.js（前缀无关 parseTaskId 多前缀单测 + 标题噪音负例）

## 不做
- 不读 config.yml、不加 --task-prefix 参数
- 不改 Monitor 生命周期/pulse/flock
- baime 自身（task- 前缀）零回归
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
# Proposal: loop-backlog 前缀无关 task ID 提取

## Background

loop-backlog 在两个层面硬编码了 `TASK-` 前缀：(1) `plugin/scripts/basic-daemon.js` 的 `parseTaskId()`（L45-52）仅匹配 `^TASK-\d+` 与 `\bTASK-\d+\b`；(2) `plugin/skills/loop-backlog/SKILL.md` 约 11 处功能性 grep 把 `TASK-` 写死。Backlog.md 使用 `task_prefix: "back"`，文件名形如 `back-511 - title.md`，`parseTaskId` 返回 null → `scanIds` 跳过 → daemon 对该任务发出零事件，这是 Backlog.md / BACK-511 卡死的真正根因（与 TASK-196/197 的 Monitor 生命周期 / pulse 问题正交）。

关键观察：`backlog/tasks/*.md` 路径本身已经保证每个文件都是 task —— 前缀不是用来「判定是否为 task」，仅用于「提取 ID」。而 ID 恒为文件名第一个空白分隔 token（`<prefix>-<n> - title.md`）。因此采用**前缀无关**方案：用通用 ID 形状抓取首 token，CLI 文本输出则按**位置/字段锚定**而非按前缀锚定。这同时消除了一个潜在缺陷：标题中出现 ID 形状 token（如 UTF-8 标题里的 `JIRA-123`）会被旧的 `grep -oP 'TASK-\d+'` 误抓 —— 位置锚定从结构上排除标题噪声。

不读 config.yml、不加 `--task-prefix` 参数、不在代码里传递配置前缀。

## Goals

1. `parseTaskId('back-511 - x.md')` → `BACK-511`，无前缀参数、不读配置。
2. `parseTaskId('task-3 - x.md')` → `TASK-3`，`parseTaskId('TASK-10 - t.md')` → `TASK-10`，`parseTaskId('back-217.02 - x.md')` → `BACK-217.02`（小数子任务保留），`parseTaskId('README.md')` → `null`（baime 零回归 + 子任务保留）。
3. claimBatch / reap 的 list 解析不会从标题里抓到 ID 形状 token；且能覆盖 `--plain` 输出中带 `[HIGH]`/`[MEDIUM]` 优先级前缀的行。
4. extractId 从 `basic-ready:BACK-511` 正确得到 `BACK-511`（任意前缀）。
5. parent / 标题提取前缀无关：`Parent`/`parent_task_id` 字段值与 `Task <ID> - <title>` 标题落地点不依赖具体前缀。
6. 不读 config.yml、不新增 `--task-prefix` 参数、不在代码中线程化配置前缀。
7. daemon 与 plugin 校验全绿（`node scripts/basic-daemon.test.js`、`bash scripts/validate-plugin.sh`）。

## Proposed Approach

### A. basic-daemon.js `parseTaskId(filename)`

文件名首 token 即 ID（路径已保证 task-ness）。两条旧正则合并为一条首 token 匹配：

```js
function parseTaskId(filename) {
  const base = path.basename(filename, path.extname(filename)).toUpperCase();
  const first = base.split(/\s+/)[0];
  const m = first.match(/^([A-Za-z][A-Za-z0-9]*-\d+(?:\.\d+)*)$/);
  return m ? m[1] : null;
}
```

- 通用 ID 形状 `^[A-Za-z][A-Za-z0-9]*-\d+(\.\d+)*$` 只对**首 token**应用 —— 广度不会造成过抓，因为锚定在位置（首 token），而非内容。
- 大写归一（`back` → `BACK`），与现有 `parent_task_id` / 事件行大写一致。
- `isProposalApproved` / `isPlanApproved` 内部对 `path.basename(filepath)` 调用同一 `parseTaskId`，自动随之前缀无关；marker 文件名 `.ftb-awaiting-plan-${id}` 也随 id 变为大写前缀。
- 事件行变为 `basic-ready:BACK-511`；Monitor 的过滤器 `^(basic-ready|epic-ready|child-done|proposal-approved|plan-approved):` 已是前缀无关，**无需改动**。
- 取舍：放弃旧的「嵌入式 ID 回退」（`sprint-TASK-7-notes.md`）。`backlog/tasks/` 下文件均由 backlog CLI 生成、ID 恒为首 token，回退场景在本仓不存在；去掉它换取简洁。daemon 单测的 `embedded id` 用例相应替换为前缀无关首 token 用例（见 Goals 2）。

### B. SKILL.md ~11 处：位置/字段锚定

- **extractId（L1437）**：事件行 `channel:ID`，用 shell 参数展开剥离 channel，无需正则：
  `extractId() { echo "${1#*:}"; }`
- **claimBatch（L770）/ reap（L731）**：`backlog task list --plain` 行形如 `␣␣TASK-148 - title` 或 `␣␣[HIGH] TASK-171 - title`。按行首位置抓 ID，**必须**容许可选优先级括号：
  `grep -oP '^\s+(\[[A-Z]+\]\s+)?\K[A-Za-z][A-Za-z0-9]*-\d+(\.\d+)*(?= - )'`
  `\K` 重置匹配起点、`(?= - )` 前瞻 —— 只抓「行首（可选 `[PRIO]` 后）+ ` - ` 前」的 token，从结构上排除标题内 ID 形状 token。
- **parent 提取（L459, L1157, L1347）**：当前实现 grep `backlog task view --plain` 输出里的 `parent_task_id:`，但现版 CLI 的 `view --plain` 实际输出 `Parent: TASK-121 - title`（无 `parent_task_id:` 行）——属既存隐患。改为字段锚定抓 `Parent:` 行的第一个 token：
  `grep -oP '(?<=^Parent: )[A-Za-z][A-Za-z0-9]*-\d+(\.\d+)*'`
  （`Parent:` 行里 ` - title` 在 ID 之后，正则不含 `.+` 故只取 ID。）
- **childrenOf（L1443）**：读原始 frontmatter，字段锚定：`(?<=^id:\s)\S+`（去掉 `TASK-` 写死）。
- **onChildDone / epic parent（L1558）**：读原始 CHILD_FILE frontmatter，字段锚定：`(?<=^parent_task_id:\s)\S+`。
- **标题提取（L974, L1246, L1292）**：以 ID 为 landmark 抓标题，不需知道前缀：
  `grep -oP '^Task \S+ - \K.+'`（`view --plain` 标题行形如 `Task TASK-148 - <title>`，已核实）。

事件过滤器、channel 名、`computePulseLines` 均无需改动。

**已天然前缀无关、无需改动的点**：`onChildDone` 里 `ls .../${CHILD_ID,,}\ *.md`（L1556）用小写化的入参 ID 做 glob —— 对 `back-511` / `task-3` 同样成立，已是前缀无关。其余非功能性出现（事件示例文案、注释、`.agent-done-TASK-N` 文档路径示例）保持不变。功能性 grep 站点共 11 处（L459, 731, 770, 974, 1157, 1246, 1292, 1347, 1437, 1443, 1558），与上文一一对应、无遗漏。

## Trade-offs and Risks

- **首 token 假设**：ID 是文件名前导 token —— backlog CLI 命名恒成立（已用 Backlog.md 真实文件 `back-200 - ...`、`back-217.02 - ...`、`back-24.02 - ...` 验证）。非 CLI 生成的手工文件若不遵循此命名将得 null；可接受，因为 daemon 只服务 backlog 板。
- **list 解析依赖 `--plain` 缩进格式**：已核实输出为 `␣␣[PRIO]? ID - title`；裸位置锚定（无括号处理）会漏掉全部优先级行（实测 115/160，漏 45 行）。故 grep **必须**含可选 `(\[[A-Z]+\]\s+)?` 段。备选（若未来缩进/装饰格式再变）：逐行取「去掉前导空白与可选 `[..]` 后的第一个 token」做 per-line 首 token 解析，语义等价但更鲁棒；当前保留单行 grep 方案，并在 SKILL.md 注释标注该假设。
- **通用形状 `[A-Za-z]+-\d+` 偏宽**：但每处都做了位置（首 token / 行首）或字段（`^id:` / `^parent_task_id:` / `^Parent:`）锚定，广度不导致过抓 —— 锚定点而非形状决定抓取范围。
- **parent 行格式修正**：把 L459/L1157/L1347 从不匹配的 `parent_task_id:`（view 输出无此行）改为实际的 `^Parent:`，顺带修复既存隐患；需保证三处都改、避免遗漏。
- **baime 零回归**：`task-N` 仍命中首 token → `TASK-N`；小数子任务 `back-217.02` / `TASK-121.1` 经 `(\.\d+)*` 保留。daemon 单测 `embedded id` 用例需同步更新为前缀无关用例（行为变更，已在方案 A 取舍中声明）。
# TASK-198 Plan — prefix-agnostic task ID extraction (simpler redo)

TDD implementation of the approved prefix-agnostic proposal
(`/home/yale/.claude/jobs/ec8485c1/tmp/ftb-proposal.md`). Three phases:
(A) daemon `parseTaskId` first-token + unit tests; (B) SKILL.md 11 functional
grep sites re-anchored to position/field; (C) end-to-end prefix-agnostic fixture.

Test command: `bash scripts/validate-plugin.sh`
Daemon units: `node scripts/basic-daemon.test.js`

## Constraints (hard)

- NO `config.yml` read; NO `--task-prefix` arg; NO config prefix threaded in code.
- Monitor lifecycle / pulse / flock UNTOUCHED. Event filter
  `^(basic-ready|epic-ready|child-done|proposal-approved|plan-approved):` is
  already prefix-agnostic — DO NOT modify.
- baime zero regression: `task-N` still maps to `TASK-N` via first-token;
  decimal sub-tasks (`back-217.02`, `TASK-121.1`) preserved via `(\.\d+)*`.
- Each phase ≤ 200 lines of change.

## Baseline (verified now)

- `node scripts/basic-daemon.test.js` → `33 passed, 0 failed`.
- `bash scripts/validate-plugin.sh` → `ALL CHECKS PASSED` (Errors: 0).
- All referenced paths exist; 11 SKILL.md sites confirmed at
  L459, L731, L770, L974, L1157, L1246, L1292, L1347, L1437, L1443, L1558.

RED-now status of every gate below was checked against the current tree and is
noted inline. Absence checks use `! grep -qF` for literals containing `\d`
(avoids the BRE `\d`-vacuous-gate trap).

---

## Phase A — daemon `parseTaskId` first-token + unit tests (≤ 80 lines)

### A.1 Tests first (RED): rewrite local `parseTaskId` copy in `scripts/basic-daemon.test.js`

Replace the local copy (L9-16) with the first-token version and update the
`parseTaskId` assertion block (L127-132):

- REMOVE the `embedded id` case (`sprint-TASK-7-notes.md` → `TASK-7`) — first-token
  drops the embedded fallback per the proposal trade-off.
- Cases asserted:
  - `parseTaskId('back-511 - x.md')` → `BACK-511`
  - `parseTaskId('task-3 - do something.md')` → `TASK-3`
  - `parseTaskId('TASK-10 - title.md')` → `TASK-10`
  - `parseTaskId('back-217.02 - sub.md')` → `BACK-217.02`
  - `parseTaskId('README.md')` → `null`
  - `parseTaskId('task-42 - long title here.md')` → `TASK-42` (keep multi-digit)

New local `parseTaskId` body:
```js
function parseTaskId(filename) {
  const base = path.basename(filename, path.extname(filename)).toUpperCase();
  const first = base.split(/\s+/)[0];
  const m = first.match(/^([A-Za-z][A-Za-z0-9]*-\d+(?:\.\d+)*)$/);
  return m ? m[1] : null;
}
```

RED-now: `grep -qE "back-7|BACK-7"` and `grep -qF "UTF-8"` on the test file are
ABSENT now (verified); the `sprint-TASK-7-notes.md` line IS present now (verified)
so removing it changes behaviour. The test ships its own `parseTaskId` copy, so
the assertion set is self-contained and exercises the new first-token shape.

### A.2 Impl (GREEN): rewrite `parseTaskId` in `plugin/scripts/basic-daemon.js`

Replace L45-52 with the identical first-token body (no prefix param). Leave the
header docstring channel examples (`basic-ready:TASK-N` etc.) as illustrative
prose — non-functional. `isProposalApproved` / `isPlanApproved` call
`parseTaskId(path.basename(...))` and need NO change — they become prefix-agnostic
automatically; marker filenames `.ftb-awaiting-plan-${id}` follow the uppercased id.

### A.3 DoD (each an executable command; all must pass)

1. `node scripts/basic-daemon.test.js`  (FIRST DoD; expect all pass, count ≥ 33)
2. `bash scripts/validate-plugin.sh`
3. Positive binding — new shape present in plugin daemon:
   `grep -qF '[A-Za-z][A-Za-z0-9]*-\d+(?:\.\d+)*' plugin/scripts/basic-daemon.js`
   (RED-now: ABSENT — verified)
4. Absence — old hardcoded TASK- regex gone from plugin daemon:
   `! grep -qF '/^TASK-\d+(\.\d+)*$/.test(part)' plugin/scripts/basic-daemon.js`
   (RED-now: literal IS present — verified — so negated form fails pre-edit)
5. Absence — embedded-fallback line gone from plugin daemon:
   `! grep -qF '\bTASK-' plugin/scripts/basic-daemon.js`
   (single backslash literal; RED-now: `\bTASK-(\d+...)` IS present at L50 — verified)
6. Absence — old embedded test case removed:
   `! grep -qF 'sprint-TASK-7-notes.md' scripts/basic-daemon.test.js`
   (RED-now: present at L130 — verified)

---

## Phase B — SKILL.md 11 functional sites re-anchored (≤ 60 lines)

### B.1 Tests first (RED greps)

Run inline as DoD greps; no new test file required:
- Absence of reap/claim literal:
  `! grep -qF "grep -oP 'TASK-\d+'" plugin/skills/loop-backlog/SKILL.md`
  (RED-now: present at L731 + L770 — verified — negated form fails pre-edit)
- Absence of title literal:
  `! grep -qF '(?<=Task TASK-\d+ - )' plugin/skills/loop-backlog/SKILL.md`
  (RED-now: present at L974/L1246/L1292 — verified)
- Absence of childrenOf / epic-parent / parent literals:
  `! grep -qF '(?<=^id:\s)TASK-' plugin/skills/loop-backlog/SKILL.md` (RED-now present L1443)
  `! grep -qF '(?<=^parent_task_id:\s)TASK-' plugin/skills/loop-backlog/SKILL.md` (RED-now present L1558)
  `! grep -qF '(?<=parent_task_id: )TASK-' plugin/skills/loop-backlog/SKILL.md` (RED-now present L459/L1157/L1347)
- Positive new anchors:
  `grep -qF '${EVENT#*:}' plugin/skills/loop-backlog/SKILL.md` OR
  `grep -qF '${1#*:}' plugin/skills/loop-backlog/SKILL.md` (extractId form; RED-now ABSENT — verified)
  `grep -qF '(?<=^Parent: )' plugin/skills/loop-backlog/SKILL.md` (parent fix; RED-now ABSENT — verified)
  `grep -qF '(\[[A-Z]+\]\s+)?' plugin/skills/loop-backlog/SKILL.md` (bracket-aware list; RED-now ABSENT — verified)

### B.2 Impl — apply the 11 site changes EXACTLY per proposal §B

| Site | Current | New |
|---|---|---|
| L1437 extractId | `extractId() { echo "$1" \| grep -oP 'TASK-\d+(\.\d+)*' \| head -1; }` | `extractId() { echo "${1#*:}"; }` |
| L731 reap | `\| grep -oP 'TASK-\d+' \` | `\| grep -oP '^\s+(\[[A-Z]+\]\s+)?\K[A-Za-z][A-Za-z0-9]*-\d+(\.\d+)*(?= - )' \` |
| L770 claimBatch | `... --plain \| grep -oP 'TASK-\d+')` | `... --plain \| grep -oP '^\s+(\[[A-Z]+\]\s+)?\K[A-Za-z][A-Za-z0-9]*-\d+(\.\d+)*(?= - )')` |
| L459 parent | `grep -oP '(?<=parent_task_id: )TASK-\d+(\.\d+)*'` | `grep -oP '(?<=^Parent: )[A-Za-z][A-Za-z0-9]*-\d+(\.\d+)*'` |
| L1157 parent | `grep -oP '(?<=parent_task_id: )TASK-\S+' \| head -1` | `grep -oP '(?<=^Parent: )[A-Za-z][A-Za-z0-9]*-\d+(\.\d+)*' \| head -1` |
| L1347 parent | `grep -oP '(?<=parent_task_id: )TASK-\S+' \| head -1` | `grep -oP '(?<=^Parent: )[A-Za-z][A-Za-z0-9]*-\d+(\.\d+)*' \| head -1` |
| L974 title | `grep -oP '(?<=Task TASK-\d+ - ).+'` | `grep -oP '^Task \S+ - \K.+'` |
| L1246 title | `grep -oP '(?<=Task TASK-\d+ - ).+'` | `grep -oP '^Task \S+ - \K.+'` |
| L1292 title | `grep -oP '(?<=Task TASK-\d+ - ).+'` | `grep -oP '^Task \S+ - \K.+'` |
| L1443 childrenOf | `grep -oP '(?<=^id:\s)TASK-\S+'` | `grep -oP '(?<=^id:\s)\S+'` |
| L1558 epic parent | `grep -oP '(?<=^parent_task_id:\s)TASK-\S+'` | `grep -oP '(?<=^parent_task_id:\s)\S+'` |

Edit-uniqueness notes (Edit tool requires unique old_string):
- L731 + L770 share the identical literal `grep -oP 'TASK-\d+'`; edit each by its
  surrounding line context (`--status "Basic: In Progress"` at L731 vs
  `--status "Basic: Ready"` at L770) to keep `old_string` unique.
- L974/L1246/L1292 share the title literal; disambiguate by surrounding assignment
  (`TITLE=` vs `TASK_TITLE=`) and adjacent lines; or `replace_all` since the
  replacement is identical for all three.
- L1157 + L1347 share `(?<=parent_task_id: )TASK-\S+' | head -1`; disambiguate by
  surrounding comment/indentation context.
- Add an inline SKILL.md comment at the reap/claim site noting the `--plain`
  `␣␣[PRIO]? ID - title` indentation/bracket format assumption (proposal risk §).

The parent-field fix changes the matched field from the non-existent
`parent_task_id:` (absent from `view --plain` output) to the actual `^Parent:`
line — all three (L459/L1157/L1347) MUST change; the B.1 absence gate
`! grep -qF '(?<=parent_task_id: )TASK-'` catches any miss.

### B.3 Post-edit review note (manual, not a gate)

`grep -n "TASK-" plugin/skills/loop-backlog/SKILL.md` — confirm only prose,
comments, channel-name examples, and `.agent-done-TASK-N` doc paths remain;
no functional grep extracts `TASK-` by hardcoded prefix.

### B.4 DoD (each executable; all must pass)

1. `bash scripts/validate-plugin.sh`  (FIRST DoD)
2. `bash plugin/skills/loop-backlog/smoke/test-monitor-lifecycle.sh`
3. All B.1 absence greps (`! grep -qF ...`) — pass (literals removed)
4. All B.1 positive greps (`grep -qF ...`) — pass (new anchors present)

---

## Phase C — end-to-end prefix-agnostic fixture (≤ 60 lines)

### C.1 Tests first (RED): extend `scripts/basic-daemon.test.js`

Add a fixture block (after the existing `scanBasicReadyIds` tests) using the
local first-token `parseTaskId` + `scanBasicReadyIds`:
- temp dir; write `back-7 - fix UTF-8 bug.md` with
  `---\nstatus: Basic: Ready\nlabels: [kind:basic]\n---\n`.
- `const ids = scanBasicReadyIds(dir)`:
  - `assert('prefix-agnostic: back- → BACK-7', ids.has('BACK-7'), true)`
  - `assert('title-noise excluded: not UTF-8', ids.has('UTF-8'), false)`
    (proves first-token / position anchoring drops the `UTF-8` title token).
- clean up temp dir.

RED-now: `grep -qE "back-7|BACK-7"` and `grep -qF "UTF-8"` on the test file are
both ABSENT now (verified). With the OLD test-local `parseTaskId`, `back-7` →
`null` → `ids.has('BACK-7')` false → test RED; after Phase A's first-token copy
it is GREEN. (Phase A and C edit the same file; C depends on A's local rewrite.)

### C.2 DoD (each executable; all must pass)

1. `node scripts/basic-daemon.test.js`  (FIRST DoD)
2. `bash scripts/validate-plugin.sh`
3. `grep -qE "back-7|BACK-7" scripts/basic-daemon.test.js`  (RED-now ABSENT — verified)
4. `grep -qF "UTF-8" scripts/basic-daemon.test.js`  (title-noise control; RED-now ABSENT — verified)

---

## Acceptance Gate (whole task; each executable; ordered)

1. `bash scripts/validate-plugin.sh`  (FIRST)
2. `node scripts/basic-daemon.test.js`
3. `bash plugin/skills/loop-backlog/smoke/test-monitor-lifecycle.sh`
4. `grep -qF '[A-Za-z][A-Za-z0-9]*-\d+(?:\.\d+)*' plugin/scripts/basic-daemon.js`
5. `! grep -qF '/^TASK-\d+(\.\d+)*$/.test(part)' plugin/scripts/basic-daemon.js`
6. `! grep -qF '\bTASK-' plugin/scripts/basic-daemon.js`
7. `! grep -qF "grep -oP 'TASK-\d+'" plugin/skills/loop-backlog/SKILL.md`
8. `! grep -qF '(?<=Task TASK-\d+ - )' plugin/skills/loop-backlog/SKILL.md`
9. `! grep -qF '(?<=parent_task_id: )TASK-' plugin/skills/loop-backlog/SKILL.md`
10. `grep -qF '(?<=^Parent: )' plugin/skills/loop-backlog/SKILL.md`
11. `grep -qF '(\[[A-Z]+\]\s+)?' plugin/skills/loop-backlog/SKILL.md`
12. `grep -qE "back-7|BACK-7" scripts/basic-daemon.test.js`
13. `grep -qF "UTF-8" scripts/basic-daemon.test.js`

All 13 verified against the current tree: gates 4-13 are RED-now (fail pre-edit);
gates 1-3 pass now and must remain green post-edit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
<!-- SECTION:NOTES:BEGIN -->

Proposal self-review: APPROVED (1 round)
premise-ledger:
[E] parseTaskId first-token extraction: VERIFIED against real Backlog.md filenames (back-200, back-217.02, back-24.02) — leading token IS the ID; path guarantees task-ness.
[E] claimBatch/reap list grep must handle [PRIORITY] bracket: VERIFIED empirically — naive ^\s+\K grep matches 115/160 lines (misses 45 priority rows); bracket-aware grep matches 160/160.
[E] title grep ^Task \S+ - \K.+: VERIFIED against 'backlog task view --plain' (Task TASK-148 - <title> line).
[E] parent extraction: view --plain emits 'Parent: TASK-121 - title', NOT 'parent_task_id:' — existing L459/1157/1347 greps target a nonexistent line (latent bug); fix anchors on ^Parent:. VERIFIED.
[E] extractId via ${EVENT#*:}: VERIFIED — basic-ready:BACK-511 -> BACK-511, proposal-approved:TASK-9 -> TASK-9.
[C] 11 functional grep sites enumerated (L459,731,770,974,1157,1246,1292,1347,1437,1443,1558) match proposal 1:1; ls glob L1556 already prefix-agnostic.
[H] generic [A-Za-z]+-\d+ shape breadth is contained by position/field anchoring at every site, not by the shape itself.
[H] dropping embedded-ID fallback: backlog/tasks/ files are CLI-generated, ID always first token — fallback scenario absent in-repo.
GCL-self-report: E=5 C=2 H=3

Proposal approved (prefix-agnostic redo). Starting plan draft.

Plan review iteration 1: APPROVED
premise-ledger:
[E] vacuous-gate audit: all 10 grep gates (acceptance 4-13) RED-now verified by running each against current tree. Absence checks 5/6/7/8/9 — literals PRESENT now (negated form fails pre-edit); positive checks 4/10/11/12/13 — ABSENT now (become green post-edit). All absence-of-literal gates use grep -qF (no BRE \d vacuous trap).
[E] empirical finding (a) bracket-aware list grep: backlog task list --plain emits '  [HIGH] TASK-171 - ...'; old 'grep -oP TASK-\d+' yields 172 (over-captures title tokens TASK-124/TASK-93), new '^\s+(\[[A-Z]+\]\s+)?\K...(?= - )' yields 160 row-anchored IDs incl. all [HIGH]/[MEDIUM] rows. Gate 11 RED-now.
[E] empirical finding (b) Parent field fix: view --plain emits 'Parent: TASK-125 - title' (verified on TASK-125.4), NOT 'parent_task_id:'. L459/1157/1347 fix is correct + closes pre-existing latent bug. Gate 10 RED-now.
[E] dropped embedded-id fallback: sprint-TASK-7-notes.md test case present at L130 now; gate 6 (! grep -qF sprint-TASK-7-notes.md) guards removal.
[C] new grep forms validated on real data: childrenOf (?<=^id:\s)\S+ -> TASK-125.4; epic-parent (?<=^parent_task_id:\s)\S+ -> TASK-125; title ^Task \S+ - \K.+ -> correct; extractId ${1#*:} on 'epic-ready:TASK-12' -> TASK-12 (no colon in channel/id).
[C] all 11 functional sites confirmed at claimed lines 459/731/770/974/1157/1246/1292/1347/1437/1443/1558; Edit-uniqueness strategy sound (L731 vs L770, title triple via replace_all).
[H] scope clean: no config.yml read, no --task-prefix, Monitor/pulse/flock + event filter untouched; baime zero regression (first-token task-N->TASK-N, decimals via (\.\d+)*). Baseline: 33 tests pass, validate exit 0, smoke present.
GCL-self-report: E=4 C=2 H=1

claimed: 2026-06-25T09:34:23Z

Phase A ✓ 2026-06-25T09:36:34Z
Phase B ✓ 2026-06-25T09:40:21Z
Phase C ✓ 2026-06-25T09:40:21Z

workerLoop pre-merge DoD: all 14 PASS

Completed: 2026-06-25T09:43:36Z
<!-- SECTION:NOTES:END -->

<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 node scripts/basic-daemon.test.js
- [ ] #2 bash scripts/validate-plugin.sh
- [ ] #3 bash plugin/skills/loop-backlog/smoke/test-monitor-lifecycle.sh
- [ ] #4 grep -qF '[A-Za-z][A-Za-z0-9]*-\d+(?:\.\d+)*' plugin/scripts/basic-daemon.js
- [ ] #5 ! grep -qF '/^TASK-\d+(\.\d+)*$/.test(part)' plugin/scripts/basic-daemon.js
- [ ] #6 ! grep -qF '\bTASK-' plugin/scripts/basic-daemon.js
- [ ] #7 ! grep -qF 'sprint-TASK-7-notes.md' scripts/basic-daemon.test.js
- [ ] #8 ! grep -qF "grep -oP 'TASK-\d+'" plugin/skills/loop-backlog/SKILL.md
- [ ] #9 ! grep -qF '(?<=Task TASK-\d+ - )' plugin/skills/loop-backlog/SKILL.md
- [ ] #10 ! grep -qF '(?<=parent_task_id: )TASK-' plugin/skills/loop-backlog/SKILL.md
- [ ] #11 grep -qF '(?<=^Parent: )' plugin/skills/loop-backlog/SKILL.md
- [ ] #12 grep -qF '(\[[A-Z]+\]\s+)?' plugin/skills/loop-backlog/SKILL.md
- [ ] #13 grep -qE "back-7|BACK-7" scripts/basic-daemon.test.js
- [ ] #14 grep -qF "UTF-8" scripts/basic-daemon.test.js
<!-- DOD:END -->
