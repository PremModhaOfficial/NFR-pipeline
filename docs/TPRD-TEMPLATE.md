<!-- cross_language_ok: true — author-facing TPRD template; phrasing is language-agnostic. Per-pack specifics belong in the language-pack manifest, not here. -->

# TPRD Template — Definitive Author Skeleton

This is the canonical Technical Product Requirements Document skeleton accepted by `/preflight-tprd` and `/run-sdk-addition`. Authoring a TPRD that conforms to this template is the human contract that gates the whole pipeline.

## What the pipeline requires

A TPRD is accepted by Phase 0 Intake when it has:

- **14 mandatory core sections** — `§1` through `§14`, each non-empty (G20 BLOCKER).
- **2 mandatory manifests** — `§Skills-Manifest` (G23 WARN; misses auto-file to `docs/PROPOSED-SKILLS.md`) and `§Guardrails-Manifest` (G24 BLOCKER; missing scripts halt with exit 6).
- **1 mandatory required field** — `§Target-Language` (Wave I1.5 BLOCKER; must match a manifest at `.claude/package-manifests/<lang>.json`).
- **2 defaulted fields** — `§Target-Tier` (default `T1`) and `§Required-Packages` (default: `["shared-core@>=1.0.0", "<§Target-Language>@>=1.0.0"]`).

Header keywords are case-insensitive and order-independent; G20 matches by topic, not by literal `§` numbers.

Coherence checks at preflight: `§1 Request Type` must agree with `§12 Breaking-Change Risk`; any `§14` open question with `Blocker: YES` must be resolved before H1.

---

## 1. Canonical skeleton

Copy the block below as your TPRD scaffold. Fill in every section non-empty before running `/preflight-tprd`.

