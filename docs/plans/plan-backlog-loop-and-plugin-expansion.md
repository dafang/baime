# Plan: Backlog/Loop 机制引入与 Plugin 技能扩展

- **对应 Proposal**: `docs/proposals/proposal-backlog-loop-and-plugin-expansion.md`
- **执行方式**: 每个 Phase 由独立 Task Agent 执行，完成后提交再进入下一 Phase
- **Phase 编号**: 接续现有 plans（当前最大为 Stage 4），本 plan 使用 Phase 5–7

---

## Phase 依赖关系

```
Phase 5（marketplace 修复，解除 CI 阻塞）
  └─► Phase 6（project-local backlog/loop 环境）
  └─► Phase 7（plugin skills 扩展 + 版本发布）
        └─► （Phase 6 和 Phase 7 可在 Phase 5 完成后并行，但 Phase 7 的发布步骤依赖 Phase 6 完成）
```

> Phase 5 无依赖，必须最先执行。Phase 6 和 Phase 7 的主体工作可在 Phase 5 完成后并行开始，但最终的 bump-version 和 push tag 发布步骤须在 Phase 6 完成后统一执行。

---

## Phase 5：修复 `plugin/.claude-plugin/marketplace.json`（目标 3）

**目标**: 删除 `plugin/.claude-plugin/marketplace.json`（非法 `source` 格式），消除歧义，使根目录 `.claude-plugin/marketplace.json` 成为唯一权威来源，解除 CI 阻塞风险。

**依赖**: 无

**代码变更预估**: ~5 行（删除 1 个文件，可选更新 1 个字段）

### Stage 5.1：删除非法 marketplace.json

**操作**:

```bash
git rm plugin/.claude-plugin/marketplace.json
```

**背景**:
- `plugin/.claude-plugin/marketplace.json` 当前内容为 `{"source": {"type": "directory", "path": "."}}` 格式，`"directory"` 不是 Claude Code 的合法 marketplace source 类型
- 根目录 `.claude-plugin/marketplace.json` 的 `source: "./plugin"` 格式合规，无需修改
- `validate-plugin.sh` 只读根目录文件，此步骤不影响 CI 行为，但消除潜在歧义

### Stage 5.2（可选）：统一 $schema 地址

**操作**: 将根目录 `.claude-plugin/marketplace.json` 的 `$schema` 字段从

```
"https://anthropic.com/claude-code/marketplace.schema.json"
```

更新为官方 schema store 地址：

```
"https://json.schemastore.org/claude-code-marketplace.json"
```

> 说明：Claude Code 文档明确指出该字段在加载时被忽略，此步骤为可选优化，与 Anthropic 官方仓库保持一致。

### 验收标准（DoD）

```bash
# 1. plugin/ 目录内不再存在 marketplace.json
[ ! -f plugin/.claude-plugin/marketplace.json ] && echo "PASS: no marketplace.json in plugin/"

# 2. 根目录 marketplace.json 的 source 格式合规
jq '.plugins[0].source' .claude-plugin/marketplace.json
# 期望："./plugin"（字符串路径，非嵌套对象）

# 3. validate-plugin.sh 通过
bash scripts/validate-plugin.sh
# 期望：ALL CHECKS PASSED

# 4. git log 确认删除已提交
git log --oneline -1
```

### 提交

```
git add -A
git commit -m "fix: remove invalid marketplace.json from plugin/ directory

Delete plugin/.claude-plugin/marketplace.json which used non-standard
source type {\"type\": \"directory\", \"path\": \".\"}.
Root .claude-plugin/marketplace.json with source \"./plugin\" is the
authoritative file and remains unchanged."
```

---

## Phase 6：创建 project-local backlog/loop 开发环境（目标 1）

**目标**: 让 baime 项目自身能用 L0 自主 worker 驱动特性开发，通过创建 `.claude/skills/` 和 `CLAUDE.md` 完成。

**依赖**: Phase 5 完成（确保 validate-plugin.sh 环境干净）

**代码变更预估**: ~50 行（4 个 SKILL.md 文件复制 + CLAUDE.md ~10 行）

### Stage 6.1：创建 `.claude/skills/` 并复制 4 个 skill

**操作**:

