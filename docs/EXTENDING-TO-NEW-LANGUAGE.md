<!-- Generated: 2026-05-01 -->
<!-- Pipeline version: 0.5.0 -->
<!-- Audience: a contributor proposing to add language support to the SDK pipeline -->

# Extending the Pipeline to a New Language

A self-contained guide. Read top-to-bottom **before** authoring anything.

This document answers four questions:

1. **What is required to add a new language?** — the artifacts, files, and contracts.
2. **What changes in the pipeline?** — what existing behavior moves vs. stays.
3. **What is the impact on output quality?** — direct and indirect effects on generated code.
4. **What can go wrong, and how do we prevent it?** — failure modes + mitigations.

The pipeline is **language-pluggable, not domain-pluggable** (per `docs/POST-PILOT-IMPROVEMENT-ROADMAP.md` Decision 1). Adding a language means authoring a new *language adapter pack*. There is no pluggability for runtime, framework, or domain underneath that.

---

## 0. Mental Model

The pipeline has three structural layers:

```
┌─────────────────────────────────────────────────────────────┐
│ shared-core (core)                                          │
│   Orchestrators (intake, design-lead, impl-lead, …)         │
│   Meta-skills (decision-logging, review-fix-protocol, …)    │
│   Cross-language guardrails (G01–G07, G20–G24, G80–G93, …)  │
│   Debt-bearer agents (sdk-design-devil, sdk-security-devil, │
│      sdk-overengineering-critic, sdk-semver-devil)          │
└─────────────────────────────────────────────────────────────┘
        │ depends on                          ▲ pulls overlays from
        │                                     │
┌───────▼──────────┐  ┌──────────────────┐   │
│ language pack A  │  │ language pack B  │ ──┘
│ (e.g. existing)  │  │ (e.g. NEW)       │
│                  │  │                  │
│  agents -A       │  │  agents -B       │
│  skills A-       │  │  skills B-       │
│  guardrails      │  │  guardrails      │
│  toolchain       │  │  toolchain       │
│  conventions.yaml│  │  conventions.yaml│
│  ast-hash backend│  │  ast-hash backend│
│  baselines/A/    │  │  baselines/B/    │
└──────────────────┘  └──────────────────┘
```

**The contract**: orchestrators stay generic; sub-agents (devils, critics, language-coupled testers, refactorers, doc authors) are forked per-language; skills are forked per-language; guardrails are *either* forked or generalized via `scripts/run-toolchain.sh` dispatch.

**The runtime**: at intake, `sdk-intake-agent` reads the TPRD's `§Target-Language: <lang>` field, resolves the language manifest plus its dependency closure (`shared-core`), and writes `runs/<run-id>/context/active-packages.json`. Phase leads then dispatch only agents in the active set. Guardrails not in the union are skipped.

**The hard invariants** (do not violate, ever):

- Files do **NOT** move into per-pack directories. The harness is flat-discovery — moving them silently breaks Claude Code's tool surface. Manifests are descriptive metadata.
- Phase leads / orchestrators do **NOT** fork per-language. They consume `active-packages.json` and dispatch sub-agents from manifest data.
- `validate-packages.sh` is the single discipline. Every artifact belongs to exactly one manifest; every manifest reference resolves to a file.
- Pipeline never creates skills/guardrails/agents at runtime. All artifacts are human-authored, PR-reviewed, static at runtime (CLAUDE.md rule 23).

---

## 1. What You Must Add

Treat the list below as a checklist. Items in **bold** are blocking — without them the pipeline cannot run a TPRD that targets your language.

### 1.1 Manifest — `.claude/package-manifests/<lang>.json`

The single source of truth for "what belongs to this language pack." Schema fields:

| Field | Required | Purpose |
|---|---|---|
| `schema_version`, `name`, `version`, `type=language-adapter`, `description` | **yes** | Identity. `name` MUST match the value TPRDs put in `§Target-Language`. |
| `depends`: `["shared-core@>=1.0.0"]` | **yes** | Every language adapter depends on shared-core. |
| `pipeline_version_compat`: `">=0.5.0"` | **yes** | Pipeline version range this pack works against. |
| `agents`, `skills`, `guardrails` | **yes** | Arrays of artifact names this pack owns. Validator checks each entry resolves on disk. |
| `waves` | **yes** | Per-wave-id list of THIS pack's agents that fire in that wave. Phase leads union per wave across active packs. |
| `tier_critical` | **yes** | Per-phase × per-tier required-agent set. Phase lead halts BLOCKER if any tier-critical agent is absent from active union. |
| `toolchain` block | **yes** for `language-adapter` | Build / test / lint / vet / fmt / coverage / bench / supply_chain / leak_check commands. Each command optionally carries `min_version` (post-roadmap U6). |
| `file_extensions`, `marker_comment_syntax`, `module_file` | **yes** for `language-adapter` | Marker scanner + AST-hash dispatcher use these to identify pack-owned files. |
| `baselines` block | **yes** | Declares which baseline files this pack owns (`scope_owned: per-language`, `owns_per_language: [...]`). |
| `aspirational_guardrails` | optional | Forward-declared guardrails not yet authored. Tracked, not executed. |
| `generalization_debt` | optional | Honest declaration of artifacts whose role is language-neutral but whose body still cites this language's idioms. |
| `notes` | optional | Free-form. |

