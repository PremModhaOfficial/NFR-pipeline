<!-- cross_language_ok: true — top-level pipeline doc references per-pack tooling and the multi-tenant SaaS platform context (per F-008 in migration-findings.md). Authoritative project description: SDK is built FOR multi-tenant SaaS consumers; multi-tenant guardrails (TenantID, JetStream, MsgPack, schema-per-tenant) are in-scope. -->

# motadata-sdk-pipeline — Executive Overview

> **Audience**: CXO + Tech Leads
> **Version**: 0.6.0
> **Date**: 2026-04-24
> **Status**: Production-ready — MCP-enhanced knowledge graph, perf-confidence regime, compensating-baseline safety net, deterministic-first reviewer gate

---

## 1. Executive Summary

**What it is.** A multi-agent pipeline that takes a Technical PRD (TPRD) for a new or extended Go SDK client and produces production-grade code, tests, benchmarks, and observability — on a dedicated git branch, against numeric quality gates declared in the spec.

**What it solves.** Today, every team that adds a backend client to the SDK target (Redis, NATS, Kafka, S3, Dragonfly, …) hand-rolls retry logic, observability, pool tuning, TLS, credential loading, and tests. The result: inconsistent quality, drift between clients, and 1–4 weeks of senior-engineer time per addition.

**What changes.** The pipeline turns "add client X to the SDK" into a single command against a detailed TPRD. A complete first-class SDK client (≥90 % coverage, OTel-instrumented, leak-clean, supply-chain-vetted, on its own branch, behind explicit human approval gates) lands in ~1–2 hours of pipeline runtime + ~3 hours of human review.

**Why now.** We have 8 backend integrations on the near-term roadmap (Dragonfly, NATS, S3, Kafka, RabbitMQ, MinIO, Redis Streams, more). At hand-rolled cost (~3 weeks senior time × 8) that is ~6 engineer-months. At pipeline cost (~3 hours review × 8) that is ~3 engineer-days, plus the one-time cost of the pipeline itself (already built).

**Risk profile.** Low. The pipeline never commits to main, never force-pushes, never modifies human-marked code, and halts at every quality gate for explicit approval. New skills, agents, and guardrails require human PR — the pipeline cannot evolve itself without supervision.

---

## 2. The Strategic Bet

> **Humans author the contract. The pipeline produces the code against it deterministically.**

We split SDK development into two distinct activities, each played to its strength:

| Human strength | Pipeline strength |
|---|---|
| Defining what the API should do (TPRD) | Implementing it consistently (38 agents, 41 skills) |
| Making policy decisions (skill authorship, breaking-change verdicts) | Mechanical conformance (52 guardrail scripts, 7 falsification axes for perf, 7 quality gates) |
| Reviewing the diff | Producing the diff (TDD, marker-aware merge, devil reviews) |
| Owning architecture | Owning consistency |

The result: every SDK client looks like every other, hits the same quality bar, has the same observability surface, and can be regenerated identically from the same TPRD + seed.

---

## 3. What It Does (in one paragraph)

Given a detailed TPRD describing a new client (Mode A), an extension to an existing client (Mode B), or an incremental tightening (Mode C), the pipeline runs five phases in sequence — Intake, Design, Implementation, Testing, Feedback — gated by seven Human-in-the-Loop (HITL) approval points. Inside each phase, a team of specialized agents (designers, implementors, testers) does the work; a parallel team of "devil" agents adversarially reviews it (security, semver, dependencies, conventions, over-engineering, leaks, ergonomics, benchmarks). Anything that fails a devil review loops back for fixes (capped at 10 iterations). The output: a feature branch on the SDK target with new code + tests + benchmarks, a full audit trail under `runs/<run-id>/`, and updated quality baselines. The user reviews the final diff and decides whether to merge.

---

