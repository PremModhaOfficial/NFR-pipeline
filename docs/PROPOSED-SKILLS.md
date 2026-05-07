<!-- cross_language_ok: true — pipeline design/decision doc references per-pack tooling. Multi-tenant SaaS platform context preserved per F-008. -->

# Proposed Skills (Human-Review Backlog)

Entries from pipeline runs are auto-filed here as WARNINGs by `scripts/guardrails/G23.sh`. They never block a run.

Human-reviewed backlog of proposed new skills. **The pipeline never creates skills at runtime.** Entries appear here from two sources:

1. **TPRD intake** — `sdk-intake-agent` Wave I2 finds a required skill missing from `skills/skill-index.json` → emits a WARN (non-blocking), files an entry here, and the pipeline continues.
2. **Phase 4 learning-engine** — on repeated patterns that lack a backing skill (3+ runs) → files an entry here; never drafts the SKILL.md itself.

## Workflow

1. Entry lands here with `status: proposed` + motivation + consumer agents
2. Human author drafts `skills/<name>/SKILL.md` with `version: 1.0.0` offline (per `SKILL-CREATION-GUIDE.md`)
3. Human opens PR; reviewers include subject-matter owner + one devil-agent owner
4. On merge: entry in this file flipped to `status: promoted` with commit SHA + link to `SKILL.md`
5. `skill-index.json` updated manually in the same PR

## Existing proposals

| Priority | Skill | Motivation | Primary consumers | Status |
|---|---|---|---|---|
| MUST | `benchmark-regression-detection` | `benchstat` integration, delta thresholds, CI gating | `sdk-benchmark-devil-go`, `performance-test-agent` | proposed |
| MUST | `test-stability-verification` | `-race -count=5` pattern, flaky-test detection, seed-based repro | `sdk-integration-flake-hunter-go`, `unit-test-agent` | proposed |
| SHOULD | `pool-reuse-policy` | When to reuse SDK's `core/pool/` vs. create own; cleanup contracts | `sdk-designer`, `concurrency-designer` | proposed |
| SHOULD | `testcontainers-client-recipes` | Per-backend recipes: dragonfly, minio, localstack, kafka, rabbitmq | `integration-test-agent` | proposed (draft candidates under `evolution/skill-candidates/`) |

## Drafts awaiting human review

See `evolution/skill-candidates/` — 8 skill drafts from prior Dragonfly-class runs:

- `hash-field-ttl-hexpire`
- `k8s-secret-file-credential-loader`
- `lua-script-safety`
- `miniredis-testing-patterns`
- `pubsub-lifecycle`
- `redis-pipeline-tx-patterns`
- `sentinel-error-model-mapping`
- `testcontainers-dragonfly-recipe`

These are **not auto-promoted**. A human reviewer must (a) audit per `SKILL-CREATION-GUIDE.md`, (b) move to `skills/<name>/`, (c) update `skill-index.json`, (d) record the promotion in git.

## Meta-skills (observability over skill set)

| Skill | Role | Status |
|---|---|---|
| `sdk-skill-drift-detector-spec` | Detect skill-prescription vs. code-reality gaps | Agent exists (`sdk-skill-drift-detector`); skill body not yet authored |
| `sdk-skill-coverage-reporter-spec` | Which skills got invoked per run; unused-but-relevant flagging | Agent exists (`sdk-skill-coverage-reporter`); skill body not yet authored |

## Policy

- **No auto-synthesis.** Pipeline emits entries; does not write `SKILL.md` bodies.
- **No runtime promotion.** Moving a draft into `skills/` is a human PR action.
- **Devil-fleet gate on first use.** Newly promoted skills must pass the devil fleet on the next pipeline run before counting as stable (pipeline does not run golden-corpus full-replay regression).

---

## Auto-filed from run `preflight-dfly-XbvV` on 2026-04-18

