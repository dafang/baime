## Background

BAIME 的核心交付资产是 SKILL.md——一种结合了 YAML frontmatter、Haskell-like 形式规格 DSL、嵌入式 shell 脚本和 Implementation 文档的复合工程制品。这类制品既不是普通源代码（无编译器、无类型检查器），也不是纯文档（其中的脚本和规格会被 LLM 逐字执行）。

当前的开发流程在 design/review 阶段投入了大量精力（proposal review、plan review、多轮迭代），但在实现完成之后没有任何自动化的回归门控。结果是：每次 skill 改动后，所有验证依赖人工执行和观察。以 loop-backlog 的近期开发为例，在同一会话中发现了 7 个 bug，全部在人工运行后才暴露，而非在写入 SKILL.md 时被截获。

现有的 `validate-plugin.sh` 只检查 JSON manifest 合法性、YAML frontmatter 有无必要字段、symlink 一致性，以及少数 hardcoded grep 规则，无法覆盖 SKILL.md 内部一致性。`test-loop-backlog-skill-monitor.sh` / `test-loop-backlog-skill-template.sh` 是手写 grep 测试，已随 skill 演进而过时，因为测试知识存在于外部文件，作者修改 spec 时无提示需同步更新测试。TASK-19 提出了 author-time 静态分析，TASK-20 提出了 execution-time manifest 校验，两者聚焦规格文本的 DSL 语义正确性。本任务提出覆盖完整质量层次的分层框架，将这两项作为 Layer 0 的上游，并向上延伸至可抽取纯函数单测（Layer 1）、co-located 结构性 contract（Layer 2）和面向可观测结果的行为 smoke test（Layer 3）。

## Goals

1. **[Layer 0]** `validate-plugin.sh` 运行时能自动检测 SKILL.md 制品结构问题：Spec 节中被调用的函数在 Implementation 节有对应 section；`allowed-tools` 字段覆盖文件中实际出现的工具关键词；嵌入脚本的 `daemon-version` tag 与 SKILL.md 声明一致。检测到违规时 `validate-plugin.sh` 以非零退出码退出。

2. **[Layer 1]** 含有可抽取纯函数测试的 SKILL.md（如现有 `ensureDaemonTest` 模式），其单测在 `validate-plugin.sh` 运行时被自动发现并执行，无需手动注册；新 skill 遵循相同路径约定后自动纳入。

3. **[Layer 2]** SKILL.md frontmatter 支持可选 `contracts:` 字段，每条规则声明 grep/not-grep 断言及目标（self 或外部脚本路径）；`validate-plugin.sh` 解析并执行这些规则；`test-loop-backlog-skill-monitor.sh` 等现有外部脚本的逻辑迁移到对应 skill 的 `contracts:` 字段后可被删除。

4. **[Layer 3]** 每个 skill 可选包含 `smoke/` 目录（含 `setup.sh`、`expect.sh`、`scenario.md`）；`expect.sh` 只使用 shell 断言（文件存在、git log 内容、task 状态），不依赖 LLM 判断结果；提供独立手动触发入口 `bash scripts/run-smoke-test.sh <skill-name>`，不集成到 `validate-plugin.sh`。

5. **[DoD 规范化]** `task-to-backlog` 和 `feature-to-backlog` 的 DoD 模板新增强制项：Layer 0–2 检查通过；新增 skill 的 `contracts:` 字段覆盖本 skill 的关键行为约束。新 skill 实现完成后 `bash scripts/validate-plugin.sh` 绿色通过即可机械验证此要求。

## Proposed Approach

### Layer 0 — 静态内部一致性检查（无 LLM，fast）

在 `validate-plugin.sh` 中增加 `validate_skill_internals()` 函数，对每个 SKILL.md 执行三项检查：

**函数覆盖检查**：从 `## Spec` 节提取所有 `funcName(` 调用模式，从 `## Implementation` 节提取所有 `### funcName` 标题，计算差集并报告缺失覆盖。初期采用保守规则（精确 `### funcName` 标题匹配），宁可漏报也避免误报阻塞 CI。对尚无 `## Implementation` 节的 skill 跳过此检查（与 TASK-16 的规格补全工作协同）。

**allowed-tools 完整性检查**：扫描 SKILL.md 全文中出现的已知工具关键词集合（Bash、Read、Write、Edit、Monitor、Agent 等），与 frontmatter `allowed-tools` 字段比对，报告未声明的工具使用。

**版本标签一致性检查**：若文件内嵌 `// daemon-version: vN` 或 `# daemon-version: vN` 注释，与 frontmatter 对应字段比对。仅对声明了版本字段的 skill 启用，无声明则跳过。

三项检查全部在现有 shell/python3 框架内实现，无新依赖。与 TASK-19 的 undefined reference detection 和 type name conflict detection 形成互补——TASK-19 聚焦 DSL 语义，Layer 0 聚焦制品结构完整性。两者共用 `validate-plugin.sh` 入口但实现独立。