```markdown
---
title: "Add <Feature> to <SDK>"
author: "you@motadata.com"
date: "YYYY-MM-DD"
---

§Target-Language: <lang>
§Target-Tier: T1
§Required-Packages:
  - "shared-core@>=1.0.0"
  - "<lang>@>=1.0.0"

# Technical Product Requirements Document — <Title>

## §1 Request Type
<Mode A (greenfield new package) | Mode B (extension to an existing package) | Mode C (incremental tightening of an existing package)>. Must agree with §12.

## §2 Scope
### In-Scope
- <bullet>
- <bullet>

### Non-Goals
- <bullet>            <!-- ≥3 required by G21 -->
- <bullet>
- <bullet>

## §3 Motivation
<Why this addition matters: business driver, customer ask, roadmap priority, compliance need.>

## §4 Functional Requirements
| ID | Description | Priority | §7 Symbol |
|---|---|---|---|
| FR-<DOMAIN>-01 | <single-sentence requirement> | Must | <Config / New / public method / sentinel> |
| FR-<DOMAIN>-02 | … | Must | … |

<!-- Each FR-id will be referenced from §Skills-Manifest "Why required" and from generated code via [traces-to: TPRD-§4-FR-<id>]. -->

## §5 Non-Functional Requirements
### Performance Targets
- **Latency** (per §7 symbol): p50 ≤ XX, p95 ≤ XX, p99 ≤ XX.
- **Throughput**: ≥ XXX ops/sec.
- **Allocation budget**: ≤ X allocs/op (G104 enforced at M3.5).
- **Complexity**: declared big-O per hot symbol (G107 scaling sweep at T5).
- **Oracle margin**: measured p50 ≤ X× the declared reference impl (G108).
- **MMD (soak)**: minimum-measurable-duration for soak symbols (G105).

### Drift Signals
<Which metrics indicate regression in production. Consumed by the perf architect at D1 to author `design/perf-budget.md`.>

## §6 Dependencies + Config Validation
<Each external dep, one row per dep:>
- `<name>@<version>` — license: <SPDX>; vuln-scan: <pack scanner status>; lockfile-scan: <pack lockfile-scanner status>; transitive count: <N>; last-commit age: <duration>.

<Config validation rules:>
- <rule, e.g. "fail fast if remote address is unset and no service-discovery hook is wired">

## §7 Config + API
<Code block in the target language. Every exported symbol carries a doc-comment that begins with the symbol name.>

```<lang>
<Config struct/class>
<constructor signature: takes Config, returns Client + error>
<public methods>
<sentinel errors / typed exception hierarchy>
```

<!-- Generated symbols will be stamped with [traces-to: TPRD-§7-<id>] (G99/G102/G103). Do not author markers by hand. -->

## §8 Observability
### Spans
| Span name | Attributes |
|---|---|
| `<low-cardinality.name>` | `<key1>`, `<key2>`, … |

### Metrics
| Metric | Type | Unit | Labels |
|---|---|---|---|
| `<name>` | counter / histogram / gauge | <unit> | <bounded-cardinality labels> |

<Trace propagation strategy: language-pack OTel helper, never raw upstream OTel SDK.>

## §9 Resilience
- **Retry**: <attempts>, base <ms>, max <ms>, jitter <strategy>; retryable error classes: <list>; non-retryable: <list>.
- **Circuit breaker**: failure threshold <count>/<window>, recovery timeout <duration>, half-open success count <N>.
- **Connection pool**: min <N>, max <N>, idle timeout <duration>, on-error reconnect strategy.

## §10 Security
- **TLS / mTLS plan**: <required-floor>, SNI required, custom CA path, client cert if mTLS.
- **Credential provider**: <static / env / file-with-rotation / IAM-STS / OAuth>; never plaintext in source (G69).
- **Auth scheme**: <bearer / API key / mTLS / OAuth>.
- **Input validation**: <bounds, regex, size limits>.

## §11 Testing
- **Unit**: table-driven cases per public method; coverage ≥ 90% on new package (G60).
- **Integration**: real backends via testcontainers / language-pack equivalent; image versions pinned.
- **Benchmarks**: per hot-path symbol; allocation reporting on (G104); benchstat-equivalent regression compare vs baseline (G65).
- **Fuzz**: parsers/validators with crash-triage workflow.
- **Leak**: pack leak-detection harness clean (G63).
- **Flake hunt**: -count=N on integration suite; flake hunter at T3.

## §12 Breaking-Change Risk
<Mode A: "No breaking changes (new exports only)." | Mode B/C: enumerate signature/behavior changes + their semver implication: major / minor / patch.>

<Must agree with §1. Each removed-or-changed exported symbol pairs with a `[stable-since: vX.Y.Z]` decision (G101).>

## §13 Rollout
- **H1** (TPRD approval): <go/no-go criteria — typically: TPRD is complete, manifests resolve, intake clarifications resolved>.
- **H5** (design): <api stub passes all design devils (semver, convention, security, over-engineering)>.
- **H7** (impl): <code passes impl devils + leak/marker/constraint, ≥90% coverage>.
- **H9** (testing): <perf-confidence gates pass: regression, oracle, allocation, complexity, drift, MMD>.
- **H10** (merge): <final diff reviewed; learning-notifications acknowledged>.

## §14 Pre-Phase-1 Clarifications
- **OQ-001**: <question> — **ANSWER REQUIRED**: <Yes/No>; **Blocker**: <YES/NO>.
- **OQ-002**: <question> — **ANSWER REQUIRED**: <Yes/No>; **Blocker**: <YES/NO>.

<!-- Any OQ with Blocker: YES that is unresolved at preflight → exit 4. Cap of 5 clarifying questions in Wave I4; >5 = ESCALATION. -->

## §Skills-Manifest
| Skill | Min version | Why required |
|---|---|---|
| <skill-id>                    | 1.0.0 | <FR-id or §-reference> |
| <skill-id>                    | 1.0.0 | <FR-id or §-reference> |

<!-- G23 (WARN-only): each skill must exist in skills/skill-index.json at version ≥ declared. Misses auto-file to docs/PROPOSED-SKILLS.md with run-id + reason. Pipeline continues. -->

## §Guardrails-Manifest
| Guardrail | Applies to | Enforcement |
|---|---|---|
| G01            | all          | BLOCKER  |
| G20            | intake       | BLOCKER  |
| G21            | intake       | BLOCKER  |
| G23            | intake       | WARN     |
| G24            | intake       | BLOCKER  |
| <G-id ranges>  | <phase>      | BLOCKER  |

<!-- G24 (BLOCKER): each declared G-id must have an executable script at scripts/guardrails/<G-id>.sh. Missing script → exit 6; entry filed to docs/PROPOSED-GUARDRAILS.md. -->

## §Docs-Manifest
<!-- OPTIONAL (v0.7+). Consumed by Phase 0 wave I-DOC. Drives Phase 3.5 (Documentation) target paths. If absent on Mode A: targets inferred from new module path. If absent on Mode B/C with ambiguous scope: H1 asks. -->
targets:
  - src/<sdk>/<module>/        # one or more directories that should receive README.md / USAGE.md / ARCHITECTURE.md / CHANGELOG.md (and MIGRATION.md on breaking changes)
skip: false                    # if true, Phase 3.5 D1 wave is skipped entirely (still applies version via V1)
examples_allowed: false        # if true, sdk-doc-writer may MINE samples from a pre-existing examples/ dir; never authors new examples regardless

## §Versioning
<!-- OPTIONAL (v0.7+). Consumed by Phase 0 wave I-VER. Drives Phase 3.5 wave V1 (sdk-version-applier). If `confirmed` is false (or absent), H1 emits a sub-question with the inferred bump + reasoning. -->
current: 1.3.0                 # optional; auto-detected from active language pack's primary version artifact (git tag, pyproject.toml, package.json, Cargo.toml, ...)
bump: MINOR                    # PATCH | MINOR | MAJOR — inferred from §1 + §12 if absent
next: 1.4.0                    # optional; computed from current + bump if absent
confirmed: false               # if true, skip H1 confirmation question (CI-only override)
reasoning: "Adds new public symbols to module X without removing or renaming existing exports."   # appended to CHANGELOG entry
```

