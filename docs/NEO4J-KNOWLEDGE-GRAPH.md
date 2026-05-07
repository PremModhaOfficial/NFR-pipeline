# Neo4j Knowledge Graph — Schema Reference

**Target pipeline version**: 0.3.0
**Backing store**: neo4j-memory MCP (`mcp__neo4j-memory__*`), local Neo4j at `bolt://localhost:7687`
**Source of truth**: JSONL under `evolution/knowledge-base/` (graph is derived)
**Owner**: `learning-engine` (primary writer), `baseline-manager` (baseline writer), `metrics-collector` (observation writer)

This document freezes the schema. Changes require a bump of `docs/MCP-INTEGRATION-PROPOSAL.md §3.1` and PR review.

---

## 1. Entities (typed nodes)

Every entity has a stable `name` (unique identifier within its type). Scalar properties below are the minimum required — additional context goes into `Observations` attached to the entity.

### 1.1 `Run`

A single pipeline execution against one TPRD.

| Property | Type | Notes |
|---|---|---|
| `run_id` | string (UUID v4) | Primary key. Prefix `sdk-<pkg>-<slug>` by convention (e.g. `sdk-dragonfly-s2`). |
| `pipeline_version` | string | Semver, matches `settings.json`. |
| `started_at` | ISO-8601 | |
| `completed_at` | ISO-8601 or null | Null while in-flight. |
| `status` | string | `completed` \| `failed` \| `in-progress` \| `degraded` |
| `mode` | string | `A` \| `B` \| `C` |
| `target_package` | string | e.g. `config/dragonfly`. |

Entity name convention: `Run:<run_id>`.

### 1.2 `Agent`

A pipeline agent as defined in `AGENTS.md`. Singleton across runs.

| Property | Type | Notes |
|---|---|---|
| `name` | string | e.g. `sdk-intake-agent`. Matches `agents/<name>.md`. |
| `role` | string | `lead` \| `designer` \| `implementor` \| `tester` \| `devil` \| `reviewer` \| `learning` \| `observer` |
| `phase` | string | Primary phase, or `cross-phase` for multi-phase agents. |

Entity name convention: `Agent:<name>`.

### 1.3 `Skill`

A skill file under `skills/<name>/SKILL.md`. Singleton across runs; version is a property, history lives in Observations + `evolution-log.md`.

| Property | Type | Notes |
|---|---|---|
| `name` | string | e.g. `go-error-handling-patterns`. |
| `version` | string | Current semver. |
| `status` | string | `stable` \| `draft` \| `deprecated` |

Entity name convention: `Skill:<name>`.

### 1.4 `Phase`

Pipeline phase (static set of 6). Singletons.

| Property | Type | Notes |
|---|---|---|
| `id` | string | `0` \| `0.5` \| `1` \| `2` \| `3` \| `4` |
| `name` | string | `Intake` \| `Analyze` \| `Design` \| `Impl` \| `Testing` \| `Feedback` |

Entity name convention: `Phase:<id>`.

### 1.5 `Defect`

A concrete defect observed in a run — test failure, bench regression, semver break, guardrail FAIL. Scoped to a single first-sighting run; recurrence tracked via additional `(Defect)-[:OBSERVED_IN]->(Run)` relations.

| Property | Type | Notes |
|---|---|---|
| `defect_id` | string | `DEF-<run_id>-<NN>` or semantically meaningful if recurring. |
| `severity` | string | `BLOCKER` \| `HIGH` \| `MED` \| `LOW` |
| `type` | string | `test-fail` \| `bench-regression` \| `semver-break` \| `coverage-drop` \| `marker-hygiene` \| `other` |
| `first_seen_run` | string | `run_id` of first observation. |

Entity name convention: `Defect:<defect_id>`.

### 1.6 `Pattern`

A cross-run generalization. Recognized by `pattern-detector` within a run, promoted to `Pattern` entity by `learning-engine` when recurrence ≥2.

| Property | Type | Notes |
|---|---|---|
| `pattern_id` | string | `PAT-<slug>`. |
| `pattern_type` | string | `defect` \| `communication` \| `failure` \| `refactor` \| `story-gap` |
| `description` | string | One-line human summary. |
| `severity` | string | `BLOCKER` \| `HIGH` \| `MED` \| `LOW` |

Entity name convention: `Pattern:<pattern_id>`.

### 1.7 `Baseline`

A persistent numeric baseline. One entity per dimension.

| Property | Type | Notes |
|---|---|---|
| `dimension` | string | `quality` \| `coverage` \| `performance` \| `skill-health` |
| `value` | number or JSON | Scalar for quality/coverage/skill-health; JSON object for `performance` (multi-metric). |
| `runs_tracked` | integer | Count of runs contributing. |
| `last_updated` | ISO-8601 | |

