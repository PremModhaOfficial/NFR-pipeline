<!-- cross_language_ok: true — pipeline design/decision doc references per-pack tooling. Multi-tenant SaaS platform context preserved per F-008. -->

# MCP Integration Proposal — motadata-sdk-pipeline

**Status**: DRAFT (for tech-lead review)
**Target pipeline version**: 0.3.0 (neo4j-memory only), 0.4.0 (Serena + code-graph), 0.5.0 (context7 at intake)
**Owner**: platform / pipeline-core
**Branch**: `mcp-enhanced-graph`
**Date**: 2026-04-20

---

## 1. Summary

The pipeline today accumulates cross-run learning in flat JSONL files under `evolution/knowledge-base/`. Pattern detection is grep + Python-dict aggregation. This works for single-run retrospectives and has zero operational cost, but it does not scale to the questions the pipeline will need to answer once it has been running for weeks:

- "Which agents regressed against baselines in the last 10 runs?"
- "Recurring defect patterns (≥2 runs, last 30 days) eligible for auto-patch?"
- "Every defect traced to Phase 1 Design in the last quarter?"
- "Which `Patch` on which `Skill` was motivated by `Pattern` X, and did it regress against any `Baseline`?"

Answering these at grep-speed is fine at run count ~10; by run count ~100 it becomes a hot spot. More importantly, the *relational* questions (patch → pattern → baseline) are not expressible as grep — they require manual stitching across files. Moving cross-run knowledge into **neo4j-memory** (already available locally as an MCP server) gives the pipeline a queryable, relational substrate without adding a net-new infra dependency. JSONL stays the source of truth and fallback; neo4j-memory is a **derived index**.

This document proposes a three-phase rollout (v0.3.0 / v0.4.0 / v0.5.0) with explicit fallback guarantees at each step. R1 (v0.3.0) is the focus of this proposal; R2/R3 are scoped here only to establish coherence.

---

## 2. Current state

| Area | Today | Pain |
|---|---|---|
| Agent performance | `evolution/knowledge-base/agent-performance.jsonl` append-only | Per-agent trend requires reading full file, grouping in Python |
| Prompt evolution | `evolution/knowledge-base/prompt-evolution-log.jsonl` append-only | No relational link patch ↔ pattern ↔ originating defect |
| Defect patterns | Detected post-hoc by `pattern-detector` grep over run dirs | Single-run scope; cross-run recurrence detected only by name collision |
| Baselines | `baselines/*.json` static snapshots | Trend over N runs requires manual diff |
| Code context | Direct file `Read` per agent turn | No symbol/call-graph awareness; agents re-parse on every turn |
| Docs lookup | Training-cutoff memory (+ occasional WebSearch) | Stale on fast-moving deps (OTel, Go stdlib, testcontainers-go) |
| Root-cause trace | Manual hop across `decision-log.jsonl` files | No edge from defect to originating phase |
| Auto-patch eligibility | Python grouper in `improvement-planner` | Cannot express "same pattern observed in ≥2 runs" declaratively |

**What works**:

- JSONL is append-only, survives crashes, diffs well in PR review, runs anywhere.
- Zero external dependency — guardrails can ship without Neo4j.
- Cheap to mirror (git diff readable).

**What hurts**:

- Joins across files are manual.
- No first-class "this patch addressed that pattern" edge.
- Trend-over-time queries scale linearly in file size.
- `root-cause-tracer` re-reads every phase's artifacts per run — cross-run patterns invisible.

---

## 3. Target state

### 3.1 neo4j-memory (v0.3.0 — this proposal's core)

A typed knowledge graph holding:

- `Run`, `Phase`, `Agent`, `Skill`, `Defect`, `Pattern`, `Baseline`, `Patch`, `TPRD` entities.
- Explicit relations: `(Defect)-[:INTRODUCED_IN]->(Phase)`, `(Patch)-[:MOTIVATED_BY]->(Pattern)`, `(Pattern)-[:OBSERVED_IN]->(Run)`, etc.
- Free-form `Observations` per entity for context that doesn't earn a schema slot.

