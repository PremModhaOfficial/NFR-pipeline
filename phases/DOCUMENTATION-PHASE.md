<!-- cross_language_ok: true — this phase is language-agnostic by design. Per-language version application is delegated via active-packages.json toolchain (Go: git tag + module path on major; Python: pyproject.toml + git tag; JS/TS: package.json + git tag; etc.). Doc templates are universal; code blocks are tagged by language. -->

# Phase 3.5: Documentation

## Purpose

After Testing PASS (H9 approved), produce developer-facing markdown docs that ship alongside the source code, and apply the run's semantic version to the source-of-truth version artifacts for the active language pack.

This phase is **strictly additive in semantics**: regenerated `README.md` / `USAGE.md` / `ARCHITECTURE.md` represent only the **current** version of the code (no deprecation warnings, no historical scaffolding). Historical motion lives in `CHANGELOG.md`. Breaking moves live in `MIGRATION.md`.

Industry standards followed:
- **CHANGELOG.md** → [Keep a Changelog 1.1](https://keepachangelog.com/en/1.1.0/) (Added / Changed / Deprecated / Removed / Fixed / Security)
- **Versioning** → [SemVer 2.0](https://semver.org/spec/v2.0.0.html)
- **README structure** → [Standard-Readme spec](https://github.com/RichardLitt/standard-readme) adapted for SDK submodules

## Trigger rule

- Runs **only after Phase 3 Testing exits PASS** (H9 approved).
- Skipped if `--phases` subset excludes `docs` OR TPRD declares `§Docs-Manifest: skip: true`.
- Mode A: always runs (new module, doc location obvious from intake).
- Mode B: runs if intake recorded a non-zero API delta (`mode.json.new_exports` non-empty OR `extension/api-diff.md` shows ≥1 added/changed/removed export).
- Mode C: runs if intake recorded an API delta. Pure refactor (no API delta) → skip docs, still bump PATCH version.

## Input

- `runs/<run-id>/intake/mode.json`
- `runs/<run-id>/intake/docs-manifest.json` (NEW — produced by Intake wave I-DOC, see INTAKE-PHASE.md)
- `runs/<run-id>/intake/version-decision.json` (NEW — produced by Intake wave I-VER, confirmed at H1)
- `runs/<run-id>/design/api.go.stub` (or per-language equivalent under design/)
- `runs/<run-id>/design/interfaces.md`, `algorithms.md`, `dependencies.md`
- `runs/<run-id>/impl/diff.md` (final implementation diff, post-H7)
- `runs/<run-id>/testing/coverage.txt`, `bench-compare.md`
- `$SDK_TARGET_DIR/<module-path>/` — existing source + any pre-existing docs
- `runs/<run-id>/context/active-packages.json` — language pack + toolchain
- TPRD §7 (Config + API), §8 (Observability), §11 (Testing — example sources), §12 (Breaking-Change Risk)

## Waves

The phase runs `D1` and `V1` **in parallel** (independent: D1 reads code → writes docs; V1 reads version decision → writes version artifacts). Both must complete before D2 can fire.

### Wave D1 — Doc Writer
**Agent**: `sdk-doc-writer`
**Mode**: parallel with V1
**Severity**: WARN on partial failure (record + continue); BLOCKER on missing `docs-manifest.json` from intake.

**Inputs read** (in this order):
1. `intake/docs-manifest.json` → target paths + which doc files to emit per target
2. `design/api.go.stub` (or lang equivalent) → exported symbols, signatures
3. `impl/diff.md` → what was added / changed / removed
4. `intake/mode.json` → Mode A | B | C
5. Existing docs at `$SDK_TARGET_DIR/<target>/README.md` etc. (if present) → for additive-regen guard
6. TPRD §7 / §8 / §11 → API surface, observability hooks, declared example sources
7. Test files matching `*_test.*` (Go: `*_test.go`, Python: `test_*.py` / `*_test.py`, JS: `*.test.ts` / `*.spec.ts`) → mineable code samples

**Outputs (per target declared in docs-manifest.json)**:

| File | Always emit? | Content |
|---|---|---|
| `README.md` | yes | Module-level intro + install + quick example + link to USAGE / ARCHITECTURE / CHANGELOG. Industry-standard structure (badges optional, intro, install, usage, API surface, links). **Current version only — no deprecated content.** |
| `USAGE.md` | yes | Task-oriented examples covering each public entry point. Code blocks lifted from `*_test.go` / `*_test.py` / `*.test.ts` (real, compile-checked) or synthesized from `api.go.stub` if no test fixture exists. **Do not author new files under `<module>/examples/` solely to populate USAGE.md** — only mine an `examples/` dir if (a) TPRD §11 listed it, or (b) the user explicitly opted in via `§Docs-Manifest: examples_allowed: true`. |
| `ARCHITECTURE.md` | yes | Internal layout: package/module map, key interfaces (from `interfaces.md`), concurrency model (from `algorithms.md`), dependency graph (from `dependencies.md`), observability hooks (from TPRD §8). Diagrams as ASCII or mermaid fenced blocks. **Current version only.** |
| `CHANGELOG.md` | yes | Keep-a-Changelog format. Entry header: `## [<semver>] — <YYYY-MM-DD>` from `version-decision.json`. Sub-sections only for non-empty buckets among Added / Changed / Deprecated / Removed / Fixed / Security. Pre-existing CHANGELOG: **append new entry at top** (most-recent-first per spec); never rewrite past entries. |
| `MIGRATION.md` | conditional | Emit ONLY if `version-decision.json.bump == "MAJOR"` OR TPRD §12 declares any item with `breaking: true`. One section per breaking change: before / after code blocks + migration steps. Pre-existing file: append new section at top under a `## v<new-semver>` header. |

**Additive-regen guard** (anti-regression):
For Mode B/C where docs already exist, after generating new content:
1. Diff old README/USAGE/ARCHITECTURE against new.
2. For every section/symbol present in old but missing from new:
   - Cross-check against `impl/diff.md`. If the missing item corresponds to a removed export AND `version-decision.json.bump == "MAJOR"` (legitimate removal): drop is allowed.
   - Otherwise: BLOCKER (`additive-regen-violation`). Re-prompt agent with explicit list of items to retain. Max 3 retries → escalate.
3. Removals recorded in CHANGELOG → `### Removed`. Never recorded as deprecation warnings inside README/USAGE/ARCHITECTURE.

**No deprecation banners** in README / USAGE / ARCHITECTURE. Those files represent **only the current version**. If a thing was removed, it is gone from the current docs; its tombstone lives in CHANGELOG (Removed) and MIGRATION (if breaking).

**Skip flag**: if TPRD `§Docs-Manifest: skip: true`, agent emits `runs/<run-id>/docs/skip-reason.md` and exits PASS without writing target docs.

**No examples authoring**: `sdk-doc-writer` MUST NOT create new files under any `examples/` directory in the target SDK. Examples directory is owned by code authorship (impl phase or TPRD-declared examples), not docs.

**Output**:
- `$SDK_TARGET_DIR/<target>/README.md` etc. (in-place writes on the run branch)
- `runs/<run-id>/docs/diff.md` — list of doc files written/modified, with diff per file
- `runs/<run-id>/docs/manifest.json` — `{ targets: [...], files_written: [...], skipped_reasons: [...] }`
- `runs/<run-id>/docs/regen-guard-report.md` — additive-regen guard verdict per modified file

### Wave V1 — Version Applier
**Agent**: `sdk-version-applier`
**Mode**: parallel with D1
**Severity**: BLOCKER on toolchain mismatch or version-artifact write failure.

**Inputs**:
- `intake/version-decision.json` — `{ "current": "1.3.0", "next": "1.4.0", "bump": "MINOR", "reasoning": "...", "user_confirmed_at": "<ISO>" }`
- `context/active-packages.json` → resolves `toolchain.version_artifacts` (per-language list of version-of-truth files)
- `$SDK_TARGET_DIR/<module-path>/` — current version artifacts

**Per-language application matrix** (resolved from `active-packages.json` → language adapter `toolchain.version_artifacts`):

| Language | Artifacts updated |
|---|---|
| `go` | git tag `v<semver>` (via `git tag` on `sdk-pipeline/<run-id>` branch — **applied locally, not pushed**); on MAJOR (≥2): module path suffix `/v<major>` rewrite in `go.mod` + import paths; optional `version.go` const if pre-existing |
| `python` | `pyproject.toml` `[project].version`; git tag `v<semver>`; optional `__version__` in `__init__.py` if pre-existing |
| `js` / `ts` | `package.json` `version` field; git tag `v<semver>`; lockfile regen (`npm install --package-lock-only` or equivalent) |
| `rust` | `Cargo.toml` `[package].version`; git tag `v<semver>`; `Cargo.lock` regen |
| `java` | `pom.xml` `<version>` or `build.gradle` `version`; git tag `v<semver>` |
| (other) | follow language adapter's `toolchain.version_artifacts` declaration; if missing → BLOCKER, file proposal to `docs/PROPOSED-PACKAGES.md` |

**Common rules** (all languages):
- Git tag is created on the run branch only. **Never pushed.** Tag move/delete remains at the H10 reviewer's discretion.
- Major bump on a language whose adapter declares `module_path_versioning: true` (Go) MUST also rewrite the module path. Skipping = BLOCKER.
- Pre-existing source-of-truth `Version` constants are updated **only if they already exist**. The agent never invents one.
- Update is performed only after D1 reaches at least the `regen-guard` checkpoint (so docs and version stay coherent).

**Output**:
- Modified version artifacts on the run branch
- `runs/<run-id>/docs/version-applied.md` — list of artifacts touched + new git tag
- `runs/<run-id>/docs/version-artifacts.json` — machine-readable `{ tag, artifacts: [...] }`

### Wave D2 — Cross-Reference Reconciliation
**Agent**: `sdk-doc-writer` (re-invoked, lightweight)
**Mode**: sequential after D1 + V1 both PASS

After version is applied, README install snippets / USAGE imports may reference the new version. D2 patches:
- `README.md` install snippet → uses `version-decision.json.next`
- `CHANGELOG.md` top entry → confirms version header matches applied tag
- For Go major bump: import path examples → `/v<major>` form

**Output**: in-place edits + `runs/<run-id>/docs/xref-patch.md`.

### Wave D3 — Root README Update (CONDITIONAL)
**Agent**: `sdk-doc-writer` (root-edit mode)
**Mode**: sequential after D2; **skipped by default**.

The target SDK's repository-root `README.md` (e.g., `$SDK_TARGET_DIR/../README.md` for an `src/<sdk>/<module>/` layout, or `$SDK_TARGET_DIR/README.md`) typically lists modules. After a Mode A new-module run, it is usually stale.

**Behavior**:
1. Detect root README path. If absent, skip (record reason).
2. Compute proposed diff: add a new entry pointing at the new module (Mode A), or update an entry's blurb (Mode B/C with descriptor change).
3. Emit `runs/<run-id>/docs/root-readme-proposal.md` containing the diff.
4. **Do not write the root file directly.** Surface as a separate `AskUserQuestion` inside H9.5 (see Gate H9.5 below). Only on explicit user approval is the root patch applied.

This preserves "explicit permission required for root edits" (no marker tracking; consent is the gate).

### Wave H9.5 — HITL Gate (Documentation + Version)
**Lead**: `sdk-doc-writer`
**Artifact bundle**:
- `runs/<run-id>/docs/diff.md` — every doc file changed
- `runs/<run-id>/docs/regen-guard-report.md`
- `runs/<run-id>/docs/version-applied.md`
- `runs/<run-id>/docs/root-readme-proposal.md` (if D3 produced one)

**Primary question** (`AskUserQuestion`):

> Phase 3.5 produced docs + version `<bump>` to `<next>`. Approve docs, version, and (if proposed) root README update?

| Option | Effect |
|---|---|
| Approve all | Docs + version stay; if root proposal exists, root patch applied |
| Approve docs/version, skip root | Root README left untouched |
| Revise docs | Re-run D1 with reviewer notes; max 3 revisions |
| Reject | Roll back doc files + version artifacts on the run branch (reset paths listed in `manifest.json` + `version-artifacts.json`); proceed to Feedback without docs |

**Default on timeout (24h)**: Revise docs.

## Failure modes & exit semantics

| Failure | Severity | Effect |
|---|---|---|
| Missing `intake/docs-manifest.json` | BLOCKER | Halt phase; require Intake re-run |
| Missing `intake/version-decision.json` | BLOCKER | Halt phase; require Intake re-run |
| `additive-regen-violation` after 3 retries | WARN | Surface in H9.5 with explicit removed-section list; user decides |
| Version artifact write failure (e.g., `pyproject.toml` malformed) | BLOCKER | Halt phase; record in `version-applied.md` |
| Root README diff fails to apply cleanly | WARN | Skip root patch; user gets advisory in H9.5 |
| H9.5 reject | normal | Proceed to Feedback with documents rolled back; record in `decision-log.jsonl` |

**No new exit code.** Doc-pass failures degrade rather than halt the run; only a missing intake artifact (configuration error) halts.

## Exit artifacts

- `$SDK_TARGET_DIR/<target>/README.md` (per target; may be multiple)
- `$SDK_TARGET_DIR/<target>/USAGE.md`
- `$SDK_TARGET_DIR/<target>/ARCHITECTURE.md`
- `$SDK_TARGET_DIR/<target>/CHANGELOG.md`
- `$SDK_TARGET_DIR/<target>/MIGRATION.md` (only when breaking)
- Updated version artifacts (per language matrix)
- `runs/<run-id>/docs/manifest.json`
- `runs/<run-id>/docs/diff.md`
- `runs/<run-id>/docs/regen-guard-report.md`
- `runs/<run-id>/docs/version-applied.md`
- `runs/<run-id>/docs/version-artifacts.json`
- `runs/<run-id>/docs/xref-patch.md`
- `runs/<run-id>/docs/root-readme-proposal.md` (conditional)
- `runs/<run-id>/state/run-manifest.json` updated with `phase: docs` completion

## Metrics

- `docs_files_written`
- `docs_targets_count`
- `docs_regen_guard_violations` (target 0)
- `version_bump` (`PATCH` | `MINOR` | `MAJOR`)
- `version_artifacts_touched`
- `docs_duration_sec` (typical ~3 min Mode A, ~2 min Mode B/C)

## Guardrails (exit gate)

- **G70** (NEW): every README emitted has all standard-readme top-level headings populated
- **G71** (NEW): CHANGELOG entry present for the run's version with non-empty body
- **G72** (NEW): MIGRATION.md present iff bump == MAJOR or any §12 item is breaking
- **G73** (NEW): no deprecation language (`deprecated`, `legacy`, `removed in`) in README / USAGE / ARCHITECTURE
- **G74** (NEW): `version-applied.md` lists ≥1 artifact (no-op runs blocked unless `bump == "PATCH"` AND impl/diff is empty)
- **G75** (NEW): no new files written under `<target>/examples/` unless declared in TPRD §11 or `§Docs-Manifest: examples_allowed: true`

## Typical durations

- Mode A (new module): ~3 min — full doc set authored from scratch
- Mode B (extend): ~2 min — additive regen + CHANGELOG entry
- Mode C (refactor with API delta): ~2 min — additive regen + CHANGELOG + (maybe) MIGRATION
- Mode C (pure refactor, no API delta): skipped; PATCH version applied only by V1 (~10s)
