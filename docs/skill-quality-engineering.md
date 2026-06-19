# Skill.md 质量保障工程

> 本文档综合 2026-06-14 至 2026-06-19 关于 prompt/skill 工程化的讨论，以及 archguard 项目的 ADR 合规检查、AI 认知分析等交叉实验，作为 BAIME 插件 skill 开发的设计参考。

---

## 1. 核心命题

**Prompt 是代码资产，不是注释。**

"写得越详细"不等于"质量越高"。Prompt 越长，带来的不是更强的约束，而是更多的上下文噪声、触发冲突和维护成本。真正重要的不是长度，而是**约束密度**——每单位 token 里有多少条可执行、可验证的要求。

三条工程准则：

1. 每增加一条行为要求，必须增加或关联一个可验证的测试
2. 每增加一段 always-on 内容，必须证明它比 skill / hook / subagent 更合适
3. Prompt 变更的质量不由文本 diff 决定，而由行为 diff 决定

---

## 2. Skill 分类学

BAIME 的 23 个 skill 在本质上分为三类，每类需要不同的 QA 机制：

### 2.1 Operator Skills（算子型）

有明确的 λ 入口、类型签名和分支结构。用户显式触发（`/skill-name`），输入窄而离散，输出是具体制品，有可验证的 postcondition。

```
loop-backlog, task-from-template, task-to-backlog,
feature-to-backlog, backlog-setup
```

测试目标：**模型能否按照 λ spec 执行正确的分支**。

### 2.2 Methodology Skills（方法论型）

有宽泛的 `ProjectContext / CodebaseContext` 输入，输出是指导模型执行多小时工程工作的参考资料。内部应包含 Operator 入口（Spec 节）和参考库（Implementation 节）两层，但当前多数 skill 把两者混在一起。

```
ci-cd-optimization, testing-strategy, cross-cutting-concerns,
dependency-health, knowledge-transfer, observability-instrumentation,
technical-debt-management, documentation-management, build-quality-gates,
baseline-quality-assessment
```

测试目标：**Spec 节的约束是否完整，Implementation 节是否与 Spec 对齐**。

### 2.3 BAIME-Meta Skills（元方法论型）

描述 BAIME 方法论本身的运作方式，受众是运行 BAIME 实验的研究者，没有清晰的"用户触发 → 产出制品"路径。本质上是文档，不是可调用的 operator。

```
methodology-bootstrapping, rapid-convergence,
agent-prompt-evolution
```

测试目标：**内容完整性和内部一致性**，不应强行套用 decision unit test。

---

## 3. 约束密度与内容分级

### 3.1 约束密度与 AI 认知成本

两个互补的质量维度，分别从作者和读者视角衡量同一件事：

**约束密度**（作者视角）：每单位 token 里有多少可执行、可验证的要求。

```
constraint_density = testable_requirements / token_count
```

可测试的 requirement 必须满足至少一个条件：
- 有明确触发条件：WHEN / IF / FOR / BEFORE / AFTER
- 有明确动作：read / write / run / ask / refuse / report
- 有明确边界：allowed paths / forbidden paths / commands
- 有明确验收：exit code / exact string / file diff / tool trace

"be careful"、"best practices"、"high quality" 不是可测试的 requirement。

**AI 认知成本**（读者视角）：LLM 处理 SKILL.md 中某个区域所需的 context 代价。来源于 archguard 项目对"面向 AI 的代码分析"的探索（2026-06-14）。

认知成本高的典型特征：
- 关键约束分散在文档中后段（"Lost in the Middle" 效应）
- 大量 P3 内容（案例数据、配置模板）在 P1 约束之前出现
- section 之间交叉引用密度低（孤岛内容：写了但从不被引用）

两个指标可能独立劣化：约束密度高但认知成本也高，说明约束写了但位置不对。`build-quality-gates` 即为此类——有验证要求，但被埋在 1879 行 P3 内容中间。