```bash
mkdir -p .claude/skills/backlog-setup
mkdir -p .claude/skills/feature-to-backlog
mkdir -p .claude/skills/task-to-backlog
mkdir -p .claude/skills/loop-backlog

# 从 archguard 复制
cp /home/yale/work/archguard/.claude/skills/backlog-setup/SKILL.md    .claude/skills/backlog-setup/SKILL.md
cp /home/yale/work/archguard/.claude/skills/feature-to-backlog/SKILL.md .claude/skills/feature-to-backlog/SKILL.md
cp /home/yale/work/archguard/.claude/skills/task-to-backlog/SKILL.md   .claude/skills/task-to-backlog/SKILL.md
cp /home/yale/work/archguard/.claude/skills/loop-backlog/SKILL.md      .claude/skills/loop-backlog/SKILL.md
```

**修复 loop-backlog 的硬编码 worktree 路径**（必须执行，否则 worktree 会被错误命名为 `archguard-TASK-N`）：

```bash
# reap 段（约第 152 行）和 withWorktree 段（约第 176 行）各有一处，共两处替换
# 在两处使用硬编码 "archguard-${TASK_ID}" 的位置前，插入 PROJECT_NAME 变量声明并替换路径
```

具体编辑：在 `reap` 的 `if [ $AGE -gt 1800 ]` 块内和 `withWorktree` 的 `BRANCH=` 行前，将：

```bash
WORKTREE="${REPO_ROOT}/../archguard-${TASK_ID}"
```

替换为：

```bash
PROJECT_NAME=$(basename "$REPO_ROOT")
WORKTREE="${REPO_ROOT}/../${PROJECT_NAME}-${TASK_ID}"
```

**说明**：`backlog-setup`、`feature-to-backlog`、`task-to-backlog` 三个 skill 无项目特定路径，原样复制即可。`loop-backlog` 的配置读取（`fromClaudeMd`/`parse_cfg`）无需修改，仅 worktree 路径需修复。

### Stage 6.2：创建 `CLAUDE.md` 含 L0 Config

**新建文件** `CLAUDE.md`（位于仓库根目录）：

```markdown
# baime

BAIME (Bootstrapped AI Methodology Engineering) - systematic methodology development framework.

Plugin directory: `plugin/`
Validation: `bash scripts/validate-plugin.sh`

## L0 Config

test-cmd: bash scripts/validate-plugin.sh
test-all: bash scripts/validate-plugin.sh
doc-path: docs
worktree-symlinks:
```

**格式约束**（来自 `parse_cfg` 正则 `(?<=^$1:\s)\S.*`）：
- 每个字段严格使用 `key: value` 格式（冒号后**单空格**，不能是两空格或零空格）
- `worktree-symlinks:` 后不跟任何内容是合法语法，等价于"无需 symlinks"（baime 是 bash 项目，无 node_modules 等大目录）
- `test-cmd` 和 `test-all` 均指向 `validate-plugin.sh`（baime 无分阶段 test vs full suite 区分）
- `doc-path: docs` 指向已存在的 `docs/` 目录（`proposals/` 和 `plans/` 子目录均已存在）

### 验收标准（DoD）

```bash
# 1. 4 个 skill 文件存在
[ -f .claude/skills/backlog-setup/SKILL.md ] && echo "PASS: backlog-setup"
[ -f .claude/skills/feature-to-backlog/SKILL.md ] && echo "PASS: feature-to-backlog"
[ -f .claude/skills/task-to-backlog/SKILL.md ] && echo "PASS: task-to-backlog"
[ -f .claude/skills/loop-backlog/SKILL.md ] && echo "PASS: loop-backlog"

# 2. loop-backlog 无硬编码 "archguard-" worktree 路径
grep -n "archguard-\${TASK_ID}" .claude/skills/loop-backlog/SKILL.md \
  && echo "FAIL: hardcoded archguard path found" || echo "PASS: no hardcoded archguard path"
# 期望：PASS（grep 返回非零退出码，即无匹配）

# 3. loop-backlog 含正确的动态路径
grep -n 'PROJECT_NAME=\$(basename "\$REPO_ROOT")' .claude/skills/loop-backlog/SKILL.md \
  && echo "PASS: dynamic PROJECT_NAME found" || echo "FAIL: PROJECT_NAME missing"
# 期望：PASS（出现两次：reap 段和 withWorktree 段各一次）

# 4. CLAUDE.md 存在且 L0 Config section 可被正确提取
[ -f CLAUDE.md ] && echo "PASS: CLAUDE.md exists"
awk '/^## L0 Config/{found=1; next} found && /^## /{exit} found{print}' CLAUDE.md
# 期望输出包含 test-cmd、test-all、doc-path、worktree-symlinks 四行

# 5. L0 Config 字段格式正确（单空格）
grep -P '^test-cmd: \S' CLAUDE.md && echo "PASS: test-cmd format"
grep -P '^test-all: \S' CLAUDE.md && echo "PASS: test-all format"
grep -P '^doc-path: \S' CLAUDE.md && echo "PASS: doc-path format"

# 6. validate-plugin.sh 仍然通过（project-local skills 不影响 plugin/ 计数）
bash scripts/validate-plugin.sh
# 期望：ALL CHECKS PASSED, Skills: 17

# 7. git log 确认提交
git log --oneline -2
```