---

## 2. Section quick-reference

What each section must contain, what header keywords G20 will accept, and what gate fires.

| § | Header keywords G20 accepts (case-insensitive) | Required content | Validator(s) |
|---|---|---|---|
| §1  | `Request Type` \| `Purpose` \| `Overview`            | Mode A / B / C declaration                                | G20; preflight §1↔§12 coherence |
| §2  | `Scope` \| `Goals`                                    | In-Scope bullets + `Non-Goals` subsection (≥3 bullets)    | G20; G21 |
| §3  | `Motivation` \| `Rationale` \| `Purpose`              | Rationale narrative                                       | G20 |
| §4  | `Functional` \| `API Surface` \| `API`                | FR-*-NN table                                             | G20; downstream `[traces-to:]` (G99/G102) |
| §5  | `Non-Functional` \| `Perf Target` \| `NFR`            | Numeric perf gates per symbol                             | G20; perf architect at D1 → `design/perf-budget.md` |
| §6  | `Dependencies` \| `Compat Matrix`                     | Deps with vuln-scan + lockfile-scan status                | G20; G32 / G33 / G34 at testing |
| §7  | `Config`                                              | Code block: Config + constructor + methods + sentinels    | G20; symbol coverage at impl |
| §8  | `Observability` \| `OTel` \| `Tracing` \| `Metrics`   | Span + metric catalog                                     | G20 |
| §9  | `Resilience` \| `Error Model` \| `Reliability`        | Retry + breaker + pool + reconnect                        | G20 |
| §10 | `Security`                                            | TLS / creds / authn-z / input validation                  | G20; G69 |
| §11 | `Testing` \| `Test Strategy`                          | Unit + integration + bench + fuzz + flake-hunt            | G20; G60 / G63 / G65 |
| §12 | `Breaking-Change` \| `Semver`                         | Semver bump declaration                                   | G20; preflight coherence |
| §13 | `Rollout` \| `Milestone` \| `Deployment`              | Per-HITL go/no-go criteria                                | G20 |
| §14 | `Clarification` \| `Open Question` \| `Risk`          | OQ-* entries with `Blocker` flag                          | G20; preflight blocker check |
| §Skills-Manifest    | literal                                  | Skill table (≥1 row)                                      | G23 (WARN) |
| §Guardrails-Manifest | literal                                 | Guardrail table (≥1 row)                                  | G24 (BLOCKER) |
| §Target-Language    | literal                                  | Single value matching a `.claude/package-manifests/*.json` | Wave I1.5 (BLOCKER) |

---

## 3. Marker contract (for §4 / §7 anchors)