## 4. Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  HUMAN: authors TPRD + §Skills-Manifest + §Guardrails-Manifest      │
│                              │                                       │
│                              ▼                                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │                                                              │    │
│  │   Phase 0   Intake     ─ validate TPRD + manifests ── H1   │    │
│  │   Phase 0.5 Analyze    ─ (Mode B/C) snapshot existing      │    │
│  │   Phase 1   Design     ─ API + 7 devil reviews ─────── H5  │    │
│  │   Phase 2   Impl       ─ TDD + marker-aware merge ── H7    │    │
│  │   Phase 3   Testing    ─ unit/int/bench/leak/fuzz ── H9    │    │
│  │   Phase 4   Feedback   ─ metrics + drift + notify ── H10   │    │
│  │                                                              │    │
│  │      review-fix sub-loop inside each phase                  │    │
│  │      (5 retries / finding · 10 global cap · auto-rerun      │    │
│  │       all devils after every rework — CLAUDE.md rule 13)    │    │
│  │                                                              │    │
│  └────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                              ▼                                       │
│  Branch sdk-pipeline/<run-id> on the SDK target                    │
│  HUMAN: reviews diff at H10, decides merge / iterate / discard      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (artifacts persist; cross-run loop)
              learning-engine patches existing skills
              drift/coverage reporters file new-skill proposals
              baseline-manager raises quality bar
