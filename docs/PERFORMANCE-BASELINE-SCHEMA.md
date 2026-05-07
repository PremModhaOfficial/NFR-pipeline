<!-- Pipeline: 0.7.0 -->
<!-- Authored: 2026-05-06 -->
<!-- Locked decisions: Option A (preserve Go↔Python divergence) + sub-gap C.1 (keying convention divergence intentional) -->

# Performance Baseline Schema

Single source of truth for the on-disk shape of `baselines/<lang>/performance-baselines.json`.

This file exists to close Gap C from `docs/POST-PILOT-IMPROVEMENT-ROADMAP.md` (U15) — four different schemas were previously documented across different agent prompts, none matching what is actually written to disk. **This document IS the canonical specification**; any agent prompt that contradicts it MUST be updated to match (or this document MUST be updated to reflect a deliberate evolution).

---

## Status

- **Schema version (current)**: `1.0`
- **Schema owner (sole writer)**: `agents/baseline-manager.md`
- **Decision regime**: shared envelope + per-language extensions; Go and Python intentionally diverge
- **Locked**: 2026-05-06 (Option A — divergence preserved; no Go migration to Python's richer history+verdict shape)

## Owner declaration

`agents/baseline-manager.md` is the **sole writer** of `baselines/<lang>/performance-baselines.json`. Every other agent that touches this file is read-only or proposes updates via `runs/<id>/testing/proposed-baseline-{lang}.json`, which `baseline-manager` merges after HITL gate H8 acceptance.

| Agent | Role | Reads via |
|---|---|---|
| `baseline-manager` | WRITER | direct file write at phase exit |
| `sdk-benchmark-devil-go` | READER + PROPOSER | reads JSON; proposes via `runs/<id>/testing/proposed-baseline-go.json` |
| `sdk-benchmark-devil-python` | READER + PROPOSER | reads JSON; proposes via `runs/<id>/testing/proposed-baseline-python.json` |
| `sdk-intake-agent` | READER (floor lookup) | reads `packages.<pkg>.symbols.<bench>` (Go) / `packages.<pkg>.history[-1].symbols.<sym>` (Python) at H1 to validate constraint floor claims |
| `sdk-testing-lead` | READER (informational) | phase input listing |

---

## Required envelope (every file MUST satisfy)

```json
{
  "schema_version": "<semver>",
  "language": "go" | "python",
  "scope": "per-language",
  "packages": { "<pkg-key>": { /* per-language extension; see below */ } }
}
```

Validation rules:

1. `schema_version` matches a known version in this document's Changelog
2. `language ∈ {"go", "python"}`
3. `scope == "per-language"` (the only currently-supported value)
4. `packages` is a JSON object (NOT an array)
5. `language` MUST match `runs/<id>/context/active-packages.json:target_language` when run context is available

## Optional envelope-level fields

| Field | Type | Notes |
|---|---|---|
| `description` | string | Human-readable purpose. Python uses this today: `"Per-symbol benchmark baselines. First-run seed for each new package; subsequent runs append to history[]..."` |
| `host_load_class` | string OR object | Captures runtime conditions for fairness in cross-run comparison. Object form (Python uses today): `{kernel, arch, python|go, container_engine, load_class}`. String form (also valid): `"dedicated-test-vm"` |
| `policy` | string | Describes how the file is updated. Python uses today: `"first-seed-then-rolling-50"` |

These fields are valid on either language but only Python populates them today. Go MAY adopt without a schema_version bump.

---

## Per-language extension — Go

Go shape is **flat current-state snapshot** (no time series, no per-run verdict trail).

```json
"packages": {
  "<pkg-key>": {
    "generated": "2026-05-06",
    "run_id": "l2cache-dragonfly-go-pilot-v1",
    "package": "motadatagosdk/core/l2cache/dragonfly",
    "scope": "per-language",
    "language": "go",
    "symbols": {
      "<bench>": {
        "ns_per_op_median": 6388,
        "bytes_per_op_median": 9040,
        "allocs_per_op_median": 70,
        "samples": 3
      }
    }
  }
}
```

**Per-package required fields** (all 6):
- `generated` — date string `"YYYY-MM-DD"` (NOT full ISO datetime)
- `run_id` — uuid or human ID of the run that produced this snapshot
- `package` — full module path (denormalized; redundant with envelope `language` + key `<pkg-key>`)
- `scope` — denormalized; MUST equal envelope `scope`
- `language` — denormalized; MUST equal envelope `language`
- `symbols` — dict of bench-name → measurement

**Per-symbol required fields** (all 4):
- `ns_per_op_median` — integer nanoseconds per op (median across `samples` runs)
- `bytes_per_op_median` — integer bytes allocated per op (median)
- `allocs_per_op_median` — integer alloc count per op (median)
- `samples` — integer count of bench runs aggregated

**Per-symbol optional fields**: none today.

`<pkg-key>` convention: relative path inside the SDK module (e.g. `"l2cache/dragonfly"`, NOT the full module path).

`<bench>` key convention: Go bench function name (e.g. `BenchmarkGet`, `BenchmarkPipeline_100`).

---

## Per-language extension — Python

Python shape is **time-series** with full per-run verdict trail (rule 32 perf-confidence regime).

```json
"packages": {
  "<pkg-key>": {
    "first_seen_run": "motadata-nats-v1",
    "first_seen_at": "2026-05-04T15:30:00Z",
    "history": [
      {
        "run_id": "motadata-nats-v1",
        "pipeline_version": "0.6.0",
        "recorded_at": "2026-05-04T15:30:00Z",
        "regression_verdict": "INCOMPLETE-first-seed",
        "g108_oracle_verdict": "INCOMPLETE-aspirational",
        "symbols": {
          "<sym>": {
            "p50_us": 43.03,
            "rounds": 200,
            "iterations": 5,
            "budget_p50_us": 250.0,
            "budget_status": "PASS",
            "headroom": 5.8,
            "go_oracle_p50_us": 80.0,
            "oracle_margin_observed": 0.54,
            "oracle_margin_threshold": 2.5,
            "oracle_status": "PASS"
          }
        },
        "complexity_sweep_g107": { /* sibling structure; see below */ },
        "alloc_audit_g104": { /* sibling structure; see below */ }
      }
    ]
  }
}
```

**Per-package required fields** (all 3):
- `first_seen_run` — run_id that established this baseline
- `first_seen_at` — ISO 8601 datetime of first appearance
- `history` — array, ≥1 entry, append-only across runs

**Per-history-entry required fields** (3):
- `run_id`
- `recorded_at` — ISO 8601 datetime
- `symbols` — dict of symbol-name → measurement

**Per-history-entry optional fields** (5):
- `pipeline_version` — semver string
- `regression_verdict` — see [Verdict enums](#verdict-enums)
- `g108_oracle_verdict` — see [Verdict enums](#verdict-enums)
- `complexity_sweep_g107` — see [Per-history-entry sibling structures](#per-history-entry-sibling-structures-python-only)
- `alloc_audit_g104` — see [Per-history-entry sibling structures](#per-history-entry-sibling-structures-python-only)

**Per-symbol required fields** (3):
- `p50_us` — float median latency in microseconds
- `rounds` — integer pytest-benchmark round count
- `iterations` — integer pytest-benchmark iterations per round

**Per-symbol optional fields** (10):
- `p50_min_us`, `p50_max_us` — min/max bounds across rounds (only present on some symbols)
- `budget_p50_us` — declared latency budget from `runs/<id>/design/perf-budget.md`
- `budget_status` — see [Verdict enums](#verdict-enums); valid only when `budget_p50_us` is set
- `headroom` — float multiplier under budget (e.g. `5.8` = 5.8× under budget); valid only when `budget_p50_us` is set
- `diagnosis` — free-form string explaining a non-PASS verdict; only present on FAIL/INCOMPLETE
- `go_oracle_p50_us` — Go reference number for cross-language oracle (G108)
- `oracle_margin_observed` — `p50_us / go_oracle_p50_us` ratio
- `oracle_margin_threshold` — declared acceptable margin
- `oracle_status` — see [Verdict enums](#verdict-enums); valid only when oracle fields are set

`<pkg-key>` convention: dotted Python module path stem (e.g. `"motadata_nats"`).

`<sym>` key convention inside `symbols`: dotted `module.Class.method` or `module.func_<variant>` form (e.g. `corenats.Publisher.publish`, `core.inject_context_3keys`). One entry per benchmark function.

---

## Per-history-entry sibling structures (Python only)

These structures are **peers of `symbols`** under one `history[N]` entry, NOT nested inside `symbols`. They carry per-run audit results from rule 32 perf-confidence gates.

### `complexity_sweep_g107` (G107 big-O scaling sweep results)

```json
"complexity_sweep_g107": {
  "<swept-sym>": {
    "loglog_slope": 0.81,
    "r2": 0.99,
    "expected": "linear (slope ≈ 1.0)",
    "verdict": "PASS",
    "notes": "..."
  }
}
```

Per-entry required: `loglog_slope` (float), `r2` (float, goodness-of-fit), `expected` (human-readable string), `verdict` (see [Verdict enums](#verdict-enums)).
Per-entry optional: `notes` (string).

### `alloc_audit_g104` (G104 alloc/heap budget audit results)

```json
"alloc_audit_g104": {
  "<audited-sym>": {
    "bytes_per_call": 0,
    "budget_bytes": 400,
    "verdict": "PASS"
  },
  "notes": "tracemalloc proxy; positive-only size_diff sum; ±200B noise floor..."
}
```

Per-entry required: `bytes_per_call` (integer), `budget_bytes` (integer, from perf-budget.md), `verdict` (see [Verdict enums](#verdict-enums)).
Per-structure optional: top-level `notes` (string) — free-form audit-level commentary that lives **alongside** the per-symbol entries inside the same dict. This is a deliberate schema-modeling exception; readers MUST handle the `"notes"` key as a non-symbol entry. See [Sub-gap C.1](#sub-gap-c1-keying-convention-divergence-is-intentional) for context.

---

## Sub-gap C.1 — keying convention divergence is intentional

The three sibling structures inside one `history[N]` entry use **different key conventions** because each measures a different scope:

| Sibling | Key shape | Example | Why |
|---|---|---|---|
| `symbols.<sym>` | `module.Class.method` or `module.func_<variant>` | `corenats.Publisher.publish`, `core.inject_context_3keys` | One entry per benchmark function (variants get distinct keys) |
| `alloc_audit_g104.<sym>` | `module.func` (no per-call-variant suffix) | `core.inject_context` (no `_3keys`) | One entry per source-level function (variants share an allocation budget) |
| `complexity_sweep_g107.<sym>` | `module.symbol_over_<param>` | `core.extract_headers_over_H` | One entry per scaling sweep (sweeps a parameter; not always an exact symbol) |

**Cross-walking between siblings is NOT 1:1 by design.** Readers MUST NOT assume that `symbols`, `alloc_audit_g104`, and `complexity_sweep_g107` share a primary-key relationship. The G87 validation guardrail MUST NOT enforce parent-child keying across these.

If you find yourself needing to JOIN them, do so by manual judgment of the underlying source-level symbol — not by string-equal lookup.

---

## Verdict enums

The `verdict` / `*_status` / `regression_verdict` / `g108_oracle_verdict` fields use the rule 33 base taxonomy plus optional composite modifiers:

**Pattern**: `^(PASS|FAIL|INCOMPLETE)(-[a-z][a-z-]*)?$`

**Base verdicts** (rule 33):
- `"PASS"` — gate ran to completion; no violation
- `"FAIL"` — gate ran; detected a violation
- `"INCOMPLETE"` — gate could not render a verdict (insufficient samples, MMD not reached, profiler unavailable, harness crashed)

**Composite forms observed in real data** (all valid):
- `"INCOMPLETE-first-seed"` — no prior baseline to compare against (first run for new package)
- `"INCOMPLETE-aspirational"` — declared target was aspirational, not measurement-grade
- `"FAIL-INCOMPLETE-aspirational"` — failed numerically, but classified INCOMPLETE because the target itself was aspirational (per CALIBRATION-WARN classification skill)

Composite modifiers MUST be lowercase, hyphenated, and start with a letter. Composite forms NEVER auto-promote to PASS at H9 — see CLAUDE.md rule 33.

---

## schema_version semver rules

- **PATCH** (1.0.0 → 1.0.1) — typo fix in description, doc-only change to this file, clarification of an enum value
- **MINOR** (1.0.0 → 1.1.0) — new optional field added (existing readers ignore safely); new optional sibling structure added under `history[N]`
- **MAJOR** (1.0.0 → 2.0.0) — required field added or removed; type change of an existing field; per-language extension shape change; sub-gap C.1 keying convention reformed

Bumping requires updating this document's [Changelog](#changelog), bumping the `schema_version` value emitted by `baseline-manager`, AND verifying G87 accepts both old + new during the migration window.

---

## Validation rules (G87 will encode)

The G87 guardrail (`scripts/guardrails/G87.sh`, to be authored as part of U15 Phase 6) MUST validate at Phase 3 (Testing) exit:

**Envelope checks** (both languages):
1. File parses as valid JSON
2. Top-level keys present: `schema_version`, `language`, `scope`, `packages`
3. `language ∈ {"go", "python"}`
4. `scope == "per-language"`
5. `packages` is a JSON object
6. `language` matches `runs/<id>/context/active-packages.json:target_language`
7. `schema_version` matches a known version in this document's [Changelog](#changelog)

**Go-specific checks**:
8. Every `packages.<pkg>` MUST have `generated`, `run_id`, `package`, `scope`, `language`, `symbols`
9. Every `packages.<pkg>.symbols.<bench>` MUST have all 4 numeric fields (`ns_per_op_median`, `bytes_per_op_median`, `allocs_per_op_median`, `samples`)

**Python-specific checks**:
10. Every `packages.<pkg>` MUST have `first_seen_run`, `first_seen_at`, `history`
11. `history` is a non-empty array
12. Every `history[N]` MUST have `run_id`, `recorded_at`, `symbols`
13. Every `history[N].symbols.<sym>` MUST have `p50_us`, `rounds`, `iterations`
14. Verdict-typed fields match the [verdict enum pattern](#verdict-enums)

**G87 MUST NOT enforce**:
- Parent-child keying between `symbols`, `alloc_audit_g104`, `complexity_sweep_g107` (sub-gap C.1)
- Presence of optional fields
- Cross-history-entry consistency (each entry stands on its own)

---

## Why divergence is preserved (the rationale)

Python's schema is a superset of capabilities — full time-series history, per-run verdict trail (G104/G107/G108), per-symbol budget tracking with headroom, cross-language oracle comparison, host-load fairness fields. Go's schema is a slimmer current-state snapshot with native Go alloc count and bytes-per-op.

Three reasons divergence is intentional:

1. **Both shapes are real and load-bearing** — Python's history-array structure is consumed by `sdk-benchmark-devil-python` for time-series regression checks; Go's flat-symbols structure is consumed by `sdk-benchmark-devil-go`'s benchstat workflow. Neither can be deleted.
2. **No functional benefit to forced unification** — promoting Go to Python's `history[]` shape would require a one-time data migration AND a Go-side writer-prompt rewrite to populate the new fields (G108 oracle, G104 budget tracking, etc. don't exist for Go today).
3. **Honest documentation > hidden divergence** — declaring the divergence is cheaper than hiding it.

A future decision to grow Go's history+verdict shape remains open; this document just adds a new schema_version entry when that happens.

---

## Out of scope for this document

- Rule 32 perf-confidence regime (G104/G105/G106/G107) — referenced, not redefined here. See `CLAUDE.md` rule 32.
- Verdict taxonomy semantics (PASS/FAIL/INCOMPLETE) — referenced, not redefined. See `CLAUDE.md` rule 33.
- Benchmark execution mechanics (`go test -bench`, `pytest-benchmark`) — out of schema concern.
- The H8 HITL acceptance flow — referenced, not redefined. See `phases/TESTING-PHASE.md` and `agents/sdk-benchmark-devil-{go,python}.md`.
- Cross-language comparison (G108 oracle) — Python-only today; future Go-side adoption is non-blocking and additive.
- Migration of Go file to Python's richer history shape — explicitly locked OUT (Option A, U15 decision 2026-05-06).

---

## Changelog

| schema_version | Date | Change | Authored by |
|---|---|---|---|
| 1.0 | (existing on-disk reality, retro-documented 2026-05-06) | First canonical declaration. Shared envelope + Go and Python per-language extensions. Sub-gap C.1 (keying convention divergence) declared intentional. | U15 Phase 3 |

---

## References

- `agents/baseline-manager.md` — schema owner / sole writer
- `agents/sdk-benchmark-devil-{go,python}.md` — primary readers + proposers
- `scripts/guardrails/G87.sh` — schema validation guardrail (to be authored, U15 Phase 6)
- `docs/POST-PILOT-IMPROVEMENT-ROADMAP.md` U15 — the gap that motivated this document
- `CLAUDE.md` rule 32 — perf-confidence regime (G104/G105/G106/G107/G109/G110)
- `CLAUDE.md` rule 33 — verdict taxonomy
- `CLAUDE.md` rule 28 — compensating baselines (this file is one)