- **MISSING** `redis-pipeline-tx-patterns` (≥1.0.0) — source run `preflight-dfly-XbvV`
- **MISSING** `hash-field-ttl-hexpire` (≥1.0.0) — source run `preflight-dfly-XbvV`
- **MISSING** `pubsub-lifecycle` (≥1.0.0) — source run `preflight-dfly-XbvV`
- **MISSING** `miniredis-testing-patterns` (≥1.0.0) — source run `preflight-dfly-XbvV`
- **MISSING** `lua-script-safety` (≥1.0.0) — source run `preflight-dfly-XbvV`
- **MISSING** `testcontainers-dragonfly-recipe` (≥1.0.0) — source run `preflight-dfly-XbvV`
- **MISSING** `k8s-secret-file-credential-loader` (≥1.0.0) — source run `preflight-dfly-XbvV`
- **MISSING** `sentinel-error-model-mapping` (≥1.0.0) — source run `preflight-dfly-XbvV`

---

## Auto-filed from run `preflight-dfly-qIUq` on 2026-04-18

- **MISSING** `redis-pipeline-tx-patterns` (≥1.0.0) — source run `preflight-dfly-qIUq`
- **MISSING** `hash-field-ttl-hexpire` (≥1.0.0) — source run `preflight-dfly-qIUq`
- **MISSING** `pubsub-lifecycle` (≥1.0.0) — source run `preflight-dfly-qIUq`
- **MISSING** `miniredis-testing-patterns` (≥1.0.0) — source run `preflight-dfly-qIUq`
- **MISSING** `lua-script-safety` (≥1.0.0) — source run `preflight-dfly-qIUq`
- **MISSING** `testcontainers-dragonfly-recipe` (≥1.0.0) — source run `preflight-dfly-qIUq`
- **MISSING** `k8s-secret-file-credential-loader` (≥1.0.0) — source run `preflight-dfly-qIUq`
- **MISSING** `sentinel-error-model-mapping` (≥1.0.0) — source run `preflight-dfly-qIUq`

---

## Auto-filed from run `preflight-dfly-pl93` on 2026-04-18

- **MISSING** `redis-pipeline-tx-patterns` (≥1.0.0) — source run `preflight-dfly-pl93`
- **MISSING** `hash-field-ttl-hexpire` (≥1.0.0) — source run `preflight-dfly-pl93`
- **MISSING** `pubsub-lifecycle` (≥1.0.0) — source run `preflight-dfly-pl93`
- **MISSING** `miniredis-testing-patterns` (≥1.0.0) — source run `preflight-dfly-pl93`
- **MISSING** `lua-script-safety` (≥1.0.0) — source run `preflight-dfly-pl93`
- **MISSING** `testcontainers-dragonfly-recipe` (≥1.0.0) — source run `preflight-dfly-pl93`
- **MISSING** `k8s-secret-file-credential-loader` (≥1.0.0) — source run `preflight-dfly-pl93`
- **MISSING** `sentinel-error-model-mapping` (≥1.0.0) — source run `preflight-dfly-pl93`

---

## Auto-filed from run `preflight-dfly-7okH` on 2026-04-18

- **MISSING** `redis-pipeline-tx-patterns` (≥1.0.0) — source run `preflight-dfly-7okH`
- **MISSING** `hash-field-ttl-hexpire` (≥1.0.0) — source run `preflight-dfly-7okH`
- **MISSING** `pubsub-lifecycle` (≥1.0.0) — source run `preflight-dfly-7okH`
- **MISSING** `miniredis-testing-patterns` (≥1.0.0) — source run `preflight-dfly-7okH`
- **MISSING** `lua-script-safety` (≥1.0.0) — source run `preflight-dfly-7okH`
- **MISSING** `testcontainers-dragonfly-recipe` (≥1.0.0) — source run `preflight-dfly-7okH`
- **MISSING** `k8s-secret-file-credential-loader` (≥1.0.0) — source run `preflight-dfly-7okH`
- **MISSING** `sentinel-error-model-mapping` (≥1.0.0) — source run `preflight-dfly-7okH`

---

## Auto-filed from run `sdk-dragonfly-s2` on 2026-04-18