### 1.2 Pack subdirectory — `.claude/package-manifests/<lang>/`

| File | Required | Purpose |
|---|---|---|
| **`conventions.yaml`** | **yes** | Language overlay for the four shared-core debt-bearer agents (`sdk-design-devil`, `sdk-overengineering-critic`, `sdk-semver-devil`, `sdk-security-devil`). Each rule keyed by `[rule-key: <key>]` in the agent body; overlay supplies `idiom`, `primitive`, `rule`, `rationale`, `example_violation`, `example_fix`. Without this file, debt-bearer agents emit `LANG-CONV-MISSING` events and fall back to a generic universal rule — degraded review quality. |
| `README.md` | recommended | Pack overview, contributor pointer, ownership summary. |
| `adapters/*.sh` | optional | Externalized toolchain scripts when inline `toolchain.<command>` strings get unwieldy. Must remain policy-free (emit normalized output; no thresholds). |
| `parsers/*` | optional | Profile-output to normalized schema converters (e.g. `pprof-to-normalized.py`, `coverage-to-normalized.py`). |

### 1.3 Sub-agents (~16–18, with `-<lang>` suffix)

Authoring discipline: read the existing-language sibling for **structure reference only**. Author each body fresh, in your target-language idioms, with citations into your `conventions.yaml`. Mechanical translation will pollute output — see §4.2.

Three shapes (categorize per agent):

**Shape A — same role, same name, fresh body** (the common case):
```
code-reviewer-<lang>                  documentation-agent-<lang>             refactoring-agent-<lang>
sdk-api-ergonomics-devil-<lang>       sdk-benchmark-devil-<lang>             sdk-breaking-change-devil-<lang>
sdk-complexity-devil-<lang>           sdk-constraint-devil-<lang>            sdk-convention-devil-<lang>
sdk-dep-vet-devil-<lang>              sdk-existing-api-analyzer-<lang>       sdk-integration-flake-hunter-<lang>
sdk-perf-architect-<lang>             sdk-profile-auditor-<lang>             sdk-soak-runner-<lang>
```

**Shape B — language-idiomatic rename** (when the role transfers but the noun is language-bound):

The agent's *role* still fits, but its *name* encodes a concept that doesn't exist in the new language. Rename the sub-agent so the name matches the language's noun for the same concern. Examples of the kind of rename this covers — without prescribing what your language needs:

- A "leak-hunter" agent: in one language the noun is "goroutine leak"; in another it's "task leak"; in another it's "thread leak"; in another it's "promise-rejection leak". The role (catch resources that outlive their owner) transfers. The name shouldn't.
- A "concurrency-devil" agent: "channel" vs. "queue" vs. "actor" depending on language.

Don't force a rename — only do it when the existing name is genuinely a misnomer in the new language.

**Shape C — new agent with no counterpart** (when the new language has a failure mode no other pack has):

Add a sub-agent specific to the new language's surface area. Examples of what this might look like:

- A packaging-devil for a language with non-trivial distribution semantics (manifest format, signing, registry rules).
- A type-stub-coverage-devil for a language with separate stub files.
- A linker / ABI-stability-devil for a language with native compilation and ABI compatibility concerns.

Add to `aspirational_guardrails` first if the script doesn't exist yet; promote to `guardrails` array when authored.

#### Per-agent authoring checklist

1. Frontmatter: `name`, `description`, `model`, `tools` array.
2. Body: Startup Protocol that reads `runs/<run-id>/context/active-packages.json` (for `target_language`) and loads `.claude/package-manifests/<target_language>/conventions.yaml` if applicable.
3. No cross-language references in the body. Every code example is target-language code.
4. Citations into your `conventions.yaml` rules by qualified name.
5. Add to manifest: `agents`, `waves.<id>`, `tier_critical.<phase>.<tier>`.
6. `validate-packages.sh` PASS.

### 1.4 Skills (~20, with `<lang>-` prefix)

A skill is a versioned body of guidance an agent consults during work. The skill set must cover at minimum these concern areas for an SDK-client-grade output:

| Concern | Skill (rename per language) |
|---|---|
| Concurrency primitives | `<lang>-concurrency-patterns` (channels / tasks / threads / promises) |
| Error / exception design | `<lang>-error-handling-patterns` |
| Test framework patterns | `<lang>-testing-patterns` |
| Mock / fake strategy | `<lang>-mock-strategy` |
| Strict typing | `<lang>-strict-typing` |
| Doc / runnable examples | `<lang>-doctest-patterns` or `<lang>-example-function-patterns` |
| OpenTelemetry instrumentation | `<lang>-otel-instrumentation` |
| SDK Config constructor convention | `<lang>-sdk-config-pattern` |
| Circuit breaker policy | `<lang>-circuit-breaker-policy` |
| Connection pool tuning | `<lang>-connection-pool-tuning` |
| Credential provider pattern | `<lang>-credential-provider-pattern` |
| Client shutdown lifecycle | `<lang>-client-shutdown-lifecycle` |
| Client TLS configuration | `<lang>-client-tls-configuration` |
| Client rate limiting | `<lang>-client-rate-limiting` |
| Backpressure / flow control | `<lang>-backpressure-flow-control` |
| Dependency vetting | `<lang>-dependency-vetting` |
| Resource leak prevention | `<lang>-leak-prevention` (adapted to the language's leak class) |
| Hexagonal architecture | `<lang>-hexagonal-architecture` |
| Property-based test patterns | `<lang>-property-based-test-patterns` |
| Containerized integration tests | `<lang>-testcontainers-setup` (or analog) |

Per skill:
- File: `skills/<lang>-<name>/SKILL.md` with frontmatter (`name`, `description`, `version`, `triggers`).
- Sibling: `evolution-log.md` — initial v1.0.0 entry.
- Body: ≥3 GOOD + ≥3 BAD examples drawn from real target-SDK code, decision criteria, cross-references, guardrail hooks.
- Register in `.claude/skill-index.json` (G90 enforces strict equality with filesystem).
- Add to `<lang>.json:skills` array.

### 1.5 Guardrails (~30 gates)

Two valid shapes — pick per script:

**Shape (a) — forked siblings** (`G30-<lang>.sh`, `G41-<lang>.sh`, …): fastest, doubles script count. Use when the language toolchain has a meaningfully different invocation contract.

**Shape (b) — generalized via `scripts/run-toolchain.sh`**: preferred long-term. Existing G30 / G41 / G60 already dispatch through the toolchain block. Authoring a new gate this way means `<lang>.json:toolchain` is the single source of language-specific commands.

The minimum gate set for an SDK-client-grade output:

| Gate | Concern |
|---|---|
| G30-`<lang>` | api-stub compiles smoke-test |
| G31, G32, G34-`<lang>` | supply-chain (vulnerability scan, license allowlist) |
| G40, G41, G42, G43-`<lang>` | build / vet / fmt |
| G48-`<lang>` | no module-level side effects |
| G60, G61, G63-`<lang>` | test / coverage / flake-hunt |
| G65-`<lang>` | benchmark regression |
| G95–G103-`<lang>` | marker protocol (delegate to `<lang>` AST-hash backend) |
| G104–G107, G109, G110-`<lang>` | perf-confidence regime (alloc, MMD, drift, complexity, profile, perf-exception) |
| G200-`<lang>` | packaging gate (manifest format, distribution correctness) |

Header schema (post-roadmap U9):
```bash
# phases:    intake design implementation testing
# severity:  BLOCKER | WARN | INFO
# mode_skip: A | B | C       (optional)
# min_phase: <phase>          (optional)
```

### 1.6 AST-hash backend — `scripts/ast-hash/`

Marker protocol (Mode B/C merge safety) requires the pipeline to compute byte-stable hashes of single symbols and enumerate symbols in a file. Adding a language means:

| File | Purpose |
|---|---|
| **`<lang>-backend.<ext>`** | Single-symbol AST hasher. Canonicalize per language rules (decided up front: doc-comments stripped or kept? annotations / decorators / metadata kept? sync-vs-async distinct? generics canonicalized?). |
| **`<lang>-symbols.<ext>`** | File / dir symbol enumerator. Same JSON output schema as existing-language siblings so G99 / G101 / G103 read all languages identically. |
| `ast-hash.sh`, `symbols.sh` | Update dispatchers with new-language fallback path keyed on `file_extensions`. |
| `README.md` | Add a language section answering the four canonicalization questions explicitly + a known-edge-case table. |

Without these, `[do-not-regenerate]` (G100), `[stable-since:]` (G101), and `[traces-to:]` (G99) cannot be enforced on your language → Mode B/C cannot run safely.

### 1.7 Baselines partition — `baselines/<lang>/`

Create the directory and seed seven empty files (the first pilot run populates them):

```
baselines/<lang>/performance-baselines.json
baselines/<lang>/coverage-baselines.json
baselines/<lang>/output-shape-history.jsonl
baselines/<lang>/devil-verdict-history.jsonl
baselines/<lang>/do-not-regenerate-hashes.json
baselines/<lang>/stable-signatures.json
baselines/<lang>/regression-report-<run-id>.md  (per-run)
```

Each JSON file carries `scope: per-language` and `language: <lang>` at top level. Manifest declares ownership in the `baselines.owns_per_language` array.

### 1.8 Perf-budget schema documentation

| File | Purpose |
|---|---|
| `docs/perf-budget-<lang>-schema.md` | Document language-native units (latency, memory unit, leak unit, etc.) so `sdk-perf-architect-<lang>` knows what to declare in `design/perf-budget.md`. |

### 1.9 Documentation updates

| File | Change |
|---|---|
| `docs/PACKAGE-AUTHORING-GUIDE.md` | Append language authoring section (or link to a dedicated page). |
| `CLAUDE.md` | Project Context block — list new language as supported. |
| `AGENTS.md` | Ownership-matrix entries for new sub-agents. |
| `README.md` | Mention new pack in supported-language list. |
| `evolution/evolution-reports/pipeline-v0.X.Y.md` | Release notes for the version that ships the new pack. |

### 1.10 TPRD acceptance

`sdk-intake-agent` Wave I1.5 must accept `§Target-Language: <lang>` (no code change required if the new value is just listed in the active-packages resolver as a known language). Validate with one synthetic small TPRD before declaring the pack ready.

---

## 2. What Changes in the Pipeline

### 2.1 What changes for runs targeting the new language

Everything: a TPRD with `§Target-Language: <new-lang>` will dispatch only the new pack's agents, run the new pack's guardrails, write to `baselines/<new-lang>/`, and read `<new-lang>/conventions.yaml` overlays in debt-bearer agents. This is the design — language-pack isolation.

### 2.2 What changes for runs targeting existing languages

In a clean implementation, **nothing changes for existing-language runs**. The active-packages resolver dispatches by `§Target-Language`. A Go run resolves `[shared-core, go]`; a Python run resolves `[shared-core, python]`; a `<new-lang>` run resolves `[shared-core, <new-lang>]`. There is no cross-pack invocation at runtime.

In practice, several shared-core touchpoints can leak: see §4 for the failure modes and §5 for the mitigations.

### 2.3 What stays unchanged regardless

- Phase contracts (`phases/INTAKE-PHASE.md` etc.) — phase-letter / wave-id structure is language-neutral.
- Slash commands (`/run-sdk-addition`, `/preflight-tprd`).
- HITL gates (H0/H1/H5/H7/H7b/H9/H10).
- `decision-log.jsonl` schema.
- `state/run-manifest.json` schema.
- Marker protocol semantics (the markers are the same; only the AST-hash backend differs).
- The seven perf-confidence axes (rule 32 / G104–G110).
- The verdict taxonomy (rule 33 — PASS / FAIL / INCOMPLETE).
- Branch-based safety (`sdk-pipeline/<run-id>`), no force-push, target-dir discipline.
- Determinism rule (rule 25 — same TPRD + same seed + same pipeline version → byte-equivalent output).

---

## 3. Impact on Output Quality

This is the question that matters most. Adding a language affects output through six channels:

### 3.1 Direct effects on new-language runs

The output for a TPRD targeting the new language is bounded by the quality of:

| Input | Effect on output |
|---|---|
| Skill bodies — depth and correctness of GOOD/BAD examples | Direct. Sparse skills → agents have nothing to consult → generated code defaults to LLM priors → idiomatic drift. |
| Conventions overlay — completeness of debt-bearer agent rules | Direct. Missing rules → debt-bearer agents emit `LANG-CONV-MISSING` and use universal fallback → reviews lose language-specific teeth. |
| TPRD-declared latency targets — calibration vs theoretical floor | Direct. Targets too tight → false-positive target-miss at H8 (rejects acceptable code); too loose → silent acceptance of slow code. perf-architect's theoretical-floor derivation is the sanity check. |
| AST-hash canonicalization rules | Direct. Wrong rules → marker hashes drift between runs → `[do-not-regenerate]` / `[stable-since:]` markers misfire → either spurious BLOCKERs or silent regenerations of MANUAL code. |
| Toolchain command shape + `min_version` | Direct. Wrong commands → guardrails INCOMPLETE → impl-lead halt-on-cumulative-INCOMPLETE → run halts. |
| Baseline seed | Indirect. First run writes the baseline; subsequent runs gate against it. A bad first run sets a bad baseline that future runs match. |

### 3.2 Indirect effects on existing-language runs

The risk is bounded but real:

| Mechanism | How it can hurt existing runs |
|---|---|
| `validate-packages.sh` | Hard-blocks all runs (Go, Python, anything) if the new pack has a dangling reference. The validator is global. |
| `skill-index.json` strict equality (G90) | Adding new skills requires updating `skill-index.json`. If you forget, G90 BLOCKER fires on every run including existing-language runs. |
| Pipeline version bump | Adding a pack typically bumps `pipeline_version` (e.g., 0.5.0 → 0.6.0). G06 enforces strict equality across all consumers. Drift = BLOCKER on every run. |
| Shared-core debt-bearer agents | If you extend the conventions.yaml overlay schema to support a new field for your language, every existing language's overlay must add the same field (or the agent's loader must default it). |
| `scripts/run-toolchain.sh` / `run-guardrails.sh` | If you modify the dispatcher logic to support your language's edge case, regression risk for existing-language dispatch. |
| `compute-shape-hash.sh` | If you add a `--lang` switch, existing callers must update or default-handle. |
| `learning-engine` skill-patch loop | Runs cross-language. If a learning-engine patch to a shared-core skill regresses on your language, the patch caps still allow it through. (Mitigated by per-language skill bodies; aggravated by skills with `generalization_debt`.) |