**实证支撑：粒度**（来自 archguard granularity 实验，2026-06-11）：对 LLM 推理任务，给出"比任务所需更细粒度的表示"（L5 源码）会显著**损害**性能，而非提升。使用含调用边的中间表示（L3）比原始源码（L5）的 F1 提升 0.128–0.63（p<0.02）。这意味着无关 P3 内容不只是零价值的噪声——它是**主动干扰**。SKILL.md 头部的案例描述和历史数据会让模型处理 P1 Contract 时付出更高代价。

**修正（来自 Exp-A P3 消融实验，2026-06-19）**：上述结论适用于与当前执行步骤无关的 P3 内容（历史数据、配置模板、案例描述）。但若 `## Implementation` 中直接规定了当前步骤的判断准则（执行规格型 P3），则该内容是**关键上下文而非干扰**。实验以 task-from-template 的 freshnessCheck 为对象：V0（Spec only）Haiku 准确率 0.76，V2（完整 SKILL.md，含 Implementation）0.92，**+16pp**；V3（V2 + 150 行无关噪声）0.90，略低于 V2 但仍大幅优于 V0。结论：应移除的是案例数据和历史统计，而非执行步骤的判断准则——后者对模型正确决策是必要的。

**实证支撑：嵌入结构化数据时的格式选择**（来自 archguard format-encoding 实验，2026-06-12）：在 545 实体的 ArchGuard 类图上测试 8 种序列化格式对 LLM 查询精度的影响（Haiku 主模型，H1 在 p=0.007 水平确认）。**适用结论**：Mermaid 总体 F1 0.286，A 类拓扑查询 0.04——若 SKILL.md 需要嵌入结构化图数据（架构快照、依赖矩阵），不应使用 Mermaid；Custom DSL F1 0.643 与 json-edge-list 0.671 无显著差异，说明自定义格式不比标准格式差。**不适用范围**：实验的任务类型是图查询（"谁的 in-degree 最高"），与 SKILL.md 的任务类型（执行规格决策）根本不同；Haskell ADT nesting depth 225 是 545 实体图递归展开的产物，BAIME λ spec 最大嵌套约 3–4 层，不在这个实验的覆盖范围内。

### 3.2 P0/P1/P2/P3 分级