Schema is pinned in `docs/NEO4J-KNOWLEDGE-GRAPH.md`. All writes are owned by `learning-engine` (feedback phase) and `metrics-collector` (feedback phase). Reads are open to `pattern-detector`, `root-cause-tracer`, `improvement-planner`, `drift-detector`, `baseline-manager`.

### 3.2 Serena + tree-sitter code-graph (v0.4.0 — later)

Out-of-scope for this proposal but mentioned for coherence:

- `sdk-marker-scanner` gets a tree-sitter-backed symbol index per run.
- `sdk-merge-planner` uses Serena's LSP layer for rename-safe 3-way merges in Mode C.
- `sdk-testing-lead` uses `find_usage` to locate call sites when crafting integration tests.

### 3.3 context7 at intake (v0.5.0 — later)

Out-of-scope here but queued:

- `sdk-intake-agent` queries context7 for current docs of any dep listed in TPRD §6 before closing H1.
- Replaces the current "we hope the agent remembers which version introduced feature X" risk.
- Counterpart benefit: `sdk-dep-vet-devil-go` gets source-of-truth changelog for MVS disputes.

---

## 4. Phased rollout

### Phase R1 — v0.3.0 — neo4j-memory adoption (this proposal)

| Wave | What | Owner | Files touched |
|---|---|---|---|
| R1.1 | Schema doc authored | this proposal | `docs/NEO4J-KNOWLEDGE-GRAPH.md` |
| R1.2 | Migration script + seed file | this proposal | `scripts/migrate-jsonl-to-neo4j.py`, `evolution/knowledge-base/neo4j-seed.json` |
| R1.3 | Health-check guardrail | this proposal | `scripts/guardrails/G04.sh` |
| R1.4 | Agent prompt deltas (MCP-aware sections) | Workstream B | 5 feedback-track agent prompts |
| R1.5 | `settings.json` MCP feature flags | Workstream C | `settings.json` |
| R1.6 | Evolution-report on first post-migration run | `learning-engine` | `evolution/evolution-reports/mcp-v0.3.0.md` |
| R1.7 | Reconciliation probe (graph vs JSONL parity) | Workstream D | `scripts/reconcile-graph-vs-jsonl.py` (follow-up) |

**Entry criterion**: neo4j-memory MCP reachable in dev + CI. Healthcheck in G04.
**Exit criterion**: First full pipeline run writes ≥1 Run entity, ≥4 Agent entities (one per phase lead), ≥1 Pattern edge without falling back to JSONL. JSONL writes still happen in parallel for this release.
**Non-goals for R1**: authoritative-flip, retention policy, graph-backed UI, ML over the graph.

### Phase R2 — v0.4.0 — Serena + code-graph

Deferred. Requires Serena MCP to be stable at project scope. Tracked separately.

### Phase R3 — v0.5.0 — context7 at intake

Deferred. Low risk, high value once R1 telemetry proves the MCP integration layer is reliable.

---

## 5. Cost / benefit

### Cost

| Item | Estimate |
|---|---|
| Schema doc | ~1 engineer-day |
| Migration script | ~0.5 engineer-day |
| Guardrail G04 | ~0.25 engineer-day |
| Agent prompt MCP-aware sections (5 agents × ~40 lines each) | ~1 engineer-day (Workstream B) |
| `settings.json` feature flags | ~0.25 engineer-day (Workstream C) |
| First-run debug + evolution report | ~1 engineer-day |
| **Total R1** | **~4 engineer-days** |

No new infra. Neo4j already runs locally (`claude-neo4j` container). CI can use `neo4j:5` ephemeral container or skip entirely (fallback path is always legal).

### Benefit