### 3.3 Cross-pollination through shared-core skills

Skills in `shared-core` (`tdd-patterns`, `idempotent-retry-safety`, `network-error-classification`, `spec-driven-development`, etc.) are consumed by all languages. They currently carry generalization debt — bodies cite specific-language idioms even though the rules themselves are universal. Two failure modes:

1. **Existing-language idioms in shared-core leak into new-language output.** Agent reading `tdd-patterns` sees existing-language test snippets and emits new-language code that copies the structure.
2. **New-language idioms added to shared-core leak into existing-language output.** If you "fix" `tdd-patterns` by adding new-language examples alongside existing ones, agents on existing-language runs may pick up new-language patterns.

The structural fix is the D6=Split mechanism: rule body in shared-core, examples in `<lang>/conventions.yaml`. Until all shared-core skills follow that pattern, both languages are exposed.

### 3.4 Quality regression detection

The compensating-baselines (CLAUDE.md rule 28) catch most quality regressions:

- **Output-shape hash** — exported-symbol-signature SHA256 per package per run. New language adds new shape buckets; existing-language hashes unaffected if dispatch is clean.
- **Devil-verdict stability** — per-skill `devil_fix_rate` / `devil_block_rate`. ≥20pp jump after a skill auto-patch surfaces as a regression warning.
- **Quality regression threshold** — 5% per-agent quality_score regression with ≥3 prior runs = BLOCKER (G86).
- **Example_* count per package** — raise-only; drops with ≥2 prior runs emit `⚠ example-drop`.