Authors do **not** write markers — the pipeline stamps them. The TPRD must give the markers something to anchor to:

| Marker | Anchor in TPRD | Validator |
|---|---|---|
| `[traces-to: TPRD-§<N>-<ID>]`                | Stable §4 FR-IDs and §7 symbol names                                   | G99 (every pipeline symbol has it), G102, G103 (no forged MANUAL-*) |
| `[constraint: <metric>:bench/<Name>]`        | §5 NFR target paired with §11 bench name                                | G97 (named bench exists in test output) |
| `[stable-since: vX.Y.Z]`                     | §12 semver decision per changed/new exported symbol                     | G101 (signature change ↔ major bump) |
| `[owned-by: pipeline | MANUAL]`              | Implicit (Mode B/C ownership map; pipeline-managed)                     | G95 (MANUAL byte-hash unchanged at Mode B/C exit) |
| `[perf-exception: <reason> bench/<Name>]`    | Requires a paired entry in `runs/<run-id>/design/perf-exceptions.md`    | G110 (orphan exceptions = BLOCKER) |

---

## 4. Pre-flight your TPRD before running the pipeline

```bash
# Validate locally without spending pipeline budget:
/preflight-tprd --spec runs/my-tprd.md
```

Expected exit codes:

| Exit | Meaning | Action |
|---|---|---|
| 0 | PASS (or WARN on §Skills-Manifest, non-blocking)         | Proceed to `/run-sdk-addition --spec runs/my-tprd.md` |
| 1 | Structure FAIL (§ missing / Non-Goals < 3)               | Edit TPRD; re-run preflight |
| 3 | §Guardrails-Manifest FAIL (missing/non-exec script)      | Author missing guardrail script via PR; re-run |
| 4 | §14 has unresolved `Blocker: YES` open question          | Resolve the blocker question in the TPRD; re-run |
| 6 | Skills/Guardrails resolution failure (pipeline runtime)  | See `runs/<run-id>/intake/<*>-check.md`; address files |
| 8 | §Target-Language missing or declared more than once      | Add exactly one `§Target-Language: <lang>` line |

Preflight never modifies the target SDK; it only reads the TPRD and reports.

---

## 5. Authoring tips

- **Keep §4 FR-IDs stable.** Generated code carries `[traces-to: TPRD-§4-FR-<id>]` markers; renaming an FR-ID after H7 invalidates traceability.
- **§5 numbers must be falsifiable.** Vague targets ("fast", "low memory") fail at H9. Pick numbers; the perf architect will refine them at D1, but a numeric starting point is required.
- **§7 is the contract.** Every symbol you list will get an impl + test + doc-comment + benchmark (if hot path) + runnable example (if applicable). Listing a symbol commits the pipeline to building it.
- **§Skills-Manifest "Why required" should cite an FR-ID or section.** That column is human-readable provenance; arbitrary prose passes G23 but loses traceability for the next author.
- **§Guardrails-Manifest is a checklist, not a specification.** The pipeline runs every guardrail script that fires for the relevant phase regardless. The manifest declares *which guardrails the author expects to be relevant*; G24 verifies those scripts exist. Don't omit guardrails because you don't think they apply — declare them and let the script no-op.
- **§14 is for *knowable unknowns only*.** Open questions whose answers change §1–§13 belong here; speculative product questions belong elsewhere. Cap is 5 clarifying questions in Wave I4; >5 escalates.

---

## 6. References

- Validators: `scripts/guardrails/G20.sh` (sections), `G21.sh` (Non-Goals ≥3), `G23.sh` (skills-manifest), `G24.sh` (guardrails-manifest).
- Preflight contract: `commands/preflight-tprd.md`.
- Intake waves: `phases/INTAKE-PHASE.md` (I1 ingest → I1.5 required-fields → I2 skills → I3 guardrails → I4 clarifications → I5 mode → I5.5 package-resolve → I6 completeness → I7 H1).
- Required field semantics: `agents/sdk-intake-agent.md` (§Target-Language).
- Marker protocol: `skills/sdk-marker-protocol/SKILL.md`.
- Pipeline overview: `PIPELINE-OVERVIEW.md` and `LIFECYCLE.md`.

## §OTel — Observability Contract

