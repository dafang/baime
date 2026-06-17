# baime

**BAIME (Bootstrapped AI Methodology Engineering)** — A systematic methodology development framework for AI coding assistants, with shared Claude and Codex entrypoints.

baime provides 19 validated skills and 6 specialized workflow agents that help teams develop, validate, and scale AI-assisted software engineering methodologies using the Observe-Codify-Automate (OCA) cycle.

---

## Install

Claude Code:

```bash
/plugin marketplace add yaleh/baime
```

Codex:

Clone this repository, then use it as a local Codex plugin or add a Codex marketplace entry that points at this plugin folder. The Codex plugin manifest is `.codex-plugin/plugin.json`; it exposes the shared methodology skills from `.claude/skills/`.

```bash
git clone https://github.com/yaleh/baime.git
cd baime

# Option A: add a local marketplace root that points at this plugin.
codex plugin marketplace add /path/to/local-marketplace-root

# Option B: use a repo or personal marketplace entry whose source.path points at this baime folder.
```

Install Codex custom agents and their `$...-agent` launcher skills with the companion installer:

```bash
bash scripts/install-codex-agents.sh --scope user --dry-run
bash scripts/install-codex-agents.sh --scope user
```

For project-scoped agents:

```bash
bash scripts/install-codex-agents.sh --scope project --target /path/to/project
```

The installer generates self-contained Codex agent TOML files from the shared `.claude/agents/` source, so installed agents do not depend on paths inside this repository. It also creates six launcher skills such as `$workflow-coach-agent` and `$stage-executor-agent` in the same Codex scope, so users can select agent workflows from Codex's `$` / `/skills` picker. These launcher skills load the installed agent instructions into the current Codex session; they do not create another subagent. Re-run with `--force` to overwrite existing BAIME agent files and launcher skills.

---

## Platform Model

baime keeps one shared source and exposes host-specific entrypoints around it:

```text
.claude/agents/*.md          shared workflow agent source
.claude/skills/*/SKILL.md    shared methodology skill source
.codex/skills/*              symlinks to ../../.claude/skills/*
.codex/agents/*.toml         repo-local Codex custom agent adapters
.codex-plugin/plugin.json    Codex plugin manifest pointing at shared skills
scripts/install-codex-agents.sh
                              installer for portable Codex custom agents and launcher skills
```

Treat `.claude/agents/` and `.claude/skills/` as the source of truth. `.codex/skills/` is a repo-local compatibility layer for direct repository checks, not copied content. `.codex/agents/` contains thin repo-local Codex custom agent adapters that point back to the matching shared workflow agent source when you run Codex inside this repository. User or project installations should use `scripts/install-codex-agents.sh`, which embeds the shared workflow source into portable installed TOML and creates Codex-only `$...-agent` launcher skills in the target Codex skills directory. The launcher skills are inline adapters for Codex's skill picker: they read the installed TOML and apply its `developer_instructions` in the current turn, avoiding recursive agent creation.

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
| `workflow-coach` | Coach users to optimize their AI coding assistant workflow (works standalone; optionally enriched by meta-cc) |

The Codex agent installer also creates six launcher skills named `{agent}-agent`, such as `$workflow-coach-agent` and `$stage-executor-agent`. These are selection shortcuts that load and apply the matching installed Codex agent instructions in the current session. They explicitly avoid spawning or delegating to another agent.

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

## Platform Notes

- `allowed-tools` in shared skill frontmatter is Claude-specific optional metadata. It is kept for Claude compatibility and is not required by the Codex compatibility layer.
- `workflow-coach` works standalone. meta-cc can enrich it with Claude Code session history, but meta-cc is optional and not a cross-platform requirement.
- `subagent-prompt-construction` is a Claude-specific specialty skill for Claude Code subagent prompts. For platform-neutral workflow prompt design, use BAIME prompt refinement or methodology bootstrapping patterns first, then adapt the result to the host agent format.
- Structural validation proves the repository layout, manifests, frontmatter, symlinks, repo-local custom agent adapters, and portable Codex agent installer output. Runtime smoke for Codex agent and skill triggering is handled by `scripts/smoke-codex-compat.sh`.