For a brand-new language, these baselines have no history (first-run = SEED). Quality protection comes only from the devil fleet on that run, not from baselines. The first 3 runs are the highest-risk window.

---

## 4. What Can Go Wrong (Failure Modes)

Catalogued by category. Each item: cause → symptom → blast radius.

### 4.1 Manifest validation failures

| Failure | Cause | Symptom | Blast radius |
|---|---|---|---|
| Dangling reference | Manifest names an artifact that doesn't exist on disk | `validate-packages.sh` exit 1 | All runs blocked (validator is global) |
| Duplicate ownership | Same artifact listed in two manifests | `validate-packages.sh` exit 1 | All runs blocked |
| Missing required field | Schema-required field absent | `validate-packages.sh` exit 1 | All runs blocked |
| Pipeline-version drift | New manifest says `pipeline_version_compat: ">=0.6.0"` but `settings.json` still says `0.5.0` | G06 BLOCKER at intake on every run | All runs blocked |

### 4.2 Quality regression in new-language output

| Failure | Cause | Symptom |
|---|---|---|
| Mechanical-translation contamination | Agent body translated from existing-language sibling instead of authored fresh | Generated code uses cross-language idioms (e.g., language-A naming style on language-B code) |
| Sparse skill bodies | Skills shipped as stubs with frontmatter only | Agents fall back to LLM priors → generic, off-convention code |
| Missing conventions overlay | `<lang>/conventions.yaml` absent or partial | Debt-bearer agents emit `LANG-CONV-MISSING`, fall back to universal rule, lose language-specific review teeth |
| Toolchain-cascade | Agent waves run before toolchain installed → INCOMPLETE markers cascade through phases | First-run cost balloons; impl-lead halts |
| Latency-target miscalibration | TPRD §10 / perf-budget.md `latency.*` targets too tight or too loose | Target-miss false-positive blocks acceptable code at H8; too loose → silent acceptance of slow code. Theoretical-floor derivation by perf-architect is the sanity check. |
| AST-hash canonicalization wrong | Backend strips wrong tokens or includes wrong tokens | Marker hashes drift between runs → `[do-not-regenerate]` misfires |
| Marker comment syntax wrong | `marker_comment_syntax` block doesn't match the language's comment forms | Marker scanner can't read provenance markers → Mode B/C unsafe |