### 提交

```
git add CLAUDE.md .claude/
git commit -m "feat: add project-local backlog/loop skills and CLAUDE.md

Create .claude/skills/ with backlog-setup, feature-to-backlog,
task-to-backlog, loop-backlog (copied from archguard, loop-backlog
patched to use dynamic PROJECT_NAME for worktree paths).
Add CLAUDE.md with L0 Config pointing to validate-plugin.sh.
Enables L0 autonomous worker for baime's own feature development."
```

---

## Phase 7：Plugin Skills 扩展与版本发布（目标 2）

**目标**: 将 5 个 backlog/loop/feature-developer skill 并入 `plugin/skills/`，更新 plugin.json 和 validate-plugin.sh，更新描述文字，发布新版本。

**依赖**:
- Phase 5 完成（validate-plugin.sh 基线正常）
- 发布步骤（Stage 7.4）额外依赖 Phase 6 完成（CLAUDE.md 已就绪，版本发布含完整变更）

**代码变更预估**: ~150 行（5 个 SKILL.md 文件复制 + plugin.json +8 行 + validate-plugin.sh +1 行 + 两个 description 更新）

### Stage 7.1：复制 5 个 skill 到 `plugin/skills/`

**操作**:

```bash
# 从 archguard 复制
cp -r /home/yale/work/archguard/.claude/skills/backlog-setup      plugin/skills/backlog-setup
cp -r /home/yale/work/archguard/.claude/skills/feature-to-backlog  plugin/skills/feature-to-backlog
cp -r /home/yale/work/archguard/.claude/skills/task-to-backlog     plugin/skills/task-to-backlog
cp -r /home/yale/work/archguard/.claude/skills/loop-backlog        plugin/skills/loop-backlog
cp -r /home/yale/work/archguard/.claude/skills/feature-developer   plugin/skills/feature-developer
```

**修复 plugin/skills/loop-backlog 的硬编码 worktree 路径**（与 Stage 6.1 相同的修复，必须执行）：

在 `plugin/skills/loop-backlog/SKILL.md` 中，将两处（`reap` 段和 `withWorktree` 段）：

```bash
WORKTREE="${REPO_ROOT}/../archguard-${TASK_ID}"
```

替换为：

```bash
PROJECT_NAME=$(basename "$REPO_ROOT")
WORKTREE="${REPO_ROOT}/../${PROJECT_NAME}-${TASK_ID}"
```

**目标结构**（新增 5 项，原有 17 个 skill 目录不变）:

```
plugin/skills/
├── backlog-setup/SKILL.md          ← 新增
├── feature-to-backlog/SKILL.md     ← 新增
├── task-to-backlog/SKILL.md        ← 新增
├── loop-backlog/SKILL.md           ← 新增（含 worktree 路径修复）
├── feature-developer/SKILL.md      ← 新增
└── ... (原有 17 个目录)
```

**说明**: 不引入 `feature-to-issues`（该 skill 与 GitHub Issues/`gh` CLI 深度耦合，对不使用 GitHub Issues 工作流的用户无价值）。`feature-developer` 无项目特定路径，原样复制即可。

### Stage 7.2：更新 `plugin/.claude-plugin/plugin.json`

> **注意**：`install.sh` 在用户安装时会动态重写缓存中的 `plugin.json`，但开发阶段（非安装时）不会自动运行。**必须手动更新仓库中的 `plugin/.claude-plugin/plugin.json`**，该文件是 `validate-plugin.sh` 的验证来源，也是安装时的基础版本。

在 `commands` 数组末尾追加 5 个新条目（直接编辑文件，路径格式与现有 17 个条目保持一致，均以 `./skills/` 开头）：

```json
"./skills/backlog-setup/SKILL.md",
"./skills/feature-to-backlog/SKILL.md",
"./skills/task-to-backlog/SKILL.md",
"./skills/loop-backlog/SKILL.md",
"./skills/feature-developer/SKILL.md"
```

同步更新 `description` 字段：

```json
"description": "BAIME: Systematic methodology development with 22 validated skills and 4 specialized agents"
```

