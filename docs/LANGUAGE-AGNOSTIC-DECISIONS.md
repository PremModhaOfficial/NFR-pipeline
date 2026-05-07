<!-- cross_language_ok: true — pipeline design/decision doc references per-pack tooling. Multi-tenant SaaS platform context preserved per F-008. -->

# Language-Agnostic Decision Board

**Status**: living document. Last update: 2026-04-27 (v0.5.0 Phase A scaffold + R2 spike).
**Audience**: future contributor (or future-Claude) picking up the multi-language work for v0.5.0+.
**Reading order**: §TL;DR → §Decisions taken → §Per-touchpoint handling table → §Open questions → §Research branches → §Next-version checklist.

---

## TL;DR

The pipeline is being made language-agnostic the **agents-are-policy, languages-are-data** way. One fleet of ~40 general agents; languages plug in as JSON package manifests + (eventually) adapter scripts. v0.4.0 shipped the package layer (manifest-only, no file moves, all current behavior preserved for Go T1 runs). v0.5.0 will pilot Python as the second adapter.

This document is the **decision register** — every architectural call that needs human judgment, with options + tradeoffs, what was chosen, and what was deferred and why.

---

## Decisions taken (v0.4.0 session, 2026-04-27)

| ID | Question | Decision | Rationale |
|---|---|---|---|
| **D1** | Baseline shape: flat-with-scope-field (A) vs per-language subdirectory (B) vs hybrid (C) | **B — per-language subdirectory** (shipped in v0.4.0) | Path encodes meaning; cleaner separation; matches "one file per concept per partition." Cross-language comparison was explicitly ruled out as a v0.5.0 goal, so the partition isolation is fine. v0.4.0 ships with files moved to `baselines/{go,shared}/` AND consumer path-refactor done (~70 substitutions across 21 files). |
| **D3** | Output-shape hash strategy: per-language native (1) vs neutral-IDL hash (2) vs drop comparison (3) | **1 — per-language native** | Each language hashes its own AST. No cross-language hash equivalence. Neutral-IDL was over-engineering for the actual purpose (intra-language churn detection). |
| **D4** | Perf units: native per language (1) vs single neutral unit (2) vs both (3) | **1 — native units per language** | `allocs/op` (Go), CPython-cycles (Python), B/op (Rust) stay native. No cross-language perf comparison; latency targets are per-language and TPRD-declared. Bucketed neutral was nice-to-have but not load-bearing. |
| **D5** | Which language pilot first: Python vs Rust vs TypeScript vs Java | **Python** | Maximum stress on the abstraction (most different from Go: async runtime, no compile-time types, different allocator). An abstraction that survives Python adapts trivially to Rust/Java. |
| **D6** | Generalization-debt resolution timing: Eager vs Lazy vs Split | **Split — rule shared, examples + per-lang rules in `<pack>/conventions.yaml`** | R2 spike (2026-04-27, `docs/R2-DEBT-REWRITE-FEASIBILITY.md`) sampled three debt-bearers. ~85–95% of rule body neutralizes cleanly; the rest are genuine per-language variants. Eager-rewrite produces vacuous prose; Lazy-rewrite delays the structural decision. Split keeps rule logic DRY while letting examples pattern-match per language. |
| **D2** | Cross-language fairness for shared-core agents with `generalization_debt`: Strict vs Lenient vs Progressive | **Lenient default + Progressive fallback** | Once D6=Split lands, the rule layer is genuinely shared, so quality_score divergence shouldn't be expected. Cheap default: keep one shared `quality-baselines.json`. Escape hatch: if first Python pilot run shows ≥3pp systematic divergence on any debt-bearer, flip that specific agent to Progressive (per-language partition) until its Split rewrite ships. |
| **L1–L7** | (See §0 below) — manifest-only packaging, one fleet, toolchain inline, T1/T2/T3, manifests human-PR'd, generalization-debt as backlog mechanism, backwards-compat fallback in dispatch | **Locked** | Each rationale carried in commit history + CLAUDE.md rule 34. |

### Decisions deferred (none currently)

All v0.4.0/R2 decisions taken. Tier-2/Tier-3 questions in §2/§3 remain open by design — they need Python pilot data to surface naturally.

---

## §0. Locked decisions from earlier turns (context only)

These are settled — included so a future reader knows what's already implicit.

