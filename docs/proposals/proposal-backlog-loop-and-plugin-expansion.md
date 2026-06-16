# Proposal: Backlog/Loop 机制引入与 Plugin 技能扩展

## 背景

### 当前状态

baime 是一个 Claude Code 插件（`/home/yale/work/baime`），包含 17 个 skills 和 4 个 agents，服务于 AI 辅助开发方法论。当前项目结构：

```
baime/
├── plugin/
│   ├── .claude-plugin/plugin.json     ← 17 skills, 4 agents
│   └── skills/                        ← 17 个 skill 目录
├── .claude-plugin/marketplace.json    ← 指向 ./plugin（根目录，已存在但有偏差）
├── docs/
│   ├── proposals/
│   └── plans/
└── scripts/
    ├── validate-plugin.sh             ← EXPECTED_SKILLS=17
    └── install/install.sh
```

存在三个相互关联的待解决问题：

**问题 1：baime 自身缺乏结构化开发流程**
- 无 CLAUDE.md（`ls /home/yale/work/baime/.claude/` 返回"no .claude dir"）
- 无 `.claude/skills/`（project-local skill 目录）
- 无 backlog 任务看板，无法做 L0 自主执行
- 特性开发依赖手工 ad-hoc 流程，无 Proposal → Plan → Backlog 流水线

**问题 2：marketplace 阻塞 CI**
- 根目录 `.claude-plugin/marketplace.json` 已存在，但 `plugin/` 子目录内还残留一份格式不合规的 `marketplace.json`（内容为 `{"name": "baime", "owner": {...}, "plugins": [{"name": "baime", "source": {"type": "directory", "path": "."}}]}`，`source` 格式使用了 `{"type": "directory", "path": "."}` 嵌套对象，该结构不是 Claude Code marketplace 的合法 source 类型；合法类型为字符串路径（`"./..."`)、`"github"` 对象、`"url"` 对象、`"git-subdir"` 对象、`"npm"` 对象，无 `"directory"` type）
- 根目录 `.claude-plugin/marketplace.json` 的 `source` 字段为 `"./plugin"`（字符串路径），这是合规的相对路径格式，无需修改
- 根目录 `marketplace.json` 的 `$schema` 字段为 `"https://anthropic.com/claude-code/marketplace.schema.json"`，而官方 anthropics/claude-code 仓库使用的是 `"https://json.schemastore.org/claude-code-marketplace.json"`；两者均可接受（Claude Code 文档明确说明"Claude Code ignores this field at load time"），但建议统一为官方 schema 地址
- `scripts/release/bump-version.sh` 写了更新根目录 `marketplace.json` 的逻辑，但 `scripts/validate-plugin.sh` 读根目录文件，版本更新链路需一致验证
- **【发现：install.sh bug，proposal 未覆盖】** `install.sh` 在写 `extraKnownMarketplaces` 时使用 `{"source": "directory", "path": $dir}` 格式，但官方文档中 `extraKnownMarketplaces` 的 marketplace source 格式为 `{"source": "github", "repo": ...}` 或 `{"source": "url", "url": ...}` 等；`"directory"` 不是文档化的 marketplace source type。本 proposal 范围内暂不处理，但需在后续 issue 中跟踪修复

**问题 3：backlog/loop 技能尚未发行给用户**
- archguard 项目已在 `.claude/skills/` 下沉淀了成熟的 4 技能互锁体系
- baime plugin 用户需要这套能力，但当前 `plugin/skills/` 中没有这些 skill

### 参照：archguard 的成熟实践

archguard（`/home/yale/work/archguard/.claude/skills/`）已落地 6 个相关 skill：

| Skill | 描述 |
|-------|------|
| `backlog-setup` | 一次性初始化看板列，idempotent |
| `feature-to-backlog` | 特性 → Proposal → Plan → Backlog，双审循环 |
| `task-to-backlog` | 非开发任务 → Plan → Backlog，单审循环 |
| `loop-backlog` | L0 自主 worker，git worktree 隔离执行，ScheduleWakeup 自驱 |
| `feature-developer` | 完整特性开发生命周期（phases 3-9），TDD + 并行 Task agents |
| `feature-to-issues` | 特性 → GitHub Issues（可选，非必须引入） |

`loop-backlog` 的核心 L0 Config 机制（从 SKILL.md 摘录）：

```
loadConfig :: () → Config
loadConfig() =
  | fromClaudeMd()   -- explicit: "## L0 Config" section in CLAUDE.md
  | autoDetect()     -- implicit: probe package.json, go.mod, Cargo.toml, etc.
```