### 4.3 Quality regression in existing-language output

| Failure | Cause | Symptom |
|---|---|---|
| Skill-index drift | New skills added without updating `skill-index.json` | G90 BLOCKER on every run (all languages) |
| Shared-core skill rewrite leaks idioms | Author "fixes" a shared-core skill body with new-language examples | Existing-language agents pick up new-language patterns |
| Conventions schema extension | `conventions.yaml` schema grows a new field for new language | Existing-language overlays missing the field → debt-bearer agents trip on existing-language runs |
| Dispatcher regression | Edits to `run-toolchain.sh` / `run-guardrails.sh` for new language break existing-language path | Existing-language guardrails skipped, INCOMPLETE, or wrong tool invoked |
| Baseline-manager edits | Baseline-manager updated to write `baselines/<new-lang>/` but breaks `baselines/<existing>/` write path | Existing-language baselines stop updating; quality regression detection blind |
| Compute-shape-hash schema break | Shape-hash script extended with `--lang` switch but existing call sites don't pass it | Existing-language `output-shape-history.jsonl` stops appending |

### 4.4 Operational / maintenance failure modes

| Failure | Cause | Symptom |
|---|---|---|
| First-run baselines locked too early | Baseline-manager promotes a SEED baseline from a noisy first run | All future runs gate against bad numbers — false-positive blocks of correct code |
| Toolchain version not pinned | `min_version` absent on `toolchain.<command>` | CVE-laden tool versions silently used; output may be insecure |
| Pack manifest references future-tense aspirational guardrails | `aspirational_guardrails` map populated but referenced by `tier_critical` | Phase lead halts BLOCKER on every run (tier-critical agent absent) |
| Dependency vetting allowlist drift | `<lang>` license allowlist diverges from existing-language packs | Inconsistent supply-chain policy across the org's SDKs |
| Soak-runner background-process cleanup | New language's soak harness spawns processes via Bash `run_in_background` but doesn't track them | Orphan processes after pipeline crash; resource exhaustion |
| Determinism break | Toolchain command is non-deterministic (e.g., timestamp-stamped output) | Rule 25 violation; same TPRD + same seed → divergent output |

### 4.5 Cross-language metric pollution

| Failure | Cause | Symptom |
|---|---|---|
| Shared quality baseline averaging | `quality-baselines.json` is `scope: shared`; per-agent `quality_score` averaged across languages | A regression in one language hides under another's improvement; G86 5% threshold blind to language-specific drift |
| Skill-health baseline averaging | `skill-health-baselines.json` shared | Same issue for skill maturity dimension |
| MCP knowledge-graph entity-mixing | If neo4j-memory entity types don't carry `language` attribute, learning-engine queries surface cross-language patterns | Patches inferred from one language applied to another |

---

## 5. Mitigation Steps

Per failure category. Apply during authoring; apply also after the pack ships, as ongoing hygiene.

### 5.1 Mitigations against manifest / validator failures

- **Run `validate-packages.sh` before every commit.** It's the single discipline. Wire into pre-commit if your environment supports it.
- **Run `check-doc-drift.sh`** — runs G06 (pipeline-version) + G90 (skill-index) + G116 (retired-terms) as a standalone sanity pass.
- **Bump pipeline-version in the same PR as the manifest.** All consumers update atomically.
- **Update `skill-index.json` in the same diff as the new SKILL.md.** Never split.

### 5.2 Mitigations against new-language output regression

- **Author every agent body fresh.** The temptation to translate from an existing language is the primary contamination vector. Read existing siblings for *structure reference* (which sections, which discipline checklists) but author the body in your target-language idioms with citations into your conventions.yaml.
- **Conventions overlay first, agents second.** Author the conventions.yaml entries before authoring the debt-bearer agents that consume them. Agents written without an overlay-anchor produce vague, generic findings.
- **Skill bodies must have ≥3 GOOD + ≥3 BAD examples drawn from real target-SDK code.** No theoretical examples. No translation of existing-language examples. If you don't have a target SDK to draw from, the skill is premature.
- **Toolchain `min_version` declared on every command.** Promote tool-version absence from runtime-INCOMPLETE to intake-BLOCKER per roadmap U6/U7.
- **Run `/preflight-tprd` against a small synthetic TPRD before any real run.** Surfaces missing skills, missing guardrails, missing toolchain.
- **First three runs go through full HITL review at every gate.** Don't enable any auto-merge convenience for the new language until baselines have ≥3 runs of history.

### 5.3 Mitigations against existing-language regression

