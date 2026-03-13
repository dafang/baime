# baime

**BAIME (Bootstrapped AI Methodology Engineering)** — A systematic methodology development framework for Claude Code.

baime provides 19 validated skills and 6 specialized agents that help teams develop, validate, and scale AI-assisted software engineering methodologies using the Observe-Codify-Automate (OCA) cycle.

---

## Installation

### Via Claude Code (recommended)

```bash
/plugin marketplace add yaleh/baime
/plugin install baime@baime
```

### Via install script

```bash
git clone https://github.com/yaleh/baime
cd baime && ./scripts/install/install.sh
```

Restart Claude Code after installation.

---

## What's Included

### 6 Agents

| Agent | Purpose |
|-------|---------|
| `stage-executor` | Execute project plan stages with formal validation and environment isolation |
| `project-planner` | Create structured project plans with phases, stages, and acceptance criteria |
| `iteration-executor` | Run iterative improvement cycles with convergence tracking |
| `iteration-prompt-designer` | Design and refine prompts for iterative AI workflows |
| `knowledge-extractor` | Extract and codify knowledge from project artifacts and session history |
| `workflow-coach` | Coach users to optimize their Claude Code workflow (works standalone; optionally enriched by meta-cc) |

### 19 Skills

| Skill | Purpose |
|-------|---------|
| `agent-prompt-evolution` | Evolve agent prompts through empirical validation |
| `api-design` | Design APIs using systematic methodology |
| `baseline-quality-assessment` | Establish quality baselines for projects |
| `build-quality-gates` | Define and enforce build quality checkpoints |
| `ci-cd-optimization` | Optimize CI/CD pipelines using BAIME |
| `code-refactoring` | Systematic code refactoring methodology |
| `cross-cutting-concerns` | Implement cross-cutting concerns consistently |
| `dependency-health` | Monitor and improve dependency health |
| `documentation-management` | Maintain living documentation systematically |
| `error-recovery` | Build robust error recovery patterns |
| `knowledge-transfer` | Transfer knowledge between sessions and team members |
| `methodology-bootstrapping` | Bootstrap new methodologies using the BAIME framework (includes Prompt Refinement methodology) |
| `next-step-generation` | Generate ready-to-use next-step prompts from conversation context |
| `observability-instrumentation` | Add observability to systems systematically |
| `rapid-convergence` | Accelerate methodology convergence |
| `retrospective-validation` | Validate outcomes with structured retrospectives |
| `subagent-prompt-construction` | Construct effective prompts for Claude Code subagents |
| `technical-debt-management` | Manage and reduce technical debt systematically |
| `testing-strategy` | Develop comprehensive testing strategies |

---

## Quick Start

### Use an Agent

In Claude Code, mention the agent in your prompt:

```
@agent-stage-executor Execute Stage 2 of the plan at @docs/plans/current-plan.md
```

### Use a Skill

Skills are automatically available to Claude. Reference the skill context in your prompt:

```
Apply the methodology-bootstrapping skill to develop a testing strategy for this project.
```

### Workflow Coaching

Start a coaching session:

```
@agent-workflow-coach Let's review my Claude Code workflow and find areas to improve.
```

The workflow coach works without any other tools installed. If you also have [meta-cc](https://github.com/yaleh/meta-cc) installed, the coach can optionally enrich its analysis with your actual session history.

---

## Related Projects

**[meta-cc](https://github.com/yaleh/meta-cc)** — MCP server for Claude Code session history analysis. Provides query tools, token usage tracking, error analysis, and timeline visualization.

baime and meta-cc are complementary:
- **baime**: methodology skills and agents (this repo)
- **meta-cc**: session history MCP tools (Go server)

---

## Validation

Run the plugin validation script locally:

```bash
pip install pyyaml
bash scripts/validate-plugin.sh
```

Expected output: 6 agents, 19 skills, all YAML frontmatter checks passed.

---

## Contributing

1. Fork the repository
2. Add or modify content in `.claude/agents/` or `.claude/skills/`
3. Ensure all YAML frontmatter includes `name` and `description` fields
4. Run `bash scripts/validate-plugin.sh` — must pass
5. Open a pull request

---

## License

MIT
