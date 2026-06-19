---
name: build-quality-gates
title: Build Quality Gates Implementation
description: |
  Systematic methodology for implementing comprehensive build quality gates using BAIME framework.
  Achieved 98% error coverage with 17.4s detection time, reducing CI failures from 40% to 5%.
version: "1.0"
category: engineering-quality
tags:
  - build-quality
  - ci-cd
  - baime
  - error-prevention
  - automation
  - testing-strategy
contracts:
  - grep: "GateConfig"
  - grep: "CI"
  - grep: "quality gate"
  - grep: "V_instance"
---

## Spec

λ(repo: Repo) → GateConfig

data GateConfig = GateConfig
  { lintGate     : Bool
  , testGate     : Bool
  , typeGate     : Bool
  , ciIntegrated : Bool
  }

## Trigger

**Use this skill when**: The user asks to add quality gates, set up CI checks, configure pre-commit hooks, add linting/testing to CI, or enforce code quality standards automatically.

**Do NOT use when**: The user wants to run existing tests (use the test runner directly), or wants code review without automation.

## Boundaries

**Allowed files**: `.github/workflows/`, `Makefile`, `.pre-commit-config.yaml`, `pyproject.toml`/`setup.cfg` (tool config sections), `package.json` (scripts section), CI config files, `scripts/check-*.sh`.

**Forbidden**: Business logic files, application source code, database migrations, production configuration.

## Workflow

1. Audit current CI/CD pipeline and identify missing gates
2. Select gate types appropriate to the tech stack (lint, type-check, unit tests, integration tests)
3. Configure each gate in CI configuration
4. Add pre-commit hooks for fast local feedback
5. Verify all gates pass on current codebase before marking done

## Verification

```bash
# Run after implementation to confirm all gates pass
make ci              # or equivalent: make check-full lint test
pre-commit run --all-files
# For GitHub Actions: gh act -j quality
```

## Implementation

### Reference: Historical Results

Past implementations using the BAIME 3-iteration approach (P0 → P1 → P2):

| Metric              | Baseline | After P0 | After P1 | After P2 (Final) |
|---------------------|----------|----------|----------|------------------|
| V_instance          | 0.47     | 0.72     | 0.822    | 0.876            |
| V_meta              | 0.525    | —        | —        | 0.933            |
| Error Coverage      | 30%      | 50–70%   | 80–90%   | 98%              |
| CI Failure Rate     | 40%      | —        | —        | 5%               |
| Detection Time      | 480s     | <10s     | <30s     | 17.4s            |

ROI: ~400% in first month (Go CLI project with 5–10 developers).

### Reference: Implementation Roadmap

**P0 — Core gates (do first, target <10s)**
- [ ] `check-temp-files.sh` — detect debug/temp files accidentally staged
- [ ] `check-deps.sh` — verify go.mod/package-lock integrity
- [ ] `check-fixtures.sh` — verify test fixtures exist
- [ ] Wire into `make check-workspace` and pre-commit hook

**P1 — Enhanced coverage (target <30s)**
- [ ] `check-scripts.sh` — shellcheck on all shell scripts
- [ ] `check-debug.sh` — detect leftover console.log / TODO / FIXME
- [ ] `check-imports.sh` — goimports / isort / eslint --fix
- [ ] Wire into `make check-quality` and CI pipeline

**P2 — Advanced (target <60s)**
- [ ] Language-specific quality: `go vet` / `mypy` / `tsc`
- [ ] Security scanning: `gosec` / `npm audit` / `safety`
- [ ] Coverage threshold gate
- [ ] Branch protection rules requiring CI pass

### Reference: Configuration Templates

**GitHub Actions (`.github/workflows/ci.yml`)**
```yaml
name: CI
on: [push, pull_request]
jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install tools
        run: go install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.64.8
      - name: Quality gates
        run: make ci
      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

**Makefile targets**
```makefile
.PHONY: check-workspace check-quality check-full ci

# P0: Critical (blocks commit, <10s)
check-workspace: check-temp-files check-fixtures check-deps
	@echo "Workspace validation passed"

# P1: Enhanced quality (<30s)
check-quality: check-workspace check-scripts check-debug check-imports
	@echo "Quality validation passed"

# P2: Full validation (<60s)
check-full: check-quality check-go-quality check-security
	@echo "Comprehensive validation passed"

# CI target
ci: check-full test-all build-all
	@echo "CI validation passed"

# Parallel execution (optimization)
check-parallel:
	@make check-temp-files & make check-fixtures & make check-deps & wait
```

**Pre-commit (`.pre-commit-config.yaml`)**
```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
```

**Check script template (`scripts/check-<category>.sh`)**
```bash
#!/bin/bash
# check-<category>.sh — <one-line purpose>
# Iteration: P0/P1/P2  |  Historical impact: X% of errors
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
ERRORS=0

echo "  [1/N] Checking <pattern>..."
if <condition>; then
    echo -e "${RED}ERROR: <description>${NC}"
    echo "Fix: <command>"
    ((ERRORS++)) || true
fi

[ $ERRORS -eq 0 ] && echo -e "${GREEN}All checks passed${NC}" && exit 0
echo -e "${RED}Found $ERRORS error(s) — fix before committing${NC}"; exit 1
```

**Language-specific quality tools**

| Language   | Formatting  | Linting        | Type-check | Security   |
|------------|-------------|----------------|------------|------------|
| Go         | `go fmt`    | `golangci-lint`| `go vet`   | `gosec`    |
| Python     | `black`     | `flake8`       | `mypy`     | `safety`   |
| JavaScript | `prettier`  | `eslint`       | `tsc`      | `npm audit`|
| Rust       | `cargo fmt` | `cargo clippy` | built-in   | `cargo audit` |

**Version pinning (`.tool-versions` for asdf)**
```
golangci-lint 1.64.8
golang 1.21.0
nodejs 18.17.0
python 3.11.4
```

### Reference: Validation Methods

**Error coverage test**
```bash
# Introduce known error, verify gate catches it
touch test_temp.go
if make check-workspace 2>/dev/null; then echo "MISSED"; exit 1; fi
rm test_temp.go
echo "Detection confirmed"
```

**Performance benchmark**
```bash
time make check-full   # target: <60s
```

**V_instance formula** (for tracking improvement):
```
V_instance = 0.4×(1−CI_failure_rate)
           + 0.3×(1−avg_iterations/baseline_iterations)
           + 0.2×min(baseline_time/actual_time, 10)/10
           + 0.1×error_coverage_rate
```
Target: V_instance ≥ 0.85, V_meta ≥ 0.80.
