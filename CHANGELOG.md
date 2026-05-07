# Changelog

All notable changes to the **motadata-sdk-pipeline** plugin are recorded here.
Format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

This file tracks the **plugin's own history**. Per-module SDK changelogs produced by Phase 3.5 (`sdk-doc-writer`) live next to the source code at `<target>/CHANGELOG.md` and are independent of this file.

## [0.7.0] — 2026-05-05

### Added
- **Phase 3.5 Documentation** — new phase between Testing (H9) and Feedback. Produces per-submodule `README.md`, `USAGE.md`, `ARCHITECTURE.md`, `CHANGELOG.md` (Keep-a-Changelog 1.1) and conditional `MIGRATION.md` (only on MAJOR or breaking).
- **HITL gate H9.5** — single approval gate for docs + applied semver + optional root-README patch.
- **`sdk-doc-writer` agent** — language-agnostic developer-doc author with additive-regen guard, no-deprecation-banner rule, no-examples-authoring rule.
- **`sdk-version-applier` agent** — per-language semver applier (Go, Python, JS/TS, Rust, Java, extensible). Local git tag only; never pushed.
- **Intake waves I-DOC + I-VER** — doc-target resolution and semver inference, both gated through H1 sub-questions when ambiguous.
- **TPRD optional sections** — `§Docs-Manifest` (target paths + skip flag + examples policy) and `§Versioning` (semver bump + next + reasoning).
- **Real PostToolUse hook** — `hooks/log-bash.sh` records JSONL audit per Bash invocation to `.claude/audit/bash-events.jsonl`. Replaces the v0.6 `advisory_hooks` comment-stub.
- **Plugin packaging** — repository is now a Claude Code plugin. Manifest at `.claude-plugin/plugin.json`. Loadable via `claude plugin install` or `claude --plugin-dir .`.
- **`LICENSE` file** — Apache-2.0 (full text now present at repo root).
- **`V7-CHANGES.md`** — colleague rebase guide with LLM rebase prompt and verification checklist.
- Phase budget for `documentation` (150k tokens, 900s wall).
- `H9_5_docs` HITL timeout (24h).
- Bash permissions for doc-pass + version-applier tooling: `git tag`, `go mod tidy`, `cargo update`, `npm/pnpm/yarn install --lockfile-only`, `uv lock`, `poetry lock`, `./scripts/guardrails/*.sh`, `./hooks/*.sh`.
- `--skip-docs` and `--skip-docs-gate` CLI flags for `/run-sdk-addition`.
- New CLI escapes: `--phases docs` to re-author docs only.

### Changed
- **Repo restructured to plugin layout.** `commands/`, `agents/`, `skills/`, `hooks/` moved to repo root from `.claude/`. The `.claude/` dir retains only dev-only state (`settings.json`, `audit/`, `package-manifests/`).
- **Path references rewritten across 29 files** (`.claude/{agents,skills,commands,hooks}/` → `{agents,skills,commands,hooks}/`).
- **MCP servers moved to `.claude/settings.json`** (project-local, dev-only; not shipped). Used servers retained: `context7`, `neo4j-memory`, `code-graph`, `serena`.
- `pipeline_version` bumped to `0.7.0`.
- README install-as-plugin section added.
- `Write` permissions re-pathed to top-level dirs (`Write(skills/...)`, `Write(agents/*.md)`).

### Removed
- **Repo-root `.mcp.json`** — would have shipped MCP servers (context7, exa, neo4j-cypher, neo4j-memory, code-graph, serena) with the plugin to every consumer. Now dev-only via `.claude/settings.json`.
- **Unused MCP servers** — `exa` and `neo4j-cypher` were never invoked by any pipeline agent or skill (verified by grep across `agents/`, `skills/`, `phases/`, `commands/`). Dropped entirely.
- **`advisory_hooks` comment-stub** in `.claude/settings.json` — replaced by the real `hooks/hooks.json` registration.
- **Dead `Write(state/**)` permission** — `state/` lives under `runs/<id>/state/` (already covered by `Write(runs/**)`); the standalone path never matched.

### Security
- **Plugin distribution no longer leaks the local Neo4j credentials** that were embedded in repo-root `.mcp.json`. Those credentials still exist for dev (in `.claude/settings.json`) but do not propagate to plugin consumers.
- `Write(.claude/**)` narrowed: agents can only write `skills/<name>/SKILL.md`, `skills/<name>/evolution-log.md`, `agents/*.md`, `.claude/audit/**`, and `docs/PROPOSED-*.md`. Settings file and arbitrary `.claude/` paths no longer writable by run-time agents.

### Deferred (explicitly NOT in v0.7)
- Guardrail scripts `scripts/guardrails/G70.sh` … `G75.sh` for Phase 3.5 invariants — first run that needs them files entries to `docs/PROPOSED-GUARDRAILS.md` per existing pipeline contract.
- Doc-devil agent (review-fix loop for `sdk-doc-writer`).
- Marker-tracking in doc files (`[owned-by: MANUAL]`).
- Plugin marketplace entry (`.claude-plugin/marketplace.json`).
- End-to-end Phase 3.5 runtime test.

---

## [0.6.0] and earlier

See git history (`git log v0.6.0`).
