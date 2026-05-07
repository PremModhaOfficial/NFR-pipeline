# Phase 0: Intake

## Purpose

Turn the human-authored TPRD (detailed, including `§Skills-Manifest` and `§Guardrails-Manifest`) into a canonical, validated spec. Validate that every required skill + guardrail exists on disk **before** any design work starts. Ask clarifying questions only for unresolved ambiguities in functional/NFR sections.

This pipeline is **NFR-driven**: every run produces an API + tests that hits numeric targets declared in TPRD §5 NFR and §Benchmarks. Intake is the single pre-design contract check.

## Trigger rule

Always runs — there is no bootstrap phase. A complete `--spec <file>` may reduce clarifications to zero, but manifest validation (I2 + I3) always executes.

## Input

- `--spec <path>` or NL request → seeds `runs/<run-id>/tprd.md`
- `$SDK_TARGET_DIR` tree (read-only)
- `skills/skill-index.json` (static, human-curated)
- `scripts/guardrails/` directory listing (for guardrail existence check)

## Waves

### Wave I1 — Ingest
**Agent**: `sdk-intake-agent`
- NL input: drafts TPRD skeleton (14 sections + Skills-Manifest + Guardrails-Manifest), infers what it can
- `--spec`: loads file, flags missing sections / `[ambiguous]` / `TBD` / `?`
- Output: `runs/<run-id>/tprd.md`

### Wave I2 — §Skills-Manifest Validation (NEW)
**Agent**: `sdk-intake-agent`
**Severity**: WARN on miss — pipeline continues; misses filed to `docs/PROPOSED-SKILLS.md`
**Purpose**: Every skill declared in TPRD §Skills-Manifest should exist in `skills/skill-index.json` at version ≥ required. Missing / under-versioned skills produce a warning but NEVER halt the run — skill authorship is a human PR concern, not a pipeline blocker.

**Check**:
```
for entry in tprd.skills_manifest:
    if entry.name not in skill_index.skills: -> WARN (file to PROPOSED-SKILLS.md)
    if skill_index[entry.name].version < entry.min_version: -> WARN (file to PROPOSED-SKILLS.md)
```

**Output**: `runs/<run-id>/intake/skills-manifest-check.md`
- PASS: all present at required version → proceed
- WARN: list of missing / under-versioned skills → pipeline continues
  - Auto-files each miss to `docs/PROPOSED-SKILLS.md` with `status: proposed`, source = `run-id`
  - Human may author skill PR at leisure; run is not blocked

**No auto-synthesis.** Agent never writes `SKILL.md` bodies.

### Wave I3 — §Guardrails-Manifest Validation (NEW)
**Agent**: `sdk-intake-agent`
**Severity**: BLOCKER on miss — pipeline halts (exit 6)
**Purpose**: Every guardrail declared in TPRD §Guardrails-Manifest must have an executable script in `scripts/guardrails/`.

**Check**:
```
for g_id in tprd.guardrails_manifest:
    if not scripts/guardrails/<g_id>.sh exists and +x: -> BLOCKER
```

**Output**: `runs/<run-id>/intake/guardrails-manifest-check.md`
- PASS: proceed
- FAIL: list missing scripts → halt; file under `docs/PROPOSED-GUARDRAILS.md` for human authoring

### Wave I4 — Clarification Loop
**Agent**: `sdk-intake-agent` (iterative)

Only runs when I1 found residual ambiguity after the TPRD parse. For each ambiguous field:
- Emit `AskUserQuestion` with 2-4 options
- Record answer as `decision` entry in decision log
- Max **5** questions (down from 7 — the TPRD is expected to be detailed)
- Exceeding 5 = `ESCALATION: TPRD underspecified` + halt

Typical triggers (rare with detailed TPRD): package placement fine-tuning, open ambiguity flags (`[AMBIGUITY] OQ-*`) from TPRD §14.

### Wave I5 — Mode Detection
Based on §1 Request Type, set `mode: A|B|C` in manifest. Mode B and C gate Phase 0.5.

### Wave I5.5 — Package Resolution (NEW in v0.4.0)
**Agent**: `sdk-intake-agent`
**Severity**: BLOCKER on dependency-resolution failure
**Purpose**: Resolve which package manifests apply to this run, and freeze the agent/skill/guardrail set the rest of the pipeline is allowed to invoke.

**TPRD optional fields** (all default to Go; backwards-compatible):

| Field | Default | Meaning |
|---|---|---|
| `§Target-Language` | `go` | Primary language adapter package required for this run. Must match a manifest in `.claude/package-manifests/<lang>.json`. |
| `§Target-Tier` | `T1` | Pipeline tier — `T1`=full perf gates (alloc/profile/soak/complexity), `T2`=skeleton+governance (build/test/lint/supply-chain only), `T3`=out-of-scope. |
| `§Required-Packages` | `["shared-core@>=1.0.0", "<§Target-Language>@>=1.0.0"]` | Override list. Advanced; rarely set explicitly. |