| # | Decision | Locked because |
|---|---|---|
| **L1** | Manifest-only packaging. No physical per-language directories under `.claude/`. | Claude Code harness auto-discovers `agents/*.md` + `skills/*/SKILL.md`; physical packaging silently breaks discovery. |
| **L2** | One agent fleet, languages are data. No `<lang>-leak-hunter` forks. | Rule 34 anti-fork armor (G213/G214/G215 proposed but not yet codified). |
| **L3** | Toolchain inline in manifest for v0.4.0; externalize in v0.5.0. | Premature externalization with one language. |
| **L4** | Tier model = T1/T2/T3. T1 full-fat, T2 lint+supply-chain only, T3 rejected at intake. | Defaulted; might revisit (see Tier-3 deferred decision Q). |
| **L5** | Manifests are human-PR'd, not runtime-synthesized. | Rule 23 extended to package manifests. |
| **L6** | `generalization_debt` array per manifest = the multi-lang backlog. | Single source of truth instead of separate tracking doc. |
| **L7** | Backwards-compat fallback in dispatch ("if `active-packages.json` missing, run everything"). Removed in v0.5.0. | Replay safety vs cleanliness tradeoff. |

---

## §1. Per-touchpoint handling table — every Go-leaky thing and how to handle it

This is the load-bearing artifact. For each Go-specific concept in the pipeline, the proposed handling shape, the governing decision, and the v0.5.0 implementation note.

