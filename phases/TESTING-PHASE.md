<!-- cross_language_ok: true — phase contract orchestrates language-specific waves; references per-pack toolchain (Go: go test/build/vet/govulncheck/goleak; Python: pytest/mypy/ruff/pip-audit) in narrative wave descriptions. The phase invariants themselves are language-neutral and resolve through active-packages.json + toolchain. Multi-tenant SaaS context preserved per F-008. -->

# Phase 3: Testing

## Purpose

Exhaustive verification beyond the TDD tests written in Phase 2. Adds integration tests against real backends, benchmarks vs. baseline, fuzz, leak verification, and flake detection.

## Input

- Target branch (`sdk-pipeline/<run-id>`) in `$SDK_TARGET_DIR`
- `runs/<run-id>/design/*`
- `baselines/go/performance-baselines.json`

## Waves

### Wave T1 — Unit Coverage Audit
**Agent**: `unit-test-agent`
- Run `go test -cover ./<pkg>/...`
- Report per-package branch coverage
- Fill gaps with new table-driven tests (error paths, edge cases, boundary values, nil inputs, concurrent access)
- Target: ≥90% per new package; zero delta on existing (Mode B/C)

### Wave T2 — Integration (testcontainers)
**Agent**: `integration-test-agent`
- Set up testcontainers recipe per backend: redis, dragonfly, minio, localstack, kafka, rabbitmq, etc.
- Tag files `//go:build integration`
- Test full lifecycle: connect → operate → close → verify cleanup
- Tenant isolation NOT applicable (SDK is a library)

### Wave T3 — Flake Hunt
**Agent**: `sdk-integration-flake-hunter-go`
- Run integration tests `-count=3`
- Any failure = flaky; BLOCKER until investigated + fixed

### Wave T4 — Benchmarks
**Agent**: `performance-test-agent`
- Write `*_benchmark_test.go` for every hot path declared in TPRD §5 NFR
- Run `go test -bench=. -benchmem -count=5 ./<pkg>/...`
- Capture output to `runs/<run-id>/testing/bench-raw.txt`

### Wave T5 — Benchmark Devil
**Agent**: `sdk-benchmark-devil-go`
- Compare raw output against `baselines/go/performance-baselines.json` for shared packages
- For new package: capture baseline (first run = baseline)
- `benchstat` compare; verdict PASS / REGRESS / ACCEPT-WITH-WAIVER
- Regression gate (from settings.json): hot path +5%, shared +10%
- FAIL = BLOCKER unless `--accept-perf-regression <n>`

### Wave T6 — Leak Hunt
**Agent**: `sdk-leak-hunter-go`
- Ensure `goleak.VerifyTestMain` in new package's TestMain
- Run `go test -race -count=5 ./<pkg>/...`
- Any leak = BLOCKER

### Wave T7 — Fuzz (conditional)
**Agent**: `fuzz-agent` (new, minimal)
- If TPRD §11 lists fuzz targets, write `FuzzXxx` functions
- Seed corpus from happy path + edge cases
- Run `go test -fuzz=FuzzXxx -fuzztime=30s`
- Record crashes

### Wave T8 — Supply Chain
**Agent**: `guardrail-validator`
- `govulncheck ./...` — zero HIGH/CRITICAL
- `osv-scanner ./go.mod` — zero HIGH/CRITICAL

### Wave T9 — Observability Tests (conditional)
**Agent**: `observability-test-agent`
- If TPRD §8 listed required spans/metrics: verify they actually emit
- In-memory OTel exporter; span matchers

### Wave T10 — Mutation (optional)
**Agent**: `mutation-test-agent`
- Run on critical business logic packages
- Target: 70%+ mutation score
- Kill surviving mutants with additional tests

### Wave T11 — HITL Gate H8 (if any regression)
**Artifact**: `runs/<run-id>/testing/perf-delta.md`
**Options**: Accept (+ file follow-up) / Reject
**Default**: Reject
**Bypass**: `--accept-perf-regression <n>`

## Exit artifacts

- Test files merged onto branch
- `runs/<run-id>/testing/coverage.txt`
- `runs/<run-id>/testing/bench-raw.txt`
- `runs/<run-id>/testing/bench-compare.md`
- `runs/<run-id>/testing/govulncheck.txt`
- `runs/<run-id>/testing/osv-scan.txt`
- `runs/<run-id>/testing/testing-summary.md`

## Guardrails (exit gate)

G60 (all tests pass -race), G61 (coverage ≥90%), G62 (goleak in TestMain), G63 (no flakes under -count=3), G64 (bench produces numbers), G65 (bench within gate), G66 (integration build-tag), G67 (Example_* per area), G68 (traces-to in tests), G69 (no hardcoded creds).

## Metrics

- `test_coverage_pct` (target ≥90%)
- `benchmark_delta_pct`
- `vuln_count` (must be 0)
- `leak_count` (must be 0)
- `flake_rate` (must be 0)
- `mutation_score_pct` (if run)
- `testing_duration_sec`

## Typical durations

- Mode A simple: ~45 min (integration containers take most time)
- Mode B extension: ~30 min (fewer new tests, existing bench re-runs)
- Mode C incremental: ~20 min