`feature-to-backlog` 的 Config 结构（决定 DoD test-cmd）：

```
Config :: {
  testCmd  : String,   -- per-phase test runner; becomes DoD[0] in generated plans
  testAll  : String,   -- full suite; becomes Acceptance Gate[0]
  docPath  : String    -- root for proposals/ and plans/ subdirectories
}
```

---

## 目标

### 目标 1：为 baime 自身开发启用 backlog/loop 机制（project-local）

让 baime 项目本身能用 L0 自主 worker 驱动自身特性开发。

- 创建 `.claude/skills/`，复制 4 个互锁 skill（`backlog-setup`、`feature-to-backlog`、`task-to-backlog`、`loop-backlog`）
- 创建 `CLAUDE.md`，包含 `## L0 Config` section（指定 `test-cmd: bash scripts/validate-plugin.sh`）
- `docs/proposals/` 和 `docs/plans/` 目录已存在，无需创建

### 目标 2：将 backlog/loop + feature-developer 技能并入 plugin/ 供用户使用

让 baime 用户也能获得这套工作流能力。

- 从 archguard 复制 5 个 skill 到 `plugin/skills/`：`backlog-setup`、`feature-to-backlog`、`task-to-backlog`、`loop-backlog`、`feature-developer`
- 更新 `validate-plugin.sh` 的 `EXPECTED_SKILLS` 从 17 改为 22
- 更新 `plugin/.claude-plugin/plugin.json` 的 `commands` 列表，加入 5 个新 skill 路径

### 目标 3：修复根目录 `.claude-plugin/marketplace.json` 确保 CI 通过

当前 `plugin/` 子目录内的 `marketplace.json` 格式不合规（`source` 使用了非法的 `{"type": "directory", "path": "."}` 格式），根目录的正规版本（`source: "./plugin"` 字符串路径）已就绪。需要删除 `plugin/.claude-plugin/marketplace.json` 以消除歧义，并将根目录版本作为唯一权威来源。

---

## 方案设计

### 3.1 文件结构变更

#### 目标 1：project-local 开发环境

新增文件：

```
baime/
├── CLAUDE.md                          ← 新增，含 L0 Config
└── .claude/
    └── skills/
        ├── backlog-setup/
        │   └── SKILL.md               ← 从 archguard 复制
        ├── feature-to-backlog/
        │   └── SKILL.md               ← 从 archguard 复制
        ├── task-to-backlog/
        │   └── SKILL.md               ← 从 archguard 复制
        └── loop-backlog/
            └── SKILL.md               ← 从 archguard 复制
```

`CLAUDE.md` 的 L0 Config section（draft）：

```markdown
## L0 Config

test-cmd: bash scripts/validate-plugin.sh
test-all: bash scripts/validate-plugin.sh
doc-path: docs
worktree-symlinks:
```

说明：
- `test-cmd` 和 `test-all` 均指向 `validate-plugin.sh`（baime 没有分阶段 test vs full suite 的区分）
- `doc-path: docs` 指向已存在的 `docs/` 目录，`proposals/` 和 `plans/` 子目录均已存在
- `worktree-symlinks:` 留空是合法语法，`parse_cfg` 返回空字符串，等价于"无需 symlink"（baime 是 bash 项目，无 `node_modules` 等需要 symlink 的大目录）
- 所有字段严格使用 `key: value`（冒号后单空格）格式，以匹配 `parse_cfg` 的正则 `(?<=^$1:\s)\S.*`

`feature-to-backlog` 和 `loop-backlog` 均通过 `fromClaudeMd()` 读取此配置，无需修改 skill 本体。

#### 目标 2：plugin skills 扩展

新增目录（从 archguard 复制）：

```
baime/plugin/skills/
├── backlog-setup/SKILL.md             ← 从 archguard 复制
├── feature-to-backlog/SKILL.md        ← 从 archguard 复制
├── task-to-backlog/SKILL.md           ← 从 archguard 复制
├── loop-backlog/SKILL.md              ← 从 archguard 复制
└── feature-developer/SKILL.md         ← 从 archguard 复制
```

`plugin/.claude-plugin/plugin.json` 的 `commands` 数组新增 5 项：

```json
"./skills/backlog-setup/SKILL.md",
"./skills/feature-to-backlog/SKILL.md",
"./skills/task-to-backlog/SKILL.md",
"./skills/loop-backlog/SKILL.md",
"./skills/feature-developer/SKILL.md"
```

