<!-- cross_language_ok: true — top-level pipeline doc references per-pack tooling and the multi-tenant SaaS platform context (per F-008 in migration-findings.md). Authoritative project description: SDK is built FOR multi-tenant SaaS consumers; multi-tenant guardrails (TenantID, JetStream, MsgPack, schema-per-tenant) are in-scope. -->

# motadata-sdk-pipeline — Agent Fleet Rules

Multi-agent **NFR-driven, language-pluggable** pipeline targeting an external SDK at `$SDK_TARGET_DIR`. Purpose: take a **detailed** TPRD (with `§Target-Language` + `§Skills-Manifest` + `§Guardrails-Manifest`) for adding / extending / incrementally updating a client in that SDK and produce production-quality code + tests + benchmarks against numeric NFR gates.

The pipeline supports per-language adapter packs declared at `.claude/package-manifests/<lang>.json`. **Go** is the canonical pack (Go 1.26, module name and source layout per the active language pack). **Python** scaffolding ships in v0.5.0 Phase A; Phase B authors Python-specific agents/skills/guardrails. Adding a third language = author one new manifest + per-language sibling agents/skills/guardrails per the naming convention in `docs/PACKAGE-AUTHORING-GUIDE.md`.

**No runtime skill synthesis.** Skills and agents are human-authored, promoted via PR, and static at runtime. `learning-engine` may patch **existing** skill bodies (minor version bump) but never creates new skill files. New-skill proposals land in `docs/PROPOSED-SKILLS.md` for human triage.

---

## Project Context

- **Target SDK shape**: declared per-run by the active language manifest. For Go runs: Go 1.26, dirs `config/ events/ core/ otel/ utils/ cmd/` (per pack convention). For Python runs (Phase B+): Python 3.12+, `pyproject.toml`-based packaging.
- **Convention**: primary `Config struct + New(cfg)` for Go (per `go-sdk-config-struct-pattern` skill); functional options only where target SDK already uses them. Python equivalent (Phase B) authored via `<lang>/conventions.yaml`.
- **No multi-tenancy** — SDK is a library, tenant context is caller-supplied (not pipeline concern)
- **No inter-service NATS/HTTP** — SDK may EXPOSE NATS capability (events/), but pipeline itself does not enforce NATS patterns on non-events clients
- **OTel required (language-native)** — Go clients wire into the SDK's OTel wrapper module (per-pack); Python clients (Phase B+) wire into the Python OTel SDK per `<lang>/conventions.yaml`. NEVER raw `go.opentelemetry.io/otel` for Go.
- **Resilience toolkit** — language-pack-supplied. Go pack reuses `core/circuitbreaker/`, `core/pool/`, existing middleware. Python pack (Phase B+) supplies equivalents.

## Agent Fleet Rules (all agents follow)

### 1. Observability Logging — MANDATORY
Every agent MUST append to `runs/<run-id>/decision-log.jsonl`. Entry types: `decision`, `lifecycle`, `communication`, `event`, `failure`, `refactor`, `skill-evolution`, `budget`. Full schema in plan §Decision Log; validator guardrail G01.

### 2. Context Sharing
- BEFORE starting: read all files in `runs/<run-id>/<phase>/context/`
- AFTER completing: write summary to `runs/<run-id>/<phase>/context/<agent-name>-summary.md` (≤200 lines)
- Summaries must be self-contained for downstream agents

### 3. Output Ownership
- Each agent writes ONLY to its designated output dir
- Never modify another agent's outputs
- Phase lead is the only writer of the phase's final report

### 4. Communication Protocol
- Use Teammate messages for urgent cross-agent coordination
- Use filesystem (context dir) for artifacts
- Prefix urgent with `ESCALATION:` or `BLOCKER:`
- Log every meaningful communication in decision log (`type: communication`)

### 5. Review Agents Are READ-ONLY
All devil / critic / reviewer / validator agents never modify source. Output only to `runs/<run-id>/<phase>/reviews/`.

### 6. Quality Standards (language-pluggable)

The rules below are language-coupled — each language pack supplies its own form via `<pack>/conventions.yaml` (Step 13 onward). The list below is the **Go pack canonical** form; Python and other packs translate per-language equivalents.

