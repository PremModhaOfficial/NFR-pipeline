<!-- cross_language_ok: true — pipeline design/decision doc references per-pack tooling. Multi-tenant SaaS platform context preserved per F-008. -->

# Package Authoring Guide

**Audience**: contributors authoring a new package manifest (a second-language adapter, a tier-specific bundle, or a domain split out of `shared-core`).

**Pipeline version**: 0.5.0+

---

## What a package is

A **package** is a JSON manifest in `.claude/package-manifests/<name>.json` that lists which on-disk artifacts (agents, skills, guardrails) belong to one logical unit. Two packages exist today:

- `shared-core` — language-agnostic orchestration, meta-skills, governance.
- `go` — Go SDK language adapter for `motadatagosdk`.

Manifests are **descriptive metadata**, not directory structure. Files do NOT move into per-package folders. Agents stay at `agents/<name>.md`, skills at `skills/<name>/SKILL.md`, guardrails at `scripts/guardrails/G*.sh`. This is a hard invariant: Claude Code's harness auto-discovers from those canonical paths, and physical packaging would silently break discovery.

---

## When to author a new package

| Scenario | Verdict |
|---|---|
| Adding a second-language adapter (Python, Rust, TypeScript, Java) | YES — author `<lang>.json` |
| Splitting `shared-core` because it grew unwieldy | YES — author `governance.json` etc., move artifacts via manifest entries (no file moves) |
| Adding a single new agent / skill / guardrail | NO — add it to an existing manifest |
| Carving out a tier-specific bundle (e.g. T2-only) | NO — tiers are a runtime filter on the existing union, not their own manifests |
| Per-target-product packaging (e.g. `motadata-go-sdk` vs `motadata-py-sdk`) | NO at v0.4.0 — defer; revisit when third adapter exists |

---

## Manifest schema

```json
{
  "schema_version": "1.0.0",
  "name": "<package-name>",
  "version": "X.Y.Z",
  "type": "core | language-adapter",
  "description": "<one-line>",
  "depends": ["shared-core@>=1.0.0", ...],
  "pipeline_version_compat": ">=0.4.0",

  "agents":     ["<agent-id>", ...],
  "skills":     ["<skill-name>", ...],
  "guardrails": ["G<NN>", ...],

  "waves": {                // per-wave: list of THIS package's agents that fire in that wave
    "<wave-id>": ["<agent-id>", ...]
  },

  "tier_critical": {        // per-phase × per-tier: agents this package considers tier-critical
    "design":         { "T1": [...], "T2": [...] },
    "implementation": { "T1": [...], "T2": [...] },
    "testing":        { "T1": [...], "T2": [...] }
  },

  "toolchain": {           // language-adapter only
    "build":            "<cmd>",
    "test":             "<cmd>",
    "lint":             "<cmd>",
    "vet":              "<cmd>",
    "fmt":              "<cmd>",
    "coverage":         "<cmd>",
    "coverage_min_pct": 90,
    "bench":            "<cmd>",
    "supply_chain":     ["<cmd>", ...],
    "leak_check":       "<cmd>"
  },
  "file_extensions":         [".<ext>"],
  "marker_comment_syntax":   { "line": "<>", "block_open": "<>", "block_close": "<>" },
  "module_file":             "<filename>",

  "generalization_debt": {
    "agents": [{"name": "...", "reason": "..."}],
    "skills": [{"name": "...", "reason": "..."}],
    "resolution_policy": "<text>"
  },

  "notes": { "<key>": "<text>", ... }
}
```

Required fields: `name`, `version`, `agents`, `skills`, `guardrails`, `waves`, `tier_critical`. Validator checks for these.

`type=core` packages do NOT carry `toolchain` / `file_extensions` / `marker_comment_syntax` / `module_file`. They're language-neutral.

`type=language-adapter` packages MUST carry all four.

### `waves` field