Entity name convention: `Baseline:<dimension>`.

### 1.8 `Patch`

A `learning-engine`-applied change to an agent prompt or skill body. Append-only.

| Property | Type | Notes |
|---|---|---|
| `patch_id` | string | `PP-<NN>-<scope>` for prompt patches; `SP-<NN>-<slug>` for skill patches. |
| `target_agent_or_skill` | string | e.g. `sdk-design-lead` or `go-error-handling-patterns`. |
| `confidence` | string | `high` \| `medium` \| `low` |
| `applied_at` | ISO-8601 | |

Entity name convention: `Patch:<patch_id>`.

### 1.9 `TPRD`

The canonicalized TPRD that drove a run.

| Property | Type | Notes |
|---|---|---|
| `tprd_id` | string | Typically matches `run_id` 1:1 in R1. |
| `target_package` | string | e.g. `config/dragonfly`. |
| `mode` | string | `A` \| `B` \| `C` |
| `created_at` | ISO-8601 | |

Entity name convention: `TPRD:<tprd_id>`.

---

## 2. Relations (typed edges)

Edges are directed. Properties in `{}` are required; edges without a property block carry no properties.

| Edge | From | To | Properties | Written by |
|---|---|---|---|---|
| `RAN_IN_PHASE` | `Run` | `Phase` |  | `metrics-collector` |
| `OBSERVED_IN` | `Agent` | `Run` | `{quality_score, retries, duration_sec}` | `metrics-collector` |
| `INTRODUCED_IN` | `Defect` | `Phase` |  | `root-cause-tracer` |
| `DETECTED_IN` | `Defect` | `Phase` |  | `root-cause-tracer` |
| `CAUSED_BY` | `Defect` | `Pattern` |  | `root-cause-tracer` |
| `OBSERVED_IN` | `Pattern` | `Run` |  | `pattern-detector` (via `learning-engine`) |
| `AFFECTS` | `Pattern` | `Skill` or `Agent` |  | `pattern-detector` (via `learning-engine`) |
| `APPLIED_TO` | `Patch` | `Agent` or `Skill` |  | `learning-engine` |
| `MOTIVATED_BY` | `Patch` | `Pattern` |  | `learning-engine` |
| `REGRESSED_AGAINST` | `Patch` | `Baseline` |  | `learning-engine` (only if regression detected) |
| `UPDATED_IN` | `Baseline` | `Run` |  | `baseline-manager` |
| `INVOKED_IN` | `Skill` | `Run` | `{count}` | `metrics-collector` |
| `EXTENDS` | `Run` | `Run` |  | `metrics-collector` (Mode C only) |
| `DRIVEN_BY` | `Run` | `TPRD` |  | `metrics-collector` |

### 2.1 Cardinality notes

- `Agent -[:OBSERVED_IN]-> Run` has one edge per (agent, run) pair; retries/duration are summarized properties, not separate edges.
- `Pattern -[:OBSERVED_IN]-> Run` has one edge per observation. Recurrence = `COUNT(*) >= 2`.
- `Patch -[:REGRESSED_AGAINST]-> Baseline` is only written when a regression is detected; absence means "patch did not regress against any tracked baseline".

### 2.2 Why edges over properties

Everything time-varying or relational is an edge, not a property. This keeps entities stable (low cardinality of property churn) and queries simple (`MATCH (a:Agent)-[:OBSERVED_IN]->(r:Run)` beats reading every `Run` and scanning an embedded list).

---

## 3. Observations

`Observations` are free-form strings attached to an entity. They carry facts that don't earn a schema slot:

- `Agent`: "worked around G32 tool-unavail during sdk-dragonfly-s2"
- `Skill`: "patch-level bump v1.0.0→v1.0.1 — added trigger-keywords frontmatter (2026-04-18)"
- `Pattern`: "first observed in sdk-dragonfly-s2; second observation pending"
- `Run`: "H8 waiver accepted for `allocs_per_GET` constraint"
- `Baseline`: "includes 7 dragonfly-family runs; excludes s-series dev runs"

### 3.1 Usage rules

- Observations are append-only from the pipeline's perspective.
- `learning-engine` removes observations only via explicit `delete_observations` call, which requires a human-authored PR in the `evolution/evolution-reports/` to justify the deletion.
- Keep observations ≤200 chars; longer context goes into the corresponding `runs/<run-id>/` artifact and is referenced by `run_id`.

---

## 4. Canonical Cypher queries

The four queries below are the MVP query surface. Agents invoke these by name through helper functions; raw Cypher authorship is not expected of non-`learning-engine` agents.

### 4.1 Which agents patched skill X across runs?