```

---

## 5. The Two Loops

### Single-run loop (one TPRD → one branch)
Forward-only. Phases run sequentially. No automatic backward jumps. The only loops within a run are bounded review-fix sub-loops inside a single phase (devil flags issue → owner fixes → re-review).

### Cross-run loop (one TPRD → next TPRD)
At end of every Phase 4, `learning-engine` writes:
- **Prompt patches** (≤10 / run, auto-applied, append-only)
- **Existing skill body patches** (≤3 / run, auto-applied with notification line per patch; user reviews `learning-notifications.md` at H10 and may revert)
- **New-skill proposals** (filed to `docs/PROPOSED-SKILLS.md` for human PR; pipeline cannot author them)
- **New-guardrail proposals** (same, filed to `docs/PROPOSED-GUARDRAILS.md`)

Effects materialize in subsequent runs. A pattern observed in Dragonfly + S3 (2-run recurrence) becomes high-confidence and is acted on. Patterns observed once are watched but not yet acted on.

---

## 6. Governance Model

| Decision | Who decides | Mechanism |
|---|---|---|
| Architecture / API contract | **Human** | TPRD authoring |
| Skill prescriptions | **Human** | PR-merge into `skills/` |
| Agent prompts (initial) | **Human** | PR-merge into `agents/` |
| Guardrail scripts | **Human** | PR-merge into `scripts/guardrails/` |
| Implementation against contract | **Pipeline** | Phase 2 TDD |
| Devil review verdicts | **Pipeline** (devil agents) | Block / approve per phase |
| Skill body refinement | **Pipeline** (learning-engine) | Patch + minor bump + notify-user via `learning-notifications.md` (no golden-corpus gate) |
| New skill creation | **Human** | PR (pipeline files proposals only) |
| Final merge to main | **Human** | H10 gate |

**The hard rule:** the pipeline can refine what humans gave it. The pipeline cannot create new contracts, new agents, or new guardrails on its own.

---

## 7. Components at a Glance

| Component | Count | Purpose |
|---|---:|---|
| Phases | **5** | Intake, Design, Impl, Testing, Feedback (+ 0.5 for Mode B/C) |
| Agents | **38** | 5 leads, 13 devils, 5 perf/drift specialists, 4 Mode B/C helpers, 11 ported feedback-track |
| Skills | **41** | 20 SDK-native + 21 generic Go/test/meta/observability/mcp (see `skills/skill-index.json` for the live list) |
| Guardrail scripts | **52** | Mechanical pass/fail checks across all phases (catalog IDs G01–G116) |
| HITL gates | **7** | Explicit human approval at every transition |
| Slash commands | **2** | `/run-sdk-addition`, `/preflight-tprd` |
| Baselines | **10** | Quality, coverage, performance, skill-health, skill-health-baselines, marker-hashes, stable-signatures, output-shape-history, devil-verdict-history, baseline-history |

### Phase responsibilities

| Phase | Lead | Output |
|---|---|---|
| 0 Intake | `sdk-intake-agent` | Canonical TPRD + manifest validation reports |
| 0.5 Analyze | Existing-API Analyzer (per-pack) | API snapshot + ownership-map (Mode B/C only) |
| 1 Design | `sdk-design-lead` | `api.go.stub`, interfaces, dependency vetting, devil verdicts |
| 2 Impl | `sdk-impl-lead` | Code + tests on `sdk-pipeline/<run-id>` branch |
| 3 Testing | `sdk-testing-lead` | Coverage, benchmarks, leak/vuln/flake reports |
| 4 Feedback | `learning-engine` | Metrics, drift, baseline updates, per-patch user notifications |

### Devil agents (adversarial review, read-only)

| Agent | Catches |
|---|---|
| `sdk-design-devil` | Bad API shape |
| Dep-Vet Devil (per-pack) | Risky / unfree / vulnerable deps |
| `sdk-semver-devil` | Hidden breaking changes |
| Convention Devil (per-pack) | Inconsistency with target SDK |
| `sdk-security-devil` | Auth, TLS, credential leaks |
| `sdk-overengineering-critic` | Unused fields, premature abstraction |
| leak hunter (per-pack) | Goroutine leaks |
| API Ergonomics Devil (per-pack) | Consumer-side ugliness |
| Benchmark Devil (per-pack) | Perf regressions |
| Integration Flake Hunter (per-pack) | Test flakes |
| `sdk-marker-hygiene-devil` | Missing or forged provenance markers |
| Constraint Devil (per-pack) | Unproven `[constraint:]` claims |
| Breaking-Change Devil (per-pack) | Mode B/C signature changes (no semver bump) |

### Perf / drift specialists (rules 32 + 33)

| Agent | Role |
|---|---|
| Perf Architect (per-pack) | Authors `design/perf-budget.md` at D1 — per-symbol p50/p95/p99, allocs/op, big-O, theoretical floor, MMD, drift signals |
| Profile Auditor (per-pack) | At M3.5: reads CPU/heap/block/mutex profiler output; enforces G104 alloc budget + G109 profile-shape coverage (≥0.8 match to declared hot paths) |
| Complexity Devil (per-pack) | At T5: scaling sweep at N ∈ {10, 100, 1k, 10k}; curve-fits and enforces G107 big-O match |
| Soak Runner (per-pack) | At T5.5: launches soaks in background, polls state files on a ladder; enforces G105 MMD (minimum-measurable-duration) |
| `sdk-drift-detector` | At T5.5: fast-fail on statistically significant positive trend in drift signals (G106) |

---

## 8. Quality Contract

The TPRD declares numeric gates. The pipeline enforces them.

| Gate | Threshold | Source |
|---|---:|---|
| New-package branch coverage | ≥ **90%** | TPRD §11 + G60 |
| Existing-package coverage delta (Mode B/C) | **≥ 0** | G60 |
| Bench regression — new-package hot path | > **5%** = BLOCKER | TPRD §10 + G65 |
| Bench regression — shared path | > **10%** = BLOCKER | G65 |
| Alloc budget (per symbol) | measured ≤ declared | G104 |
| Big-O complexity match | curve-fit ≤ declared | G107 |
| Absolute target latency | measured p50/p95/p99 ≤ TPRD-declared `latency.*` in `perf-budget.md` | Benchmark Devil (per-pack) — H8 surfaces target-miss for user resolution |
| Profile-shape coverage | top-10 CPU samples ≥ 0.8 match to declared hot paths | G109 |
| Soak MMD | `actual_duration_s ≥ mmd_seconds` or verdict = INCOMPLETE | G105 |
| Drift trend | no statistically significant positive trend on declared drift signals | G106 |
| the pack's leak-detection harness | clean | G63 |
| the pack's vulnerability scanner HIGH/CRITICAL | **0** | G32 |
| the pack's lockfile vulnerability scanner HIGH/CRITICAL | **0** | G33 |
| Dep license | Allowlist (MIT, Apache-2.0, BSD, ISC, 0BSD, MPL-2.0) | G34 |
| Determinism (same TPRD + seed) | Byte-equivalent | CLAUDE.md rule 25 |
| Quality regression (cross-run) | ≤ **5%** per-agent `quality_score` once ≥3 prior runs | G86 |

**Override**: `--accept-perf-regression <pct>` on the run command (logged + flagged for review).

---

## 9. Safety Mechanisms

| Mechanism | Effect |
|---|---|
| Dedicated branch (`sdk-pipeline/<run-id>`) | Never touches main; never force-pushes |
| Target-dir discipline (G07) | Writes only to `$SDK_TARGET_DIR` + `runs/` |
| `--dry-run` mode | Halts before any target-dir write; emits `preview.md` |
| Marker protocol (G95–G103) | `[owned-by: MANUAL]` symbols byte-hash-checked; pipeline cannot modify them |
| Compensating baselines × 4 (rule 28) | Output-shape hash + devil-verdict stability + tightened 5% quality threshold (G86) + runnable examples (per-pack: `Example_*` in Go, doctest blocks in Python) count per package — replaces retired golden-corpus gate |
| Learning-notifications loop (G85) | Every learning-engine patch emits a line to `learning-notifications.md`; user reviews at H10 and may revert per-patch |
| Deterministic-first reviewer gate (rule 13) | Reviewer fleet only re-runs on iterations where build, vet, fmt, static-check, race-detection (if supported), leak-detection, vulnerability-scan, lockfile-scan, marker-hash, constraint-bench, license are green |
| MCP health check (G04) | WARN-only; writes `runs/<id>/<phase>/mcp-health.md`; pipeline never halts on MCP failure (rule 31) |
| Doc-drift gate (G06 + G90 + G116 + check-doc-drift.sh) | Intake refuses to run on a drifted repo: `pipeline_version` consistency, skill-index ↔ filesystem equality, retired-term registry enforcement |
| Per-phase token + wall-clock budget | Soft cap → WARN; hard cap → user confirms |
| HITL gates × 7 | Every phase transition requires human approval (or explicit timeout policy) |
| Decision log | Every agent action JSONL-appended; full audit trail per run |
| Resume from checkpoint | Halted runs resume from last completed wave (`--resume <run-id>`) |
| Credential hygiene (G69) | Source-scan blocks plaintext credentials in committed code |
| Supply-chain gate (G32–G34) | No vulnerable / unfree dependencies enter the SDK |
| Skill / agent / guardrail authorship | Human PR only — pipeline cannot expand its own permission surface |

---

## 10. Self-Improvement Mechanics

The pipeline gets better over time, within tightly bounded rules.

```
After every Phase 4:

  metrics-collector ─→ per-agent quality scores (0.0–1.0)
                       per-phase rework / devil-block-rate / coverage
                       per-run pipeline_quality, bench-delta, vuln-count

  drift-detector ──→ skill-prescription vs. code-reality gaps
  coverage-reporter → declared-but-unused skills
  root-cause-tracer → defect → introducing-phase mapping
  improvement-planner → categorize: prompt-patch / skill-patch / new-skill-proposal

  learning-engine:
    ✓ apply prompt patches  (≤10/run)
    ✓ apply skill body patches  (≤3/run, minor version bump, notify user via learning-notifications.md)
    ✗ create new skills       (FILE TO BACKLOG instead — human PR required)
    ✗ create new agents       (same)
    ✗ create new guardrails   (same)

  baseline-manager:
    raise quality bar if improved >10%
    keep on regression (never lower)
    full reset every 5 runs
    update 4 compensating baselines (rule 28):
      - output-shape-history.jsonl        (⚠ shape-churn WARN on skill-patched runs)
      - devil-verdict-history.jsonl       (⚠ devil-regression WARN on ≥20pp jump)
      - quality regression (G86, BLOCKER) (≥5% delta with ≥3 prior runs)
      - Example_* count per package       (⚠ example-drop WARN on drop with ≥2 prior runs)
