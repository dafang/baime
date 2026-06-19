# Skill Specification Standard

This document defines the minimum formal specification requirements for BAIME skills.

## Purpose

Skills without formal specifications behave unpredictably — their constraints are implicit, cannot be statically validated, and are hard to test. This standard establishes a minimum bar for all new skills and a target for existing skills.

## Minimum Standard

Every skill MUST have, in its `SKILL.md` frontmatter and body:

### Trigger

The `description:` frontmatter field must be specific enough that only one skill would match a given user input. Avoid broad terms that overlap with other skills.

### Failure behavior

Every skill MUST document what happens when it cannot complete successfully:
- What conditions cause failure
- What the skill outputs or signals on failure (e.g., escalate, write signal file, ask user)

### contracts:

Each SKILL.md MUST have a `contracts:` field in its **YAML frontmatter** listing machine-verifiable invariants in structured format:

```yaml
contracts:
  - grep: "some-keyword"       # PASS if pattern found in body
  - not-grep: "forbidden"      # PASS if pattern absent from body
```

**Enforcement**: `validate-plugin.sh` Layer 2 reads contracts exclusively from the YAML frontmatter via `yaml.safe_load`. Plain strings or contracts placed in the body (`## Spec` section) are silently skipped — they carry no enforcement weight.

**Pattern selection**: choose terms that must appear in any correct implementation — function names from the λ spec, required section headers, key output type names, or forbidden behaviors. Avoid overly common words.

**Prose invariants** that cannot be expressed as grep patterns (e.g., "idempotent: running twice produces the same result") belong in the body under `## Spec` or `## Constraints` as human documentation only — do not put them in the frontmatter `contracts:` field.

## Required Sections

A conforming SKILL.md must include:

1. **Frontmatter** with at minimum: `name`, `description`, `version`
2. **`## Spec`** section with:
   - `λ` entry point signature (the main function the skill exports)
   - Core data type definitions (inputs/outputs)
   - Main workflow function signatures
3. **`contracts:`** line listing behavioral invariants

## Example Spec Structure

Frontmatter (machine-enforced):
```yaml
---
name: my-skill
description: "..."
contracts:
  - grep: "MyOutputType"
  - not-grep: "git push --force"
---
```

Body (human documentation, not enforced):
```
## Spec

contracts (prose):
  - never modifies files outside the designated output path
  - idempotent: running twice produces the same result

λ(input: Input) → Output

data Input = Input { ... }
data Output = Done Result | NeedsHuman Reason

mainWorkflow :: Input → Output
mainWorkflow(i) = ...
```

## Spec Quality Levels

| Level | Criteria |
|-------|----------|
| 0 | No spec section at all |
| 1 | Has `## Spec` and `contracts:` but no type signatures |
| 2 | Has type signatures for inputs/outputs |
| 3 | Full Haskell-style spec with all major functions |

New skills must reach at least Level 2. Level 1 is the minimum acceptable for existing skills in this migration.
