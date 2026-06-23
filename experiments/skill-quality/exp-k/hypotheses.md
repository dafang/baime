# Exp-K Hypotheses: Prompt Completeness Ablation on Decomposer Persona Effect

## Background
Exp-I and Exp-J found cross-model disagreement: Haiku benefits from expert persona (V1), Sonnet is hurt. Both experiments used a prompt with explicit CODE-CHANGE/DOC-ONLY classification rules. Exp-K tests whether prompt completeness mediates this effect.

## Prompt Levels
- **P-minimal**: opening directive + subtaskHint + epicPlanExcerpt + output instruction. NO classification rules.
- **P-rules**: P-minimal + explicit CODE-CHANGE/DOC-ONLY rule block (identical to Exp-I/Exp-J).
- **P-full**: P-rules + 3 few-shot examples (one clear CC, one clear DO, one ambiguous CC — from Exp-I fixtures, NOT from the Exp-J test set).

## Variants
- V0: "You are the autonomous decomposer agent for epic TASK-N."
- V1: "You are an experienced software architect decomposing an epic into independently implementable child tasks. Your primary skill is distinguishing implementation work (code and file changes) from analytical or documentation work (research, prose writing, audits)."

## Hypotheses

### H-K1: Persona more helpful with minimal prompt
Persona Δ(AMBIG) at P-minimal > Δ(AMBIG) at P-rules.
Rationale: When no rules are present, the expert persona provides implicit classification guidance. When explicit rules are present, the persona adds little.

### H-K2: Persona more helpful with rules than with examples
Persona Δ(AMBIG) at P-rules > Δ(AMBIG) at P-full.
Rationale: When few-shot examples are present in addition to rules, the persona's contribution is further diminished — the examples already calibrate the model.

### H-K3: Persona universally helpful under minimal prompt
At P-minimal, both Haiku and Sonnet show positive Δ (V1 acc > V0 acc).
Rationale: Without explicit rules, both models benefit from the expert framing regardless of model-specific tendencies.

## Cross-model consistency rule
If Haiku and Sonnet disagree on the monotone ordering H-K1 (Δ_minimal > Δ_rules), tag verdict [underpowered].

## Fixture set
16 AMBIGUOUS fixtures from fixtures/exp-j/ambiguous/ (same as Exp-J).
Models: claude-haiku-4-5-20251001 (primary), claude-sonnet-4-6 (cross-check).
k=5 per cell. Total: 16 × 6 variants × 5 reps × 2 models = 960 LLM calls.
