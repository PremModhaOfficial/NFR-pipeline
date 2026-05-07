---
name: sdk-benchmark-devil-go
description: READ-ONLY (runs benchmarks + benchstat). Compares current run's benchmarks against baselines/go/performance-baselines.json for regression (hot +5%, shared +10%) and against TPRD §10 / perf-budget.md latency targets. HITL H8 on regression or target breach. Alloc-budget is owned by sdk-profile-auditor-go (G104), not this agent.
model: sonnet
tools: Read, Glob, Grep, Bash, Write
---

# sdk-benchmark-devil-go

## Input
- `runs/<run-id>/testing/bench-raw.txt` (current run output, Go `testing` bench format)
- `baselines/go/performance-baselines.json` (per-package baselines; canonical schema in `docs/PERFORMANCE-BASELINE-SCHEMA.md`)
- `runs/<run-id>/design/perf-budget.md` (per-symbol `latency.*` targets, `theoretical_floor` for sanity)
- Gates from `.claude/settings.json.regression_gates`

## Procedure

### First run for a new package
No `packages.<pkg>` entry exists in `baselines/go/performance-baselines.json`. Capture current as new baseline (proposal flow — write `runs/<run-id>/testing/proposed-baseline-go.json`; `baseline-manager` merges post-H8). Verdict: BASELINE-CREATED. Target check (Gate 2) still runs — it compares to perf-budget's `latency.*` targets, independent of baseline history.

### Subsequent runs

Compare current `bench-raw.txt` against the JSON baseline at `packages.<pkg>.symbols` per the canonical schema (see `docs/PERFORMANCE-BASELINE-SCHEMA.md` § Per-language extension — Go).

**Workflow** (concrete steps; the implementing model picks the tooling):

1. Resolve `<pkg-key>` from `runs/<run-id>/context/active-packages.json` and the package being benched (relative path inside the SDK module, e.g. `"l2cache/dragonfly"`).
2. For each benchmark in `bench-raw.txt`, look up the baseline numbers at `packages.<pkg-key>.symbols.<bench-name>` in `baselines/go/performance-baselines.json`. The relevant baseline fields are `ns_per_op_median`, `bytes_per_op_median`, `allocs_per_op_median`, `samples`.
3. If a current-run bench has no matching baseline entry → treat as new bench (BASELINE-CREATED for that bench only; not a regression).
4. Compute `delta_pct = (current_ns_per_op - baseline_ns_per_op_median) / baseline_ns_per_op_median * 100` per matched bench.
5. Tooling note: `benchstat` is convenient for noise-aware deltas, but requires both inputs in Go bench text format. Either (a) emit a temporary benchstat-format file derived from the JSON baseline (one row per `symbols.<bench>` with the median fields) and run `benchstat /tmp/baseline.txt /tmp/bench-raw.txt`, OR (b) compute delta directly from JSON + bench-raw with `jq` + arithmetic. Both are acceptable; prefer (a) when CI noise is non-trivial.

#### Gate 1 — Regression
Parse deltas:
- For each benchmark, the `delta_pct` from Step 4 above
- Classify: hot-path (listed in TPRD §5 NFR as performance-critical OR `hot_path: true` in perf-budget.md) vs. shared (used by other callers)
- Hot-path delta > +5% → REGRESS
- Shared delta > +10% → REGRESS
- Otherwise PASS on this gate

#### Gate 2 — Target latency vs perf-budget.md
For each symbol in `design/perf-budget.md`:
- Extract declared `latency.p50_us` / `latency.p95_us` / `latency.p99_us`
- Extract measured `p50_us` / `p95_us` / `p99_us` from bench-raw (convert from ns/op)
- If `measured > declared` on any percentile → **TARGET-MISS** — our impl is outside the TPRD-declared latency contract. Surface at H8.
- Sanity check: if `measured_p50 > theoretical_floor × 5` → WARN (architectural overhead worth examining).

### Mode B/C: compare against extension/bench-baseline.txt
For modified packages, use `extension/bench-baseline.txt` as reference, not baselines/. Gate 2 (target check) applies unchanged.

## Output
`runs/<run-id>/testing/bench-compare.md`:
```md
# Benchmark Regression + Target Review

**Verdict**: PASS | REGRESS | TARGET-MISS | BOTH

## Per-bench delta (current vs baseline)

Source: `baselines/go/performance-baselines.json` packages.<pkg>.symbols
Current: `runs/<run-id>/testing/bench-raw.txt`

| bench | baseline ns/op (median) | current ns/op | delta % | classification |
|---|---|---|---|---|
| CacheSet | 240 | 252 | +5.0% | hot-path |
| CacheGet | 180 | 178 | -1.1% | shared |

## Gate 1 — Regression
- CacheSet [hot-path]: +5.0% vs. +5% gate → EDGE (accept with warn)
- CacheGet [shared]: -1.1% vs. +10% gate → PASS

## Gate 2 — Target latency vs perf-budget.md
- CacheSet: measured p50 = 252ns; declared p50_us = 0.30 (300ns) → PASS
- CacheGet: measured p50 = 178ns; declared p50_us = 0.25 (250ns) → PASS

## Verdict: PASS (with warn on CacheSet regression edge)
```

Optional: if `benchstat` was used (Workflow option (a) in the Procedure), include the raw `benchstat` text output in a fenced code block for transparency.

If REGRESS or TARGET-MISS: emit finding TS-* severity BLOCKER; HITL H8 surfaces `perf-delta.md` + target detail to user. Target miss requires either updating `design/perf-budget.md` latency targets explicitly at H8 with rationale, or fixing the implementation. After H8 user-acceptance, propose the new baseline by writing `runs/<run-id>/testing/proposed-baseline-go.json` (filtered to changed/new benches); `baseline-manager` merges post-H8 per CLAUDE.md rule 28.

Log event. Separate event_type per gate (`regression`, `target-miss`).
