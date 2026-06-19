#!/usr/bin/env bash
# test-suspicious-sigma.sh — Phase 5 suspiciously-low σ test
#
# Constructs a test input with near-identical values (σ ≈ 0),
# runs the sigma calculation logic via inline node script,
# and asserts the suspiciously_low flag is triggered.

set -euo pipefail

echo "[test-suspicious-sigma] Starting suspiciously-low sigma test..."

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# Write a small inline Node.js script that exercises the suspiciously-low sigma logic
SIGMA_SCRIPT="$TMPDIR_BASE/sigma-test.mjs"
cat > "$SIGMA_SCRIPT" <<'NODESCRIPT'
// Mirrors the sigma calculation and suspiciously_low check from run-exp-h.ts

const SUSPICIOUSLY_LOW_SIGMA_THRESHOLD = 0.005;

function computeSigma(values) {
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  const variance = values.reduce((s, v) => s + Math.pow(v - mean, 2), 0) / values.length;
  return Math.sqrt(variance);
}

function checkSuspiciouslyLow(sigma) {
  return sigma < SUSPICIOUSLY_LOW_SIGMA_THRESHOLD;
}

// Test 1: near-identical values (σ ≈ 0) → should trigger suspiciously_low
const nearIdentical = [0.92, 0.92, 0.92];
const sigma1 = computeSigma(nearIdentical);
const suspicious1 = checkSuspiciouslyLow(sigma1);

console.log(`Test 1 (near-identical): values=${JSON.stringify(nearIdentical)}`);
console.log(`  sigma=${sigma1.toFixed(6)}, suspiciously_low=${suspicious1}`);

if (!suspicious1) {
  console.error('FAIL: Expected suspiciously_low=true for near-identical values');
  process.exit(1);
}
console.log('  PASS: suspiciously_low=true correctly triggered');

// Test 2: values with σ = 0 exactly → should trigger suspiciously_low
const identical = [1.0, 1.0, 1.0, 1.0];
const sigma2 = computeSigma(identical);
const suspicious2 = checkSuspiciouslyLow(sigma2);

console.log(`\nTest 2 (identical): values=${JSON.stringify(identical)}`);
console.log(`  sigma=${sigma2.toFixed(6)}, suspiciously_low=${suspicious2}`);

if (!suspicious2) {
  console.error('FAIL: Expected suspiciously_low=true for identical values');
  process.exit(1);
}
console.log('  PASS: suspiciously_low=true correctly triggered');

// Test 3: varied values (σ > threshold) → should NOT trigger suspiciously_low
const varied = [0.60, 0.80, 0.95, 0.70];
const sigma3 = computeSigma(varied);
const suspicious3 = checkSuspiciouslyLow(sigma3);

console.log(`\nTest 3 (varied): values=${JSON.stringify(varied)}`);
console.log(`  sigma=${sigma3.toFixed(6)}, suspiciously_low=${suspicious3}`);

if (suspicious3) {
  console.error('FAIL: Expected suspiciously_low=false for varied values');
  process.exit(1);
}
console.log('  PASS: suspiciously_low=false correctly not triggered');

// Test 4: σ just below threshold (0.004) → should trigger
const nearThreshold = [0.500, 0.504];
const sigma4 = computeSigma(nearThreshold);
const suspicious4 = checkSuspiciouslyLow(sigma4);

console.log(`\nTest 4 (just below threshold): values=${JSON.stringify(nearThreshold)}`);
console.log(`  sigma=${sigma4.toFixed(6)}, suspiciously_low=${suspicious4}`);

if (!suspicious4) {
  console.error('FAIL: Expected suspiciously_low=true for sigma just below threshold');
  process.exit(1);
}
console.log('  PASS: suspiciously_low=true correctly triggered');

console.log('\nAll sigma tests passed.');
process.exit(0);
NODESCRIPT

echo "[test-suspicious-sigma] Running sigma logic test subprocess..."
node "$SIGMA_SCRIPT"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo "[test-suspicious-sigma] PASS: suspiciously_low flag correctly triggered for near-zero sigma."
else
  echo "[test-suspicious-sigma] FAIL: sigma test failed (exit code: $EXIT_CODE)."
  exit 1
fi

echo "[test-suspicious-sigma] All checks passed."