| Touchpoint | Shape (v0.4.0+, shipped) | Future evolution | Governed by | Notes |
|---|---|---|---|---|
| **Baselines: perf, coverage, output-shape, devil-verdict, do-not-regenerate-hashes, stable-signatures, regression-report** | `baselines/go/<file>` with `scope: per-language, language: go` stamp. Manifest declares `owns_per_language` + `owns_per_language_paths`. | v0.5.0 adds `baselines/python/<file>` parallel partition. | D1=B | Done in v0.4.0: file moves + consumer path-refactor across baseline-manager, metrics-collector, learning-engine, sdk-benchmark-devil-go, sdk-intake-agent, sdk-skill-coverage-reporter, sdk-testing-lead, G81/G86/G101, etc. Mechanical extension to Python. |
| **Baselines: quality, skill-health, baseline-history** | `baselines/shared/<file>` with `scope: shared` stamp. Manifest declares `owns_shared` + `owns_shared_paths`. | If D2 lands as Strict in v0.5.0, debt-bearer subset moves to `languages.<lang>` partition until rewritten. | D1=B | Done in v0.4.0. |
| **Cross-language baseline comparison** (e.g. is `sdk-design-devil`'s quality systematically lower in Python runs?) | n/a | **NOT a v0.5.0 goal.** Each adapter compares against its own history. | D1=B + D2 deferred | Don't build cross-language reporting. If pressure builds, do R1 study first. |
| **Output-shape AST hash** | Go AST → SHA256 of sorted exported-symbol signatures | Per-language native: `baselines/go/output-shape-history.jsonl` uses Go AST; `baselines/python/output-shape-history.jsonl` uses Python `ast` module. No cross-language hash equivalence. | D3=native | Each adapter ships its own hasher. Coarse cross-lang sanity (symbol-count delta) is a possible add-on but not required. |
| **Perf units** (allocs/op, ns/op, B/op) | Go-native in `baselines/go/performance-baselines.json` + `runs/<id>/design/perf-budget.md` | Per-language native. `language: go` adapter declares `units: {latency: "ns/op", alloc: "allocs/op", memory: "B/op"}`. Python adapter declares its own units. | D4=native | No bucketed neutral mapping. Latency targets (TPRD-declared) are per-language. |
| **`Example_*` count** (Go-only concept) | Counted per-package in `coverage-baselines.json` | Adapter materializes the metric per-language: Go = `Example_*` testable functions, Python = `>>>` doctests, Rust = `#[example]`. Coverage baseline becomes per-language. | D1=B + adapter responsibility | The METRIC name stays "examples_per_pkg" but the materialization differs. |
| **Marker comment syntax** (`//`, `/* */`) | `marker_comment_syntax` field on language manifest | Same — already neutralized via per-lang declaration | (already in shape) | No work. |
| **Marker payloads** (`[constraint: bench/BenchmarkX]`) | Go-shaped (literal Go bench path) | Two options being considered: (a) keep Go-style per-language, adapter-resolved, (b) introduce neutral form `[constraint: <metric> <op> <value> on workload <W>]` and let adapters resolve to local bench id. | T2-4 (decide during Python pilot) | First Python `[constraint:]` marker forces this. |
| **Toolchain commands** | Inline strings in manifest `toolchain` block | Externalized to `adapters/<seam>.sh` referenced by manifest path. Adapter emits normalized JSON to stdout. | L3 + T2-7 | v0.5.0 work. |
| **Profile artifact** (Go pprof in M3.5) | Hardcoded pprof in `sdk-profile-auditor-go` agent | `seam:profile` adapter runs language-native profiler (pprof / py-spy / cargo-flamegraph). Parser emits normalized JSON profile schema (top-N functions + alloc sites + mutex contention). Agent reads schema, not raw tool output. | T2-7 | v0.5.0; the parser is the load-bearing artifact. |
| **Bench output** (benchstat-formatted) | Hardcoded `go test -bench` parsing | `seam:bench` adapter runs language-native bench, parser emits normalized: `{benchmark, language, metric, unit, p50, p95, p99, allocs}`. Agent's regression math is shared. | T2-7 | v0.5.0. |
| **Leak detection** (goleak) | Hardcoded in `sdk-leak-hunter-go` | `seam:leak-check` adapter runs goleak (Go) / asyncio leak detector (Python) / miri (Rust). Returns boolean + leaked-resources list. | T2-7 | v0.5.0. |
| **Soak harness** (`run_in_background` + state file) | Generic state-file shape | State file format already neutral; per-lang harness writes `ops`, `heap_bytes`, `concurrency_units` (renamed from `goroutines` — see drift signals below) | T2-3 (drift signals taxonomy) | The harness is fine; only the FIELD NAMES need neutralizing. |
| **Drift signals** (`heap_bytes`, `goroutines`, `gc_pause_p99_ns`) | Go-named (`goroutines` is Go-only) | Neutral abstraction: `concurrency_units` (count of OS threads OR async tasks OR goroutines). `heap_bytes` and `gc_pause_p99_ns` already neutral but Python's GC is a different beast — define what we MEAN by gc_pause when applied cross-language. | T2-3 | Pilot Python soak; rename surfaces naturally. |
| **Big-O scaling sweep** (Go `testing.B` at N∈{10,100,1k,10k}) | Hardcoded Go bench harness | `seam:scaling-harness` per-language. `sdk-complexity-devil-go`'s curve-fit + comparison logic is shared. | T2-7 | v0.5.0. |
| **Supply-chain scanners** (govulncheck/osv-scanner) | Inline in `toolchain.supply_chain` array | Per-lang scanners (pip-audit / cargo-audit / npm audit). License allowlist stays neutral (MIT/Apache-2.0/BSD/ISC/0BSD/MPL-2.0). | (already in shape) | Python adapter declares `["pip-audit", "safety check"]`; rest is plumbing. |
| **Type lattice for §7 API symbols** | Free-form §7 in TPRD; agents read Go type literals | Neutral IDL with per-lang type mapping. **DEFER until N=3** (third language). At N=2, free-form is fine. | T3-1 | Don't engineer this in v0.5.0. |
| **Concurrency idioms in skills** (`go-concurrency-patterns`) | Lives in `go` package | Stay in `go`; v0.5.0 adds `python-asyncio-patterns` etc. as separate skills. | (already in shape) | No work — just author per-lang skills as needed. |
| **Error idioms** (`go-error-handling-patterns`) | Lives in `go` package | Same — per-language skill. | (already in shape) | No work. |
| **Convention layer** (`Config struct + New(cfg)`) | Embedded in agent prompts (sdk-convention-devil-go, sdk-design-devil) | `conventions.yaml` per language pack; `sdk-convention-devil-go` reads from pack instead of hardcoding. **R2 confirmed: this seam is load-bearing for D6=Split.** | T2-5 + D6 (Split) | First Python `sdk-convention-devil-go` run forces materialization. |
| **Mock framework** (gomock) | `go-mock-patterns` skill | Per-language skill: `gomock-patterns` / `unittest-mock-patterns` / `mockall-patterns`. | T3-2 | Wait for N=3. |
| **Container test framework** (testcontainers-go) | `go-testcontainers-setup` skill | Per-language skill; same project family, different bindings. | T3-2 | Wait for N=3. |
| **Intake clarification questions** | Some Go-specific (aws-sdk-go-v2 vs v1) | Question bank per pack; intake asks `<lang>`-relevant subset. | Folds into T2-5 (convention layer) | Pilot Python intake; surfaces. |
| **Semver application** (Go's v2+ module path suffix) | `sdk-semver-governance` skill | Skill body generic; per-lang exception notes (Go's v2+ requirement, Python's PEP 440, Rust's `^` operator) move to `<lang>/conventions.yaml`. | T2-5 | Pilot Python; small lift. |
| **HITL gate set** (H0..H10) | Unified across langs | Stay unified; per-lang adapters fill the proof not the gate. | T3-8 | No work. |
| **Run-id namespace** | Flat in `runs/<id>/` | Stay flat; run-id is unique enough. | T3-6 | No work. |
| **Learning-engine patch authority** | Unrestricted across all skills | Restrict to same-language partition until LTE (Learning Transfer Entropy) metric has data. | T3-5 | Conservative default; revisit later. |
| **`shared-core` agents/skills with `generalization_debt`** | Live in shared-core; body cites Go idioms | **Lenient default**: one shared `baselines/shared/quality-baselines.json`. **Progressive fallback**: if Phase B shows ≥3pp quality_score divergence on any debt-bearer, flip that agent to per-language partition until its Split rewrite ships. | D2 (taken — R2 evidence) | Phase B is the empirical test. |
| **Generalization-debt rewrite timing** | Debt list known; not yet acted on | **Split**: rule body stays in `shared-core/<agent>.md`; examples + language-specific rules go in `<pack>/conventions.yaml`. Rewrites happen lazily in Phase B as Python TPRD exposes which conventions actually fire. | D6 (taken — R2 evidence) | See `docs/R2-DEBT-REWRITE-FEASIBILITY.md`. |

---

## §2. Open questions (Tier 2 — decide during the Python pilot)

These will *surface* during pilot work; pre-deciding risks getting them wrong.

| # | Decision | Forcing function |
|---|---|---|
| ~~**T2-1**~~ | ~~Workload encoding for cross-lang oracle~~ | **WITHDRAWN v0.6.x** — oracle / cross-language third-party comparison concept removed; only TPRD-declared targets used per-language. |
| ~~**T2-2**~~ | ~~Reference oracle catalog location~~ | **WITHDRAWN v0.6.x** — see T2-1. |
| **T2-3** | Drift signals taxonomy (rename `goroutines` → `concurrency_units`?) | First Python soak run |
| **T2-4** | Marker payload neutrality (`bench/BenchmarkX` vs neutral `[constraint: throughput >= X on workload W]`) | First Python `[constraint:]` marker |
| **T2-5** | Convention layer authoring: keep Go conventions in `go.json` only vs extract to `conventions.yaml` per pack | First Python `sdk-convention-devil-go` invocation |
| **T2-6** | Rule 25 (determinism) reinterpretation: same TPRD → same code modulo language-mechanism, OR same TPRD → same invariants enforced (regardless of code shape) | First Python re-run of a Go TPRD |
| **T2-7** | Adapter script policy strictness: must be policy-free (just emit normalized stdout) vs allow inline thresholds for one-offs | First Python adapter script with a non-trivial check |

For each, the *correct* answer becomes much clearer once you see real Python data. Don't pre-decide.

---

## §3. Open questions (Tier 3 — defer until 3rd language exists)

Real questions but premature with only Go + Python.

| # | Decision | Why defer |
|---|---|---|
| **T3-1** | TPRD §7 neutral IDL format (in-house vs protobuf vs Smithy vs OpenAPI) | Both Go and Python tolerate freeform §7; design hardens with 3rd lang |
| **T3-2** | Mock + container framework parity | Per-language is fine at N=2 |
| **T3-3** | Per-skill body splitting (`SKILL.md` → `SKILL.md` + `examples/<lang>.md`) | `generalization_debt` mechanism is sufficient at N=2 |
| **T3-4** | Tier model overhaul (T1/T2/T3 → "opt-in axes") | Wait until a TPRD actually wants partial perf gating |
| **T3-5** | Cross-language learning transfer (Go-derived patches → Python skill bodies?) | Speculative until LTE metric has data |
| **T3-6** | Run isolation by language (`runs/<lang>/<run-id>/`) | Run-id is unique enough; flat OK |
| **T3-7** | Per-target-product separation (motadata-go-sdk-prod vs -experimental as separate manifests) | One target per language is the assumption |
| **T3-8** | HITL gate count parity (per-lang skip semantics?) | Today's H0..H10 set is fine for both |

---

## §4. Research branches

Small spikes whose output *informs* decisions. Both can run in parallel.

### ~~R1. Cross-language oracle calibration study~~ — **WITHDRAWN v0.6.x**

The oracle / third-party-comparison concept that this spike was meant to inform was removed
in v0.6.x. The pipeline now compares only against TPRD-declared targets, per-language.
Cross-language perf comparison is explicitly out of scope; no spike needed.

### R2. Generalization-debt rewriting feasibility study (~1 day) — **DONE 2026-04-27**

**Question**: Take ONE shared-core agent with debt (e.g., `sdk-design-devil`) and try to author a language-neutral version of its prompt body. Is the result genuinely useful for both Go and Python design review? Or does it become so abstract it's vacuous?

**Outcome**: **Split** is the load-bearing shape. Rule body neutralizes cleanly (~85–95% across the three sampled debt-bearers); examples + a small minority of rules are genuinely per-language and belong in `<pack>/conventions.yaml`. Eager-rewrite produces vacuous prose; Lazy-rewrite delays the structural decision.

**Deliverable**: `docs/R2-DEBT-REWRITE-FEASIBILITY.md` — full study, side-by-side Original/Neutralized/Split for `sdk-design-devil`, judgment calls for D6 + D2, implementation shape for v0.5.0.

---

## §5. Next-version (v0.5.0) checklist

The actual work to onboard Python, in execution order.

### Pre-flight (before authoring `python.json`)

1. ~~**Run R2 spike** (1 day) → judgment call on D2 + D6.~~ ✅ **DONE 2026-04-27** — see `docs/R2-DEBT-REWRITE-FEASIBILITY.md`. Outcome: D6=Split, D2=Lenient+Progressive.
2. ~~**Run R1 spike** (2 days)~~ — **WITHDRAWN v0.6.x** (oracle concept removed; see R1).
3. Confirm Python target SDK exists (`motadata-py-sdk` or equivalent) and has at least one client to model the §7 surface against. *Defer to Phase B start.*

### Phase A — adapter scaffold (days 1-2)

4. Author `.claude/package-manifests/python.json` with `toolchain` block (pytest, ruff, mypy, pip-audit, etc.) and `baselines` block declaring `owns_per_language` paths under `baselines/python/`.
5. Author Python-specific skills: `python-asyncio-patterns`, `pytest-fixtures`, etc. as gaps surface.
6. Run `bash scripts/validate-packages.sh` — must PASS.
7. ~~Bump `pipeline_version` 0.4.0 → 0.5.0.~~ ✅ DONE — settings.json reads `0.5.0`; G06 propagated to 13 consumer files.
8. ~~`mkdir baselines/python/` (empty; populates on first Python run).~~ ✅ DONE — `baselines/python/.gitkeep` placeholder shipped.

> **NOTE (post-v0.4.0)**: Phase B from the original v0.4.0 plan is **already done**. `baselines/go/` and `baselines/shared/` are populated; consumer path-refactor is in. Phase A only needs to add the parallel `baselines/python/` partition — no Go-side migration work remains.

### Phase B — first Python TPRD (days 3-6)

9. Author a small Python TPRD (smallest possible client — e.g. a config loader).
10. Run intake → design → impl → testing → feedback.
11. Observe: does `sdk-design-devil`'s quality_score drop on this Python run? Does `sdk-convention-devil-go` produce useful output? **This data answers D2 + T2-5.**
12. Pair-program the resolution: write the rewrites lazy as the data demands.

### Phase C — touchpoint hardening (days 7-9)

13. Address each Tier-2 decision (T2-1 through T2-7) with the data from Phase B.
14. Update CLAUDE.md, this doc, manifests with the chosen shapes.
15. Cut v0.5.0 release; evolution report.

### Phase D — cleanup (post-pilot)

16. Remove backwards-compat fallback in dispatch (L7).
17. Remove any scope-stamping that turned out unnecessary.
18. Archive R1+R2 study docs into `evolution/`.

---

## §6. What v0.4.0 actually shipped (for verification)

So a future reader can mechanically check what's already done:

**Package layer (manifest-only)**:
- `.claude/package-manifests/{shared-core,go}.json` — full manifests with `baselines` block, `generalization_debt` array, toolchain block (go.json)
- `scripts/validate-packages.sh` — orphan/duplicate/dangling check
- `scripts/guardrails/G05.sh` — `active-packages.json` validator
- `phases/INTAKE-PHASE.md` Wave I5.5 — Package Resolution
- `agents/sdk-intake-agent.md` — writes `runs/<id>/context/active-packages.json` + `toolchain.md`
- `agents/guardrail-validator.md` Delta 6 — package-scoped dispatch
- `agents/sdk-{design,impl,testing}-lead.md` — Active Package Awareness blocks
- `CLAUDE.md` rule 34 (Package Layer) + rule 28 (Partitioning contract subsection)

**Baseline partitioning (D1=B, shipped — files moved + consumers updated)**:
- `baselines/go/{performance,coverage}-baselines.json` (per-language; `scope: per-language, language: go`)
- `baselines/go/{output-shape,devil-verdict}-history.jsonl` (per-language)
- `baselines/go/{do-not-regenerate-hashes,stable-signatures}.json` (per-language)
- `baselines/go/regression-report-sdk-dragonfly-s2.md` (per-language historical)
- `baselines/shared/{quality,skill-health,skill-health-baselines}.json` (`scope: shared` / `shared-stub`)
- `baselines/shared/baseline-history.jsonl` (shared)
- Consumer path-refactor across: `baseline-manager`, `learning-engine`, `metrics-collector`, `sdk-benchmark-devil-go`, `sdk-intake-agent`, `sdk-skill-coverage-reporter`, `sdk-testing-lead`, `mcp-knowledge-graph` skill, `sdk-marker-protocol` skill, `sdk-semver-governance` skill, `G81.sh`, `G86.sh`, `G101.sh`, `CLAUDE.md`, `LIFECYCLE.md`, `phases/{FEEDBACK,TESTING}-PHASE.md`, `improvements.md`, `docs/PROPOSED-GUARDRAILS.md`. ~70 path substitutions across 21 files.

**Docs**:
- `docs/PACKAGE-AUTHORING-GUIDE.md` — including §Baselines section
- `docs/LANGUAGE-AGNOSTIC-DECISIONS.md` (this file)
- `evolution/evolution-reports/pipeline-v0.4.0.md`

**Version**:
- `pipeline_version` bumped 0.3.0 → 0.4.0 across settings.json + 9 propagating consumers; G06 PASS post-bump.

**Did NOT ship in v0.4.0** (deferred):
- ~~D2~~ → resolved 2026-04-27 (Lenient + Progressive)
- ~~D6~~ → resolved 2026-04-27 (Split)
- ~~R1 — cross-language oracle calibration study~~ → withdrawn v0.6.x (oracle concept removed)
- ~~R2~~ → done 2026-04-27 (`docs/R2-DEBT-REWRITE-FEASIBILITY.md`)
- Python adapter scaffold (= v0.5.0 Phase A — next up)

---

## §7. Reading list (in order)

For someone picking up this work fresh:

1. `CLAUDE.md` rule 34 (Package Layer) — the canonical contract
2. `CLAUDE.md` rule 28 §Partitioning contract — baseline scope rules
3. `docs/PACKAGE-AUTHORING-GUIDE.md` — how-to + §Baselines section
4. `evolution/evolution-reports/pipeline-v0.4.0.md` — v0.4.0 release notes
5. **This file** — full decision board
6. `.claude/package-manifests/{shared-core,go}.json` — canonical manifest examples
7. `phases/INTAKE-PHASE.md` Wave I5.5 — per-run resolution flow

---

## Change log

| Date | Pipeline version | Change |
|---|---|---|
| 2026-04-27 | 0.4.0 | Initial — D1=B, D3=native, D4=native, D5=Python locked. D2, D6 deferred. R1, R2 spikes proposed. |
| 2026-04-27 | 0.4.0 (post-R2) | R2 spike complete (`docs/R2-DEBT-REWRITE-FEASIBILITY.md`). D6=Split + D2=Lenient/Progressive promoted to "Decisions taken". Phase A unblocked. R1 remains optional pre-Phase-B. |