| 优先级 | 类型 | 适合的载体 |
|---|---|---|
| P0 | Safety / Security | Hook、sandbox policy，不能只靠 prompt |
| P1 | Workflow Contract | `contracts:` 断言、fixtures/*.yaml decision test |
| P2 | Quality Preference | LLM judge、code review |
| P3 | Background Context | `## Implementation` 节、外部 docs，不适合 always-on |

**常见反模式**：把 P3 内容（历史实验数据、配置模板、案例描述）写在 skill 头部当作 P1，导致每次触发都加载大量无法被约束的内容。`build-quality-gates` 是典型案例（1879 行，P3 内容占 90%，contracts 仅 1 条）。

### 3.3 作用域正确性

| 加载时机 | 适合的内容 | 代价 |
|---|---|---|
| Always-on（CLAUDE.md） | P0/P1，绝对约束，最高频 workflow | 每次会话全量加载 |
| Skill description | 触发条件，精确、互斥 | 每次会话加载（仅 description） |
| Skill body | P1 Spec + P3 Reference | 触发后加载全文 |
| Hook / script | 可程序化的强约束 | 不占模型上下文 |
| Subagent | 需要隔离状态的复杂调查 | Fresh isolated context |
| MCP tool schema | 工具定义，在 context 里占固定位置 | 每条工具定义约 200–800 tokens |

**Context Budget 视角**（来自 archguard ADR-006，25K token MCP 工具预算约束）：会话可用的有效 context 是有限的，消耗来自多个方向：

```
context_budget = conversation_history
               + CLAUDE.md（always-on）
               + skill body（被触发时）
               + MCP schema（所有已注册工具）
               + tool outputs（工具返回值）
```

任何一项超出预算都会压缩其他项，最终影响决策质量。SKILL.md 的行数软警告（TASK-33）和 MCP 工具数量约束（ADR-006）是同一个 budget 问题的两个入口，应该在同一个框架下考虑。

---

## 4. 静态质量保障（Layer 0–2）

### 4.1 结构完整性（Layer 0）

`validate-plugin.sh` 执行的机器检查：

- **函数覆盖**：`## Spec` 里调用的函数，在 `## Implementation` 里有对应 section
- **allowed-tools 完整性**：SKILL.md 正文中出现的工具关键词，均在 frontmatter 声明
- **contracts 密度软警告**：skill 行数 > 500 且 contracts 条数 < 3，输出 WARNING（TASK-33）

### 4.2 纯函数单测（Layer 1）

约定路径：`scripts/<skill-name>.test.js` 或 `scripts/<skill-name>.test.sh`。

`validate-plugin.sh` 自动发现并执行，无需手动注册。适用于 skill 中可提取的纯函数逻辑（如 `ensureDaemon`、`detectLang`）。

### 4.3 Co-located 合约断言（Layer 2）

frontmatter `contracts:` 字段，每条规则声明 grep 或 not-grep 断言：

```yaml
contracts:
  - grep: "Monitor(persistent=true"
    target: self
  - not-grep: "ScheduleWakeup"
    target: self
  - grep: "## Shutdown"
    target: self
```

设计原则：
- 断言与 spec 同文件提交，spec 演进时若不同步更新 contracts，CI 立即失败
- 优先断言**排他性约束**（not-grep）和**关键函数名**（grep），而非泛化关键词
- 每个 Operator Skill 目标 ≥ 3 条；每个 Methodology Skill 目标 ≥ 2 条

**豁免注释机制**（来自 archguard ADR 合规检查实践）：contracts 断言应支持在 SKILL.md 中标注合理豁免，避免随着 skill 演化而被删除：

```yaml
contracts:
  - grep: "Monitor(persistent=true"
    target: self
  - not-grep: "ScheduleWakeup"
    target: self
    ignore-if: "## Experimental"   # 豁免：实验性节中允许出现
```

豁免的存在本身就是文档：未来维护者看到 `ignore-if` 时会思考豁免条件是否仍然成立，而不是直接删掉断言。没有豁免机制的硬断言，随着 skill 演化会变成维护负担，最终被整条删除——比豁免更坏的结果。

当前覆盖状态（2026-06-19）：18/23 有 contracts，待补充：feature-to-backlog、task-from-template、task-to-backlog、methodology-bootstrapping、agent-prompt-evolution（TASK-35）。

### 4.4 Trigger 重叠检测

`validate-plugin.sh` Layer 0 中的 n-gram Jaccard 检测，当前阈值 0.45。

Jaccard 只检测词法重叠，捕获不了"用不同词表达相同功能"的语义重叠。后续工作（TASK-32）：
1. 计算所有 skill 对在 0.20–0.45 区间内的分数，人工标注 TRUE_OVERLAP vs FALSE_POSITIVE
2. 对 TRUE_OVERLAP 对改写 description，增加"Do not use when X"短语
3. 将阈值从 0.45 收紧至 0.35

---

## 5. 动态质量保障（Layer 2.5–3）

### 5.1 现有体系的根本性缺口

Layer 0–2 测的是 **SKILL.md 文件的结构属性**，不是**模型读完 SKILL.md 后的推理行为**。

```
contracts: grep: "freshnessCheck"
```

这在测"文件里有没有这个字符串"，而不是"模型遇到 STALE verdict 时会不会真的停下来"。两者之间的跳跃就是 Layer 2.5 要填补的空白。

### 5.2 Decision Unit Tests（Layer 2.5）

> **Exp-B Oracle 标定结论（2026-06-19）**：
> - Class A（binary-gate / freshnessCheck）：Haiku F1 = 0.70，未达阈值 0.85 → **输出 WARNING 而非 FAIL，需人工审查**
> - Class B（invariant-check / reviewPlan）：Haiku F1 = 0.625，未达阈值 0.70 → **输出 WARNING 而非 FAIL，需人工审查**
> - Class C（branch-selection / verifyDod）：Haiku F1 = 1.00，达阈值 0.80 → **可接入 CI 自动化**
>
> 实验数据：`experiments/skill-quality/artifacts/analysis/exp-b-results.json`

**仅适用于 Operator Skills**。从 λ spec 的分支结构机械提取测试用例：

```yaml
# plugin/skills/task-from-template/fixtures/freshness-stale.yaml
name: freshness-check-stale
step: freshnessCheck
state:
  template_last_used: "2026-04-01"
  recent_changes:
    - "feat: loop-backlog now supports parallel workers (2026-06-15)"
expect:
  result_type: Stopped
  reason_contains: "STALE"
  must_not_call: createTask

# plugin/skills/task-from-template/fixtures/freshness-fresh.yaml
name: freshness-check-fresh
step: freshnessCheck
state:
  template_last_used: "2026-06-18"
  recent_changes:
    - "docs: typo fix (2026-06-17)"
expect:
  result_type: BacklogTask
  must_call: [createTask, updateLastUsed]
```

Runner 设计原则：
- 每个 fixture 触发一次 LLM call（Haiku 优先，速度快、成本低）——archguard format-encoding 实验以 Haiku 为主模型（k=5 runs）完成 545 实体的图推理任务，在 p=0.007 水平区分了格式优劣，证明 Haiku 具备工程级推理任务所需的区分能力
- 只注入相关的 spec section，不是整个 SKILL.md
- 输出强制 JSON，直接断言，不用 LLM judge
- `validate-plugin.sh` 仅在 `fixtures/` 目录存在时触发，不强制所有 skill

**完整验证流水线**（来自 archguard ADR 检查实践，2026-06-15）：

```
Layer 2 contracts:（机械 grep）
    → 发现可疑（FAIL 或 WARNING）
        ↓ 若存在 fixtures/
Layer 2.5 decision test（Haiku API）
    → 确认为 TRUE_VIOLATION → CI FAIL，提示修改 spec
    → 确认为 FALSE_ALARM   → 在 SKILL.md 添加 ignore-if 注释 → 重新运行
        ↓ PASS
继续 Layer 3 smoke test
```

这条流水线解决了"机械检查误报"问题：grep 是词法的，不能理解语义，必然产生 false alarm；用 LLM 在 Layer 2.5 做一次语义确认，既不放弃机械检查的速度，也不让误报阻塞正常开发。archguard 在 ADR-006 合规检查中验证了这个模式的可行性（pre-commit hook → 可疑情况 → Claude Code 语义确认 → 代码加注释 → 自动重试 commit）。

覆盖目标（每个 Operator Skill）：
- 每条 λ 条件分支至少一个正例
- 每条 `require()` 前置条件至少一个违反反例
- 每种返回类型（如 `BacklogTask | Stopped`）至少一个用例

### 5.3 端到端 Smoke Tests（Layer 3）

每个 skill 可选 `smoke/` 目录：

```
plugin/skills/<skill-name>/smoke/
  setup.sh      # 创建 fixture 环境（临时 git repo、backlog state）
  run.sh        # 触发 skill（可以是 backlog CLI 命令序列）
  expect.sh     # Shell 断言（文件存在、git log、task 状态）
```

`expect.sh` 只用 shell 断言，不依赖 LLM 判断结果——测的是可观察的系统状态变化，不是输出内容质量。

### 5.4 Trace Schema（policy 与 trace 的连接）

loop-backlog 执行时，Monitor 工具已经捕获事件流，但没有结构化为"(state, decision, spec_rule_applied)"三元组。

目标格式：

```json
{
  "task_id": "TASK-35",
  "skill": "task-to-backlog",
  "decisions": [
    {
      "step": "loadConfig",
      "state": {"claude_md_has_l0_config": false},
      "applied_rule": "autoDetect()",
      "outcome": {"docPath": "docs"}
    }
  ]
}
```

两个用途：
1. **回归检测**：相同输入的 decisions 序列应保持稳定
2. **Fixture 生成**：从真实执行中提取 state，比手写 synthetic state 更贴近实际分布

---

## 6. Methodology Skills 的转换分析

### 6.1 A 类：可直接转为 Operator Skills

输出是单一具体制品，边界清晰：

| skill | 转换后的 λ |
|---|---|
| `dependency-health` | `λ(manifest: FilePath) → DependencyReport` |
| `knowledge-transfer` | `λ(level: Day1\|Week1\|Month1) → OnboardingDoc` |
| `build-quality-gates` | `λ(repo: Repo) → GateConfig`（已有 Trigger + Boundaries） |

转换成本：收紧输入类型定义，加入具体 postconditions，写 fixtures。

### 6.2 B 类：可拆分为"Operator 入口 + 参考库"

现有 skill 把 P1 Spec 和 P3 Reference 混在一起。解法是**结构分离**而不是内容删减：

```
## Spec（Operator 部分）         ← contracts: 覆盖这里
λ(lang: Go, layer: Service) → InstrumentedCode
require(target_dir_exists(layer))
ensure(tests_pass_after_instrumentation())

## Implementation（Reference 部分） ← 按需参考，不进入 contracts 计算
### Go slog Patterns
[详细内容]
```

适用 skill：ci-cd-optimization、testing-strategy、cross-cutting-concerns、observability-instrumentation、technical-debt-management、documentation-management、baseline-quality-assessment。

转换成本：明确枚举输入类型（如 `ci_platform: GitHub|GitLab`），把 P3 内容移至 Implementation 节，在 Spec 节加入具体 postconditions 和 contracts。

### 6.3 C 类：保留为文档，退出 skill 激活系统

没有清晰的"用户触发 → 制品"路径，强行套 operator 模式只会产生形式合规而内容空洞的 spec：

```
methodology-bootstrapping, rapid-convergence, agent-prompt-evolution
```

建议处理：在 description 加注 "Reference material"，从 Claude Code skill 激活候选中移除（或降为内部文档），停止对其做无效的 contracts 测试。

---

## 7. Rule Coverage Matrix

测试覆盖不看行数，看规则类型的覆盖：

| | activation | ordering | forbidden | verification | failure-path |
|---|---|---|---|---|---|
| `loop-backlog` | ✓ contracts | ✓ unit test | ✓ contracts | ✓ smoke | ✓ unit test |
| `task-from-template` | ✓ smoke | ✗ | ✗ | ✓ smoke | ✗ |
| `task-to-backlog` | ✗ | ✗ | ✗ | ✗ | ✗ |
| `feature-to-backlog` | ✗ | ✗ | ✗ | ✗ | ✗ |
| Methodology Skills | — | — | ✓ contracts(部分) | ✓ contracts(部分) | — |

`loop-backlog` 是唯一在多维度有覆盖的 skill，对应它也是最活跃维护的 skill（10 次提交 vs 其他 skill 的 2–3 次）。**约束密度高的 skill 会吸引维护；约束密度低的 skill 会腐化。**

---

## 8. 当前状态与优先路径

### 已完成

- Layer 0 结构检查（validate-plugin.sh）
- Layer 1 纯函数单测（loop-backlog daemon test）
- Layer 2 contracts（18/23 skill，TASK-16 后）
- Trigger 重叠检测，threshold 0.45（TASK-30）

### 进行中

| Task | 内容 | 优先级 |
|---|---|---|
| TASK-32 | 语义重叠分析 + description 改写 + threshold → 0.35 | Medium |
| TASK-33 | contracts 密度软警告（>500 行且 <3 条） | Medium |
| TASK-34 | build-quality-gates P3 内容降级，P1 提炼 | Low |
| TASK-35 | 5 个无 contracts skill 补充断言 | Medium |

### 待实施（Layer 2.5）

1. 定义 `fixtures/*.yaml` 格式标准（参见第 5.2 节）
2. 实现 `scripts/run-decision-tests.py`（Haiku API，JSON 输出断言）
3. 为 `task-from-template` 写首批 fixtures（FRESH/STALE 两个分支）
4. 将 Layer 2.5 接入 `validate-plugin.sh`（发现 `fixtures/` 目录时触发）

执行顺序建议：**TASK-35 → TASK-33 → TASK-32 → Layer 2.5 → TASK-34**

先补齐机器可检查的结构覆盖，再做需要判断的语义分析，最后做需要内容改写的大规模重构。

---

## 9. 跨项目实证：archguard 实验的关联

本文档的若干设计决策有来自 archguard 项目（2026-06-14 至 06-16）的实证支撑，记录如下备查：

### 9.1 λ 规格符号的来源

BAIME SKILL.md 的 λ-calculus/Haskell 符号记法，来自 2026-06-16 archguard 项目中的显式实验："用 prompt-find.md 风格的 Haskell 表达式写 SKILL.md"（session 9481908e）。loop-backlog 在同一时间段被重写为 λ 规格格式，并加入了 `conditionalCommit` 分支逻辑——这次真实改写验证了"λ spec → 可测分支提取"路径在工程上是可行的，不只是理论。

### 9.2 机械/语义边界的实证

archguard ADR 合规检查（session c0b36524，2026-06-15）独立得出了与 BAIME Layer 0–2.5 相同的结论：
- 机械 grep 处理结构合规，快速、无 LLM 成本
- 语义合规需要 LLM 确认，不能用脚本完全替代
- "是否能用脚本完全实现 ADR 的语义？"——答案是否定的，与 BAIME "contracts: 测的是结构不是决策"的结论一致

两个项目独立收敛到同一个边界，增加了这个判断的可信度。

### 9.3 AI 认知分析作为未来方向

archguard 2026-06-14 探索的"AI 认知成本指标 + 认知负荷热力图"是 BAIME skill 质量评估的潜在工具：
- archguard 已能分析代码文件的结构复杂度（outDegree、cyclomatic complexity）
- 理论上相同分析可以应用于 SKILL.md 的 `## Spec` 节：函数调用图的 outDegree = 规格复杂度，λ 分支数 = 测试用例下界
- 这意味着 archguard 不只是分析被 skill 操作的代码，也可以分析 skill 本身

这个方向尚未实施，但提供了一条将 BAIME 和 archguard 真正整合的路径。

### 9.4 Format-Encoding 实验：符号选择的边界

archguard format-encoding 实验（2026-06-12）在 545 个实体的 ArchGuard 类图上测试了 8 种序列化格式的 LLM 推理 F1，使用 Haiku 作为主答题模型（k=5 runs）：

| 格式 | 总体 F1 | 特点 |
|---|---|---|
| json-edge-list | 0.671 | 扁平结构，最优 |
| Custom DSL | 0.643 | 自定义格式，与 JSON 相当 |
| Haskell ADT | 0.571 | 嵌套深度 225，低于等效 JSON |
| Mermaid | 0.286 | A 类任务仅 0.04，最差 |

H1（格式选择显著影响 LLM 推理，p=0.007）被确认。但实验的**适用边界**是"图结构序列化 + 图查询任务"，与 SKILL.md 的"执行规格 + 决策任务"是不同任务类型。以下推论只在对应范围内成立：

1. **在 SKILL.md 中嵌入结构化图数据时，不使用 Mermaid**：A 类拓扑查询 F1 仅 0.04，接近随机。如果未来 SKILL.md 需要内嵌架构快照或依赖图，使用 json-edge-list 或 custom-dsl，不用 Mermaid。λ 分支本身不受此约束——λ 表达式不是图序列化格式。

2. **自定义 DSL 不是劣化选择**（任务类型差异大，谨慎外推）：Custom DSL F1 0.643 与 json-edge-list 0.671 无显著差异（H-pretrain NULL）。这为"自定义格式不比标准格式差"提供了一定支撑，但该任务是图查询，不是执行规格读取，直接类比需要保留余地。

**不适用**：Haskell ADT nesting depth 225 是 545 实体图递归展开的产物，BAIME λ spec 最大嵌套约 3–4 层，不在这个实验的覆盖范围内。"λ spec 应保持扁平"对 BAIME 是自然成立的，不需要这个实验来验证。