Each entry maps a wave-id → list of THIS package's agents that fire in that wave. Phase leads at runtime read `runs/<id>/context/active-packages.json` and union per-wave across active packages:

```
ACTIVE_AGENTS_FOR_WAVE = ⋃ (pkg.waves[wave] for pkg in active-packages)
```

Wave-id naming: `<phase-letter><number>_<short-purpose>` where phase-letter ∈ {I=intake, D=design, M=impl, T=testing, F=feedback}. Example: `D3_devils`, `M3_5_profile_audit`, `T5_5_soak`.

Mode-specific waves use suffix `_mode_bc` (e.g. `D3_devils_mode_bc`). Phase lead conditionally adds when run mode ∈ {B, C}.

If a wave's resolved agent list is empty for a run, the lead skips it and logs `INCOMPLETE: no active agents for wave <id>` per CLAUDE.md rule 33 (verdict taxonomy).

### `tier_critical` field

Per-phase × per-tier list of THIS package's agents that the phase lead REQUIRES to be present in the active-packages union. If a tier-critical agent is missing, the lead halts with BLOCKER. Phase lead unions per (phase, tier) across active packages.

Tiers: `T1` (full perf-confidence regime), `T2` (skip perf gates, keep build/test/lint/supply-chain). `T3` is out-of-scope and halts at intake.

---

## Per-language conventions.yaml overlay (D6=Split mechanism, v0.5.0+)

Some agents in `shared-core` have **language-neutral roles** but **language-flavored examples** — `sdk-design-devil`, `sdk-overengineering-critic`, `sdk-semver-devil`, `sdk-security-devil`. Per the D6=Split decision (`docs/LANGUAGE-AGNOSTIC-DECISIONS.md`, R2 spike), these agents keep one rule body in shared-core and pull language-specific examples from a per-pack overlay file.

**Overlay file location**: `.claude/package-manifests/<lang>/conventions.yaml`

**Schema** (v1.0):

```yaml
schema_version: "1.0"
language: <lang>                  # MUST match parent manifest's name
pipeline_version_compat: ">=0.5.0"

agents:
  <agent-name>:
    rules:
      <rule-key>:
        idiom: "<language term for the concept>"     # optional
        primitive: "<language primitive>"            # optional
        rule: "<language-coupled rule statement>"    # optional
        rationale: "<why this rule exists>"          # optional
        example_violation: |                          # optional, multi-line code
          <code>
        example_fix: |                                # optional, multi-line code
          <code>
        examples_violations:                          # optional, list of short examples
          - "<short violation>"
```

