# V7 Change Manifest (v0.6.0 → v0.7.0)

> **Audience**: a colleague (or LLM rebase assistant) who is on v0.6.0 from `origin/main` and needs to rebase outstanding work onto v0.7.0.
>
> **Read this file as the canonical context** for what shifted between v6 and v7. Every move, addition, and contract change is enumerated. Pair it with `git log v0.6.0..v0.7.0` for line-level diffs.

---

## TL;DR

Three shifts:

1. **New phase: Phase 3.5 Documentation** — runs after Testing PASS (H9), produces per-submodule `README.md` / `USAGE.md` / `ARCHITECTURE.md` / `CHANGELOG.md` (Keep-a-Changelog 1.1) + `MIGRATION.md` on breaking. New gate **H9.5**. New parallel agents: `sdk-doc-writer` and `sdk-version-applier`.
2. **Repo restructured to Claude Code plugin layout** — `commands/`, `agents/`, `skills/`, `hooks/` are now at **repo root** (no longer under `.claude/`). New `.claude-plugin/plugin.json` manifest. The `.claude/` dir retains **only** dev-only project state (`settings.json`, `audit/`, `package-manifests/`).
3. **Real PostToolUse hook** — `hooks/log-bash.sh` writes JSONL audit trail to `.claude/audit/bash-events.jsonl`. Replaces the v0.6 `advisory_hooks` comment-stub.

---

## File-by-file delta

### NEW files (introduced in v0.7)

| Path | Purpose |
|---|---|
| `.claude-plugin/plugin.json` | Claude Code plugin manifest (name, version, author). Required for plugin packaging. |
| `phases/DOCUMENTATION-PHASE.md` | Phase 3.5 spec — D1 (doc-writer) ‖ V1 (version-applier) → D2 (xref) → D3 (root proposal) → H9.5 |
| `agents/sdk-doc-writer.md` | Language-agnostic doc author (D1, D2, D3). Additive-regen guard. No deprecation banners. Never authors `examples/`. |
| `agents/sdk-version-applier.md` | Per-language semver applier (V1). Git tag + per-language version artifacts (Go, Py, JS/TS, Rust, Java, extensible). Local tag only — never pushed. |
| `hooks/log-bash.sh` | PostToolUse Bash hook. Appends one JSONL event per Bash call. Failures never block runs. |
| `hooks/hooks.json` | Plugin-canonical hook registration (matcher + command). Loaded by Claude Code when plugin is installed or via `claude --plugin-dir .`. |
| `V7-CHANGES.md` | This file. |

### MOVED files (location changed; content preserved unless noted)

| Old path (v0.6) | New path (v0.7) | Notes |
|---|---|---|
| `commands/run-sdk-addition.md` | `commands/run-sdk-addition.md` | Path unchanged at root, BUT now meaningful (it was previously invisible to the harness because Claude Code only auto-discovers commands under `.claude/commands/` or as part of a plugin at the plugin root — v0.7 adds the plugin manifest, so the harness now picks them up). Content also patched (see "edited" section). |
| `commands/preflight-tprd.md` | `commands/preflight-tprd.md` | Same as above. |
| `.claude/agents/<*>.md` (~80 files) | `agents/<*>.md` | Bulk move via `mv`. Frontmatter unchanged. |
| `.claude/skills/<name>/{SKILL.md,evolution-log.md}` (~50 dirs) | `skills/<name>/{SKILL.md,evolution-log.md}` | Bulk move. `skills/skill-index.json` also moved. |

### EDITED files (existing files with v0.7 changes)