`scripts/validate-plugin.sh` 的计数断言（两处，均需更新）：

```bash
EXPECTED_AGENTS=4    # 不变，新增的均为 skill，不是 agent
EXPECTED_SKILLS=22   # 原 17 + 新增 5
```

注意：`validate-plugin.sh` 第 142-143 行同时存在 `EXPECTED_AGENTS=4` 和 `EXPECTED_SKILLS=17` 两个断言，两行均需审查。`EXPECTED_AGENTS` 保持 4 不变（新增的 5 项均为 skill），`EXPECTED_SKILLS` 从 17 改为 22。

#### 目标 3：marketplace.json 修复

根目录 `.claude-plugin/marketplace.json`（已存在，格式正确，保持不变）：

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "baime",
  ...
  "plugins": [{"name": "baime", "source": "./plugin", "version": "1.0.0", ...}]
}
```

此文件 `source` 字段为 `"./plugin"`（相对路径字符串），符合 Claude Code 官方规范——相对路径 source 必须以 `./` 开头，解析时相对于 marketplace root（即 `.claude-plugin/` 的上级目录）。路径 `./plugin` 正确指向 `baime/plugin/` 目录。

`plugin/.claude-plugin/marketplace.json`（当前格式不合规，必须删除）：

```json
{"name": "baime", "owner": {...}, "plugins": [{"name": "baime", "source": {"type": "directory", "path": "."}}]}
```

此文件在 `plugin/` 子目录内，不应存在（plugin root 只需 `plugin.json`，不需要 `marketplace.json`）。`source` 字段的 `{"type": "directory", "path": "."}` 格式不是 Claude Code 的合法 source 类型（合法类型：字符串路径、`"github"` 对象、`"url"` 对象、`"git-subdir"` 对象、`"npm"` 对象），**必须删除此文件**。`validate-plugin.sh` 只读根目录的 `marketplace.json`，无需改动验证逻辑。

可选优化（非阻塞）：将根目录 `marketplace.json` 的 `$schema` 从 `"https://anthropic.com/claude-code/marketplace.schema.json"` 更新为官方 schema store 地址 `"https://json.schemastore.org/claude-code-marketplace.json"`，与 Anthropic 官方仓库保持一致。

### 3.2 执行顺序

建议按以下顺序执行（依赖关系决定）：

1. **修复 marketplace.json**（目标 3）— 解除 CI 阻塞，无依赖
2. **创建 `.claude/skills/` + 复制 4 个 skill**（目标 1 前置；loop-backlog 复制后修复两处硬编码 worktree 路径）
3. **创建 CLAUDE.md + L0 Config**（目标 1 完成）
4. **复制 5 个 skill 到 `plugin/skills/`**（目标 2 前置；loop-backlog 同样修复两处硬编码 worktree 路径）
5. **更新 `validate-plugin.sh` EXPECTED_SKILLS=22**（目标 2 完成）
6. **更新 `plugin.json` commands**（目标 2 完成）
7. bump version → push tag → 发布

---

## 权衡分析

### 权衡 A：project-local skill 路径（`.claude/skills/` vs 其他位置）

| 方案 | 优点 | 缺点 |
|------|------|------|
| `.claude/skills/`（采用） | Claude Code 原生 project-local skill 加载路径，无需额外配置 | `.claude/` 目录当前为空，需新建 |
| `scripts/skills/`（备选） | 与现有 scripts 目录对齐 | 非标准路径，Claude Code 无法自动发现 |

结论：`.claude/skills/` 是唯一标准路径，没有争议。

### 权衡 B：CLAUDE.md 中的 test-cmd 选择

| 选项 | 内容 | 适用性 |
|------|------|--------|
| `bash scripts/validate-plugin.sh`（采用） | 运行完整插件验证（JSON 合规、YAML frontmatter、计数断言、forbidden 检查） | 适合，验证 skill 文件质量 |
| `echo ok`（备选） | 空命令，跳过验证 | 不推荐，失去 DoD 保障 |
| `make validate`（备选） | Makefile 目标 | 依赖 Makefile 存在，当前已有 Makefile，可用 |

结论：`bash scripts/validate-plugin.sh` 最直接，不依赖 Makefile 是否包含 validate 目标。

### 权衡 C：是否将 `feature-to-issues` 也并入 plugin

archguard 还有一个 `feature-to-issues` skill（将特性转换为 GitHub Issues，`allowed-tools: Read, Glob, Grep, Bash, Agent`）。

- **不引入（采用）**：该 skill 专门生成 GitHub Issues 并通过 `Bash`（`gh` CLI）调用 GitHub API，与 GitHub 深度耦合；对不使用 GitHub Issues 工作流的用户毫无意义；核心工作流仅需 5 个 skill。
- 引入（备选）：增加 1 个 skill，总计 23 个，validate-plugin.sh 需改为 `EXPECTED_SKILLS=23`。

结论：暂不引入，保持最小化。

### 权衡 D：skill 内容是否需要修改后再引入

`loop-backlog` 的 `ScheduleWakeup` 工具调用是 Claude Code 标准功能（非 archguard 特有），baime 环境同样支持。`feature-developer` 的 Agent tool 调用方式无项目差异。所有 5 个 skill 均通过 `fromClaudeMd()` 读取 project-specific 配置（`test-cmd`、`test-all`、`doc-path`、`worktree-symlinks`），配置部分可原样复用。

`loop-backlog` 的 `loadConfig` 解析逻辑：`parse_cfg()` 正则匹配 `(?<=^$1:\s)\S.*`，如果某字段在 CLAUDE.md 的 `## L0 Config` section 中留空（如 `worktree-symlinks:` 后无内容），`parse_cfg` 返回空字符串，`loop-backlog` 会将 `"none"` 规范化为空字符串，留空等价于"无需 symlinks"，是合法语法。

