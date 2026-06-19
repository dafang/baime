#!/usr/bin/env bash
# test-harness-injection.sh — Verify that the harness injection self-check works
#
# Tests that when a fixture has a 'state' field but the prompt builder does NOT inject it,
# the detection logic correctly reports an error and exits non-zero.
#
# This is a negative control / sanity test for the injection check mechanism.
# The test PASSES when the detection logic correctly catches the missing injection.

set -euo pipefail

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

echo "=== Harness injection self-check ==="
echo ""

# Write the inline node test script
cat > "$TMPDIR_WORK/test-injection.mjs" <<'NODEOF'
/**
 * Inline node test: verify that injection detection logic works.
 *
 * Scenario:
 *   - fixture has state: { backlogDirExists: false }
 *   - a "bad" builder that only uses fixture.input (ignores state)
 *   - a "good" builder that also injects state
 *
 * Expected:
 *   - bad builder: checkInjection returns error (state field not injected)
 *   - good builder: checkInjection returns ok
 */

// ---- Minimal fixture ----
const fixture = {
  id: "bs-init-project-test",
  skill: "backlog-setup",
  decisionPoint: "initProject",
  specSection: "initProject :: () → ()\ninitProject() =\n  | exists(\"backlog/\") → skip\n  | otherwise → init",
  input: { projectName: "test-project" },
  state: { backlogDirExists: false },
  answer: "init",
  answerType: "exact",
  fixtureClass: "CLEAR",
};

// ---- Injection check function ----
// Returns { ok: true } if all fields present in the fixture are reflected in the prompt,
// Returns { ok: false, missing: string[] } otherwise.
function checkInjection(fixture, prompt) {
  const missing = [];

  // Check each field that could carry semantics
  const fieldsToCheck = ["state", "input", "plan", "config"];
  for (const field of fieldsToCheck) {
    if (fixture[field] === undefined) continue;
    const serialized = JSON.stringify(fixture[field], null, 2);
    // Heuristic: at least one key from the field's JSON must appear in the prompt
    const keys = Object.keys(fixture[field]);
    const anyKeyPresent = keys.some(k => prompt.includes(k));
    if (!anyKeyPresent && serialized !== "{}") {
      missing.push(field);
    }
  }

  return missing.length === 0
    ? { ok: true }
    : { ok: false, missing };
}

// ---- Bad builder: only injects input, silently ignores state ----
function badBuilder(fixture) {
  return [
    `You are executing a decision step in the ${fixture.skill} skill.`,
    `## Decision Point: ${fixture.decisionPoint}`,
    `## Spec`,
    fixture.specSection,
    `## Input`,
    "```json",
    JSON.stringify(fixture.input ?? {}, null, 2),
    "```",
    `What is the result of ${fixture.decisionPoint}?`,
    'Output ONLY valid JSON: {"answer": "<result>"}',
  ].join("\n");
}

// ---- Good builder: injects both input and state ----
function goodBuilder(fixture) {
  const lines = [
    `You are executing a decision step in the ${fixture.skill} skill.`,
    `## Decision Point: ${fixture.decisionPoint}`,
    `## Spec`,
    fixture.specSection,
    `## Input`,
    "```json",
    JSON.stringify(fixture.input ?? {}, null, 2),
    "```",
  ];
  if (fixture.state !== undefined) {
    lines.push("## Environment State");
    lines.push("```json");
    lines.push(JSON.stringify(fixture.state, null, 2));
    lines.push("```");
  }
  lines.push(`What is the result of ${fixture.decisionPoint}?`);
  lines.push('Output ONLY valid JSON: {"answer": "<result>"}');
  return lines.join("\n");
}

// ---- Run tests ----
let allPassed = true;

// Test 1: bad builder should fail injection check
const badPrompt = badBuilder(fixture);
const badResult = checkInjection(fixture, badPrompt);
if (badResult.ok) {
  console.error("FAIL: bad builder passed injection check (should have failed)");
  allPassed = false;
} else {
  console.log(`PASS: bad builder correctly detected missing fields: [${badResult.missing.join(", ")}]`);
}

// Test 2: good builder should pass injection check
const goodPrompt = goodBuilder(fixture);
const goodResult = checkInjection(fixture, goodPrompt);
if (!goodResult.ok) {
  console.error(`FAIL: good builder failed injection check (missing: [${goodResult.missing.join(", ")}])`);
  allPassed = false;
} else {
  console.log("PASS: good builder correctly passed injection check");
}

// Test 3: fixture without state — bad builder should pass (no state to inject)
const fixtureNoState = { ...fixture };
delete fixtureNoState.state;
const resultNoState = checkInjection(fixtureNoState, badPrompt);
if (!resultNoState.ok) {
  console.error(`FAIL: fixture without state failed check unexpectedly (missing: [${resultNoState.missing.join(", ")}])`);
  allPassed = false;
} else {
  console.log("PASS: fixture without state correctly passes check with bad builder");
}

if (!allPassed) {
  console.error("\nHARNESS INJECTION SELF-CHECK FAILED");
  process.exit(1);
} else {
  console.log("\nAll injection detection tests passed.");
  process.exit(0);
}
NODEOF

echo "Running injection detection tests..."
node "$TMPDIR_WORK/test-injection.mjs"
echo ""
echo "test-harness-injection: PASSED"
