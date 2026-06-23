/**
 * prompts.ts — Exp-K prompt builders
 *
 * Six prompt builders for the prompt completeness ablation:
 *   P-minimal/V0, P-minimal/V1, P-rules/V0, P-rules/V1, P-full/V0, P-full/V1
 *
 * P-minimal: opening + output instruction only (no classification rules)
 * P-rules:   P-minimal + explicit CODE-CHANGE/DOC-ONLY rule block
 * P-full:    P-rules + 3 few-shot examples (from CLEAR fixtures, NOT from the test set)
 *
 * V0: functional directive opening
 * V1: expert architect persona opening
 */

import type { DecompFixture } from '../exp-j/run-exp-j.js';
export type { DecompFixture };

// ---------- Shared blocks ----------

const CLASSIFICATION_RULES = `
## Classification Rules

CODE-CHANGE: The sub-task creates or modifies files under plugin/, scripts/, any SKILL.md, or *.sh scripts.
DOC-ONLY: The sub-task scope is exclusively reading, researching, writing prose docs, or updating backlog notes. The natural output is a document or measurement report — no source file is created or modified.

When in doubt, apply the rule strictly based on whether the task's primary output is a file change or a prose document.
`.trim();

const OUTPUT_INSTRUCTION = `
Sub-task hint: {HINT}

Epic plan excerpt:
{PLAN}

Classify this sub-task as CODE-CHANGE or DOC-ONLY.
Output exactly one token: CODE-CHANGE or DOC-ONLY
`.trim();

const FEW_SHOT_EXAMPLES = `
## Examples

### Example 1 — CODE-CHANGE
Sub-task hint: Implement basic-daemon.cjs detection script in scripts/
Epic plan excerpt: Sub-Task Decomposition:
- Implement basic-daemon.cjs detection script in scripts/
- Add tests for detection edge cases
Classification: CODE-CHANGE
Rationale: Explicit scripts/ path triggers the CODE-CHANGE rule directly.

### Example 2 — DOC-ONLY
Sub-task hint: Research alternative ESM detection approaches and write comparison doc
Epic plan excerpt: Sub-Task Decomposition:
- Research alternative ESM detection approaches and write comparison doc
- Survey existing tooling
Classification: DOC-ONLY
Rationale: Explicit research + write doc task with no source file modification.

### Example 3 — CODE-CHANGE (ambiguous)
Sub-task hint: Improve decomposer prompt clarity for multi-file epic edge cases
Epic plan excerpt: Sub-Task Decomposition:
- Improve decomposer prompt clarity for multi-file epic edge cases
- Test with sample epics
Classification: CODE-CHANGE
Rationale: "Improve prompt" sounds like documentation but the decomposer prompt lives in SKILL.md, which triggers the CODE-CHANGE rule.
`.trim();

// ---------- Opening lines ----------

const V0_OPENING = 'You are the autonomous decomposer agent for epic TASK-N.';

const V1_OPENING = [
  'You are an experienced software architect decomposing an epic into independently implementable child tasks.',
  'Your primary skill is distinguishing implementation work (code and file changes) from analytical or',
  'documentation work (research, prose writing, audits).',
].join('\n');

// ---------- Prompt builders ----------

function fillOutput(fixture: DecompFixture): string {
  return OUTPUT_INSTRUCTION
    .replace('{HINT}', fixture.subtaskHint)
    .replace('{PLAN}', fixture.epicPlanExcerpt);
}

export function buildPMinimalV0(fixture: DecompFixture): string {
  return [V0_OPENING, '', fillOutput(fixture)].join('\n');
}

export function buildPMinimalV1(fixture: DecompFixture): string {
  return [V1_OPENING, '', fillOutput(fixture)].join('\n');
}

export function buildPRulesV0(fixture: DecompFixture): string {
  return [V0_OPENING, '', CLASSIFICATION_RULES, '', fillOutput(fixture)].join('\n');
}

export function buildPRulesV1(fixture: DecompFixture): string {
  return [V1_OPENING, '', CLASSIFICATION_RULES, '', fillOutput(fixture)].join('\n');
}

export function buildPFullV0(fixture: DecompFixture): string {
  return [V0_OPENING, '', CLASSIFICATION_RULES, '', FEW_SHOT_EXAMPLES, '', fillOutput(fixture)].join('\n');
}

export function buildPFullV1(fixture: DecompFixture): string {
  return [V1_OPENING, '', CLASSIFICATION_RULES, '', FEW_SHOT_EXAMPLES, '', fillOutput(fixture)].join('\n');
}

// ---------- Dispatch ----------

const BUILDERS: Record<string, (fixture: DecompFixture) => string> = {
  'P-minimal/V0': buildPMinimalV0,
  'P-minimal/V1': buildPMinimalV1,
  'P-rules/V0': buildPRulesV0,
  'P-rules/V1': buildPRulesV1,
  'P-full/V0': buildPFullV0,
  'P-full/V1': buildPFullV1,
};

export function buildPrompt(fixture: DecompFixture, variant: string): string {
  const builder = BUILDERS[variant];
  if (!builder) {
    throw new Error(`Unknown variant: ${variant}. Expected one of: ${Object.keys(BUILDERS).join(', ')}`);
  }
  return builder(fixture);
}