```

| Self-improvement cap | Value | Why |
|---|---:|---|
| Confidence threshold for auto-apply | `high` | Conservative |
| Recurrence required | 2+ runs | Avoid noise-driven changes |
| Prompt patches per run | ≤ 10 | Bounded surface area |
| Existing-skill body patches per run | ≤ 3 | Avoid skill-churn destabilizing pipeline |
| New skills / agents / guardrails per run | **0** | Strictly human-PR-only |
| Learning-notifications (G85) | required per patch | User reviews at H10, may revert |
| Quality regression (G86) | BLOCKER at 5% once ≥3 prior runs | Tightened from 10% with retirement of golden-corpus |
| Baseline reset | every 5 runs | Re-anchor to current performance |

---

## 11. MCP-Enhanced Knowledge Graph

The pipeline's cross-run state (defects, patterns, baselines, agent performance, patches) lives in a Neo4j graph database via the `mcp__neo4j-memory__*` MCP. What used to be grep-through-JSONL becomes queryable Cypher.

### What it enables

| Before (flat JSONL) | After (neo4j-memory) |
|---|---|
| "Which runs patched skill X?" → grep N files | `MATCH (p:Patch)-[:APPLIED_TO]->(s:Skill {name: $x}) RETURN p` |
| "Recurring defects last 30 days" → regex scan | `MATCH (d:Defect)<-[:CAUSED_BY]-(p:Pattern) WHERE count(r) >= 2 ...` |
| Baseline trend plots | Direct Cypher + time-series |
| Defect origin tracing across runs | `(Defect)-[:INTRODUCED_IN]->(Phase)` — 1-line query |

### Entities (graph schema)

`Run`, `Agent`, `Skill`, `Phase`, `Defect`, `Pattern`, `Baseline`, `Patch`, `TPRD` — see `docs/NEO4J-KNOWLEDGE-GRAPH.md` for the full schema + canonical queries.

### Fallback guarantee

If Neo4j is unreachable, every affected agent falls back to the existing JSONL under `evolution/knowledge-base/`. The pipeline never halts on MCP failure. `scripts/migrate-jsonl-to-neo4j.py` backfills the graph on the next healthy run.

### Rollout

| Version | Integration |
|---|---|
| 0.3.0 | neo4j-memory for cross-run knowledge (this release) |
| 0.4.0 | Serena for Phase 0.5 + Phase 2; code-graph for blast-radius queries |
| 0.5.0 | context7 at Intake + Design for current library docs |

See `docs/MCP-INTEGRATION-PROPOSAL.md` for the full proposal.

---

## 11a. Performance-Confidence Regime (rules 32 + 33)

"Best performance" is uncomputable — the space of equivalent programs is infinite. What the pipeline can do is build a **falsification regime**: if a meaningful perf improvement is available, these gates surface it. Confidence = ∪ of failure modes actively falsified.

### Six falsification axes

| # | Axis | When | Agent | Gate |
|---|---|---|---|---|
| 1 | **Declaration** | D1 | Perf Architect (per-pack) | `design/perf-budget.md` exists; per-§7 symbol p50/p95/p99, allocs/op, big-O, theoretical floor, MMD, drift signals |
| 2 | **Profile shape** | M3.5 | Profile Auditor (per-pack) | G109 — top-10 CPU samples match declared hot paths (coverage ≥ 0.8) |
| 3 | **Allocation** | M3.5 | Profile Auditor (per-pack) | G104 — measured `allocs/op` ≤ declared budget |
| 4 | **Complexity** | T5 | Complexity Devil (per-pack) | G107 — scaling sweep at N ∈ {10, 100, 1k, 10k}; curve-fit ≤ declared big-O |
| 5 | **Regression + Target** | T5 | Benchmark Devil (per-pack) | G65 run-to-run regression + absolute-target check vs TPRD-declared `latency.*` (target-miss requires fix or explicit H8 budget update) |
| 6 | **Drift + MMD** | T5.5 | Soak Runner (per-pack) + `sdk-drift-detector` | G106 drift fail-fast + G105 MMD satisfied or verdict = INCOMPLETE |
| 7 | **Profile-backed exceptions** | design + impl | `sdk-overengineering-critic` | G110 — `[perf-exception: ... bench/X]` marker requires design-time entry in `perf-exceptions.md` AND profile-auditor-measured win |

### Verdict taxonomy (rule 33)

Three verdicts, not two. `INCOMPLETE` is never silently promoted to `PASS`.

- **PASS** — gate ran to completion; no violation. For soaks requires `actual_duration_s ≥ mmd_seconds`.
- **FAIL** — gate detected a violation (drift, regression, target miss, complexity mismatch, alloc over budget, surprise hotspot). BLOCKER.
- **INCOMPLETE** — gate could not render a verdict (MMD not reached, too few samples, profiler unavailable, harness crashed). Surfaced explicitly at H9. User chooses: extend window, accept risk with written waiver, or reject. Never auto-merges.

Any gate that historically returned "passed so far" on timeout now returns INCOMPLETE.

---

## 12. Numbers

### Resource limits

| Limit | Value |
|---|---:|
| Context summary per agent | ≤ 200 lines |
| Decision-log entries per agent per run | ≤ 15 |
| Review-fix retries per finding | 5 |
| Stuck detection (non-improving iters) | 2 |
| Global review-fix iterations per run | 10 |
| Intake clarifying questions | ≤ 5 |

### Phase budgets (soft, per run)

| Phase | Tokens | Wall-clock |
|---|---:|---:|
| Intake | 150 K | 20 min |
| Design | 500 K | 60 min |
| Implementation | 1 000 K | 120 min |
| Testing | 500 K | 60 min |
| Feedback | 200 K | 30 min |
| **Total** | **2.35 M** | **~4.5 hours** |

### HITL gate timeouts

| Gate | Timeout | Default action |
|---|---:|---|
| H1 TPRD acceptance | 24 h | Revise |
| H5 Design sign-off | 24 h | Revise |
| H7 Impl diff | 24 h | Revise |
| H7b Mid-impl checkpoint | 48 h | Continue |
| H9 Testing sign-off | 24 h | Revise |
| H10 Merge verdict | 72 h | Keep branch |

### Quality-score formula (per agent, per wave)

```
quality_score = completeness         × 0.20
              + review_severity      × 0.25
              + guardrail_pass_rate  × 0.15
              + rework_score         × 0.15
              + communication_health × 0.10
              + failure_recovery     × 0.10
              + downstream_impact    × 0.05