- **Pack-isolation discipline at runtime.** All language-specific work goes in the new pack. Touch `shared-core` only when the change is genuinely cross-cutting AND every existing-language pack has been tested against the change.
- **Conventions.yaml schema is additive-only.** Add new fields with default values; never rename or remove. Existing-language overlays without the new field continue to work.
- **`scripts/run-toolchain.sh` / `run-guardrails.sh` regression-test on existing language before merging.** Run a full smoke test of an existing-language TPRD through both dispatchers; verify guardrail pass-set unchanged.
- **`baseline-manager` edits accompanied by per-language smoke test.** If you touch the baseline-manager agent prompt, verify it still writes the existing-language baselines correctly.
- **Generalization-debt declarations are honest.** When a shared-core skill is touched and you don't have time to D6=Split it, declare the new debt in `shared-core.json:generalization_debt` rather than letting the body silently encode a second language's idioms.

### 5.4 Mitigations against operational failures

- **First-run baselines are SEED-only, not gating.** Configure baseline-manager so the first run for a new language writes baselines but does not block on regression. Switch to gating after run #3.
- **Soak-runner harness must register cleanup.** Background processes spawned via Bash `run_in_background` track PID into `runs/<id>/state/soak-pids.txt`; pipeline-final cleanup hook kills any survivors.
- **`min_version` BLOCKER at intake.** Catches CVE-laden / API-incompatible tool versions before any agent fires.
- **`G-toolchain-probe.sh` BLOCKER at intake.** Mandatory preflight per roadmap U7. Closes the toolchain-cascade failure class.
- **Determinism smoke test.** Run the same synthetic TPRD twice with the same seed; verify byte-equivalent output. Add to the new-language CI gate.

### 5.5 Mitigations against cross-language metric pollution

- **Per-language baseline partitioning is enforced today** for `performance-baselines.json`, `coverage-baselines.json`, `output-shape-history.jsonl`, `devil-verdict-history.jsonl`, `do-not-regenerate-hashes.json`, `stable-signatures.json`. Don't alter scope.
- **Quality-baselines.json scope is `shared` today (D2=Lenient/Progressive)** — accepts pooling until rolling-3 runs accumulate per language. Once you have ≥3 runs in the new language, decide whether to flip to per-language partition (D2=Strict). Re-evaluate G86 thresholds against per-language history.
- **MCP entity schema includes `language` attribute** on Run / Agent / Skill / Pattern entities. Enforce in `mcp-knowledge-graph` skill body. Cross-language pattern inference must be explicit, never implicit.
- **Learning-engine patch caps stay at 3 existing-skill patches per run** (CLAUDE.md rule 23, settings.json `safety_caps.existing_skill_patches_per_run`). Cap forces prioritization which forces correctness review.

### 5.6 Mitigations against AST-hash / marker drift

- **Document canonicalization rules up-front** in `scripts/ast-hash/README.md` § new-language section. Answer: doc-comment handling? annotation handling? generic / type-parameter canonicalization? sync-vs-async distinction? formatting / whitespace? Ambiguity here is the primary marker-hash drift source.
- **Round-trip test the AST-hash backend** on a fixture file: hash → modify whitespace → re-hash → must equal. Hash → modify symbol body → re-hash → must differ. Add to new-language CI.
- **Round-trip test the symbols enumerator** on a multi-symbol file; output JSON must be deterministic ordering.

---

## 6. Validation Strategy — How to Know You Got It Right

Five gates. All must pass before the pack is considered shippable.

```bash
# 1. Manifest consistency
bash scripts/validate-packages.sh                          # exit 0 = clean
bash scripts/check-doc-drift.sh                            # G06 + G90 + G116 = PASS

# 2. Toolchain dispatch
bash scripts/run-toolchain.sh build                        # dispatches new language's build cmd
bash scripts/run-toolchain.sh --check-versions             # min_version verified

# 3. Guardrail dispatch
bash scripts/run-guardrails.sh testing <synthetic-run-dir>  # new pack guardrails fire; existing pack guardrails skipped

# 4. AST-hash round-trip
bash scripts/ast-hash/ast-hash.sh <fixture> <symbol>       # deterministic hash
bash scripts/ast-hash/symbols.sh <fixture-dir>             # deterministic enumeration

# 5. Smoke TPRD end-to-end
/preflight-tprd <small-new-language-tprd>                  # no missing skills / guardrails / toolchain
/run-sdk-addition --spec <tprd> --run-id <lang>-smoke-v1   # run completes, all phase gates PASS
```

Plus three calendar-time validations that can't be compressed:

- **Determinism check across runs.** Same TPRD + same seed → byte-equivalent output (rule 25). Run twice on different days, diff outputs.
- **Cross-version determinism.** Once the pack ships, and pipeline-version bumps (0.5.0 → 0.6.0 → 0.7.0), re-run a canonical TPRD and verify the bump didn't silently regress.
- **3-run baseline accumulation.** First three end-to-end runs produce SEED baselines. Run four onward gates against the rolling baseline. Don't auto-merge anything in the first window.

