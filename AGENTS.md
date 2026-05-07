<!-- cross_language_ok: true — top-level pipeline doc references per-pack tooling and the multi-tenant SaaS platform context (per F-008 in migration-findings.md). Authoritative project description: SDK is built FOR multi-tenant SaaS consumers; multi-tenant guardrails (TenantID, JetStream, MsgPack, schema-per-tenant) are in-scope. -->

# Agent Roster

This file is the single source of truth for every agent in this pipeline. Canonical per-agent prompt files live in `agents/<name>.md`.

**Multi-language note**: rows tagged `Go` or `Python` belong to a per-language pack and are dispatched only when `runs/<run-id>/context/active-packages.json:target_language` matches. Rows tagged `Shared` are language-neutral orchestrators that run on every pipeline regardless of language.

## Ownership Matrix

| Domain | Lang | Owner agent | Consulted | MCPs used |
|---|---|---|---|---|
| TPRD canonicalization + manifest validation | Shared | `sdk-intake-agent` | — | `context7` |
| New skill authorship | Shared | **human only** (PR merge per CLAUDE.md rule 23) | — | — |
| Existing skill body patches | Shared | `learning-engine` (Phase 4; scope-validated per Patch Scope Validation Gate) | `baseline-manager`, `improvement-planner` | `neo4j-memory` |
| Extension pre-design snapshot | Go | `sdk-existing-api-analyzer-go` | — | `serena`, `code-graph` |
| Extension pre-design snapshot | Python | `sdk-existing-api-analyzer-python` | — | `serena`, `code-graph` |
| Target-SDK marker ownership map | Shared | `sdk-marker-scanner` | — | `serena`, `ast-grep` |
| API design | Shared | `sdk-design-lead` | `pattern-advisor`, `sdk-designer` | `context7` |
| Interface signatures | Shared | `interface-designer` | `sdk-designer` | — |
| Retry/backoff/CB algorithms | Shared | `algorithm-designer` | `sdk-designer` | — |
| Concurrency patterns | Shared | `concurrency-designer` | — | — |
| Performance-budget declaration (latency targets, floor, MMD, big-O, allocs, drift signals) | Go | `sdk-perf-architect-go` | `algorithm-designer`, `concurrency-designer` | `context7`, `exa` |
| Performance-budget declaration | Python | `sdk-perf-architect-python` | `algorithm-designer`, `concurrency-designer` | `context7`, `exa` |
| Dependency vetting | Go | `sdk-dep-vet-devil-go` | — | — |
| Dependency vetting | Python | `sdk-dep-vet-devil-python` | — | — |
| Semver verdict | Shared | `sdk-semver-devil` | `sdk-breaking-change-devil-{go,python}` (Mode B/C) | — |
| Breaking-change verdict | Go | `sdk-breaking-change-devil-go` (Mode B/C) | `sdk-existing-api-analyzer-go` | — |
| Breaking-change verdict | Python | `sdk-breaking-change-devil-python` (Mode B/C) | `sdk-existing-api-analyzer-python` | — |
| Target SDK convention conformance | Go | `sdk-convention-devil-go` | — | — |
| Target SDK convention conformance | Python | `sdk-convention-devil-python` (PEP 8/257/484/621) | — | — |
| Distribution packaging validation | Python | `sdk-packaging-devil-python` (PEP 517/518/621/639 + py.typed; Mode A only) | — | — |
| Constraint marker proof | Go | `sdk-constraint-devil-go` | — | — |
| Constraint marker proof | Python | `sdk-constraint-devil-python` (pytest-benchmark + scipy Mann-Whitney) | — | — |
| Security review | Shared | `sdk-security-devil` | — | — |
| Code generation in target | Shared | `sdk-impl-lead` | `sdk-implementor`, `code-generator` | `serena`, `tree-sitter` |
| Merge planning (marker-aware) | Shared | `sdk-merge-planner` | `sdk-marker-scanner` | `serena` |
| Marker hygiene | Shared | `sdk-marker-hygiene-devil` | — | `ast-grep` |
| pprof / py-spy profile audit (alloc-budget G104; profile no-surprise G109) | Go | `sdk-profile-auditor-go` (CPU/heap/block/mutex pprof) | — | — |
| Profile audit | Python | `sdk-profile-auditor-python` (py-spy + scalene + tracemalloc) | — | — |
| Leak hunt | Go | `sdk-leak-hunter-go` (goroutines via goleak + `-race -count=5`) | — | — |
| Leak hunt | Python | `sdk-asyncio-leak-hunter-python` (asyncio tasks + sessions + fds via custom pytest fixtures) | — | — |
| API ergonomics (consumer POV) | Go | `sdk-api-ergonomics-devil-go` | — | — |
| API ergonomics | Python | `sdk-api-ergonomics-devil-python` | — | — |
| TPRD §7 conformance audit | Shared | `sdk-prd-conformance-devil` | — | — |
| Refactoring | Go | `refactoring-agent-go` | — | — |
| Refactoring | Python | `refactoring-agent-python` | — | — |
| Documentation | Go | `documentation-agent-go` | — | — |
| Documentation | Python | `documentation-agent-python` (Google-style docstrings + doctest) | — | — |
| Code review | Go | `code-reviewer-go` | — | — |
| Code review | Python | `code-reviewer-python` | — | — |
| Testing lead | Shared | `sdk-testing-lead` | per-language test/leak/bench/soak agents | — |
| Benchmark regression + target-latency verdict | Go | `sdk-benchmark-devil-go` (benchstat) | `baseline-manager`, `sdk-perf-architect-go` | — |
| Benchmark regression + target-latency verdict | Python | `sdk-benchmark-devil-python` (pytest-benchmark JSON + Mann-Whitney) | `baseline-manager`, `sdk-perf-architect-python` | — |
| Complexity scaling verdict (declared-vs-measured big-O; G107) | Go | `sdk-complexity-devil-go` | `sdk-perf-architect-go` | — |
| Complexity scaling verdict | Python | `sdk-complexity-devil-python` (curve fit on `@pytest.mark.parametrize` sweep) | `sdk-perf-architect-python` | — |
| Soak test launch (background harness + state file) | Go | `sdk-soak-runner-go` | `sdk-perf-architect-go` | — |
| Soak test launch | Python | `sdk-soak-runner-python` (nohup + tracemalloc JSONL snapshots) | `sdk-perf-architect-python` | — |
| Soak drift verdict (trend detection; MMD G105; drift G106) | Shared | `sdk-drift-detector` | `sdk-soak-runner-{go,python}` | — |
| Integration flake hunt | Go | `sdk-integration-flake-hunter-go` | — | — |
| Integration flake hunt | Python | `sdk-integration-flake-hunter-python` (pytest-repeat) | — | — |
| Metrics collection | Shared | `metrics-collector` | — | `neo4j-memory` |
| Phase retrospective | Shared | `phase-retrospector` | — | — |
| Root-cause trace | Shared | `root-cause-tracer` | — | `neo4j-memory` |
| Improvement planning + scope classification | Shared | `improvement-planner` | — | `neo4j-memory` |
| Learning + patch application + scope validation | Shared | `learning-engine` | `baseline-manager`, `improvement-planner` | `neo4j-memory` |
| Skill drift detection | Shared | `sdk-skill-drift-detector` (per-language scoreboard) | — | `serena`, `ast-grep`, `neo4j-memory` |
| Skill coverage reporting | Shared | `sdk-skill-coverage-reporter` (per-language coverage history) | — | `neo4j-memory` |
| Defect classification | Shared | `defect-analyzer` | — | — |
| Mechanical guardrail checks | Shared | `guardrail-validator` (filters by `active-packages.json` union) | — | — |
| Baseline management | Shared | `baseline-manager` (per-language partitions + shared partition) | — | `neo4j-memory` |