```

**Mature target**: quality_score ≥ 0.80 across all agents in a run.

### Tracked metrics

- **Per-run** (12): duration, tokens, rework, devil-block-rate, skill-coverage-pct, pipeline_quality, coverage, bench-delta, vuln-count, leak-count, flake-rate, determinism-diff
- **Per-phase** (5): duration, tokens, rework_iterations, devil-block-rate, skill-coverage-pct
- **Per-agent** (12): see formula above
- **Pipeline-maturity** (rolling 10-run window, 6 metrics): `skill_stability` (target <0.3), `existing_skill_patch_accept_rate` (≥0.8), `manifest_miss_rate` (→0), `learning_patches_reverted_by_user` (↘, trending down = notifications are well-calibrated), `mean_time_to_green_sec` (↘), `user_intervention_rate` (↘)

---

## 13. Worked Example: Dragonfly L2 Cache

**TPRD**: `<sdk-target>/<src-root>/core/l2cache/dragonfly/TPRD.md` — 470 lines, Mode B (extension to existing package, Slice 1 already shipped). Adds Slices 2–6: string ops, hash + HEXPIRE, pipeline + transactions, pubsub, scripting.

**Preflight verdict** (run today against the live pipeline):

| Check | Verdict |
|---|---|
| G20 TPRD completeness | PASS |
| G21 §Non-Goals (13 bullets) | PASS |
| G22 Clarifications | PASS (info-only) |
| G23 §Skills-Manifest (27 declared) | **WARN** — 19 in library, 8 missing (filed to `docs/PROPOSED-SKILLS.md`); **non-blocking** |
| G24 §Guardrails-Manifest (38 declared) | **PASS** — all scripts present + executable |

**Forecast** (mature pipeline run, post-preflight):

```
[00:00] H0 preflight ............................... PASS
[00:05] Phase 0 Intake ............................. PASS (WARN on 8 skills, continues)
[00:45] Phase 1 Design (~10 min) ................... 7 devils run; ~1 NEEDS-FIX expected
[09:00] Phase 2 Impl (~20 min) ..................... 5 slices, ~30 files, TDD
[27:00] Phase 3 Testing (~15 min) .................. testcontainers Dragonfly + miniredis
[39:00] Phase 4 Feedback (~6 min) .................. metrics + drift + notifications
[45:00] Exit 0 — branch sdk-pipeline/dragonfly-p0 ready
```

**Cost comparison**:

| Approach | Engineer time | Wall-clock |
|---|---:|---:|
| Hand-rolled (current) | ~3 weeks senior | ~3 weeks |
| Pipeline + review (proposed) | ~3 hours review | ~4–5 hours total |
| **Reduction** | **~98%** | **~99%** |

---

## 14. Operating Model

| Role | What they do | When |
|---|---|---|
| **Tech Lead** | Author the TPRD; review the design (H5) and final diff (H10); decide merge | Per addition |
| **Senior Engineer** | Author new skills via PR; audit skill-candidates; review guardrail-script changes | Continuous |
| **Pipeline (35 agents, autonomous)** | Run all 5 phases; produce code, tests, benches; flag violations | Per run |
| **CXO** | Approve roadmap; review quarterly pipeline-maturity report (skill_stability, mean_time_to_green, user_intervention_rate) | Quarterly |

**No new headcount required.** The pipeline operates within the existing SDK team.

---

## 15. What's Next

### Immediate (next run)
- Add 2 minimum manifest sections to the Dragonfly TPRD (already done in current branch)
- First production run: Dragonfly Slices 2–6

### Q1 (next 3 months)
- 5 more SDK additions: NATS, S3, Kafka, MinIO, RabbitMQ
- Promote 8 Dragonfly-class skill drafts (`evolution/skill-candidates/`) via human PR
- First learning-engine patch cycle (≥2 runs needed for 2-run recurrence rule)

### Q2 (months 4–6)
- Cross-run skill stability assessment (target: `skill_stability < 0.3`)
- Pipeline version 0.3.0: introduce CI integration for `/preflight-tprd` on TPRD PRs
- Optional: extend pipeline to non-SDK repos (probably out of scope)

### Open questions
- Should `learning-engine` be allowed to propose **renames** of existing skills? (Currently no — only body patches.)
- Should we expose pipeline metrics to a Grafana dashboard? (Trivially possible; deferred until 5+ runs of data.)
- Should `/preflight-tprd` be a PR-required CI check on TPRD changes?

---

## 16. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Pipeline produces wrong code | Low | Medium | 7 HITL gates; final diff reviewed before merge |
| Devil agents over-reject | Medium | Low | Stuck-detection at 2 iterations; human can override at gate |
| Skill drift over time | Medium | Medium | drift-detector + coverage-reporter run every Phase 4; user reviews `learning-notifications.md` at H10 and may revert bad patches |
| Pipeline breaks existing code (Mode B/C) | Low | High | Marker protocol (G95-G103); MANUAL symbols byte-hash-checked; cannot modify |
| Bench regression on shared paths | Medium | High | G65 BLOCKER at 10% on shared, 5% on hot; explicit override required |
| Pipeline runs forever / consumes runaway tokens | Low | Medium | Per-phase soft + hard token caps; user confirms past hard cap |
| Determinism breaks | Medium | Low | Same TPRD + seed produces byte-equivalent; variance is a learning signal, not a failure |
| Auto-applied skill patch breaks future runs | Low | High | Append-only evolution-log makes every patch revertible; per-patch notification line at H10; baseline-manager flags quality regressions next run |
| Human authors a bad skill | Medium | Medium | Human PR review; first-use devil fleet catches regressions on the live run |
| `learning-engine` over-patches | Low | Medium | ≤3 skill-body patches per run; high-confidence + 2-run recurrence required |

---

## 17. Glossary

| Term | Meaning |
|---|---|
| **TPRD** | Technical PRD — the single contract authored by humans |
| **§Skills-Manifest** | TPRD section listing required skills + min versions |
| **§Guardrails-Manifest** | TPRD section listing required guardrail scripts |
| **Mode A** | Greenfield new package |
| **Mode B** | Extension to existing package |
| **Mode C** | Incremental update to existing package |
| **HITL gate** | Human-in-the-Loop approval point between phases |
| **Devil agent** | Read-only adversarial reviewer (security, semver, dep-vet, etc.) |
| **Marker protocol** | Code annotations (`[traces-to:]`, `[owned-by:]`, `[constraint:]`, `[perf-exception:]`) that drive provenance + safety checks |
| **Compensating baselines** | Four cross-run baselines that replaced golden-corpus (rule 28): output-shape hash, devil-verdict stability, tightened quality threshold, example-count |
| **Deterministic-first gate** | Rule 13: reviewer fleet only re-runs on iterations where build, vet, fmt, static-check, race-detection (if supported), leak-detection, vulnerability-scan, lockfile-scan, marker-hash, constraint-bench, license are green |
| **Absolute target latency** | TPRD-declared `latency.*` in `perf-budget.md` — Benchmark Devil enforces measured p50/p95/p99 ≤ declared, surfaces target-miss at H8 |
| **MMD** | Minimum-measurable-duration for soak verdicts (G105) |
| **Verdict taxonomy** | PASS / FAIL / INCOMPLETE (rule 33) — timeouts yield INCOMPLETE, never silently promoted |
| **Skill-candidate** | Draft skill awaiting human PR review (cannot be auto-promoted) |

---

## 18. Reference Documents

- `LIFECYCLE.md` — operator's manual (this is its complement)
- `improvements.md` — what we built on top of the reference fleet
- `CLAUDE.md` — agent fleet rules (33 rules)
- `AGENTS.md` — full agent ownership matrix
- `docs/MCP-INTEGRATION-PROPOSAL.md` — scope + rollout of neo4j-memory, Serena, code-graph, context7
- `docs/NEO4J-KNOWLEDGE-GRAPH.md` — graph schema + canonical Cypher
- `docs/DEPRECATED.md` — retirement registry (concepts + commit + replacement)
- `evolution/evolution-reports/pipeline-v0.3.0.md` — current release notes
- `phases/*-PHASE.md` — per-phase contracts
- `commands/run-sdk-addition.md` — slash command spec
- `commands/preflight-tprd.md` — risk-free TPRD validation spec
- `send.md` — example NATS-client TPRD (full 14-section format)

---

## TL;DR for the CXO

> **8 backend SDK clients on the roadmap. Hand-rolled cost: 6 engineer-months. Pipeline cost: 3 engineer-days of review + already-built infrastructure. Quality is uniform, auditable, and improves automatically within bounded human-controlled rules. Risk is low: the pipeline cannot touch main, cannot modify human-marked code, and cannot create its own skills or guardrails. We are ready to run the first production TPRD (Dragonfly L2 cache) today.**