### Layer 1 — 可抽取纯函数单测自动发现（无 LLM，fast）

在 `validate-plugin.sh` 中增加 `run_skill_unit_tests()` 函数：扫描约定路径（`scripts/<skill-name>.test.js` 或 `scripts/<skill-name>.test.sh`），若文件存在则执行并汇报结果。`loop-backlog-daemon.test.js` 已是此模式的原型，现有的 `ensureDaemonTest` 在 bootstrap 时写入并运行该文件，Layer 1 在 `validate-plugin.sh` 中增加第二个触发点（静态注册），使其脱离 skill 执行路径也能运行。

新 skill 遵循命名约定后自动纳入，无需修改 `validate-plugin.sh`。

### Layer 2 — Co-located 结构性 Contract 测试（无 LLM，fast）

SKILL.md frontmatter 新增可选 `contracts:` 字段：

```yaml
contracts:
  - grep: "Monitor(persistent=true"
    target: self
  - not-grep: "schedule("
    target: self
  - grep: "ensureDaemonScript"
    target: self
```

`validate-plugin.sh` 的 frontmatter 解析扩展为同时读取并执行 `contracts:` 规则。规则与 SKILL.md 主体同文件提交，当 spec 演进导致旧断言过时时，作者若不同步更新 contracts，CI 会立即失败，消除 stale test 的漏窗口。现有 `test-loop-backlog-skill-monitor.sh` 的四条 grep 断言可直接迁移为 loop-backlog 的 `contracts:` 字段，之后删除外部脚本文件。

初期 `contracts:` 为可选字段；新 skill 实现时（通过 DoD 规范化 Goal 5）强制要求。

### Layer 3 — 行为 Smoke Test（需 LLM，slow，可选）

每个 skill 可选包含 `smoke/` 目录：

```
plugin/skills/<skill-name>/smoke/
  setup.sh      # 在临时 git repo 中创建 backlog fixture（task 状态、文件等）
  scenario.md   # 给 subagent 的自然语言触发指令
  expect.sh     # 纯 shell 断言：task 状态、git log 内容、文件存在性
```

触发：`bash scripts/run-smoke-test.sh <skill-name>`。Subagent 在 fixture repo 中执行 skill，`expect.sh` 对 fixture repo 做断言，无需 LLM 判断。不集成到 `validate-plugin.sh`（避免 CI 依赖 LLM）。初期只为 loop-backlog 和 feature-to-backlog 建立 smoke test，降低维护面。

### DoD 规范化

`task-to-backlog` 和 `feature-to-backlog` Implementation Plan 模板的最终阶段新增：

```
- [ ] bash scripts/validate-plugin.sh 绿色通过（含 Layer 0-2 检查）
- [ ] 新 SKILL.md 的 contracts: 字段覆盖本 skill 的关键行为约束（≥ 2 条）
```

## Trade-offs and Risks

### Trade-offs

**Layer 0 误报率控制**：函数名提取使用 regex，对 DSL 中 lambda 表达式、高阶函数、管道符等语法可能产生漏报。初期采用保守规则，只对有完整 `## Implementation` 节的 skill 启用函数覆盖检查，避免对存量 16 个无规格 skill 产生大量噪音。

**contracts: 表达能力上限**：grep/not-grep 只能捕获字面量存在性，无法表达顺序、数量、语义约束。对于复杂约束，需 Layer 3 smoke test 或人工 review。不引入 YAML 内嵌表达式语言，避免在 frontmatter 内部创建新 DSL。

**Layer 3 的 LLM 依赖**：smoke test 需要 LLM 执行 skill，单次运行成本和时间不可预测，不适合每次提交触发。定位为"大版本变更前的手动验收门"或可选 DoD item。

**与 TASK-19/20 的边界清晰性**：三个任务共用 `validate-plugin.sh` 入口，但检查对象不同——TASK-19 检查 DSL 语义（undefined ref、type conflict），TASK-20 检查 execution-time manifest，本任务检查制品结构和测试框架。实现时需明确哪个任务负责往 `validate-plugin.sh` 注入哪一节，避免合并冲突。

### Risks

**Layer 0 对存量 skill 的破坏性**：23 个现有 skill 中约 16 个无 `## Implementation` 节（实测：`grep -L "## Implementation"` 返回 16 个），对它们启用函数覆盖检查会立即产生大量 FAIL。必须在实现时决策跳过策略，否则 `validate-plugin.sh` 第一次运行即全红。

**contracts: 的维护负担**：若作者在修改 spec 时遗忘同步更新 contracts，CI 将产生误报（与 stale test 方向相反）。代码 review 仍需关注 contracts 与 spec 的一致性；不能完全消除此风险，只能缩短暴露窗口。

**smoke/ fixture 腐化**：`setup.sh` 创建的 fixture 状态随 backlog CLI 版本或 skill 接口演进可能过时。初期限定 loop-backlog 等高风险 skill 建立 smoke test，接受每次大版本升级时需手动验证和更新 fixture 的维护成本。