> Every field below is REQUIRED. Use exact enum values. `TBD`/`maybe`/empty trigger
> G20 BLOCKER at intake H1. Authoring guide: see `spec-driven-development` skill §OTel.

### Signals
- `signals.traces`: <on|off>
- `signals.metrics`: <on|off>
- `signals.logs`: <on|off>

### Provider integration
- `consumer_provider_optin`: <yes|no>
  - `yes` = SDK accepts `WithTracerProvider(tp)`/`WithMeterProvider(mp)`/`WithLoggerProvider(lp)` (Go) or `tracer_provider=`/`meter_provider=`/`logger_provider=` kwargs (Python). SDK uses passed provider but never calls Shutdown on it.
  - `no` = SDK uses global API only (`otel.Tracer(name)` Go / `trace.get_tracer(__name__)` Python).
- `facade_used_go`: <module-path | not-applicable>
  - Required if Go pack AND any signal on. Example: `motadatagosdk/otel`.
- `facade_used_python`: <module-path | not-applicable>
  - Python idiom is bare `opentelemetry` API; default `not-applicable`.

### Attributes — sensitive value forbid-list
- `forbidden_attributes`:
  - tenant_id
  - user.id
  - password
  - token
  - api_key
  - secret
  - <add SDK-specific keys here>
  - SDK code MUST NOT emit these. Consumer adds at runtime via W3C baggage; collector copies baggage → span attr at backend boundary.

### Declared identifiers
- `declared_metric_ids`: <list, may be empty>
  - Format: `motadata.<sdk-name>.<thing>` per OTel `<domain>.client.*` semconv.
  - Empty `[]` = SDK emits ONLY facade defaults.
- `declared_span_names`: <list, non-empty if signals.traces=on>
  - Format: lowercase dot-separated. Static, low-cardinality. Example: `motadata.cache.get`.

### Logging
- `log_correlation`: <required|consumer-side|off>
  - Go default `required` — `slog.Handler` middleware at facade injects `trace_id`/`span_id`.
  - Python default `consumer-side` — library only emits via `logging.getLogger(__name__)`; correlation is consumer's `LoggingHandler` setup.
  - `off` = no log emission expected.

### Surface
- `nats_surface`: <yes|no>
  - `yes` = SDK propagates W3C `traceparent` header through NATS messages. Triggers NATS-propagation sub-check at impl review.

### Tenant attribution (if applicable)
- `tenant_attribution`: <consumer-baggage|consumer-resource-attr|none>
  - SDK never sets tenant_id directly (G38 BLOCKER).
  - `consumer-baggage` = consumer adds `tenant_id` via baggage at request entry; collector processor copies to span.
  - `consumer-resource-attr` = process-isolated multi-tenancy; consumer sets `service.namespace=tenant-X` at provider init.
  - `none` = single-tenant SDK or tenant attribution out of scope.

### Authoring example

```
## §OTel — Observability Contract

### Signals
- signals.traces: on
- signals.metrics: on
- signals.logs: on

### Provider integration
- consumer_provider_optin: yes
- facade_used_go: motadatagosdk/otel
- facade_used_python: not-applicable

### Attributes — sensitive value forbid-list
- forbidden_attributes:
  - tenant_id
  - user.id
  - password
  - token
  - api_key
  - secret

### Declared identifiers
- declared_metric_ids:
  - motadata.cache.requests
  - motadata.cache.duration_ms
  - motadata.cache.errors
- declared_span_names:
  - motadata.cache.get
  - motadata.cache.set
  - motadata.cache.delete

### Logging
- log_correlation: required

### Surface
- nats_surface: no

### Tenant attribution
- tenant_attribution: consumer-baggage
```

### Common authoring mistakes (G20 will reject)
- `signals.traces: TBD` — pick yes or no
- `consumer_provider_optin:` (empty) — must specify
- `forbidden_attributes: see standards` — must enumerate
- `declared_span_names: <varies>` — names must be static at SDK author time
- `log_correlation: maybe` — pick `required`/`consumer-side`/`off`

> §OTel completeness validated by `scripts/guardrails/G20.sh` at intake (BLOCKER). Ambiguous values (`TBD`/`maybe`/empty/non-enum) → FAIL → escalate H1.