---

## 7. Effort Estimate

For a competent author with target-language fluency:

| Workstream | Effort |
|---|---|
| Manifest + conventions.yaml + AST-hash backend (foundations) | 1.5–2 days |
| Pack agents (~17, fresh-authored) | ~4 days |
| Pack skills (~20, ≥3 GOOD/BAD each, real-code citations) | ~6 days |
| Pack guardrails (~30, fork-or-generalize calls) | ~5 days |
| Baselines + perf-budget schema | ~1 day |
| Documentation + validator green | ~1 day |
| First pilot run + calibration + review | ~2–3 days |
| **Total** | **~3 engineering weeks** |

Calendar realistically 4–8 weeks if not full-time, plus 6+ weeks of trust-validation runs before auto-merge can be considered.

---

## 8. Hard Non-Goals (Do Not Do These)

- ❌ **Do not move agent / skill files into per-pack directories.** Harness discovery is flat-only; subdirs silently break it.
- ❌ **Do not fork phase leads or orchestrators per language.** They consume `active-packages.json` and dispatch from manifest data. Forking them duplicates orchestration logic across packs and accumulates drift.
- ❌ **Do not put threshold logic in the `toolchain` block.** Strings are commands; policy lives in agents. Adapter scripts must emit normalized output, not verdicts.
- ❌ **Do not bypass `validate-packages.sh`.** It's the only discipline keeping manifests honest.
- ❌ **Do not mechanically translate agent bodies from existing languages.** Translation contaminates output. Read for structure reference only; author the body in your target-language idioms.
- ❌ **Do not author runtime-synthesized manifests.** Manifests are human-authored, PR-reviewed, static at runtime (CLAUDE.md rule 23 extended).
- ❌ **Do not invent a domain dimension.** The pipeline is language-pluggable, not domain-pluggable. Domain knowledge stays in TPRDs (`§7 API`, `§10 NFRs`, `§3 Non-Goals`).
- ❌ **Do not promote a SEED baseline to gating** before three runs of history accumulate.
- ❌ **Do not enable auto-merge / convenience automation** in the new language's first three runs. Force HITL review at every gate while baselines stabilize.

---

## 9. Failure-Mode Quick Reference

| Symptom | First place to look |
|---|---|
| All runs suddenly fail at intake | `validate-packages.sh`; `check-doc-drift.sh`; G06 (pipeline-version) |
| New-language output looks like another language | Agent body translated rather than authored fresh; conventions.yaml missing |
| Marker scanner emits "unknown comment syntax" | `marker_comment_syntax` block in manifest |
| `[do-not-regenerate]` markers misfiring | AST-hash canonicalization rules; round-trip test fixture |
| Existing-language run shows degraded review quality | Shared-core conventions.yaml schema regression; debt-bearer overlay drift |
| First-run baselines block subsequent runs | Baseline-manager promoted SEED to gating prematurely |
| Toolchain INCOMPLETE cascading through phases | `min_version` not declared; `G-toolchain-probe.sh` not run at intake |
| Target-miss false-positive at H8 | TPRD §10 / perf-budget.md `latency.*` targets too tight; perf-architect's theoretical-floor derivation should catch this at D1 |
| Quality regression detection blind | `quality-baselines.json` shared across languages; not enough per-language history yet |
| Pipeline halts mid-impl with no clear cause | Cumulative-INCOMPLETE halt policy fired (≥2/wave or ≥3/phase); check `decision-log.jsonl` for `BLOCKER: cumulative-incomplete` |

---

## 10. See Also

- `CLAUDE.md` rule 34 — canonical Package Layer rule.
- `CLAUDE.md` rule 32 — Performance-Confidence Regime (the seven falsification axes).
- `CLAUDE.md` rule 28 — Compensating Baselines.
- `CLAUDE.md` rule 25 — Determinism rule.
- `docs/PACKAGE-AUTHORING-GUIDE.md` — manifest schema reference.
- `docs/POST-PILOT-IMPROVEMENT-ROADMAP.md` — quality-improvement backlog (U5 / U6 / U7 strongly recommended *before* adding a third language).
- `docs/LANGUAGE-AGNOSTIC-DECISIONS.md` — design decisions D1 (filesystem), D2 (baseline partition), D6 (Split debt-bearer).
- `phases/INTAKE-PHASE.md` — Wave I1.5 / I5.5 (target-language acceptance + active-packages resolution).
- `scripts/guardrails/G05.sh` — `active-packages.json` validator.

---

> **Working principle**: language-pack isolation is real but not free. Every shared-core touchpoint is a potential cross-language regression vector. Author the new pack as if it cannot rely on existing packs to test its work — because the only thing that catches contamination is per-language end-to-end runs through the full review fleet.