Source: `sdk-intake-agent` Wave I2 §Skills-Manifest validation (G23 WARN, non-blocking).
TPRD: `motadatagosdk/core/l2cache/dragonfly/TPRD.md` §Skills-Manifest (27 declared; 19 present; 8 missing, all WARN-expected per TPRD footnote).
Status: `proposed` (awaiting human PR authorship per rule #23).

- **MISSING** `redis-pipeline-tx-patterns` (≥1.0.0) — source run `sdk-dragonfly-s2`; TPRD reason: "§5.4 Pipeline + TxPipeline + Watch". Draft in `evolution/skill-candidates/`.
- **MISSING** `hash-field-ttl-hexpire` (≥1.0.0) — source run `sdk-dragonfly-s2`; TPRD reason: "§5.3 HEXPIRE/HPEXPIRE/HTTL/HPersist family". Draft in `evolution/skill-candidates/`.
- **MISSING** `pubsub-lifecycle` (≥1.0.0) — source run `sdk-dragonfly-s2`; TPRD reason: "§5.5 Subscribe/PSubscribe lifetime + cancellation". Draft in `evolution/skill-candidates/`.
- **MISSING** `miniredis-testing-patterns` (≥1.0.0) — source run `sdk-dragonfly-s2`; TPRD reason: "§11.1 miniredis fakes for unit tests". Draft in `evolution/skill-candidates/`.
- **MISSING** `lua-script-safety` (≥1.0.0) — source run `sdk-dragonfly-s2`; TPRD reason: "§5.6 Eval/EvalSha/ScriptLoad". Draft in `evolution/skill-candidates/`.
- **MISSING** `testcontainers-dragonfly-recipe` (≥1.0.0) — source run `sdk-dragonfly-s2`; TPRD reason: "§11.2 Dragonfly container image + readiness probe". Draft in `evolution/skill-candidates/`.
- **MISSING** `k8s-secret-file-credential-loader` (≥1.0.0) — source run `sdk-dragonfly-s2`; TPRD reason: "§9 `LoadCredsFromEnv` helper". Draft in `evolution/skill-candidates/`.
- **MISSING** `sentinel-error-model-mapping` (≥1.0.0) — source run `sdk-dragonfly-s2`; TPRD reason: "§7 `mapErr` switch + 30 sentinels". Draft in `evolution/skill-candidates/`.

---

## Auto-filed from run `sdk-dragonfly-s2` on 2026-04-18 (F6 improvement-planner)

Source: `improvement-planner` Wave F6, derived from retro patterns P1/P2/P5 (not intake manifest gaps).
Status: `proposed` (awaiting human PR authorship per rule #23). These are net-new proposals beyond the 8 intake-filed WARN-absent set.

| Priority | Skill | Motivation | Primary consumers | Source pattern |
|---|---|---|---|---|
| SHOULD | `miniredis-limitations-reference` | Documents which Redis commands miniredis v2 does/doesn't support (HEXPIRE family not supported; Lua subset; scripting edge cases). Bridges the TPRD §11.1 gap surfaced in sdk-dragonfly-s2. | `integration-test-agent`, `unit-test-agent`, `sdk-testing-lead` | P5 (retro-testing) |
| SHOULD | `bench-constraint-calibration` | Pattern for verifying TPRD §10 numeric constraints against dep-lib measured floors before declaring them acceptable. Methodology + lookup-table approach + CALIBRATION-WARN vs FAIL taxonomy. | `sdk-intake-agent`, `sdk-benchmark-devil-go`, `sdk-testing-lead` | P1 (retro-intake, retro-testing) |
| SHOULD | `mvs-forced-bump-preview` | Pattern for running Go MVS simulation against the live target `go.mod` (not a scratch module) to surface forced bumps of existing direct deps at design time, not impl time. | `sdk-dep-vet-devil-go`, `sdk-design-lead`, `sdk-impl-lead` | P2 (retro-design, retro-impl) |

Note: These are proposals only. Per CLAUDE.md Rule #23 skills are human-authored; the pipeline does NOT draft SKILL.md bodies for these entries. Related guardrails are proposed in `docs/PROPOSED-GUARDRAILS.md` (G25, G36, G66) — guardrails and skills reinforce each other but are independently PR-able.

---

## Auto-filed from run `sdk-dragonfly-p1-v1` on 2026-04-22

- **MISSING** `redis-pipeline-tx-patterns` (≥1.0.0) — source run `sdk-dragonfly-p1-v1`
- **MISSING** `go-iter-seq-patterns` (≥1.0.0) — source run `sdk-dragonfly-p1-v1`
- **MISSING** `redis-set-sortedset-semantics` (≥1.0.0) — source run `sdk-dragonfly-p1-v1`
- **MISSING** `generic-codec-helper-design` (≥1.0.0) — source run `sdk-dragonfly-p1-v1`

---

## Auto-filed from run `sdk-dragonfly-p1-v1` on 2026-04-23

- **MISSING** `redis-pipeline-tx-patterns` (≥1.0.0) — source run `sdk-dragonfly-p1-v1`
- **MISSING** `go-iter-seq-patterns` (≥1.0.0) — source run `sdk-dragonfly-p1-v1`
- **MISSING** `redis-set-sortedset-semantics` (≥1.0.0) — source run `sdk-dragonfly-p1-v1`
- **MISSING** `generic-codec-helper-design` (≥1.0.0) — source run `sdk-dragonfly-p1-v1`

---

## Auto-filed from run `sdk-dragonfly-p1-v1` on 2026-04-23

- **MISSING** `redis-pipeline-tx-patterns` (≥1.0.0) — source run `sdk-dragonfly-p1-v1`
- **MISSING** `go-iter-seq-patterns` (≥1.0.0) — source run `sdk-dragonfly-p1-v1`
- **MISSING** `redis-set-sortedset-semantics` (≥1.0.0) — source run `sdk-dragonfly-p1-v1`
- **MISSING** `generic-codec-helper-design` (≥1.0.0) — source run `sdk-dragonfly-p1-v1`

---

## Auto-filed from run `sdk-dragonfly-s2` on 2026-04-24

- **MISSING** `redis-pipeline-tx-patterns` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `hash-field-ttl-hexpire` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `pubsub-lifecycle` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `miniredis-testing-patterns` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `lua-script-safety` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `testcontainers-dragonfly-recipe` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `k8s-secret-file-credential-loader` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `sentinel-error-model-mapping` (≥1.0.0) — source run `sdk-dragonfly-s2`

---

## Auto-filed from run `sdk-dragonfly-s2` on 2026-04-24

- **MISSING** `redis-pipeline-tx-patterns` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `hash-field-ttl-hexpire` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `pubsub-lifecycle` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `miniredis-testing-patterns` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `lua-script-safety` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `testcontainers-dragonfly-recipe` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `k8s-secret-file-credential-loader` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `sentinel-error-model-mapping` (≥1.0.0) — source run `sdk-dragonfly-s2`

---

## Auto-filed from run `sdk-dragonfly-s2` on 2026-04-24

- **MISSING** `redis-pipeline-tx-patterns` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `hash-field-ttl-hexpire` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `pubsub-lifecycle` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `miniredis-testing-patterns` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `lua-script-safety` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `testcontainers-dragonfly-recipe` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `k8s-secret-file-credential-loader` (≥1.0.0) — source run `sdk-dragonfly-s2`
- **MISSING** `sentinel-error-model-mapping` (≥1.0.0) — source run `sdk-dragonfly-s2`

---

## Auto-filed from run `sdk-resourcepool-py-pilot-v1` on 2026-04-29 (F6 improvement-planner → learning-engine)

Source: `improvement-planner` Wave F6, derived from Phase 4 backlog items PA-001/PA-002, PA-012, PA-013 + retrospective Skill Gaps rows 1-3 + root-cause-traces. Status: `proposed` (awaiting human PR authorship per CLAUDE.md rule 23). First Python adapter pilot run.

### Proposed: python-bench-harness-shapes
<!-- Run: sdk-resourcepool-py-pilot-v1 | Date: 2026-04-30 | Confidence: HIGH -->

- **scope**: python
- **proposed_version**: 1.0.0
- **priority**: SHOULD
- **target_consumers**: sdk-impl-lead (python overlay), sdk-profile-auditor-python, sdk-benchmark-devil-python
- **provenance**: feedback-derived(PA-001, PA-002, run sdk-resourcepool-py-pilot-v1)
- **confidence**: HIGH
- **source_evidence**: defect-log DEF-001, DEF-002; root-cause-traces "PA-001 / PA-002"; retrospective Skill Gaps row 1
- **rationale**: pytest-benchmark's per-call timing model assumes `setup → measure → teardown` per iteration. Two real symbol shapes break that assumption: (a) **sync-fast-path-in-async** (`try_acquire`: a sync method called inside an asyncio context that returns immediately) — pytest-benchmark cannot reliably measure sub-µs sync calls; (b) **bulk-teardown** (`aclose`: drains N resources in one call) — per-iteration timing is meaningless because the work is amortized. Both shapes need bespoke harness templates. Without the skill, every Python adapter rediscovers the gap; PA-001/PA-002 will recur in every Python pack release.
- **proposed_body_outline**:
  1. §When-to-apply: any benchmarking task on a Python SDK client with sync/async or bulk-amortized methods
  2. §Three harness shapes — per-call (default; pytest-benchmark group), sync-fast-path-in-async (loop.call_soon timing harness; warmup loop sized to 10k iters; uses time.perf_counter_ns delta for sub-µs precision), bulk-teardown (parametrize over N ∈ {10, 100, 1k}; report µs/resource not µs/call; assert linear scaling)
  3. §GOOD examples for each shape (harness fixture + bench function + result-assertion pattern)
  4. §BAD example: pytest-benchmark @benchmark on a sync method called from async context (exhibits the PA-001 INCOMPLETE symptom)
  5. §Cross-reference: `python-pytest-patterns`, `sdk-marker-protocol` (constraint:bench markers)
- **suggested_path**: `skills/python-bench-harness-shapes/SKILL.md`

### ~~Proposed: python-floor-bound-perf-budget~~ — **WITHDRAWN v0.6.x**

The entire rationale for this skill was suppressing G108 (oracle-margin) false-positives on
Python symbols whose latency is bounded by CPython runtime overhead (frozen-dataclass init,
async ctx-mgr enter, etc.) where a Go reference impl is mechanically faster. With G108 / the
oracle concept removed in v0.6.x (only TPRD-declared targets are checked, no third-party
comparison), there is nothing for this skill to suppress. The underlying observation is still
valid — perf-architect-python should sanity-check declared targets against the Python
language floor — but that's already covered by `theoretical_floor.derivation` in
`design/perf-budget.md`. No separate skill needed.

### Proposed: soak-sampler-cooperative-yield
<!-- Run: sdk-resourcepool-py-pilot-v1 | Date: 2026-04-30 | Confidence: MEDIUM -->

- **scope**: shared-core
- **proposed_version**: 1.0.0
- **priority**: SHOULD
- **target_consumers**: sdk-soak-runner-python, sdk-soak-runner-go, future <lang>-soak-runners
- **provenance**: feedback-derived(PA-012, run sdk-resourcepool-py-pilot-v1; cross-language carry-over from existing Go-pack soak skill)
- **confidence**: MEDIUM
- **source_evidence**: defect-log DEF-012, DEF-019; root-cause-traces "PA-012 / SAMPLER-STARVATION" (called out as 'clearest example in the run of insufficient skill-content abstraction across languages'); retrospective Surprises bullet 2 + Skill Gaps row 3
- **rationale**: Python pack rediscovered a sampler-starvation bug already documented in the Go pack's soak skill, because that documentation is Go-specific. Cooperative-yield starvation in any single-threaded scheduler (asyncio event loop, goroutine scheduler, future Java virtual-thread carrier) under hot worker loops causes the soak sampler to under-sample during high-throughput phases — soak verdicts then reflect sampling artifacts rather than steady-state behavior. A shared-core skill ensures every future language pack inherits the warning by reading one shared body, not by re-deriving from runtime-specific symptoms.
- **proposed_body_outline**:
  1. §The pattern: cooperative-yield starvation under hot worker loops; symptom = sampler reports flat / dropped metrics during high-throughput phase, recovers during cooldown
  2. §Why language-neutral: applies to any cooperative scheduler — asyncio (Python), goroutine (Go), virtual-thread carrier (Java loom), tokio current_thread (Rust)
  3. §Mitigations: dedicated sampler thread/process (preferred); explicit `await asyncio.sleep(0)` / `runtime.Gosched()` between sample interval batches; subprocess sampler that observes process from outside (py-spy / pprof)
  4. §Per-language overlays: short subsection naming the language-native symptom + concrete cite into language-pack skills (`python-asyncio-patterns`, Go soak skill section X)
  5. §Validation: how to confirm sampler health post-soak — sample-count vs. expected per-second rate, gap detection
- **suggested_path**: `skills/soak-sampler-cooperative-yield/SKILL.md`
- **note**: explicitly cross-link from existing Go soak skill body and from `python-asyncio-patterns` SKILL.md once authored.

---

## Auto-filed from run `motadata-nats-v1` on 2026-05-04

- **MISSING** `asyncio-cancellation-patterns` (≥1.0.0) — source run `motadata-nats-v1`
- **MISSING** `python-class-design` (alias for `python-sdk-config-pattern`)` (≥1.0.0) — source run `motadata-nats-v1`
- **MISSING** `pytest-table-tests` (≥1.0.0) — source run `motadata-nats-v1`
- **MISSING** `python-tdd-patterns` (≥1.0.0) — source run `motadata-nats-v1`
- **MISSING** `python-idempotent-retry-patterns` (≥1.0.0) — source run `motadata-nats-v1`
- **MISSING** `python-api-ergonomics-patterns` (≥1.0.0) — source run `motadata-nats-v1`
- [ ] `python-library-api-shape-verification` — scope: python — confidence: medium — runs: 1 — first seen: motadata-nats-v1 — rationale: stand-alone skill prescribing the V-12 library-API-shape verification protocol (reflection patterns, multi-version testing matrix, cibuildwheel/tox version-matrix integration). Cited by sdk-impl-lead at M3.5 and sdk-dep-vet-devil-python at H6. Existing `python-dependency-vetting` v1.1.0 patch covers v0.1 of the use case; this skill would elevate to first-class.
- [ ] `python-m3-5-smoke-integration` — scope: python — confidence: low — runs: 1 — first seen: motadata-nats-v1 — rationale: skill prescribing the M3.5 30-second smoke-integration test for wrapped external libraries (between H7b and H7). Catches library-API-shape drift in impl phase rather than testing phase. Could alternatively live as a `sdk-impl-lead` Learned Pattern (already applied in this run's PP-feedback-2 patch) — promote to skill if pattern recurs across 3+ runs and authors find the embedded form too easy to skip.

---

## Auto-filed from run `l2cache-dragonfly-go-pilot-v1` on 2026-05-04

- **MISSING** `redis-pipeline-tx-patterns` (≥1.0.0) — source run `l2cache-dragonfly-go-pilot-v1`
- **MISSING** `hash-field-ttl-hexpire` (≥1.0.0) — source run `l2cache-dragonfly-go-pilot-v1`
- **MISSING** `pubsub-lifecycle` (≥1.0.0) — source run `l2cache-dragonfly-go-pilot-v1`
- **MISSING** `miniredis-testing-patterns` (≥1.0.0) — source run `l2cache-dragonfly-go-pilot-v1`
- **MISSING** `lua-script-safety` (≥1.0.0) — source run `l2cache-dragonfly-go-pilot-v1`
- **MISSING** `testcontainers-dragonfly-recipe` (≥1.0.0) — source run `l2cache-dragonfly-go-pilot-v1`
- **MISSING** `k8s-secret-file-credential-loader` (≥1.0.0) — source run `l2cache-dragonfly-go-pilot-v1`
- **MISSING** `sentinel-error-model-mapping` (≥1.0.0) — source run `l2cache-dragonfly-go-pilot-v1`