- **Queryable cross-run history** — replaces ad-hoc Python aggregation with 4-line Cypher queries (see `NEO4J-KNOWLEDGE-GRAPH.md §4`).
- **Auditability** — every `Patch` has a typed edge to the `Pattern` that motivated it and the `Baseline` it regressed against, if any. Today, this is reconstructed by hand from `prompt-evolution-log.jsonl` free-text `source_evidence`.
- **Auto-patch eligibility** — 2-run recurrence detection for patterns becomes a single `MATCH` query instead of a Python grouper over JSONL.
- **Foundation for R2/R3** — once neo4j-memory is in the agents' toolbelt, code-graph and context7 become incremental.
- **Observability parity with file-memory** — the CLAUDE global policy prefers neo4j-memory when relationships matter; this proposal aligns the pipeline with that preference without disturbing file-memory's role for short preferences.

### Effort-to-value

R1 is the smallest step that unlocks cross-run querying. No agent is forced to read Cypher; `learning-engine` is the only writer, and query helpers ship as named functions in feedback-track agents' prompts. All Cypher lives in one document (`NEO4J-KNOWLEDGE-GRAPH.md`) which makes the blast radius of a schema change explicit.

---

## 6. Migration plan

### 6.1 Steps

1. **Seed from existing JSONL** (one-shot).
   `scripts/migrate-jsonl-to-neo4j.py` reads `agent-performance.jsonl` + `prompt-evolution-log.jsonl` and emits `evolution/knowledge-base/neo4j-seed.json` — a list of entity + relation specs in the exact shape `mcp__neo4j-memory__create_entities` and `create_relations` expect. Idempotent via sidecar `.migrated-offsets.json`.

2. **First-run batch import** (first pipeline run on v0.3.0).
   `learning-engine` reads `neo4j-seed.json`, batches `create_entities` + `create_relations` calls (recommended batch size 50), records a `skill-evolution` log entry with the batch size + timing.

3. **Ongoing writes** (every subsequent run).
   `learning-engine` continues to append to JSONL **and** mirror the same events as entities/relations in neo4j-memory. Dual-write for one release cycle (v0.3.x). JSONL stays authoritative.

4. **Read adoption** (v0.3.x minor releases).
   `pattern-detector`, `root-cause-tracer`, `improvement-planner` add optional neo4j-memory queries gated on G04 passing. If G04 WARNed, they fall back to JSONL grep.

5. **Authoritativeness flip** (v0.4.0 or later).
   Deferred until dual-write has been stable for 10+ runs and a reconciliation harness confirms parity. No flip in this proposal's scope.

### 6.2 Dual-write protocol

Each event that mutates cross-run state goes through a small helper, conceptually:

```
def record_event(event):
    append_jsonl(event)                 # authoritative
    if mcp_neo4j_memory_available():
        try:
            mirror_to_graph(event)      # derived
        except Exception as e:
            log_decision(type="skill-evolution",
                         tags=["neo4j-unreachable","jsonl-fallback"],
                         details=str(e))
```

The pipeline never blocks on graph writes. Reconciliation (§6.3) catches drift.

### 6.3 Reconciliation