```cypher
MATCH (p:Patch)-[:APPLIED_TO]->(s:Skill {name: $skill_name})
MATCH (p)-[:MOTIVATED_BY]->(pat:Pattern)
MATCH (pat)-[:OBSERVED_IN]->(r:Run)
RETURN p.patch_id          AS patch,
       p.applied_at        AS applied_at,
       p.confidence        AS confidence,
       pat.pattern_id      AS motivating_pattern,
       r.run_id            AS source_run
ORDER BY p.applied_at DESC;
```

Use: audit skill evolution, answer "who has been touching `go-error-handling-patterns` and why?"

### 4.2 Recurring patterns (≥2 runs, last 30 days) eligible for auto-patch

```cypher
MATCH (pat:Pattern)-[:OBSERVED_IN]->(r:Run)
WHERE r.completed_at >= datetime() - duration({days: 30})
WITH pat, count(DISTINCT r) AS recurrence, collect(DISTINCT r.run_id) AS runs
WHERE recurrence >= 2
OPTIONAL MATCH (pat)-[:AFFECTS]->(target)
RETURN pat.pattern_id     AS pattern,
       pat.pattern_type   AS type,
       pat.severity       AS severity,
       recurrence,
       runs,
       collect(DISTINCT target.name) AS affects
ORDER BY recurrence DESC, pat.severity;
```

Use: `improvement-planner` drives its auto-patch eligibility list off this query.

### 4.3 Defect trace: every defect traced to Phase 1 Design in the last 10 runs

```cypher
MATCH (r:Run)-[:RAN_IN_PHASE]->(:Phase {id: '1'})
WITH r ORDER BY r.completed_at DESC LIMIT 10
MATCH (d:Defect)-[:INTRODUCED_IN]->(:Phase {id: '1'})
MATCH (d)-[:DETECTED_IN]->(detected:Phase)
OPTIONAL MATCH (d)-[:CAUSED_BY]->(pat:Pattern)
RETURN d.defect_id      AS defect,
       d.severity       AS severity,
       d.type           AS type,
       detected.name    AS detected_in_phase,
       pat.pattern_id   AS pattern,
       d.first_seen_run AS first_seen
ORDER BY d.severity, d.first_seen_run DESC;
```

Use: `root-cause-tracer` answers "are we consistently shipping design-phase defects into impl?"

### 4.4 Baseline trend per dimension over last N runs

```cypher
MATCH (b:Baseline {dimension: $dimension})-[:UPDATED_IN]->(r:Run)
WHERE r.completed_at IS NOT NULL
RETURN r.run_id          AS run,
       r.completed_at    AS at,
       b.value           AS value,
       b.runs_tracked    AS runs_tracked
ORDER BY r.completed_at DESC
LIMIT $n;
```

Use: `baseline-manager` quotes the tail of the trend in `runs/<run-id>/feedback/baseline-summary.md`.

---

## 5. Write protocol (for `learning-engine`)

1. At start of feedback phase: `search_memories` for existing `Run` with this `run_id`. If present, bail (idempotency).
2. `create_entities` for the `Run`, then for each `Agent` observed, each `Pattern` detected, each `Patch` applied.
3. `create_relations` for all edges, batched.
4. `add_observations` for free-form context.
5. Log each MCP call in `decision-log.jsonl` with `type: "skill-evolution"`, `tags: ["neo4j-write"]`.
6. On any MCP error: catch, log `tags: ["neo4j-unreachable","jsonl-fallback"]`, continue with JSONL-only write.

---

## 6. Read protocol (for reader agents)

1. Check G04 status in `runs/<run-id>/intake/mcp-health.md` (or `feedback/mcp-health.md`). If WARN, skip graph queries and fall back to JSONL grep.
2. Use the named query helpers (§4) rather than authoring Cypher inline.
3. Cache query results within a wave; do not re-query the same dimension twice per wave.

---

## 7. Schema versioning

Schema version is implicit in `pipeline_version`. Any change to entity shape, required property set, or edge type requires:

1. Bump `pipeline_version` minor.
2. Update this document.
3. Update `scripts/migrate-jsonl-to-neo4j.py` migration header.
4. Record the change in `evolution/evolution-reports/schema-<version>.md`.

---

## 8. Glossary

- **Derived index**: the graph is *not* the source of truth — JSONL is. The graph can be wiped and rebuilt from JSONL without data loss.
- **Singleton entity**: `Agent`, `Skill`, `Phase`, `Baseline` — one node per identity across all runs. Edges connect the singleton to per-run entities.
- **Recurrence**: `COUNT(DISTINCT Run)` via `(Pattern)-[:OBSERVED_IN]->(Run)`. Recurrence ≥2 triggers auto-patch eligibility.
- **Dual-write**: R1 protocol — every event written to both JSONL (authoritative) and graph (derived). Flip to graph-authoritative is deferred to v0.4.0+.