**Cross-language rules (apply to every pack)**:
- Doc-comment on every exported symbol (Go: doc-comment with symbol name first word; Python: docstring on every public class/function)
- Table-driven tests, table-driven benchmarks
- No global mutable state at package/module level
- Interface-first for testability; compile-time interface assertions where the language supports them
- Configuration entrypoint per pack convention (Go: `Config struct + New(cfg)`; Python pack defines its own per `<pack>/conventions.yaml`)
- OTel via the language-native pack helper (Go: the SDK's OTel wrapper module (per-pack); Python: package-defined wrapper) — NEVER raw `go.opentelemetry.io/otel` for Go

**Go-specific (lives in go pack)**:
- No `init()` functions
- cancellation primitive first on every I/O method (per language adapter)
- compile-time interface conformance check (per-pack) compile-time assertions

### 7. Ownership Matrix — single owner per domain
See `AGENTS.md` for full matrix. Key: TPRD canonicalization + manifest validation = `sdk-intake-agent`; API design = `sdk-design-lead`; code = `sdk-impl-lead`; tests = `sdk-testing-lead`; existing-skill patches = `learning-engine`.

### 8. Conflict Resolution
Agent discovering conflict sends `ESCALATION: CONFLICT` to phase lead; lead decides per ownership matrix; logs with `tags: ["conflict-resolution"]`.

### 9. State Management & Checkpointing
Phase lead maintains `runs/<run-id>/state/run-manifest.json`. Checkpoint after every wave. On restart, read manifest; `in-progress` → resume, `completed` → start fresh.

### 10. Error Recovery
Agent failure → `lifecycle: failed` entry + assess retry-vs-proceed. Max 1 retry per agent per wave. Second failure = degraded; proceed with warning.

### 11. Resource Limits
- Context summary ≤200 lines
- Schema/spec files ≤500 lines/service
- Decision log ≤15 entries per agent per run
- Review-fix loop: 5 retries per finding, stuck detection at 2 non-improving iterations, global 10-iter cap

### 12. Observability & Run Isolation
Every run has `run_id` (UUID v4). Every log entry stamps `run_id` + `pipeline_version`. Context summaries timestamp with `<!-- Generated: ISO-8601 | Run: run_id -->`.

### 13. Post-Iteration Review Re-Run — MANDATORY (gated)
After ANY rework iteration **that passes the deterministic-first gate**, phase lead re-runs ALL review/devil agents. No exceptions on iterations the gate admits. Iterations with BLOCKER-level guardrail failures (build, vet, fmt, static-check, race-detection if supported, leak-detection, vulnerability + lockfile scans, marker byte-hash, constraint bench, license allowlist) loop back to fix agents without spawning the reviewer fleet — fleet re-runs once the gate is green. See `review-fix-protocol` v1.1.0 §Deterministic-First Gate. Invariant preserved: every iteration whose output a reviewer would meaningfully evaluate still gets reviewed.

### 14. Implementation Completeness
- Zero `ErrNotImplemented` / `TODO` in generated code
- Every interface has real impl
- Tests cover real behavior (not mocked away)
- Coverage ≥90% on new package
- Benchmarks recorded for hot paths
- the pack's leak-detection harness clean
- the pack's vulnerability scanner + the pack's lockfile vulnerability scanner clean
- Every exported func has at least one runnable examples (per-pack: `Example_*` in Go, doctest blocks in Python) where applicable

### 16. Story → Feature-Level Completeness
For each symbol declared in TPRD §7 API: (a) impl exists, (b) test exists, (c) doc-comment exists, (d) benchmark if hot path, (e) runnable examples (per-pack: `Example_*` in Go, doctest blocks in Python) where applicable, (f) `[traces-to: TPRD-<section>-<id>]` marker on generated symbols.

**Verdict policy (added 2026-05-07):** A TPRD §7 declared symbol absent at M3 exit = **FAIL**, not INCOMPLETE. Waiver path closed (R33). Only resolutions: deliver the symbol, reject the run, or iterate TPRD §7 via H1 to remove the symbol from declared scope. Enforced by G70 (BLOCKER, impl + testing) and `sdk-prd-conformance-devil` at M7.

### 17. Target-dir Discipline
Writes ONLY to `$SDK_TARGET_DIR` and `runs/`. Guardrail G07 enforces.

### 18. Target SDK Convention Respect
Agents MUST read target SDK tree before designing. No contradicting existing patterns (e.g., if target uses `Config struct + New()`, don't default to functional options without justification).

### 19. Dependency Justification
Every new dependency add (per the active language pack) requires `runs/<run-id>/design/dependencies.md` entry: name, version, license, size, the pack's vulnerability scanner, the pack's lockfile vulnerability scanner, last-commit-age, transitive-count. Dep-Vet Devil (per-pack) verdict required. License allowlist: MIT / Apache-2.0 / BSD / ISC / 0BSD / MPL-2.0.

### 20. Benchmark Regression + Target + Alloc Gates
Three independent perf gates, all enforced at Phase 3 T5:

1. **Regression** — >10% on shared paths OR >5% on new-package hot path = BLOCKER, waivable with `--accept-perf-regression <pct>`. Owner: Benchmark Devil (per-pack).
2. **Absolute target** — measured p50/p95/p99 must stay within the TPRD-declared latency targets in `design/perf-budget.md` (`latency.*`). BLOCKER if breached. Waiver requires updating the targets in perf-budget.md with rationale at H8 (or fixing the implementation). Owner: Benchmark Devil (per-pack).
3. **Alloc budget (G104)** — measured `allocs/op` must be ≤ declared `allocs_per_op` in perf-budget.md. BLOCKER. Enforced at M3.5 by Profile Auditor (per-pack) (BEFORE T5; alloc issues don't reach testing).

Rule 32 (Performance-Confidence Regime) lists the full gate set. Rule 33 (Verdict Taxonomy) disambiguates PASS / FAIL / INCOMPLETE.

### 21. Git-Based Safety
`$SDK_TARGET_DIR` MUST be a git repo. Pipeline works on dedicated branch `sdk-pipeline/<run-id>`. Final diff shown to user before merge recommendation. No force-push. No direct main commit.

### 22. Budget Tracking
`manifest.json` tracks per-phase token + wall-clock. Soft caps → warn. Hard caps → user confirm-to-continue.

### 23. Skill Versioning & Human-Only Authorship
Every skill MUST have `version: X.Y.Z` frontmatter + adjacent `evolution-log.md`. **Skill files are human-authored only** — `learning-engine` may patch existing skill bodies (minor bump, append to `evolution-log.md`, write one line per patch to `learning-notifications.md`) but MUST NOT create new `SKILL.md` files. New skill proposals file to `docs/PROPOSED-SKILLS.md`; a human authors + PR-merges the skill before it can be referenced by any TPRD `§Skills-Manifest`. Major changes require human PR review (no golden-corpus gate; pipeline does not run full-replay regression).

### 24. Supply Chain
the pack's vulnerability scanner + the pack's lockfile vulnerability scanner MUST be green on all new deps.

### 25. Determinism
Same TPRD + same pipeline version + same seed MUST converge on equivalent output (modulo comments/formatting). Variance is a learning-engine signal.

### 26. Dry-Run Honored
`--dry-run` halts before any target-dir write; produces `runs/<run-id>/preview.md`.

### 27. Credential Hygiene
Integration tests read creds from `.env.example` (committed, fake) and `.env` (gitignored). No creds in spec/design/test source. Guardrail G69.

### 28. Learning-Engine Notification + Compensating Baselines (replaces former Golden Regression rule)
Every patch `learning-engine` applies (prompt patch or existing-skill body patch with minor bump) MUST also append one notification line to `runs/<run-id>/feedback/learning-notifications.md`. The user reviews this file at H10 and may revert any individual patch before approving merge. Full-pipeline golden-corpus regression replay has been retired — it was the dominant Phase 4 cost once a corpus seeded (~1.5–3M tokens, 30+ min per run) and caught almost nothing the devil fleet was not already catching on the live run.

The safety net is now the user notification loop backed by **four compensating baselines** that recover most of what golden-corpus was guarding:

1. **Output-shape hash** (`baselines/go/output-shape-history.jsonl`) — SHA256 of sorted exported-symbol signatures per generated package per run. `learning-engine` surfaces hash churn on runs that invoked any just-patched skill as `⚠ shape-churn` lines.
2. **Devil-verdict stability** (`baselines/go/devil-verdict-history.jsonl`) — per-skill `devil_fix_rate` + `devil_block_rate` tracked per run. A ≥20pp jump after a skill auto-patch surfaces as `⚠ devil-regression`.
3. **Tightened quality regression threshold** — 10% → 5% on per-agent `quality_score`. G86.sh enforces as BLOCKER at feedback phase exit when ≥3 prior runs exist.
4. **Example_* count per package** (`baselines/go/coverage-baselines.json`) — raise-only; a drop with ≥2 prior runs on a package emits `⚠ example-drop`.

G85 enforces `learning-notifications.md` is written whenever any patch is applied. G86 enforces the quality regression threshold. Signals (1), (2), (4) are WARN-level (H10 reviewer decides); signal (3) is BLOCKER-level once the sample-size precondition is met.

**Drift-prevention gates** (added in v0.3.0 straighten): G06 enforces `pipeline_version` consistency (settings.json is the single source of truth); G90 (tightened to strict equality) enforces `skill-index.json` ↔ filesystem equality; G116 enforces that retired concepts catalogued in `docs/DEPRECATED.md` do not appear in live docs. All three are BLOCKERs at intake — the pipeline refuses to operate on a drifted repo. `scripts/check-doc-drift.sh` runs all three as a standalone sanity pass.

**Partitioning contract** (shipped in v0.4.0 package layer): every baseline file declares a `scope` field — `per-language` (perf, coverage, output-shape hash, devil-verdict, source byte hashes, stable signatures) or `shared` (quality, skill-health, baseline-history) or `shared-stub` (legacy `skill-health.json`). Each language manifest declares which baselines it `owns_per_language` (Go owns perf+coverage+shape-hash+devil-verdict); `shared-core` declares `owns_shared`. **Shape (Decision D1=B)**: per-language subdirectories — `baselines/go/<file>` for per-language data, `baselines/shared/<file>` for cross-language data. v0.4.0 ships the moves AND the consumer path-refactor (baseline-manager, metrics-collector, learning-engine, G81/G86/G101). Cross-language metric comparison (e.g. is `sdk-design-devil`'s quality_score systematically lower in Python runs?) is **explicitly NOT a v0.5.0 goal** (Decision D2 deferred); each adapter compares against its own language's history. See `docs/LANGUAGE-AGNOSTIC-DECISIONS.md` for the full decision board + per-touchpoint handling table.

### 29. Code Provenance Markers
Markers (`[traces-to:]`, `[constraint:]`, `[stable-since:]`, `[deprecated-in:]`, `[do-not-regenerate]`, `[owned-by:]`, `[perf-exception:]`) are machine-read by `sdk-marker-scanner`. Marker rules:

- MANUAL-marked symbols NEVER modified by pipeline (guardrail G96, byte-hash match)
- `[constraint: ... bench/BenchmarkX]` triggers automatic bench proof (guardrail G97)
- `[do-not-regenerate]` = hard lock (G100)
- `[stable-since: vX]` signature changes require major semver + TPRD §12 declaration (G101)
- Pipeline-authored symbols MUST have `[traces-to: TPRD-<section>-<id>]` marker (G99)
- Pipeline NEVER forges `[traces-to: MANUAL-*]` (G103)
- `[perf-exception: <reason> bench/BenchmarkX]` exempts a symbol from `sdk-overengineering-critic` findings, but ONLY if: (a) an entry exists in `runs/<run-id>/design/perf-exceptions.md` declaring the exception at design time, (b) the named bench exists and measurably justifies the complexity, (c) Profile Auditor (per-pack) has profile evidence. Guardrail G110 enforces the marker↔perf-exceptions.md pairing. Orphan `[perf-exception:]` markers (no matching entry) = BLOCKER.

### 30. Incremental Update Support
Pipeline supports three request modes: A (new package), B (extension), C (incremental update). Mode C uses marker-aware 3-way merge via `sdk-merge-planner`. Existing tests + bench MUST continue passing post-update (G95).

### 31. MCP Fallback Policy
Every MCP integration (`mcp__neo4j-memory__*`, `mcp__serena__*`, `mcp__code-graph__*`, `mcp__context7__*`) is an **enhancement, not a correctness dependency**. Guardrail `G04.sh` runs at phase start, verifies each MCP is reachable, and writes a verdict to `runs/<id>/<phase>/mcp-health.md`. On MCP unavailability: agents degrade to existing JSONL / Grep / text-based fallbacks with a WARN log entry. Pipeline NEVER halts on MCP failure. See `skills/mcp-knowledge-graph/SKILL.md` for the canonical read/write + fallback pattern. See `docs/MCP-INTEGRATION-PROPOSAL.md` for scope + rollout.

### 32. Performance-Confidence Regime
"Best performance" is uncomputable — the space of equivalent programs is infinite. What the pipeline CAN do is build a falsification regime: if a meaningful perf improvement is available, these gates surface it. Confidence = ∪ of failure modes we actively falsify.

**The six falsification axes**:

1. **Declaration** — Perf Architect (per-pack) writes `design/perf-budget.md` (rule 20) at D1: per-§7-symbol latency p50/p95/p99, allocs/op, throughput, hot-path flag, theoretical floor, big-O complexity, MMD (soak symbols), drift signals. Without a declaration, downstream gates have nothing to falsify against.
2. **Profile shape (G109)** — Profile Auditor (per-pack) at M3.5 reads CPU/heap/block/mutex profiler output; top-10 CPU samples must match declared hot paths (coverage ≥0.8); surprise hotspots = BLOCKER. Catches design-reality drift before testing phase.
3. **Allocation (G104)** — Profile Auditor (per-pack) enforces `allocs/op ≤ design budget` from perf-budget.md. Mandatory allocation reporting on every benchmark.
4. **Complexity (G107)** — Complexity Devil (per-pack) at T5 runs a scaling sweep at N ∈ {10, 100, 1k, 10k}, curve-fits, compares to declared big-O. Catches accidental quadratic paths that pass wallclock gates at microbench sizes.
5. **Regression + Target (rule 20)** — Benchmark Devil (per-pack) at T5: run-to-run regression vs. baseline AND absolute-target check vs. TPRD-declared `latency.*` numbers in perf-budget.md. Target miss requires either fixing the implementation or updating the declared target at H8 with rationale.
6. **Drift (G106) + MMD (G105)** — Soak Runner (per-pack) + `sdk-drift-detector` at T5.5 launch soaks in background (Bash `run_in_background`), poll state files on a ladder, fast-fail on statistically significant positive trend in drift signals. MMD enforces that a soak verdict reflects a long-enough run.
7. **Profile-backed exceptions (G110)** — the `[perf-exception:]` marker (rule 29) lets impl carry hand-optimized code through the `sdk-overengineering-critic` — but only when paired with a design-time entry in `perf-exceptions.md` AND a profile-auditor-measured benchmark win.

**Interpretation**: the pipeline's perf confidence is exactly the union of these axes. Anything they don't catch is an unknown-unknown. Add a new axis when you identify a failure mode none of the seven catches.

### 33. Verdict Taxonomy — PASS / FAIL / INCOMPLETE
Three verdicts, not two. An INCOMPLETE verdict is NEVER silently promoted to PASS.

- **PASS** — the gate ran to completion and found no violation. For soak tests, this requires `actual_duration_s ≥ mmd_seconds` from perf-budget.md (G105).
- **FAIL** — the gate ran and detected a violation (drift, regression, target-miss, complexity-mismatch, alloc-over-budget, surprise hotspot). BLOCKER; no auto-merge.
- **INCOMPLETE** — the gate could not render a verdict: MMD not reached within wallclock cap, too few samples for regression fit, profiler unavailable, harness crashed without writing state. H9 MUST surface INCOMPLETE verdicts explicitly. User chooses: extend window, accept risk with written waiver, or reject. INCOMPLETE never auto-merges.

Wherever a gate historically returned "passed so far" on a timeout, it MUST now return INCOMPLETE. A synchronous Bash tool call hitting the 10-minute ceiling with a running soak = INCOMPLETE, not PASS.

**Scope of INCOMPLETE (added 2026-05-07):** Reserved for measurement gates only — soak MMD (G105), profiler unavailable, sample insufficiency, harness crash. **TPRD-gap (declared §7 symbol missing impl/test/marker) → FAIL, never INCOMPLETE.** Pipeline tooling (`/pm`) MUST reject any proposal that re-routes TPRD-gap to INCOMPLETE.

### 34. Package Layer (v0.4.0+) — Manifest-Only

The agent / skill / guardrail set a run is allowed to invoke is **scoped by package manifests**. Manifests are JSON files in `.claude/package-manifests/<name>.json` that list which artifacts belong to one logical package. Three packages ship today: `shared-core` (language-neutral orchestration), `go` (Go SDK language adapter, fully populated), `python` (Phase A scaffold; Phase B authors content). All on-disk artifacts MUST belong to exactly one manifest — `scripts/validate-packages.sh` enforces.

**Manifest-only**: files do NOT move into per-package subdirectories. Agents stay at `agents/<name>.md`, skills at `skills/<name>/SKILL.md`, guardrails at `scripts/guardrails/G*.sh`. Claude Code's harness auto-discovers from those canonical paths; physical packaging would break discovery. Manifests are descriptive metadata, not directory structure.

**Per-run resolution (v0.5.0+)**: `sdk-intake-agent` Wave I1.5 enforces `§Target-Language` as REQUIRED (BLOCKER if missing — no silent default). Wave I5.5 reads `§Target-Language`, `§Target-Tier` (default `T1`), `§Required-Packages` (default `[shared-core, <lang>]`), resolves the manifest set + dependencies, and writes `runs/<run-id>/context/active-packages.json`. G05 validates the file resolves cleanly. Phase leads dispatch from manifest data: `waves` (per-wave agent contributions, unioned across packs) and `tier_critical` (per-phase × tier required-set). `scripts/run-guardrails.sh` filters guardrails by active-packages union ∩ phase header. `scripts/run-toolchain.sh` resolves `toolchain.<command>` from the active language manifest. Agents NOT in the active set are skipped (logged as `event: agent-not-in-active-packages`); guardrails NOT in the active set are not run.

**Aspirational guardrails**: a manifest may carry `aspirational_guardrails: { "G<NN>": "<rationale>" }` for forward-declared scripts not yet authored (today: G81/G83/G84 in shared-core; G104–G110 in go). These are tracked but never executed at runtime; promote to `guardrails` array when the script lands.

**Tier semantics** (per phase lead's tier-critical table):
- **T1** — full perf-confidence regime (rule 32): perf-architect, profile-auditor, leak-hunter, benchmark-devil, complexity-devil, soak-runner, drift-detector. Default for SDK clients.
- **T2** — build/test/lint/fmt/staticcheck/supply-chain only. Skip Waves M3.5, M4, M7 (impl), T4–T7, T10 (testing). Coverage gate still applies.
- **T3** — out-of-scope; intake refuses.

**Backwards compatibility**: TPRDs without the v0.4.0 fields default to `go T1`. Runs missing `active-packages.json` (legacy replays) fall back to invoking everything with a WARN. Fallback removed in v0.5.0.

**Generalization debt** is tracked per-manifest in the `generalization_debt` field — artifacts whose role is language-neutral but whose body still cites Go idioms. This list is the v0.5.0 second-language-pilot backlog. No action required in v0.4.0.

---

## Phase Flow

```
Phase 0   Intake     → TPRD canonicalization + §Skills-Manifest validation (WARN, non-blocking) + §Guardrails-Manifest validation (BLOCKER) + clarifications
Phase 0.5 Analyze    → (Mode B/C only) snapshot existing API + tests + bench
Phase 1   Design     → API design + devil review
Phase 2   Impl       → TDD red/green/refactor/docs (marker-aware)
Phase 3   Testing    → unit + integration + bench + leak
Phase 4   Feedback   → metrics + drift + coverage + learning-engine (existing-skill patches only, per-patch notify)
```

HITL gates: H0 (target-dir preflight), H1 (TPRD + manifests acceptance), H5 (design sign-off), H7/H7b (impl sign-off / mid-impl checkpoint), H9 (testing sign-off), H10 (merge verdict). **H2 and H3 removed** (were bootstrap skill/agent approval gates).

## Pipeline Versioning

`settings.json` declares `pipeline_version: "0.6.0"` — the **single source of truth**. Every log entry stamps it; every other file that mentions a pipeline version MUST match. Divergence = drift (guardrail G06 enforces at intake). Upgrade path: bump semver in `.claude/settings.json`; propagate to all consumers in the same PR; record changes in `evolution/evolution-reports/pipeline-v<X.Y.Z>.md`.

## Directory Reference

```
docs/                          — Pipeline docs, missing-skills-backlog
phases/                        — Phase contracts
commands/                      — Slash commands
agents/                — Agent prompts (canonical, harness-discovered)
skills/<n>/SKILL.md    — Skills (versioned, harness-discovered)
.claude/package-manifests/     — Package metadata (v0.4.0): shared-core.json, go.json, README.md
scripts/guardrails/G*.sh       — Guardrail scripts (referenced by package manifests)
scripts/validate-packages.sh   — Manifest ↔ filesystem consistency check
runs/<run-id>/                 — Per-run state
  decision-log.jsonl           — All agent entries
  state/run-manifest.json      — Wave / agent status
  context/active-packages.json — (v0.4.0) Resolved package set; consumed by phase leads + guardrail-validator
  context/toolchain.md         — (v0.4.0) Language adapter's toolchain digest (informational)
  intake/                      — TPRD + manifest checks + clarifications
  extension/                   — Phase 0.5 outputs (Mode B/C)
  design/                      — Phase 1 outputs
  impl/                        — Phase 2 outputs (ownership-map, merge plan)
  testing/                     — Phase 3 outputs
  feedback/                    — Phase 4 outputs
baselines/                     — Persistent quality/coverage/perf/skill-health
evolution/                     — Learning-engine state
state/ownership-cache.json     — Target-SDK-wide marker ownership map
```