**Loader protocol** (every Split agent's prompt MUST contain):

```markdown
## Startup Protocol

1. Read `runs/<run-id>/context/active-packages.json` to get `target_language`.
2. Read `.claude/package-manifests/<target_language>/conventions.yaml` (loaded as `LANG_CONVENTIONS`).
   Each rule in this prompt has a `[rule-key: <key>]` tag matching
   `LANG_CONVENTIONS.agents.<this-agent-name>.rules.<key>`. Apply the language-flavored
   `idiom`, `primitive`, `example_violation`, `example_fix` when emitting findings.
   If `LANG_CONVENTIONS` is missing or has no entry for a rule, fall back to the
   universal rule and surface a `LANG-CONV-MISSING` event.
```

**Per-rule reference in the agent body**:

```markdown
### Parameter count [rule-key: parameter_count]
Functions with >4 positional params → NEEDS-FIX. Propose the active language's
grouped-arguments idiom (Go: `Config struct`; Python: `dataclass`; Rust: builder).
```

**Adding a new language**: author `<lang>/conventions.yaml` with the same shape; the agent's loader picks it up automatically. Adding a new debt-bearer agent: extend the `agents:` map in every existing language's conventions.yaml.

**Three remaining skill debt items** (`tdd-patterns`, `idempotent-retry-safety`, `network-error-classification`) will follow the same pattern in a future pass — schema extends conventions.yaml with a top-level `skills:` map alongside `agents:`.

---

## Naming convention for language-specific artifacts

When the same role exists per-language, **agents** get a `-<lang>` suffix and **skills** get a `<lang>-` prefix. Truly language-agnostic artifacts carry neither.

| Kind | Language-agnostic | Go-specific | Python-specific |
|---|---|---|---|
| Orchestrator agent | `sdk-design-lead` | (n/a — leads stay generic) | (n/a) |
| Devil/critic agent | `sdk-design-devil` *(today; debt-bearer)* | `sdk-design-devil-go` *(after Split rewrite)* | `sdk-design-devil-python` |
| Pure-language agent | (n/a) | `sdk-perf-architect-go` | `sdk-perf-architect-python` |
| Cross-language skill | `tdd-patterns` | (n/a) | (n/a) |
| Language-specific skill | (n/a) | `go-concurrency-patterns` | `python-asyncio-patterns` |
| Guardrail (build/test/etc) | (n/a — guardrails always live in a language pack) | `G30-go.sh` *(if disambiguation ever needed; today flat is fine)* | `G30-python.sh` |

### Decision rules

1. **Phase leads stay generic.** `sdk-intake-agent`, `sdk-design-lead`, `sdk-impl-lead`, `sdk-testing-lead` and similar orchestrators do NOT get a suffix. They consume `active-packages.json` and dispatch language-specific sub-agents from manifest data — see CLAUDE.md rule 34.

2. **Language-specific sub-agents get a `-<lang>` suffix.** Example: `sdk-design-devil-go`, `sdk-design-devil-python`, `code-reviewer-go`, `sdk-perf-architect-go`.

3. **Language-specific skills get a `<lang>-` prefix.** Example: `go-concurrency-patterns`, `go-client-tls-configuration`, `python-asyncio-patterns`. Don't double-tag (`go-concurrency-patterns-go` is wrong; `python-asyncio-patterns-python` is wrong). The prefix shape is what `validate-packages.sh` and the harness already see for the existing 25 go-pack skills, so keep using it.

4. **A skill whose name already encodes the language** (`goroutine-leak-prevention` — `goroutine-` is a Go-only term) keeps its existing shape. Don't double-tag with `go-` prefix.

5. **Today's Go-only roles without a `-go` suffix or `go-` prefix are debt items**, not the convention. The Go-leakage cleanup (Step 13 of structure-finalization) will rename them as it moves them from `shared-core` into the `go` pack. Don't pre-rename now — wait for the move.

### Why suffix for agents, prefix for skills

- **Flat layout, both forms**: Claude Code's discovery is flat (one glob on `agents/*.md`, one on `skills/*/`); `scripts/validate-packages.sh` also assumes flat. Both suffix and prefix need zero infra changes.
- **Agents → suffix**: agent names already start with role qualifiers (`sdk-*`, `code-*`, `documentation-*`). Putting the language at the end (`sdk-design-devil-go`) keeps role-first reading order and groups same-role siblings alphabetically (`sdk-design-devil-go` next to `sdk-design-devil-python`).
- **Skills → prefix**: language-specific skills already group by language at the start (`go-concurrency-patterns`, `python-asyncio-patterns`). Putting the language at the front matches the existing 25 go-pack skill names, mirrors stdlib library names (`go-`, `py-`, `rs-`), and `<lang>-*` reads naturally as "the language's library of patterns for X."
- **Subdir** (`agents/go/<name>.md`, `skills/go/<name>/`) was considered. Rejected — would silently break harness discovery and require validator rewrite.

### Filesystem and manifest grouping

- Flat filesystem layout stays. Per-language grouping is **manifest membership**, not directory structure.
- Alphabetical sort naturally groups same-role siblings (`sdk-design-devil-go` next to `sdk-design-devil-python`).
- `active-packages.json` reads `["sdk-design-devil-go", "sdk-perf-architect-go"]` cleanly without hierarchical paths.

---

## How to add a second-language adapter (worked example: Python)

### Step 1 — author `.claude/package-manifests/python.json`

Use `go.json` as a template. Fill the `toolchain` block:

```json
{
  "schema_version": "1.0.0",
  "name": "python",
  "version": "1.0.0",
  "type": "language-adapter",
  "description": "Python SDK pipeline adapter for motadatapysdk. Target: Python 3.12.",
  "depends": ["shared-core@>=1.0.0"],
  "pipeline_version_compat": ">=0.5.0",

  "agents":     [...],   // python-specific agents — use -python suffix (sdk-asyncio-leak-hunter-python, sdk-perf-architect-python, etc.)
  "skills":     [...],   // python-specific skills — language-prefix convention (python-asyncio-patterns, python-pytest-fixtures, etc.)
  "guardrails": [...],   // python-specific gates (G-codes; flat naming today, see Naming Convention)

  "toolchain": {
    "build":            "python -m build",
    "test":             "pytest -x --no-header",
    "lint":             "ruff check .",
    "vet":              "mypy --strict .",
    "fmt":              "ruff format --check .",
    "coverage":         "pytest --cov=src --cov-report=json",
    "coverage_min_pct": 90,
    "bench":            "pytest --benchmark-only",
    "supply_chain":     ["pip-audit", "safety check"],
    "leak_check":       "asyncio-leak-test"
  },
  "file_extensions":         [".py"],
  "marker_comment_syntax":   { "line": "#", "block_open": "\"\"\"", "block_close": "\"\"\"" },
  "module_file":             "pyproject.toml"
}
```

### Step 2 — author the agents / skills / guardrails the manifest references

Each must exist on disk before `scripts/validate-packages.sh` will pass. Author them per the existing canonical patterns:

- Agents: `agents/<name>.md` with frontmatter (`name`, `description`, `model`, `tools`).
- Skills: `skills/<name>/SKILL.md` with frontmatter (`name`, `description`, `version`).
- Guardrails: `scripts/guardrails/G<NN>.sh` executable, with `# phases:` and `# severity:` headers.

### Step 3 — work through `shared-core.json`'s `generalization_debt` list

Each entry needs one of:
- **Rewrite** the agent / skill body to be language-neutral (no Go idioms in examples).
- **Move** to a language-specific manifest if role turns out to be Go-specific (rare).
- **Split** into shared + per-language parts (e.g. `tdd-patterns` becomes `tdd-patterns-shared` + `go-tdd-snippets` + `python-tdd-snippets`).

### Step 4 — run the validator

```bash
bash scripts/validate-packages.sh
```

Must exit 0. Any orphan / duplicate / dangling reference = FAIL. Fix the manifest until clean.

### Step 5 — author a new TPRD that declares `§Target-Language: python`

Run intake. **`§Target-Language` is REQUIRED in every TPRD as of v0.5.0** — `sdk-intake-agent` Wave I1.5 halts with BLOCKER if absent (no silent default). Wave I5.5 then resolves `python.json` and writes `runs/<id>/context/active-packages.json` with the union set. G05 verifies. Phase leads dispatch only Python agents. Wave I6 cross-checks every skill listed in §Skills-Manifest against the active-package skill union; orphans (registered globally but not in active packs) emit WARN, not BLOCKER.

---

## Phase B Python authoring checklist

The Phase B work below fills `python.json`'s empty `agents` / `skills` / `guardrails` arrays so a real Python TPRD can run end-to-end. Steps are ordered for incremental landing — each wave produces a green `validate-packages.sh` and shippable PR.

### Wave B-1: Foundations *(complete — shipped 2026-04-28 in v0.5.0 Phase B)*

Mechanical groundwork that doesn't depend on Python idiom decisions. Only this wave's files were authored directly; later waves are scoped lazily as TPRDs expose need.

- [x] `scripts/ast-hash/python-backend.py` — single-symbol AST hasher; stdlib-only; mirrors `go-backend.go` interface and exit codes.
- [x] `scripts/ast-hash/python-symbols.py` — file/dir symbol enumerator; same JSON schema as `go-symbols.go` (so G99 / G101 / G103 read both languages identically).
- [x] `scripts/ast-hash/ast-hash.sh` + `symbols.sh` — dispatchers extended with `scripts/ast-hash/python-*.py` fallback path.
- [x] `scripts/ast-hash/README.md` — § "Python backend" with explicit answers to the four canonicalization questions (docstrings stripped, type hints included, decorators included, async-vs-sync distinct) plus the Python edge-case table.
- [x] `.claude/package-manifests/python/conventions.yaml` — Python overlay for the four shared-core debt-bearer agents (`sdk-design-devil`, `sdk-overengineering-critic`, `sdk-semver-devil`, `sdk-security-devil`). Captures Python-only footguns: mutable default args, `pickle.loads`, `yaml.load`, `==` for token compare, etc.
- [x] `.claude/package-manifests/python/README.md` — pack overview + Phase B authoring path pointer.
- [x] `docs/PACKAGE-AUTHORING-GUIDE.md` § Phase B Python authoring checklist — this section.

### Wave B-2: Python pack agents *(in progress)*

Author each Python pack agent independently — fresh body, Python-only idioms, citations into `python/conventions.yaml`. Do NOT mechanically translate from the Go pack. Some agents have Python-idiomatic names that diverge from `<go-name>-python`, and Python may need agents that have no Go counterpart at all.

Three categories:

**A. Mirror with same name** — generic name and role transfer; body authored fresh.

| Agent | Wave | Status |
|---|---|---|
| `code-reviewer-python` | M7 | shipped |
| `documentation-agent-python` | M6 | shipped |
| `refactoring-agent-python` | M5 | shipped |
| `sdk-api-ergonomics-devil-python` | M7 | shipped |
| `sdk-benchmark-devil-python` | T5 | pending |
| `sdk-breaking-change-devil-python` | D3 (Mode B/C) | pending |
| `sdk-complexity-devil-python` | T5 | pending |
| `sdk-constraint-devil-python` | D3 + M4 | pending |
| `sdk-convention-devil-python` | D3 | pending |
| `sdk-dep-vet-devil-python` | D3 | pending |
| `sdk-existing-api-analyzer-python` | I3 (Mode B/C) | pending |
| `sdk-integration-flake-hunter-python` | T3 | pending |
| `sdk-perf-architect-python` | D1 | pending |
| `sdk-profile-auditor-python` | M3.5 | pending |
| `sdk-soak-runner-python` | T5.5 | pending |

**B. Mirror with Python-idiomatic rename** — role transfers but the name encodes a Go-only concept.

| Go name | Python rename | Wave | Status |
|---|---|---|---|
| `sdk-leak-hunter-go` | `sdk-asyncio-leak-hunter-python` | M7 + T6 | shipped |

**C. Python-only agents** — no Go counterpart needed. Author fresh.

| Agent | Wave | Why |
|---|---|---|
| `sdk-packaging-devil-python` | D3 (Mode A) + M9 | PEP 517/518/621 pyproject.toml; wheel/sdist correctness; `py.typed` marker; namespace package handling. Go has no analog. |
| `sdk-stub-coverage-devil-python` *(optional)* | M7 | Triggered when SDK ships `*.pyi` stubs — verify completeness + signature parity with impl. |

Use Category A as the default; only deviate to B (rename) when the Go name is genuinely Go-specific (goroutines, channels, gofmt-quirks). Add to C when Python authoring exposes a gate worth its own agent. Add a "skip" entry below if a Go agent turns out to have no Python need.

**Skip list** — Go agents intentionally not mirrored in Python. (Empty at v0.5.0; populated as authoring proceeds.)

For each new Python pack agent:
1. Read the Go sibling (if any) for **structure reference only** — do not translate the body.
2. Author the body fresh: independent voice, Python-only idioms, citations into `python/conventions.yaml` by qualified name.
3. Zero Go cross-references in the body. Agent stands on its own.
4. Add to `python.json`: `agents`, the relevant `waves.<id>`, `tier_critical.<phase>.<tier>`.
5. Run `bash scripts/validate-packages.sh` — must pass.

### Wave B-3: Python-native skills + guardrails *(pending)*

**Skills (~20)**, all `python-` prefixed, at `skills/python-<name>/SKILL.md`:

```
python-asyncio-patterns                    python-pytest-fixtures
python-async-context-managers              python-pytest-parametrize
python-error-handling-patterns             python-mypy-strict-typing
python-example-function-patterns           python-pip-audit-vetting
python-async-generator-patterns            python-otel-hook-integration
python-type-hints-best-practices           python-asyncio-leak-prevention
python-pyproject-tomls                     python-bench-pytest-benchmark
python-secrets-handling                    python-context-managers-vs-decorators
python-asyncio-cancellation                python-stdlib-logging
python-protocol-vs-abc                     python-hexagonal-architecture
```

**Guardrails (~30)** — two viable shapes per script:

1. **Forked siblings** (`G30-py.sh`, `G41-py.sh`, etc.) — fastest authoring, but doubles the script count. Use when the Python tooling has a meaningfully different invocation contract from the Go side.
2. **Generalized via `scripts/run-toolchain.sh`** — preferred long-term. Existing `G30.sh` / `G41.sh` / `G60.sh` already dispatch through `run-toolchain.sh` and so serve both languages already once `python.json:toolchain` is honored. Author new gates this way unless the language semantics genuinely differ.

Mapping for the Python-side gates:

| Gate | Tool | Notes |
|---|---|---|
| `G30-py` | `python -c "import <pkg>"` | api-stub compiles smoke-test |
| `G41-py` | `python -m build` | toolchain.build |
| `G42-py` | `mypy --strict .` | toolchain.vet |
| `G43-py` | `ruff format --check .` | toolchain.fmt |
| `G48-py` | static-scan for top-level I/O | no module-level side effects |
| `G60-py` | `pytest -x` | toolchain.test |
| `G61-py` | `pytest --cov ... --cov-fail-under=90` | coverage gate |
| `G63-py` | `pytest --count=3` (pytest-repeat) | flake hunt |
| `G65-py` | `pytest-benchmark` JSON delta | benchmark regression |
| `G95–G103-py` | wraps `python-symbols.py` + `python-backend.py` | marker protocol |
| `G104–G107, G109, G110-py` | py-spy / scalene; pytest-benchmark allocs/MB | perf-confidence regime |

**Perf-budget format:**

- `docs/perf-budget-python-schema.md` — document Python-native units (seconds, MB, asyncio-tasks-leaked-per-1k-ops). Targets are TPRD-declared, not third-party-comparison.

### Wave B-4: First Python pilot run *(pending — calibration milestone)*

After B-1 / B-2 / B-3 land:

1. Author a small Python TPRD (e.g., "add a Redis client to motadatapysdk").
2. Run intake → expect Wave I1.5 to accept `§Target-Language: python` cleanly.
3. Run through full pipeline → expect every wave to dispatch only Python pack content (verified via `runs/<run-id>/context/active-packages.json`).
4. Establish first-run baselines from this real run. Lock the calibration in `baselines/python/performance-baselines.json` so future runs can regress against it.

### Verification at each wave

```bash
bash scripts/validate-packages.sh    # must PASS — orphan / duplicate / dangling = FAIL
bash scripts/run-toolchain.sh build   # must dispatch python -m build for python target_language
bash scripts/run-guardrails.sh testing <run-dir>   # python guardrails fire on python run; go guardrails skipped
```

After B-3 lands, `python.json` should have non-empty `agents` (16+) / `skills` (~20) / `guardrails` (~10–30 depending on fork-vs-generalize calls); after B-4 lands, `baselines/python/` is populated.

---

## Maintenance: adding / removing a single artifact

When you add a NEW agent / skill / guardrail in any PR:

1. Decide which manifest owns it. Default: `shared-core` if role is language-neutral, `<lang>` if role is language-specific.
2. Add the artifact's name/id to the manifest's `agents` / `skills` / `guardrails` array (alphabetical).
3. Run `scripts/validate-packages.sh` — must exit 0.
4. Commit both the artifact AND the manifest update in one PR.

When you DELETE an artifact:

1. Remove from manifest first (otherwise validate-packages.sh will FAIL with "dangling reference").
2. Remove the file.
3. Validator confirms.

When you MOVE an artifact between manifests (e.g. discovered a `shared-core` skill is actually Go-specific):

1. Update both manifests in one diff.
2. If the move surfaces generalization debt, add an entry to the destination manifest's `generalization_debt` array.

---

## The validator

`scripts/validate-packages.sh` enforces:

- Every `agents/*.md` is referenced in exactly one manifest.
- Every `skills/*/` directory is referenced in exactly one manifest.
- Every `scripts/guardrails/G*.sh` file is referenced in exactly one manifest.
- No manifest references a non-existent file (dangling).
- No artifact appears in two manifests (duplicate).

Exit codes: 0 = clean, 1 = drift, 2 = infra problem (jq missing, manifest dir missing).

Run on every PR; runs in pre-merge CI eventually (not yet wired).

---

## Baselines — partitioning contract

Every baseline file (under `baselines/`) declares a `scope` field. Every language manifest declares which baselines it owns. This is how the pipeline knows whether a given metric is intrinsically per-language (perf units, AST hashes) or genuinely cross-language (per-agent quality, per-skill stability).

**Three scope values**:

| Scope | Examples | Lives at (v0.4.0+, shipped) |
|---|---|---|
| `per-language` | `performance-baselines.json`, `coverage-baselines.json`, `output-shape-history.jsonl`, `devil-verdict-history.jsonl`, `do-not-regenerate-hashes.json`, `stable-signatures.json`, `regression-report-<run-id>.md` | `baselines/<lang>/<file>` (today: `baselines/go/<file>`) |
| `shared` | `quality-baselines.json`, `skill-health-baselines.json`, `baseline-history.jsonl` | `baselines/shared/<file>` |
| `shared-stub` | `skill-health.json` (legacy pointer at `skill-health-baselines.json`) | `baselines/shared/<file>` (likely deleted in v0.5.0) |

**JSON files** carry the `scope` field at top level (right after `pipeline_version`):

```json
{
  "schema_version": "1.0.0",
  "pipeline_version": "sdk-pipeline@0.7.0",
  "scope": "per-language",
  "language": "go",
  "scope_note": "<reason this is per-language; what units are stored>",
  ...
}
```

**JSONL files** do not carry per-line scope — classification lives only in the manifest's `baselines` block.

**Manifest declaration**:

```json
// go.json (language-adapter)
"baselines": {
  "scope_owned": "per-language",
  "owns_per_language": ["performance-baselines.json", "coverage-baselines.json", ...],
  "contributes_per_language_partition_to": []   // empty in v0.4.0; fills if D2 lands as Strict
}

// shared-core.json (core)
"baselines": {
  "scope_owned": "shared",
  "owns_shared": ["quality-baselines.json", "skill-health-baselines.json", ...]
}
```

**v0.4.0 scope** (shipped): files moved to `baselines/go/` + `baselines/shared/`; consumers (`baseline-manager`, `metrics-collector`, `learning-engine`, G81/G86/G101) updated to read partitioned paths; manifest declares ownership; `scope` field stamped on each JSON baseline.

**v0.5.0 scope** (Python pilot): adds `baselines/python/` partition with per-language baselines. Mechanical because the manifest schema is already in shape and the consumer code already path-joins on `<lang>`.

**Cross-language comparison is explicitly NOT a goal.** Each language adapter compares its perf / coverage / shape baselines against its own language's history. There is no "the Python p99 is X% slower than the Go p99" metric in v0.5.0 — that's deferred to a future research branch.

**Decisions deferred to v0.5.0+**:
- **D2** — should shared-core agents/skills with `generalization_debt` partition into `languages.<lang>` until rewritten? Defer.
- **D6** — eager rewrite of all 7 debt items vs lazy vs split? Defer; pilot Python with debt-bearers in shared and observe.

See `docs/LANGUAGE-AGNOSTIC-DECISIONS.md` for the full decision board + per-touchpoint handling table.

---

## generalization_debt — convention

When a `shared-core` artifact has a language-neutral *role* but its *body* still cites idioms of a specific language, declare it:

```json
"generalization_debt": {
  "agents": [
    {"name": "sdk-design-devil", "reason": "examples reference Go API shape; review heuristics generalize"}
  ],
  "skills": [
    {"name": "tdd-patterns", "reason": "examples use Go testing.T; TDD cycle itself is language-neutral"}
  ],
  "resolution_policy": "Flagged here so the v0.5.0 second-language pilot knows the backlog. No action required in v0.4.0. When a second language adapter is authored, each item gets either (a) a language-neutral rewrite of the prompt/body, (b) move to the <lang> package if role turns out to also be lang-specific, or (c) a split into shared + per-language parts."
}
```

This is the **single source of truth** for "what's left to do for full agnosticism." Don't track it elsewhere.

---

## Where adapter scripts will live (v0.5.0+ preview)

Today (v0.4.0): the `toolchain` block in a language-adapter manifest carries inline shell-command strings:

```json
"toolchain": { "build": "go build ./...", "test": "go test ./... -race -count=1", ... }
```

This is the right shape while there's only one adapter. Once a second adapter exists and the inline strings start growing per-language flag matrices, v0.5.0 will move them under:

```
.claude/package-manifests/
├── go.json                         # references adapter scripts via path
├── go/
│   ├── adapters/
│   │   ├── build.sh
│   │   ├── test.sh
│   │   ├── leak-check.sh
│   │   └── ...
│   ├── parsers/
│   │   ├── pprof-to-normalized.py  # pprof → neutral profile schema
│   │   └── coverage-to-normalized.py
└── python/
    └── ...
```

Adapter scripts must remain **policy-free**: emit normalized output to stdout; no threshold comparisons, no FAIL/BLOCKER strings. Policy stays in agents.

This is a v0.5.0 concern. Don't externalize in v0.4.0; the inline form is fine.

---

## Non-goals (don't do these)

- ❌ **Don't move agent / skill files into per-package directories.** Harness discovery will break.
- ❌ **Don't author runtime-synthesized manifests.** Manifests are human-authored, PR-reviewed, static at runtime (CLAUDE.md rule 23 extended).
- ❌ **Don't put threshold logic in the `toolchain` block.** Strings are commands, not policy.
- ❌ **Don't fork phase leads or orchestrators per language.** `sdk-design-lead`, `sdk-impl-lead`, `sdk-testing-lead`, `sdk-intake-agent` stay generic and dispatch from manifest data. **Do** fork language-specific sub-agents (devils, critics, language-coupled testers) — those get a `-<lang>` suffix per the Naming Convention section above. See CLAUDE.md rule 34.
- ❌ **Don't bypass `validate-packages.sh`.** The validator is the single discipline keeping manifests honest.

---

## See also

- `CLAUDE.md` rule 34 — the canonical Package Layer rule.
- `phases/INTAKE-PHASE.md` Wave I5.5 — per-run package resolution.
- `scripts/guardrails/G05.sh` — `active-packages.json` validator.
- `evolution/evolution-reports/pipeline-v0.4.0.md` — full release notes.
- `.claude/package-manifests/README.md` — manifest directory overview.
- `.claude/package-manifests/shared-core.json` / `go.json` — canonical examples.