| Path | What changed |
|---|---|
| `.claude/settings.json` | (1) `pipeline_version` 0.6.0 → 0.7.0. (2) added `phase_budgets.documentation` (150k tokens, 900s wall). (3) added `hitl_gate_timeouts_hours.H9_5_docs: 24`. (4) Bash perms expanded for doc-pass / version-applier tooling: `git tag`, `go mod tidy`, `cargo update`, `npm/pnpm/yarn install --lockfile-only`, `uv lock`, `poetry lock`, `./scripts/guardrails/*.sh`, `./hooks/*.sh`. (5) Write perms re-pathed: `Write(.claude/skills/...)` → `Write(skills/...)`, same for agents. Dropped dead `Write(state/**)` (never matched). (6) v0.6 `advisory_hooks` comment-stub replaced by `_hooks_note` pointer to `hooks/hooks.json`. |
| `phases/INTAKE-PHASE.md` | Added two new waves: **I-DOC** (doc-target resolution; emits `runs/<id>/intake/docs-manifest.json`) and **I-VER** (semver inference + H1 confirmation; emits `runs/<id>/intake/version-decision.json`). Wave I7 (HITL H1) now includes optional sub-questions: doc-targets ambiguity (Mode B/C only) + version-bump confirmation (unless `§Versioning.confirmed: true`). Exit-artifacts list extended. |
| `phases/TESTING-PHASE.md` | (No structural change in v0.7; still produces same artifacts. Phase 3.5 reads them.) |
| `phases/FEEDBACK-PHASE.md` | (No structural change.) |
| `LIFECYCLE.md` | Phase 3.5 inserted in the lifecycle ASCII diagram between H9 and Phase 4. New row `H9.5` in HITL gate table. New `runs/<id>/docs/` block in artifacts map. New loop caps (additive-regen retries=3, doc revision retries=3). New summary table entries (`--skip-docs`, `--phases docs`, `§Versioning`, `§Docs-Manifest`). Path refs `.claude/skills/skill-index.json` → `skills/skill-index.json`. |
| `commands/run-sdk-addition.md` | (1) Default `--phases` now includes `docs`. (2) New flags `--skip-docs`, `--skip-docs-gate`. (3) Phase list narration adds Documentation paragraph. (4) `Delegates to` chain updated: `... → sdk-testing-lead → sdk-doc-writer ‖ sdk-version-applier → learning-engine`. |
| `commands/preflight-tprd.md` | Path refs to `skills/skill-index.json` rewritten. |
| `PIPELINE-OVERVIEW.md` | `commands/...` paths rewritten to `commands/...` (was already at root, but now indexed because plugin layout makes them discoverable). |
| `docs/TPRD-TEMPLATE.md` | Preflight contract path rewritten. (TPRD optional sections `§Docs-Manifest` and `§Versioning` are described in INTAKE-PHASE.md; consider adding to the template if desired.) |
| `docs/PROPOSED-GUARDRAILS.md` | Reference to `commands/run-sdk-addition.md` path rewritten. |
| `docs/PROPOSED-SKILLS.md`, `docs/PROPOSED-PROCESS.md`, `docs/PACKAGE-AUTHORING-GUIDE.md`, `docs/LANGUAGE-AGNOSTIC-DECISIONS.md`, `docs/NEO4J-KNOWLEDGE-GRAPH.md` | Path refs rewritten by bulk sed (`.claude/{agents,skills,commands,hooks}/` → `{agents,skills,commands,hooks}/`). |
| `AGENTS.md`, `AGENT-CREATION-GUIDE.md`, `SKILL-CREATION-GUIDE.md`, `README.md`, `CLAUDE.md` (if it had stale paths), `migration-findings.md` | Same path-ref rewrite. |
| `agents/sdk-skill-drift-detector.md`, `agents/learning-engine.md`, `agents/improvement-planner.md`, `agents/sdk-intake-agent.md` | Internal path refs rewritten. |
| `skills/api-ergonomics-audit/SKILL.md`, `skills/go-backpressure-flow-control/SKILL.md`, `skills/go-backpressure-flow-control/evolution-log.md`, `skills/go-tdd-patterns/evolution-log.md`, `skills/go-idempotent-retry-patterns/evolution-log.md`, `skills/go-api-ergonomics-patterns/evolution-log.md`, `skills/mcp-knowledge-graph/SKILL.md`, `skills/skill-index.json`, `.claude/package-manifests/README.md` | Same path-ref rewrite (where they referenced sibling assets via `.claude/{agents,skills,...}/`). |

### UNCHANGED but conceptually relevant