**【关键问题：loop-backlog 有硬编码的 archguard worktree 路径】**

检查 archguard 原始 `loop-backlog/SKILL.md` 可知，`reap` 和 `withWorktree` 两处均使用了硬编码的项目名：

```bash
WORKTREE="${REPO_ROOT}/../archguard-${TASK_ID}"  # 出现两次：reap 和 withWorktree
```

在 baime 项目中运行时，worktree 路径应为 `${REPO_ROOT}/../baime-${TASK_ID}`。正确做法是复制后将硬编码的 `archguard` 替换为动态项目名：

```bash
PROJECT_NAME=$(basename "$REPO_ROOT")
WORKTREE="${REPO_ROOT}/../${PROJECT_NAME}-${TASK_ID}"
```

两处替换均需进行（`reap` 和 `withWorktree` 各一处）。

`feature-developer` 的 Agent tool 调用无项目特定路径，无需修改。

结论：**`loop-backlog` 的 SKILL.md 复制后必须修改两处硬编码路径**，使用 `PROJECT_NAME=$(basename "$REPO_ROOT")` 动态派生；`feature-developer`、`backlog-setup`、`feature-to-backlog`、`task-to-backlog` 无硬编码，可原样复制。

### 权衡 E：install.sh 是否需要更改以支持新增 5 个 skill

`install.sh` 的 skill 安装逻辑（第 36-44 行）使用 `for skill_dir in "$INSTALL_DIR/skills"/*/` 动态遍历所有 skill 目录，无硬编码 skill 列表。新增 5 个 skill 后，`install.sh` **无需任何改动**，安装时自动包含全部 22 个 skill。

结论：install.sh 不需要修改。

---

## 风险

### 风险 1：validate-plugin.sh 的 `plugin/` 子目录内 marketplace.json 干扰

- **描述**：`plugin/.claude-plugin/marketplace.json` 当前存在且 `source` 格式不合规（非法的 `{"type": "directory", "path": "."}` 格式），但 `validate-plugin.sh` 读的是根目录 `$REPO_ROOT/.claude-plugin/marketplace.json`，不读 plugin 子目录内的版本。因此不影响 CI，但该文件会误导 Claude Code 将 `plugin/` 目录本身识别为 marketplace，可能引发意外行为。
- **缓解**：在目标 3 实施时删除 `plugin/.claude-plugin/marketplace.json`，消除歧义。此文件的存在无任何合理用途，必须删除。

### 风险 2：EXPECTED_SKILLS 计数随新增 skill 漂移

- **描述**：每次 `plugin/skills/` 新增目录，必须同步更新 `validate-plugin.sh` 的 `EXPECTED_SKILLS`，否则 CI 失败。
- **缓解**：在提交 PR 时将 validate-plugin.sh 的修改与 skill 文件变更绑定在同一 commit。长期可考虑将 EXPECTED_SKILLS 从硬编码改为动态计数（`find plugin/skills -maxdepth 1 -mindepth 1 -type d | wc -l`），但会失去意外新增的保护。

### 风险 3：loop-backlog 的 `ScheduleWakeup` 在 baime 开发环境不可用