（原值为 `"17 validated skills and 4 specialized agents"`，agents 数量 4 不变，skills 17→22）

### Stage 7.3：更新 `scripts/validate-plugin.sh` 和根目录 `marketplace.json`

**validate-plugin.sh**（第 143 行）：

```bash
# 修改前
EXPECTED_SKILLS=17

# 修改后
EXPECTED_SKILLS=22
```

> 注意：第 142 行 `EXPECTED_AGENTS=4` 不变（新增的 5 项均为 skill，不是 agent）。

**根目录 `.claude-plugin/marketplace.json`**，更新 `plugins[0].description`：

```json
"description": "22 validated skills and 4 specialized agents for systematic AI methodology engineering via OCA cycles and dual-layer value functions"
```

（原值为 `"19 validated skills and 6 specialized agents"`，修正为实际数字：22 skills，4 agents）

### Stage 7.4：bump version 并发布

更新 `plugin/.claude-plugin/plugin.json` 的 `version` 字段（1.0.0 → 1.1.0）和根目录 `marketplace.json` 的 `plugins[0].version`（保持一致）：

```bash
bash scripts/release/bump-version.sh v1.1.0
# 或手动编辑两个 JSON 文件的 version 字段
```

更新 `CHANGELOG.md`，新增版本条目（位于 `## [1.0.0]` 之前）：

```markdown
## [1.1.0] - 2026-06-16

### Added
- 5 new skills: backlog-setup, feature-to-backlog, task-to-backlog,
  loop-backlog, feature-developer (copied from archguard)
- CLAUDE.md with L0 Config enabling autonomous backlog/loop workflow
- project-local .claude/skills/ for baime's own development workflow

### Fixed
- Removed invalid plugin/.claude-plugin/marketplace.json with
  non-standard source type {"type": "directory", "path": "."}
- Fixed loop-backlog SKILL.md: replaced hardcoded archguard worktree
  path with dynamic PROJECT_NAME=$(basename "$REPO_ROOT")
```

然后执行发布：

```bash
make release VERSION=v1.1.0
# 或手动：
git add -A
git commit -m "chore: release v1.1.0"
git tag -a v1.1.0 -m "v1.1.0"
git push origin main
git push origin v1.1.0
```

### 验收标准（DoD）

```bash
# Stage 7.1 验证：5 个新 skill 目录存在
[ -d plugin/skills/backlog-setup ]      && echo "PASS: backlog-setup"
[ -d plugin/skills/feature-to-backlog ] && echo "PASS: feature-to-backlog"
[ -d plugin/skills/task-to-backlog ]    && echo "PASS: task-to-backlog"
[ -d plugin/skills/loop-backlog ]       && echo "PASS: loop-backlog"
[ -d plugin/skills/feature-developer ]  && echo "PASS: feature-developer"

# plugin/skills/loop-backlog 无硬编码 "archguard-" worktree 路径
grep -n "archguard-\${TASK_ID}" plugin/skills/loop-backlog/SKILL.md \
  && echo "FAIL: hardcoded archguard path found" || echo "PASS: no hardcoded archguard path"
# 期望：PASS

# plugin/skills/loop-backlog 含正确的动态路径（两处）
grep -c 'PROJECT_NAME=\$(basename "\$REPO_ROOT")' plugin/skills/loop-backlog/SKILL.md
# 期望：2（reap 段和 withWorktree 段各一次）

# 总 skill 数量正确
ls plugin/skills/ | wc -l
# 期望：22

# Stage 7.2 验证：plugin.json commands 包含 5 个新条目
jq '.commands | length' plugin/.claude-plugin/plugin.json
# 期望：22

jq '.description' plugin/.claude-plugin/plugin.json
# 期望包含 "22 validated skills and 4 specialized agents"

# Stage 7.3 验证：validate-plugin.sh 通过（含新 skill 计数）
bash scripts/validate-plugin.sh
# 期望：ALL CHECKS PASSED, Skills: 22, Agents: 4

# 根目录 marketplace.json description 已更新
jq '.plugins[0].description' .claude-plugin/marketplace.json
# 期望包含 "22 validated skills and 4 specialized agents"

# Stage 7.4 验证：版本号一致
jq '.version' plugin/.claude-plugin/plugin.json
# 期望："1.1.0"

jq '.plugins[0].version' .claude-plugin/marketplace.json
# 期望："1.1.0"

# git tag 存在
git tag | grep v1.1.0
# 期望：v1.1.0
```