## Agent Groups

### Leads (orchestrators)
- `sdk-intake-agent` — Phase 0 (also acts as its own lead)
- `sdk-existing-api-analyzer-go` — Phase 0.5 (Mode B/C only)
- `sdk-design-lead` — Phase 1
- `sdk-impl-lead` — Phase 2
- `sdk-testing-lead` — Phase 3
- `learning-engine` — Phase 4 (skill-patch scope narrowed)

### Design agents (SDK-specific)
- Shared: `sdk-designer`, `interface-designer`, `algorithm-designer`, `concurrency-designer`, `pattern-advisor`
- Go: `sdk-perf-architect-go`
- Python: `sdk-perf-architect-python`

### Implementation agents
- Shared: `sdk-implementor`, `code-generator`, `test-spec-generator`
- Go: `refactoring-agent-go`, `documentation-agent-go`, `code-reviewer-go`, `sdk-profile-auditor-go`
- Python: `refactoring-agent-python`, `documentation-agent-python`, `code-reviewer-python`, `sdk-profile-auditor-python`

### Testing agents
- Shared: `unit-test-agent`, `integration-test-agent`, `performance-test-agent`, `mutation-test-agent`, `observability-test-agent`, `fuzz-agent`, `sdk-drift-detector`
- Go: `sdk-soak-runner-go`, `sdk-leak-hunter-go`, `sdk-integration-flake-hunter-go`, `sdk-benchmark-devil-go`, `sdk-complexity-devil-go`
- Python: `sdk-soak-runner-python`, `sdk-asyncio-leak-hunter-python`, `sdk-integration-flake-hunter-python`, `sdk-benchmark-devil-python`, `sdk-complexity-devil-python`