---

## Quick Start

### Use a Workflow Agent

Claude example:

```
@agent-stage-executor Execute Stage 2 of the plan at @docs/plans/current-plan.md
```

Codex example:

```
Use the stage-executor custom agent to execute Stage 2 of the plan at docs/plans/current-plan.md.
```

### Use a Skill

Skills are available through the host skill mechanism. Reference the skill by name in your prompt.

Claude or host-neutral prompt:

```
Apply the methodology-bootstrapping skill to develop a testing strategy for this project.
```

Codex explicit invocation:

```
Use $methodology-bootstrapping to develop a testing strategy for this project.
```

In Codex CLI or IDE sessions, you can also use `/skills` or type `$` to select an installed BAIME skill. To run an agent from the skill picker, first run `scripts/install-codex-agents.sh`, then choose one of the installed launcher skills, for example `$workflow-coach-agent` or `$stage-executor-agent`. Claude and Codex plugin installs both read the shared skill source from `.claude/skills/`; `.codex/skills/` remains a repo-local symlink layer for compatibility checks.

### Workflow Coaching

Start a coaching session:

```
Use the workflow-coach agent to review my AI coding assistant workflow and find areas to improve.
```

The workflow coach works without any other tools installed. If you also have [meta-cc](https://github.com/yaleh/meta-cc) installed, the coach can optionally enrich its analysis with your actual session history.

---

## Related Projects

**[meta-cc](https://github.com/yaleh/meta-cc)** — MCP server for Claude Code session history analysis. Provides query tools, token usage tracking, error analysis, and timeline visualization. In baime, meta-cc is an optional Claude-specific enrichment, not a cross-platform requirement.

baime and meta-cc are complementary:
- **baime**: methodology skills and agents (this repo)
- **meta-cc**: session history MCP tools (Go server)

---

## Validation

Run the structural validation script locally:

```bash
pip install pyyaml
bash scripts/validate-plugin.sh
```

Expected output includes:

```text
Claude Agents: 6, Claude Skills: 19
Codex Custom Agents: 6, Codex Skills: 19
ALL CHECKS PASSED
```

This validates the dual-platform repository structure and the portable Codex agent installer output. It does not claim runtime smoke for Codex agent or skill triggering.

Run the Codex compatibility smoke separately when you need runtime evidence:

```bash
bash scripts/smoke-codex-compat.sh --preflight
bash scripts/smoke-codex-compat.sh --live
```

`--preflight` performs deterministic checks only, uses a temporary Codex home for marketplace validation, and verifies the Codex agent installer with a temporary project. `--live` runs `codex exec` against the local repository in read-only mode and depends on your local Codex auth, model access, and network. Smoke reports are written to `compatibility/smoke/latest/`.

---

## Contributing

1. Fork the repository
2. Add or modify shared source content in `.claude/agents/` or `.claude/skills/`
3. For skills, keep YAML frontmatter `name` equal to the skill directory slug and keep `description` present
4. Do not copy skill content into `.codex/skills/`; those entries must remain symlinks to `../../.claude/skills/{slug}`
5. Keep `.codex/agents/{agent}.toml` as repo-local custom agent adapters that reference the matching `.claude/agents/{agent}.md`
6. Keep installed Codex agent and launcher skill files generated by `scripts/install-codex-agents.sh`; do not hand-copy repo-local adapter TOML into user or project Codex directories
7. Do not add workflow agents to `.codex/skills/`; Codex `$...-agent` entries are installed dynamically by the agent installer
8. Run `bash scripts/validate-plugin.sh` — must pass
9. Open a pull request

---

## License

MIT