### 提交（Stage 7.1–7.3 合并为一个 commit）

```
git add plugin/skills/ plugin/.claude-plugin/plugin.json scripts/validate-plugin.sh .claude-plugin/marketplace.json
git commit -m "feat: add 5 backlog/loop skills to plugin and update counts

Add backlog-setup, feature-to-backlog, task-to-backlog, loop-backlog,
feature-developer to plugin/skills/ (copied from archguard;
loop-backlog patched to use dynamic PROJECT_NAME for worktree paths).
Update EXPECTED_SKILLS=22, plugin.json commands (22 entries),
and description fields in plugin.json and marketplace.json."
```

---

## 测试策略

baime 是纯文档/skill/agent 插件，无运行时代码。所有验证通过 `bash scripts/validate-plugin.sh` 执行，该脚本检查：

1. **JSON 合规性**: `plugin/.claude-plugin/plugin.json` 和 `.claude-plugin/marketplace.json` 均为合法 JSON
2. **YAML frontmatter**: 所有 SKILL.md 文件含合法 YAML frontmatter（含 `allowed-tools` 等必需字段）
3. **计数断言**: `EXPECTED_AGENTS=4`，`EXPECTED_SKILLS=22`（Phase 7 完成后）
4. **forbidden 检查**: skill 文件内容不含禁止模式

每个 Phase 完成后均须通过 `bash scripts/validate-plugin.sh`，输出 `ALL CHECKS PASSED`。

### 关键格式约束

- `CLAUDE.md` 的 `## L0 Config` section 字段必须严格使用 `key: value`（冒号后**单空格**），`parse_cfg` 正则 `(?<=^$1:\s)\S.*` 对此严格依赖
- `plugin.json` 的 `commands` 数组路径格式必须以 `./skills/` 开头（与现有 17 个条目保持一致）
- `EXPECTED_SKILLS` 与 `plugin.json` 的 `commands` 数组长度必须严格一致，否则 CI 失败

---

## 变更文件汇总

| Phase | 文件 | 操作 |
|-------|------|------|
| 5 | `plugin/.claude-plugin/marketplace.json` | 删除 |
| 5（可选） | `.claude-plugin/marketplace.json` | 更新 `$schema` 字段 |
| 6 | `.claude/skills/backlog-setup/SKILL.md` | 新增（从 archguard 原样复制） |
| 6 | `.claude/skills/feature-to-backlog/SKILL.md` | 新增（从 archguard 原样复制） |
| 6 | `.claude/skills/task-to-backlog/SKILL.md` | 新增（从 archguard 原样复制） |
| 6 | `.claude/skills/loop-backlog/SKILL.md` | 新增（从 archguard 复制 + **修复两处硬编码 archguard worktree 路径**） |
| 6 | `CLAUDE.md` | 新增（L0 Config） |
| 7 | `plugin/skills/backlog-setup/SKILL.md` | 新增（从 archguard 原样复制） |
| 7 | `plugin/skills/feature-to-backlog/SKILL.md` | 新增（从 archguard 原样复制） |
| 7 | `plugin/skills/task-to-backlog/SKILL.md` | 新增（从 archguard 原样复制） |
| 7 | `plugin/skills/loop-backlog/SKILL.md` | 新增（从 archguard 复制 + **修复两处硬编码 archguard worktree 路径**） |
| 7 | `plugin/skills/feature-developer/SKILL.md` | 新增（从 archguard 原样复制） |
| 7 | `plugin/.claude-plugin/plugin.json` | 更新 `commands`（+5）、`description`、`version` |
| 7 | `scripts/validate-plugin.sh` | 更新 `EXPECTED_SKILLS=22` |
| 7 | `.claude-plugin/marketplace.json` | 更新 `plugins[0].description`、`plugins[0].version` |
| 7 | `CHANGELOG.md` | 新增 `[1.1.0]` 条目 |

---

## Task Agent 执行指令模板

每个 Phase 启动时，向 Task Agent 提供如下上下文：

```
工作目录：/home/yale/work/baime
参考文档：docs/proposals/proposal-backlog-loop-and-plugin-expansion.md
参考项目：/home/yale/work/archguard（skill 来源，可从 .claude/skills/ 复制）

任务：执行 plan-backlog-loop-and-plugin-expansion.md 中的 Phase N
  - 严格按照 Phase N 的「Stage」列表执行
  - 完成后运行「验收标准（DoD）」中的所有命令，确认全部通过
  - 按照「提交」部分的 commit message 格式提交
  - 不要跨越到 Phase N+1
```