Once per release cycle (manual trigger in R1, automated in R2), `scripts/reconcile-graph-vs-jsonl.py` (authored in R1.7, not in this proposal's 4-file scope) walks the last N runs in JSONL and verifies every `run_id` is represented in the graph with the expected agent + patch edges. Discrepancies file into `docs/PROPOSED-GUARDRAILS.md` for human triage — not auto-corrected.

### 6.4 Fallback guarantee

> **Neo4j unreachable → pipeline still runs.** Every neo4j-memory call is wrapped by a try-or-fallback shim. On failure, the agent logs a `skill-evolution` decision-log entry with `tags: ["neo4j-unreachable", "jsonl-fallback"]` and proceeds against JSONL. G04 emits WARN (never BLOCKER).

This mirrors the pipeline's existing posture on external deps (e.g., `govulncheck` tool-unavail → downgrade to WARN, not halt).

---

## 7. Risk table

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Neo4j container down in dev | MED | LOW | G04 WARN + JSONL fallback; documented in CLAUDE.md startup |
| neo4j-memory MCP schema drift | LOW | MED | Pin to observed schema in `NEO4J-KNOWLEDGE-GRAPH.md`; migration script version header |
| Seed file malformed on first import | LOW | MED | Migration script exits 0 always; `learning-engine` validates shape before calling `create_entities` |
| Graph drift from JSONL | MED | MED | Dual-write for one full release cycle; periodic reconciliation job (R1.7) |
| Cypher queries become load-bearing before schema is stable | MED | HIGH | Freeze schema in doc; all 4 canonical queries shipped as named functions agents invoke by name, not raw Cypher |
| Over-indexing cross-run knowledge | LOW | LOW | 30-day retention policy (future); node count monitored in feedback phase |
| MCP rate-limit or batch-size regression | LOW | MED | Explicit batch size 50 in migration script; backoff on error; test coverage in R1.7 |
| Node-id collision across runs | LOW | LOW | Entity names prefixed by `run_id` where scope matters (Patch, Defect); globals (Agent, Skill, Baseline) remain singletons |
| Graph wipe mistaken for data loss | LOW | LOW | Graph is derived; wiping is zero-loss by design; rollback §8 documents the command |

---

## 8. Rollback procedure

R1 is additive. Rollback = stop writing to neo4j-memory; JSONL remains authoritative.

Steps if a rollback is needed mid-release:

1. Set `settings.json` `mcp.neo4j_memory.enabled: false` (flag added by Workstream C).
2. Re-run any affected feedback phase — `learning-engine` will write JSONL only.
3. (Optional) Wipe the graph: `docker exec claude-neo4j cypher-shell -u neo4j -p neo4jneo4j "MATCH (n) DETACH DELETE n"`. Not required for correctness; the graph is derived data.
4. File an evolution report documenting what failed so R1.x can address it before re-enabling.
5. If rollback is taken, Workstream B agent prompts remain backward-compatible: they already gate MCP calls on G04 passing.

No data loss is possible because JSONL is the source of truth throughout R1.

---

## 9. Affected agents

Five feedback-track agents receive MCP-aware sections in their prompts (Workstream B's scope; listed here for traceability):

| Agent | MCP role | Reads | Writes |
|---|---|---|---|
| `metrics-collector` | reader + writer | `search_memories`, `read_graph` (for trends) | `create_entities` (Run + Agent observations) |
| `pattern-detector` | reader | `search_memories` (find patterns across runs) | none |
| `root-cause-tracer` | reader | `search_memories`, `find_memories_by_name` | none |
| `improvement-planner` | reader | `search_memories` (patches + their Pattern edges) | none |
| `learning-engine` | writer (primary) | `search_memories` (check existing patterns) | `create_entities`, `create_relations`, `add_observations` |
| `baseline-manager` | writer | `search_memories` (prior baseline entities) | `create_entities` (`Baseline`), `create_relations` (`UPDATED_IN`) |

Non-feedback-track agents are unaffected in v0.3.0. The single writer (`learning-engine`) and single-baseline-writer (`baseline-manager`) rule preserves the pipeline's existing Output Ownership discipline (CLAUDE.md §3).

---

## 10. Observability

Every MCP call is logged in `runs/<run-id>/decision-log.jsonl` with:

- `type: "skill-evolution"` or `type: "event"`
- `tags`: one of `["neo4j-write"]`, `["neo4j-read"]`, `["neo4j-unreachable","jsonl-fallback"]`
- `details.batch_size` and `details.duration_ms` where applicable

`metrics-collector` adds a new section to its report (`runs/<run-id>/feedback/metrics.md`):

```
### MCP health
- neo4j-memory reachable: yes/no
- entities created this run: N
- relations created this run: M
- fallback events: K
```

This surfaces drift between the pipeline's intended and actual graph-write rate without requiring a separate dashboard.

---

## 11. Security

- Neo4j bound to `localhost:7687` only. No network exposure.
- Credentials (`neo4j` / `neo4jneo4j`) are local dev defaults. Production (if ever) would use secrets manager — out of scope for R1.
- No PII in the graph: entities are synthetic IDs + scalar metrics. TPRD content is not mirrored into observations beyond `target_package` + `mode`.
- Guardrail G69 (credential-hygiene) unaffected; no credentials leak into graph or JSONL.

---

## 12. Open questions

1. Do we want a separate `RunStatus` entity or put status on the `Run` node as a property? **Proposal: property.** Fewer joins, no querying across statuses planned.
2. 30-day retention for `Pattern` entities? **Proposal: no retention in v0.3.0.** Start permissive; revisit at v0.4.0 once graph size is known.
3. Should `TPRD` entities cross-reference the actual file path? **Proposal: yes, as observation.** Lets agents jump from graph to file without a second lookup.
4. Mode C (incremental update) runs — do they get their own Run entity or attach to the prior run's? **Proposal: own Run entity, with `(ThisRun)-[:EXTENDS]->(PriorRun)` relation.** Preserves per-run audit while keeping the chain queryable.
5. Do we want typed `Failure` entities or fold failures into observations on the affected `Agent`? **Proposal: observations for R1.** Promote to entity in R2 if failure-clustering queries emerge.
6. Should `metrics-collector` or `learning-engine` own `Baseline` writes? **Proposal: `baseline-manager` (as per Ownership Matrix).** Avoids dual-writer conflicts on the one entity that materially affects auto-patch decisions.

---

## 13. Acceptance checklist (for merge into `mcp-enhanced-graph` branch)

- [ ] `docs/MCP-INTEGRATION-PROPOSAL.md` reviewed by tech-lead
- [ ] `docs/NEO4J-KNOWLEDGE-GRAPH.md` schema frozen
- [ ] `scripts/migrate-jsonl-to-neo4j.py` runs cleanly on current `evolution/knowledge-base/`
- [ ] `scripts/guardrails/G04.sh` passes in both Neo4j-up and Neo4j-down scenarios
- [ ] Workstream B delivers 5 agent prompt updates
- [ ] Workstream C delivers `settings.json` flags
- [ ] First post-merge run produces a non-empty graph without BLOCKER
- [ ] Rollback procedure validated once in dev
- [ ] Evolution report `mcp-v0.3.0.md` published

---

## 14. Appendix A — Why not SQLite?

Considered and rejected for R1:

| Criterion | SQLite | neo4j-memory |
|---|---|---|
| Relational joins | yes (SQL) | yes (Cypher) |
| Typed edges as first-class | no (FK + join table) | yes |
| MCP integration available | no (would need bespoke) | yes (global MCP) |
| Cost to adopt | medium (schema + FK + migrations) | low (MCP server runs) |
| Readable in PR review | yes (SQL dump diffs) | no (requires tooling) |
| Alignment with global MCP policy | weak | strong (CLAUDE.md §MCP) |

Decision: the pipeline's questions are inherently graph-shaped (patch ↔ pattern ↔ defect ↔ phase ↔ run). SQLite would require join tables that replicate graph edges without typing them. The global MCP policy already prefers neo4j-memory for relational data. For R1, adopt neo4j-memory; revisit if graph scale outgrows local Neo4j.

---

## 15. Appendix B — Non-goals

Explicitly out of R1 scope, tracked for later:

- Graph-backed visual dashboard (Neo4j Browser is the MVP visualizer).
- ML / embedding-based pattern similarity.
- Multi-user concurrent writes (pipeline is single-writer per run).
- Graph-backed skill recommendation at intake time.
- Authoritative flip (JSONL → graph as SoT).
- Retention / TTL policy.
- Graph-level access control beyond local-loopback binding.

These are legitimate future work but will each warrant their own proposal. R1 deliberately ships the smallest coherent slice.
