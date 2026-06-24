# GCL H7 Validation: gate_actor_type × escape rate

**Status:** PENDING — awaiting ≥10 llm gate events in gcl-events.jsonl  
**Date created:** 2026-06-24  
**Task:** TASK-185 (dyad experiment design + boss CC channel)  
**Dataset:** `docs/research/gcl-events.jsonl`  
**Depends on:** docs/research/dyad-experiment-design.md, plugin/skills/loop-backlog/SKILL.md (boss CC channel)

---

## H7 Hypothesis

**H7**: In the routine gate subset, controlling for evidence_independence, gate_actor_type
(human vs llm) has no significant effect on escape rate.

Formal statement:

```
H0: P(escape_rate=1 | gate_actor_type=llm,  evidence_independence=X)
  = P(escape_rate=1 | gate_actor_type=human, evidence_independence=X)
  for all X in {high, medium, low}

H1: The above equality does not hold for at least one X.
```

**Directional prediction (null)**: No significant difference. If gate evidence is
sufficiently independent (evidence_independence=high), an LLM boss performing the
gate should achieve escape_rate indistinguishable from a human gate reviewer.

**Source**: docs/research/gcl-complete-observation-mechanism.md §5 H7;
docs/research/cc-actor-network.md §3.

---

## Measurement Protocol

### Data source

`docs/research/gcl-events.jsonl` — gate events with `gate_type: epic-evaluate`.

Relevant fields:
- `gate_actor_type`: "llm" (boss CC channel, TASK-185) or "human" (human confirmation)
- `escape_rate`: 0 (no escape) or 1 (escape: task reached Needs Human after gate)
- `evidence_independence`: "high" | "medium" | "low" | "unknown"
- `task_kind`: must be "epic" for this analysis
- `gate_type`: must be "epic-evaluate"

### Event production

Each `epicEvaluate` invocation produces ONE gate event:
- `gate_actor_type=llm`: written by the boss CC channel in `epicEvaluate()` (TASK-185)
- `gate_actor_type=human`: written by `recordHumanEpicGate()` when human sets Epic: Done

### escape_rate labeling

`escape_rate=1` if, after the epic gate was passed, any child task or the epic itself
subsequently reached `Basic: Needs Human` (i.e., the gate missed a defect).

Default is `escape_rate=0` at write time. Retroactive labeling when defects discovered.

### Statistical test

**Primary**: Fisher exact test on 2×2 contingency table:

```
               escape_rate=0  escape_rate=1
gate_actor_type=llm   a            b
gate_actor_type=human c            d
```

Stratified by `evidence_independence` level (run Fisher separately for each level
with sufficient N).

**Fallback**: If escape_rate is too sparse (all zeros), use Mann-Whitney U on a
proxy outcome (e.g., re-work time, child escalation count).

---

## Sample Size Requirement

**PENDING condition**: This analysis MUST NOT be run until:

| Requirement | Status |
|-------------|--------|
| N_llm ≥ 10 gate events (gate_actor_type=llm, gate_type=epic-evaluate) | PENDING |
| N_human ≥ 10 gate events (gate_actor_type=human, gate_type=epic-evaluate) | PENDING |
| escape_rate variance > 0 (at least one escape_rate=1 event) | PENDING |
| evidence_independence field is NOT all-"unknown" | PENDING |

**Current status** (as of 2026-06-24): All conditions PENDING. The boss CC channel
(TASK-185) has just been implemented. Data accumulation begins now.

### Rationale for N ≥ 10 per group

Fisher exact test at alpha=0.05, 80% power, odds ratio OR=3.0 (detectable meaningful
difference) requires approximately:
- N_total ≥ 20 (10 per group, balanced)
- This is sufficient for a preliminary test at OR=3.0 but not for small effects (OR<2.0)

For full power analysis see: docs/research/gcl-h5-h6-h7-validation.md §4.

---

## Data-Gated Analysis Script

DO NOT RUN until sample size requirements above are met.

```python
#!/usr/bin/env python3
"""
H7 validation script — gate_actor_type × escape_rate (Fisher exact)
Prerequisite: N_llm >= 10, N_human >= 10, escape_rate variance > 0
"""
import json
from scipy import stats
from collections import Counter

records = [json.loads(l) for l in open('docs/research/gcl-events.jsonl') if l.strip()]

# Filter to epic-evaluate gate events only
epic_gates = [r for r in records if r.get('gate_type') == 'epic-evaluate']

# Count by gate_actor_type
by_type = Counter(r.get('gate_actor_type') for r in epic_gates)
print(f"N by gate_actor_type: {dict(by_type)}")

n_llm   = by_type.get('llm', 0)
n_human = by_type.get('human', 0)

# Prerequisite check
if n_llm < 10:
    raise SystemExit(f"PENDING: N_llm={n_llm} < 10. Accumulate more llm gate events.")
if n_human < 10:
    raise SystemExit(f"PENDING: N_human={n_human} < 10. Accumulate more human gate events.")

escape_rates = [r.get('escape_rate', 0) for r in epic_gates]
if len(set(escape_rates)) < 2:
    raise SystemExit(f"PENDING: escape_rate has no variance (all={set(escape_rates)}). "
                     "Label at least one escape_rate=1 event.")

# Build 2x2 contingency table
llm_gates   = [r for r in epic_gates if r.get('gate_actor_type') == 'llm']
human_gates = [r for r in epic_gates if r.get('gate_actor_type') == 'human']

a = sum(1 for r in llm_gates   if r.get('escape_rate', 0) == 0)
b = sum(1 for r in llm_gates   if r.get('escape_rate', 0) == 1)
c = sum(1 for r in human_gates if r.get('escape_rate', 0) == 0)
d = sum(1 for r in human_gates if r.get('escape_rate', 0) == 1)

table = [[a, b], [c, d]]
print(f"Contingency table:\n  llm:   no_escape={a}, escape={b}\n  human: no_escape={c}, escape={d}")

odds_ratio, p_value = stats.fisher_exact(table)
print(f"\nFisher exact test:")
print(f"  OR = {odds_ratio:.3f}")
print(f"  p  = {p_value:.4f}")
print(f"\nH7 verdict: {'RETAIN H0 (no significant effect)' if p_value > 0.05 else 'REJECT H0 (significant effect)'}")
```

---

## Current Data Summary

As of 2026-06-24, gcl-events.jsonl contains N=23 gate events with:
- gate_actor_type: all "llm" (0 human, 0 epic-evaluate with gate_actor_type=llm)
- escape_rate: all 0 (no variance)

**H7 status: UNTESTABLE** — no variation in gate_actor_type (no human gates exist yet)
and no escape events.

See: docs/research/gcl-h5-h6-h7-validation.md §3.3 for full null-result analysis.

---

## Next Steps

1. Boss CC channel (TASK-185) will auto-produce `gate_actor_type=llm` events on each
   `epicEvaluate` invocation going forward.
2. Human confirmation gate (`recordHumanEpicGate`) will produce `gate_actor_type=human`
   events when humans set Epic: Done.
3. Monitor accumulation: re-check when N_llm ≥ 10 in gcl-events.jsonl.
4. When escape_rate=1 events appear (defects caught after gate), retroactively label.
5. Run analysis script above once all PENDING conditions are met.
