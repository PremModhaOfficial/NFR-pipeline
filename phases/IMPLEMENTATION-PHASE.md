<!-- cross_language_ok: true — phase contract orchestrates language-specific waves; references per-pack toolchain (Go: go test/build/vet/govulncheck/goleak; Python: pytest/mypy/ruff/pip-audit) in narrative wave descriptions. The phase invariants themselves are language-neutral and resolve through active-packages.json + toolchain. Multi-tenant SaaS context preserved per F-008. -->

# Phase 2: Implementation

## Purpose

Produce compilable, tested Go code in `$SDK_TARGET_DIR` that satisfies the design. Uses TDD (red/green/refactor/docs) with marker-aware merging in Mode B/C.

## Input

- `runs/<run-id>/design/*` (all design artifacts)
- `runs/<run-id>/tprd.md`
- `runs/<run-id>/ownership-map.json` (Mode B/C)
- Target SDK tree (read/write via branch `sdk-pipeline/<run-id>`)

## Pre-phase setup

`sdk-impl-lead`:
1. Verify `$SDK_TARGET_DIR` is a git repo + clean
2. Create branch `sdk-pipeline/<run-id>` from current HEAD
3. Write `runs/<run-id>/impl/base-sha.txt`
4. Initialize `runs/<run-id>/impl/manifest.json` with per-symbol status map from TPRD §7

## Waves

### Wave M1 — Red (failing tests)
**Agent**: `sdk-test-spec-generator`
For each symbol in TPRD §7 API:
- Write `<pkg>/<sym>_test.go` with failing table-driven tests encoding TPRD §4 FRs
- Add `// [traces-to: TPRD-4-FR-<n>]` marker on each test case
- Commit to branch with message `test: red for TPRD-4-FR-<n>`
**Exit**: `go test ./<pkg>/...` compiles; all tests FAIL as expected.

### Wave M2 — Merge Planning (Mode B/C only)
**Agent**: `sdk-merge-planner`
- Read `ownership-map.json`
- For each file in design's target list:
  - Enumerate existing symbols + markers
  - Plan per-symbol: preserve (MANUAL) / regenerate (pipeline-owned) / surface-for-user (CO-OWNED)
  - Plan constraint proofs: which benchmarks must run before/after
- Output: `runs/<run-id>/impl/merge-plan.md`
- H7b gate surfaces plan to user for per-symbol approval

### Wave M3 — Green (make tests pass)
**Agent**: `sdk-implementor`
For each failing test:
- Write minimum code to pass
- Respect merge plan (Mode B/C)
- Add `// [traces-to: TPRD-<section>-<id>]` marker on each new symbol
- Wire OTel via `motadatagosdk/otel`
- Wire circuit breaker + pool where designed
- Commit: `feat: green for TPRD-<n>`
**Exit per file**: `go build ./...` + `go test ./<pkg>/... -race -count=1` pass.

### Wave M4 — Constraint Proof (Mode B/C only)
**Agent**: `sdk-constraint-devil-go`
For each `[constraint]` with named bench in touched files:
- Run bench BEFORE changes (from `bench-baseline.txt`)
- Run bench AFTER changes
- `benchstat` compare; stated-tolerance check (default 0% if unstated)
- FAIL = BLOCKER; halt, surface to user

### Wave M5 — Refactor
**Agent**: `refactoring-agent-go`
- Remove duplication
- Apply `simplify` skill patterns
- Maintain test green

### Wave M6 — Docs
**Agent**: `documentation-agent-go`
- Godoc on every exported symbol (first word = symbol name)
- Add `Example_*` functions where applicable
- Write / update `<pkg>/README.md`

### Wave M7 — Devil Reviews (parallel)

| Agent | Role |
|-------|------|
| `sdk-api-ergonomics-devil-go` | SDK-consumer POV: boilerplate, surprising defaults, missing examples |
| `sdk-leak-hunter-go` | Run `go test -race -count=5` + `goleak.VerifyTestMain`; report leaks as BLOCKER |
| `sdk-overengineering-critic` | Reject unused options, speculative interfaces, dead abstractions |
| `sdk-marker-hygiene-devil` | Every pipeline-authored symbol has `[traces-to: TPRD-*]`; every preserved MANUAL symbol retained its marker byte-identical; no forged MANUAL markers |
| `code-reviewer-go` | Go idioms, error wrapping, naming, package structure |

### Wave M8 — Review-Fix Loop
Same protocol as Design. Route fixes to implementer; re-run devils after each batch.

### Wave M9 — Mechanical Checks
- `go build ./...`
- `go vet ./...`
- `gofmt -l` returns empty
- `staticcheck ./...` (if installed)
- `go test ./... -race -count=1`
- Per-symbol completeness: grep `[traces-to: TPRD-*]` for every new export

### Wave M10 — HITL Gate H7 (Diff Review)
**Artifact**: `git diff` of branch vs. base
**Options**: Approve / Request changes / Cancel
**Default**: Request changes
**Bypass**: `--skip-impl-gate` (CI only)

## Exit artifacts

- `$SDK_TARGET_DIR/<new-pkg>/*.go` (on branch `sdk-pipeline/<run-id>`)
- `$SDK_TARGET_DIR/<new-pkg>/*_test.go`
- `$SDK_TARGET_DIR/<new-pkg>/README.md`
- `runs/<run-id>/impl/merge-plan.md` (Mode B/C)
- `runs/<run-id>/impl/constraint-proofs.md`
- `runs/<run-id>/impl/reviews/*.md`
- `runs/<run-id>/impl/impl-summary.md`

## Guardrails (exit gate)

G40 (no `ErrNotImplemented`/`TODO`), G41 (build), G42 (vet), G43 (fmt), G44 (staticcheck), G45 (godoc), G47 (no encoding/json internal), G48 (no init), G49 (no global mut state), G50 (ctx first), G51 (no unbounded goroutines), G52 (Close drains), G95 (extension tests still green), G96 (MANUAL hash match), G97 (constraint proofs), G98 (no marker deletion), G99 (traces-to on every new export), G100 (do-not-regenerate hash), G101 (stable-since signatures), G102 (deprecated-in not removed early), G103 (no forged MANUAL markers).

## Metrics

- `impl_build_pass_count` (must be green by exit)
- `impl_tests_pass_count`
- `impl_coverage_pct` (per symbol)
- `impl_leak_count` (must be 0)
- `impl_rework_iterations`
- `impl_token_consumption`

## Typical durations

- Mode A simple package: ~60–90 min
- Mode B extension: ~60 min (smaller code surface, merge planning overhead)
- Mode C incremental: ~30 min (small diffs)