| Path | Why mentioned |
|---|---|
| `.claude/settings.json` (location) | Stays under `.claude/` — this is dev-only project config, not part of the plugin distribution. Plugin consumers do not get this file. |
| `.claude/audit/` | Created at runtime by `hooks/log-bash.sh`. Local-only, never shipped, never committed. |
| `.claude/package-manifests/` | Pipeline-internal data store (language adapter manifests). Stays under `.claude/` because it is pipeline runtime input, not a Claude Code asset. |
| `.mcp.json` | Already at repo root in v0.6. With v0.7 plugin layout, it now also functions as the plugin's MCP server registration. **Consumer-impact**: anyone installing the plugin gets these MCP servers (context7, exa, neo4j-cypher, neo4j-memory). If teammates don't want them, move to project `.claude/settings.json` instead. |
| `phases/DESIGN-PHASE.md`, `phases/IMPLEMENTATION-PHASE.md` | No phase changes for v0.7. Existing waves untouched. |
| `scripts/guardrails/G*.sh` | Unchanged. New guardrails G70–G75 declared in DOCUMENTATION-PHASE.md but not yet implemented as scripts (file proposals expected on first run, per existing pipeline contract). |

---

## Contract changes (semantic)

### New TPRD optional sections

```markdown
## §Docs-Manifest                # consumed by INTAKE-PHASE.md wave I-DOC
targets:
  - src/<sdk>/<module>/
skip: false
examples_allowed: false

## §Versioning                   # consumed by INTAKE-PHASE.md wave I-VER
current: 1.3.0                   # optional; auto-detected if absent
bump: MINOR                      # PATCH | MINOR | MAJOR; inferred if absent
next: 1.4.0                      # optional; computed from current+bump
confirmed: false                 # if true, skip H1 confirmation question
reasoning: "..."                 # appended to changelog entry
```

If a TPRD authored under v0.6 is replayed under v0.7 without these sections: I-DOC infers from Mode A (no question) or asks at H1 (Mode B/C ambiguous); I-VER infers from §12 / mode and confirms at H1.

### New HITL gate H9.5 (Documentation)

| Field | Value |
|---|---|
| Phase | 3.5 (Documentation) |
| Lead agent | `sdk-doc-writer` |
| Artifact bundle | `runs/<id>/docs/diff.md`, `regen-guard-report.md`, `version-applied.md`, `root-readme-proposal.md` (if any) |
| Options | Approve all / Approve docs+version, skip root / Revise (max 3) / Reject |
| Default on timeout | Revise (24h) |

### Run-artifact map additions

```
runs/<run-id>/
├── intake/
│   ├── docs-manifest.json        ← NEW v0.7 (I-DOC output)
│   └── version-decision.json     ← NEW v0.7 (I-VER output)
├── docs/                         ← NEW v0.7 (Phase 3.5 output)
│   ├── manifest.json
│   ├── diff.md
│   ├── regen-guard-report.md
│   ├── version-applied.md
│   ├── version-artifacts.json
│   ├── xref-patch.md
│   └── root-readme-proposal.md   (conditional)
```

### Doc-pass invariants (read-once if you author docs anywhere in the pipeline)

1. README / USAGE / ARCHITECTURE represent **only the current version**. Strings `deprecated`, `legacy`, `will be removed`, `removed in`, `obsolete` are forbidden in those three files. Tombstones go in CHANGELOG (`### Removed`) and (if breaking) MIGRATION.md.
2. **Additive-regen guard**: a regen MUST NOT silently drop a section/symbol that was in the old doc and still has a counterpart in the current code. If a guard violation is unresolved after 3 retries, it surfaces in H9.5 for user decision.
3. **No examples authoring** by `sdk-doc-writer`. Examples may be MINED from `*_test.*` files (always) or from a pre-existing `examples/` dir (only if `§Docs-Manifest.examples_allowed: true`). Creating new files under any `examples/` / `samples/` / `demo` dir is forbidden in this phase.
4. **CHANGELOG**: Keep-a-Changelog 1.1. Header `## [<next>] — <YYYY-MM-DD>`. Sections only for non-empty buckets. Past entries never rewritten — new entry inserted directly under the `# Changelog` H1.
5. **MIGRATION.md** appears iff `bump == MAJOR` OR any TPRD §12 item has `breaking: true`.
6. **Version artifacts** (V1) — language-agnostic via `active-packages.json` → `toolchain.version_artifacts`. Git tag is created locally, never pushed. Module-path rewrite (Go MAJOR ≥ 2) is mandatory when the language adapter declares `module_path_versioning: true`.