### Feedback agents (feedback-track) — all Shared
- `metrics-collector`, `phase-retrospector`, `root-cause-tracer`, `defect-analyzer`, `improvement-planner`, `baseline-manager`, `learning-engine`, `sdk-skill-drift-detector`, `sdk-skill-coverage-reporter`

### Devil / adversarial agents

D-numbering preserved from the Go pack; Python siblings carry the same number with a `-py` suffix where they exist (operators reading the matrix can map `D9-py` to `D9` mentally).

**Shared (run on every pipeline regardless of language)**:
- `sdk-design-devil` (D3)
- `sdk-semver-devil` (D5)
- `sdk-security-devil` (D7)
- `sdk-overengineering-critic` (D8)
- `sdk-skill-drift-detector` (D13)
- `sdk-skill-coverage-reporter` (D14)
- `guardrail-validator` (D16)
- `sdk-marker-hygiene-devil` (D18)
- `sdk-drift-detector` (D21, testing-phase T-SOAK observer; READ-ONLY)

**Go pack**:
- `sdk-dep-vet-devil-go` (D4)
- `sdk-convention-devil-go` (D6)
- `sdk-leak-hunter-go` (D9)
- `sdk-api-ergonomics-devil-go` (D10)
- `sdk-integration-flake-hunter-go` (D11)
- `sdk-benchmark-devil-go` (D12)
- `sdk-constraint-devil-go` (D17)
- `sdk-complexity-devil-go` (D19)
- `sdk-profile-auditor-go` (D20, impl-phase M3.5; READ-ONLY)

**Python pack**:
- `sdk-dep-vet-devil-python` (D4-py)
- `sdk-convention-devil-python` (D6-py)
- `sdk-asyncio-leak-hunter-python` (D9-py)
- `sdk-api-ergonomics-devil-python` (D10-py)
- `sdk-integration-flake-hunter-python` (D11-py)
- `sdk-benchmark-devil-python` (D12-py)
- `sdk-constraint-devil-python` (D17-py)
- `sdk-complexity-devil-python` (D19-py)
- `sdk-profile-auditor-python` (D20-py)
- `sdk-packaging-devil-python` (D22-py — NEW; Python-only Mode A distribution-metadata gate; no Go counterpart since Go's packaging is implicit in `go.mod`)

D1 (`sdk-skill-devil`) and D2 (`sdk-agent-devil`) REMOVED with Phase -1.

### Mode-conditional helpers

**Mode B/C** (Go): `sdk-existing-api-analyzer-go`, `sdk-breaking-change-devil-go`, `sdk-marker-scanner`, `sdk-merge-planner`
**Mode B/C** (Python): `sdk-existing-api-analyzer-python`, `sdk-breaking-change-devil-python`, `sdk-marker-scanner` (shared), `sdk-merge-planner` (shared)
**Mode A** (Python only): `sdk-packaging-devil-python` (greenfield Python packages need PEP 517/518/621 packaging validation; non-greenfield extensions inherit the host package's existing packaging)

The phase-lead's Active Package Awareness handles `_mode_a` and `_mode_bc` wave-id suffixes automatically — see `sdk-design-lead.md` § Active Package Awareness.

## Review-only guarantee

Every agent whose name contains `devil`, `critic`, `reviewer`, or `validator` is READ-ONLY on source code. They write only to `runs/<run-id>/<phase>/reviews/`.

## MCP Integration

MCPs listed in the **MCPs used** column are enhancements, not correctness dependencies. All agents fall back to JSONL / Grep / text-based paths on MCP unavailability (WARN-only; pipeline never halts). See `CLAUDE.md` rule 31 for the policy, `docs/MCP-INTEGRATION-PROPOSAL.md` for scope + rollout, and `skills/mcp-knowledge-graph/SKILL.md` for the canonical read/write + fallback pattern.