- **描述**：`loop-backlog` 的 `allowed-tools` 包含 `ScheduleWakeup`，该工具在 Claude Code 的 schedule skill 体系下可用，但具体环境需验证。
- **缓解**：如果 `ScheduleWakeup` 不可用，`loop-backlog` 仍可手动触发执行单个任务，只是无法自驱循环。不影响 `feature-to-backlog` 和 `task-to-backlog` 的使用。

### 风险 4：CLAUDE.md 的 L0 Config 被 loop-backlog 跳过

- **描述**：`loop-backlog`（及 `feature-to-backlog`）的 `loadConfig` 优先读 `fromClaudeMd()`，若 CLAUDE.md 的 `## L0 Config` section 格式不符合预期，会 fallback 到 `autoDetect()`。baime 项目没有 `package.json`/`go.mod`/`Cargo.toml`，autoDetect 会返回 Unknown，testCmd 回退为 `make test`，但 Makefile 的 `test` 目标未指向 `validate-plugin.sh`，DoD 会静默失效。
- **parse_cfg 语法约束**：解析正则为 `(?<=^$1:\s)\S.*`，要求字段值与冒号之间有且仅有一个空格，且值不能以空格开头。例如 `test-cmd: bash scripts/validate-plugin.sh` 合法，`test-cmd:bash scripts/validate-plugin.sh`（无空格）或 `test-cmd:  bash ...`（两空格）均无法被正确解析。
- **缓解**：在 CLAUDE.md 中严格按 `key: value`（单空格）格式书写 L0 Config；在实施时运行 `bash -c 'awk "/^## L0 Config/{found=1; next} found && /^## /{exit} found{print}" CLAUDE.md'` 验证 section 可被正确提取。

### 风险 5：版本号与新 skill 数量的 marketplace.json 描述文字过时

- **描述**：根目录 `.claude-plugin/marketplace.json` 中描述文字当前为"19 validated skills and 6 specialized agents"（历史数据），与实际不符（当前为 17 skills 4 agents）；同时 `plugin/.claude-plugin/plugin.json` 的 `description` 字段也写着"17 validated skills and 4 specialized agents"。加入 5 个新 skill 后，两个文件均需同步更新为"22 validated skills and 4 specialized agents"。
- **影响文件**：
  - `.claude-plugin/marketplace.json` 的 `plugins[0].description`
  - `plugin/.claude-plugin/plugin.json` 的 `description`
- **缓解**：在 bump-version 步骤同步更新两个文件中的 description 字段。

### 风险 6：install.sh 的 extraKnownMarketplaces source 格式可能不合规（超出本 proposal 范围）

- **描述**：`install.sh` 写入 `settings.json` 时使用 `{"source": "directory", "path": $dir}` 格式，但 Claude Code 官方文档中 `extraKnownMarketplaces` 的 source 仅文档化了 `"github"`, `"url"`, `"git-subdir"` 等类型；`"directory"` 类型未在公开文档中出现。此问题在使用 `install.sh` 安装时可能导致 marketplace 无法被 Claude Code 正确识别。
- **缓解**：此 bug 超出本 proposal 范围，需另开 issue 跟踪；本 proposal 执行不依赖 install.sh 的正确性（CI 验证通过 `validate-plugin.sh`，不通过 install.sh）。

---

## 实施优先级

| 顺序 | 动作 | 影响范围 | 阻塞关系 |
|------|------|---------|---------|
| 1 | 删除 `plugin/.claude-plugin/marketplace.json` | CI 消歧义 | 无 |
| 2 | 创建 `.claude/skills/` + 复制 4 个 skill（含修复 loop-backlog worktree 路径） | baime 开发流程 | 无 |
| 3 | 创建 `CLAUDE.md` + L0 Config | 完成目标 1 | 依赖步骤 2 |
| 4 | 复制 5 个 skill 到 `plugin/skills/`（含修复 loop-backlog worktree 路径） | 用户可见功能 | 无 |
| 5 | 更新 `plugin/.claude-plugin/plugin.json` commands | 用户安装完整性 | 依赖步骤 4 |
| 6 | 更新 `validate-plugin.sh` EXPECTED_SKILLS=22 | CI 通过 | 依赖步骤 4 |
| 7 | 更新 `.claude-plugin/marketplace.json` 和 `plugin.json` 中的 description 数字 | 元数据一致性 | 依赖步骤 4 |
| 8 | bump version + push tag + 发布 | 版本发布 | 依赖步骤 1-7 |

步骤 1-3（目标 1+3）和步骤 4-6（目标 2）可并行执行。步骤 7 依赖步骤 4 确定最终 skill 数量后更新。