---

## Plugin distribution

After v0.7 the repo is a Claude Code plugin. Consumers can:

```bash
# Install via marketplace OR direct from git
claude plugin install <marketplace>/motadata-sdk-pipeline

# Local dev inside this repo (developer / pipeline maintainer):
claude --plugin-dir .
```

When invoked via `--plugin-dir .` (or after install), the harness automatically discovers:

- Slash commands → `commands/*.md`
- Subagents → `agents/*.md`
- Skills → `skills/<name>/SKILL.md`
- Hooks → `hooks/hooks.json` (PostToolUse Bash → `hooks/log-bash.sh`)
- MCP servers → `.mcp.json`

Project dev-only state (`.claude/settings.json`, `.claude/audit/`, `.claude/package-manifests/`) is NOT shipped as part of the plugin. Plugin consumers configure their own project-level settings.

---

## Hook behavior (v0.7 vs v0.6)

| Aspect | v0.6 | v0.7 |
|---|---|---|
| Declaration | `settings.json.advisory_hooks` (a comment object — not a real hook) | `hooks/hooks.json` (real `PostToolUse` matcher) |
| Bash audit | None — agents had to self-log via prompt instructions | Hook fires after every Bash call; appends JSONL to `.claude/audit/bash-events.jsonl` |
| Per-run rollup | N/A | Phase lead slices `bash-events.jsonl` by `runs/<id>/state/run-manifest.json` start/end timestamps. (Slicing logic is the lead's responsibility — no separate runtime tool.) |
| Failure semantics | N/A | Hook script `set -euo pipefail` but always `exit 0` — failures must never block a run |

Schema of one event:

```json
{
  "ts": "2026-05-05T10:23:14Z",
  "session_id": "...",
  "hook_event_name": "PostToolUse",
  "tool_name": "Bash",
  "command": "go test ./...",
  "description": "Run unit tests",
  "exit_code": 0,
  "stdout_bytes": 1872,
  "stderr_bytes": 0,
  "interrupted": false
}
```

---

## Rebase guidance

If you have local v0.6 work in flight, the rebase strategy depends on what it touches:

| Your work touches | Rebase action |
|---|---|
| Files **inside** `.claude/agents/`, `.claude/skills/`, `.claude/commands/`, `.claude/hooks/` | Move them to the new top-level dir (`agents/`, `skills/`, `commands/`, `hooks/`) **before** rebasing — otherwise git will see them as adds in the old location and the v0.7 deletes will conflict. |
| File **content** referencing `.claude/{agents,skills,commands,hooks}/` paths | Run the same bulk sed v0.7 ran: `sed -i 's|\.claude/agents/|agents/|g; s|\.claude/skills/|skills/|g; s|\.claude/commands/|commands/|g; s|\.claude/hooks/|hooks/|g'` on your changed `.md` / `.json` files (excluding `.claude/settings.json`, `migration-quarantine.md`, `runs/`, `baselines/`, `evolution/`). |
| `phases/INTAKE-PHASE.md` | New waves I-DOC and I-VER were inserted **before** Wave I6. If you added your own intake wave, place it relative to I5.5 / I6, not to I-DOC / I-VER. |
| `LIFECYCLE.md` | Phase 3.5 row added in the ASCII diagram. Manual merge: keep your phase additions and the v0.7 Docs row both. |
| `commands/run-sdk-addition.md` | Default `--phases` list expanded to include `docs`. If you added a flag, conflict will be in the flag table. |
| `.claude/settings.json` | Multiple v0.7 patches (version bump, new budget, new timeout, new perms, hooks-block removal). Manual three-way merge if you also touched any of those keys. |
| Phase docs other than INTAKE / TESTING | No conflict expected. |

### LLM rebase prompt (drop into a fresh Claude session)

> You are rebasing branch `<colleague-branch>` onto `v0.7.0`. The branch was forked from `v0.6.0`.
>
> Read `V7-CHANGES.md` first — it enumerates every move, addition, and contract change between v0.6 and v0.7.
>
> Strategy:
> 1. Run `git log v0.6.0..HEAD --oneline` to list the colleague's commits.
> 2. Run `git rebase v0.7.0`.
> 3. For each conflict, classify it using the "Rebase guidance" table in `V7-CHANGES.md`.
> 4. For path-rename conflicts (`.claude/agents/` → `agents/` etc.), prefer the v0.7 location: move the colleague's file to the new path and resolve.
> 5. For string-rewrite conflicts inside `.md` / `.json` files, apply the bulk sed pattern from the rebase guidance table to the colleague's hunks.
> 6. For semantic conflicts in `phases/INTAKE-PHASE.md`, `LIFECYCLE.md`, `commands/run-sdk-addition.md`, `.claude/settings.json`: do a manual three-way merge keeping both sets of additions; never delete a v0.7 wave / row / flag.
> 7. After resolving, run `python3 -c "import json; json.load(open('.claude/settings.json'))"` and `python3 -c "import json; json.load(open('skills/skill-index.json'))"` to confirm JSON validity.
> 8. Run `bash hooks/log-bash.sh < /dev/null` to confirm the hook script is executable and fault-tolerant.
> 9. Commit with `Co-Authored-By: <colleague>` preserved per commit, no rewriting their messages.
>
> Do not invent changes. If a conflict is ambiguous, surface it as a numbered question instead of guessing.

---

## Verification checklist (run after rebase)

```bash
# 1. JSON validity
python3 -c "import json; json.load(open('.claude/settings.json'))"
python3 -c "import json; json.load(open('skills/skill-index.json'))"
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"
python3 -c "import json; json.load(open('hooks/hooks.json'))"

# 2. Plugin layout invariants
test -f .claude-plugin/plugin.json && echo "plugin manifest OK"
test -d commands && test -d agents && test -d skills && test -d hooks && echo "plugin dirs OK"
test ! -d .claude/agents && test ! -d .claude/skills && echo "old dirs gone"

# 3. Hook script executable + fault-tolerant
bash hooks/log-bash.sh < /dev/null && echo "hook script OK"

# 4. No stale path refs in active docs
! grep -rE '\.claude/(agents|skills|commands|hooks)/' --include='*.md' . \
  | grep -Ev '\.git/|/runs/|/baselines/|/evolution/|migration-quarantine.md|V7-CHANGES.md' \
  | grep . && echo "no stale refs"

# 5. Phase 3.5 wired everywhere
grep -l "Phase 3.5\|H9.5\|sdk-doc-writer\|sdk-version-applier" \
  phases/DOCUMENTATION-PHASE.md \
  phases/INTAKE-PHASE.md \
  LIFECYCLE.md \
  commands/run-sdk-addition.md \
  agents/sdk-doc-writer.md \
  agents/sdk-version-applier.md
```

If any check fails, the rebase is incomplete — surface the failure and fix before merging.

---

## Out-of-scope for v0.7 (explicitly NOT done)

- Guardrail scripts `scripts/guardrails/G70.sh` … `G75.sh` for the new doc-pass rules — not yet authored. First run that needs them files entries to `docs/PROPOSED-GUARDRAILS.md` per existing pipeline contract.
- Doc-devil agent (review-fix loop for `sdk-doc-writer`) — explicitly deferred. Phase 3.5 has no devil.
- Marker-tracking in doc files (`[owned-by: MANUAL]`) — not implemented. Wholesale regen with additive-regen guard is the v0.7 protection model.
- TPRD template (`docs/TPRD-TEMPLATE.md`) does not yet contain `§Docs-Manifest` / `§Versioning` example sections; adding them is a small follow-up.
- `pipeline_version: "0.7.0"` is set in `.claude/settings.json`; a corresponding git tag `v0.7.0` is not auto-created — tag locally when merging.