**Resolution algorithm**:
1. Parse `§Target-Language` (default `go`), `§Target-Tier` (default `T1`), `§Required-Packages` (default derived as above).
2. For each declared package: verify `.claude/package-manifests/<name>.json` exists; verify version satisfies declared semver range; recursively resolve `depends`.
3. Compute the union of `agents`, `skills`, `guardrails` arrays across all resolved manifests → the run's **active set**.
4. Write `runs/<run-id>/context/active-packages.json` (canonical artifact downstream agents read).
5. Write `runs/<run-id>/context/toolchain.md` (informational digest of the language adapter's `toolchain` block).

**Failure modes**:
- Manifest missing → BLOCKER (file `docs/PROPOSED-PACKAGES.md` entry; halt with exit 7).
- Version range unsatisfiable → BLOCKER.
- Circular `depends` → BLOCKER.

**Output**: `runs/<run-id>/context/active-packages.json`, `runs/<run-id>/context/toolchain.md`.

### Wave I-DOC — Documentation Target Resolution (NEW)
**Agent**: `sdk-intake-agent`
**Severity**: BLOCKER on unresolved ambiguity at H1 timeout (default Revise).
**Purpose**: Decide which target paths inside `$SDK_TARGET_DIR` will receive the doc bundle (README / USAGE / ARCHITECTURE / CHANGELOG / MIGRATION) produced by Phase 3.5.

**Resolution algorithm**:
1. If TPRD declares `§Docs-Manifest` with `targets: [...]` → use as-is.
2. Else if Mode A → infer `targets = [<new-module-path-from-mode.json>]`. Doc location is the new module dir; no question.
3. Else (Mode B/C) → consult `mode.json.target_package`. If unambiguous (single dir touched per `extension/api-diff.md` or §1 scope), set targets = that one path; record inference.
4. Else (Mode B/C, multiple plausible targets, or no clear scope) → emit `AskUserQuestion` at H1 with up to 4 candidate paths derived from impl scope.

**TPRD optional section**:

```markdown
## §Docs-Manifest
targets:
  - src/<sdk>/<module>/
skip: false                # if true, Phase 3.5 D1 wave is skipped entirely
examples_allowed: false    # if true, doc-writer may mine an examples/ dir already in scope; never authors new examples
```

**Output**: `runs/<run-id>/intake/docs-manifest.json`
```json
{ "targets": ["..."], "skip": false, "examples_allowed": false, "source": "tprd|inferred|user-confirmed" }
```

### Wave I-VER — Versioning Decision (NEW)
**Agent**: `sdk-intake-agent`
**Severity**: BLOCKER on unconfirmed inference at H1 timeout.
**Purpose**: Decide the SemVer bump and resulting version that Phase 3.5 V1 will stamp onto the active language pack's version artifacts.

**Resolution algorithm**:
1. Read current version from the active language pack's primary version artifact (resolved via `context/active-packages.json` → `toolchain.version_artifacts[0]`). Examples: latest `git tag` matching `v*`, `pyproject.toml [project].version`, `package.json version`.
2. If TPRD declares `§Versioning` with explicit `bump:` and/or `next:` → use as-is, skip inference.
3. Else infer `bump`:
   - `MAJOR` if §12 lists any `breaking: true` item OR removes/renames an existing public symbol.
   - `MINOR` if §1 declares Mode A (new module) OR §7 adds new public symbols without breakage.
   - `PATCH` otherwise (Mode C refactor, internal-only changes).
4. Compute `next = increment(current, bump)`.
5. Always emit `AskUserQuestion` at H1 with the inference + reasoning unless `§Versioning.confirmed: true` is present in TPRD. User options: Confirm / Override (free-form semver) / Set to PATCH / Set to MINOR / Set to MAJOR.

**TPRD optional section**:

```markdown
## §Versioning
current: 1.3.0           # optional override; usually inferred from artifact
bump: MINOR              # PATCH | MINOR | MAJOR (optional; inferred if absent)
next: 1.4.0              # optional override; usually computed from current + bump
confirmed: false         # if true, skip H1 confirmation question
reasoning: "..."         # optional human note attached to changelog entry
```

**Output**: `runs/<run-id>/intake/version-decision.json`
```json
{ "current": "1.3.0", "next": "1.4.0", "bump": "MINOR", "reasoning": "...", "source": "tprd|inferred|user-confirmed", "user_confirmed_at": "<ISO>" }
```

### Wave I6 — Completeness Check
**Agent**: `sdk-intake-agent`
Runs `spec-completeness-guardrail` (G20 + G21):
- All 14 TPRD sections non-empty
- §Skills-Manifest and §Guardrails-Manifest non-empty (NEW)
- `[ambiguous]` / `TBD` / `?` count = 0
- §Non-Goals populated

FAIL → back to I4; else → I7.

### Wave I7 — HITL Gate H1 (TPRD Acceptance)
**Lead**: `sdk-intake-agent`
**Artifact**: canonical `runs/<run-id>/tprd.md` + manifest-check reports + `docs-manifest.json` + `version-decision.json`
**Sub-questions** (only emitted when not pre-resolved):
- Doc targets — fired by I-DOC step 4 (Mode B/C ambiguity only)
- Version bump confirmation — fired by I-VER unless `§Versioning.confirmed: true`
**Options**: Approve / Revise / Cancel
**Default**: Revise (timeout 24h)
**Bypass**: `--auto-approve-tprd` (CI only; still requires I2 + I3 PASS, and forces I-VER inference to `confirmed: true` with a logged warning if no §Versioning declaration is present)

## Exit artifacts

- `runs/<run-id>/tprd.md` — canonical, all sections + both manifests non-empty
- `runs/<run-id>/intake/skills-manifest-check.md` — PASS or WARN verdict (never halts pipeline; misses filed to `docs/PROPOSED-SKILLS.md`)
- `runs/<run-id>/intake/guardrails-manifest-check.md` — PASS verdict (FAIL halts pipeline with exit 6)
- `runs/<run-id>/intake/clarifications.jsonl` — every Q + A (may be empty for detailed TPRDs)
- `runs/<run-id>/intake/mode.json` — `{ "mode": "A|B|C", "target_package": "...", "new_exports": [...] }`
- `runs/<run-id>/intake/docs-manifest.json` (NEW) — doc target paths, skip flag, examples policy; consumed by Phase 3.5 D1
- `runs/<run-id>/intake/version-decision.json` (NEW) — semver bump + next + reasoning; consumed by Phase 3.5 V1
- `runs/<run-id>/context/active-packages.json` (NEW v0.4.0) — resolved package set for this run; consumed by phase leads + guardrail-validator
- `runs/<run-id>/context/toolchain.md` (NEW v0.4.0) — language adapter's toolchain digest; informational
- `runs/<run-id>/state/run-manifest.json` updated with intake completion

## Metrics

- `user_clarifications_asked` (target 0 with detailed TPRD; >3 = spec-quality issue → `improvement-planner`)
- `intake_duration_sec`
- `manifest_misses_skills`, `manifest_misses_guardrails` (both target 0)

## Guardrails

G20 (all 14 sections + 2 manifests non-empty), G21 (§Non-Goals populated), G22 (clarifications ≤3 — info only), **G23 (§Skills-Manifest validation, WARN)**, **G24 (§Guardrails-Manifest validation, BLOCKER)**, **G05 (v0.4.0: active-packages.json valid + resolves, BLOCKER)**.

## Example flows

### Flow 1: Detailed TPRD submitted (expected path)
Input: `--spec runs/nats-v1-tprd.md` (complete, with both manifests)
- I1: load TPRD; 14 sections + 2 manifests present
- I2: all 12 required skills present at version ≥ declared → PASS
- I3: all 9 guardrails scripts present → PASS
- I4: 0 clarifications (TPRD is detailed)
- I6: completeness PASS
- I7: H1 approve
- Duration: <20s

### Flow 2: TPRD missing a required skill (non-blocking)
Input: `--spec runs/redis-streams-tprd.md` (declares `redis-pipeline-tx-patterns` v1.0.0)
- I1: load
- I2: `redis-pipeline-tx-patterns` not in `skill-index.json` → WARN (non-blocking)
  - Auto-files entry to `docs/PROPOSED-SKILLS.md` with status `proposed` + reason
  - `runs/<run-id>/intake/skills-manifest-check.md` records `Status: WARN`
- I3: guardrails all present → PASS
- Pipeline proceeds through design / impl / testing / feedback
- Human may author skill + PR at leisure; future runs pick it up automatically. No re-run required for the current run to complete.

### Flow 3: NL one-liner (degenerate path, discouraged)
Input: `"add S3 client"` (no TPRD)
- I1: drafts TPRD skeleton; flags all sections as `TBD`
- I4: asks ~5 clarifying questions (placement, SDK version, encryption, retry, bench)
- Completeness FAIL → return to I4 up to cap
- If cap exceeded: halt with `ESCALATION: TPRD underspecified`
- **Recommended**: author detailed TPRD off-pipeline and re-submit via `--spec`.
