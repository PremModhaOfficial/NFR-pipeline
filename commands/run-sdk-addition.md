---
name: run-sdk-addition
description: Launch the NFR-driven SDK-addition pipeline. Accepts a detailed TPRD path or an NL request; intake validates §Skills-Manifest (WARN; non-blocking) + §Guardrails-Manifest (BLOCKER) and asks clarifying questions only for residual ambiguities. Writes to $SDK_TARGET_DIR on a dedicated branch. Never commits to main, never pushes.
user-invocable: true
---

# /run-sdk-addition

Launches the NFR-driven SDK-addition pipeline against `$SDK_TARGET_DIR` (Go SDK repo).

## Arguments

| Flag | Default | Description |
|------|---------|-------------|
| `--target <path>` | `$SDK_TARGET_DIR` env | Target Go SDK dir (must be git repo) |
| `--spec <file>` | — | Path to pre-written TPRD (recommended; must include §Skills-Manifest + §Guardrails-Manifest) |
| `--phases <list>` | `intake,design,impl,testing,docs,feedback` | Comma-separated subset to run |
| `--skip-docs` | false | Skip Phase 3.5 Documentation entirely (CI escape; runs feedback directly after testing) |
| `--skip-docs-gate` | false | Run Phase 3.5 but auto-approve H9.5 (CI only; logged) |
| `--resume <run-id>` | — | Resume a halted run from its last checkpoint in `runs/<run-id>/state/run-manifest.json` |
| `--dry-run` | false | Don't write to target; produce `preview.md` |
| `--accept-perf-regression <n>` | — | Override `sdk-benchmark-devil-go` for n% regression |
| `--auto-approve-tprd` | false | Skip H1 gate on TPRD acceptance (CI only; manifest checks still enforced) |
| `--skip-design-gate` | false | Skip H5 (risky; logged) |
| `--skip-impl-gate` | false | Skip H7 (CI only) |
| `--budget-tokens <n>` | per settings.json | Override per-phase token budget |
| `--seed <int>` | — | Determinism verification seed |

## Positional arg

`<request-or-spec-path>` — one of:
- NL string (`"add S3 client"`)
- TPRD file path (`runs/my-tprd.md`)

## Examples

```
/run-sdk-addition --target ~/projects/nextgen/motadata-go-sdk/src/motadatagosdk "add Redis streams consumer client"

/run-sdk-addition --spec runs/s3-tprd.md

/run-sdk-addition --dry-run "add Kafka consumer wrapper"

/run-sdk-addition --phases intake,design "tighten dragonfly retry defaults"

/run-sdk-addition --resume s3-v1
```

## Execution flow

1. Parse flags; resolve `$SDK_TARGET_DIR` (prompt if unset)
2. Generate `run_id` (UUID v4); create `runs/<run-id>/`
3. Load `settings.json`; stamp `pipeline_version`, budgets
4. **H0 gate** (first-time only):
   - Confirm target-dir is a git repo (exit 5 on miss)
   - Run `bash scripts/preflight-check.sh --infra-only` — checks infra-tier toolchain only (target_language not yet resolved). HARD blocker miss → exit 7; user must install missing tool before re-run. Soft / optional misses are non-blocking. See `PREREQUISITES.md`.
   - Language-pack preflight runs in intake Wave I5.5 (after `active-packages.json` resolves `§Target-Language`).
5. Run phases in order (respecting `--phases` subset):
   - Intake (TPRD canonicalization + §Skills-Manifest + §Guardrails-Manifest validation)
     - BLOCKER on missing guardrail (exit 6) → halt; file to `docs/PROPOSED-GUARDRAILS.md`
     - WARN on missing skill → file to `docs/PROPOSED-SKILLS.md`, continue (non-blocking)
   - Mode detection → if B/C, run Phase 0.5 Extension-analyze
   - Design
   - Implementation (on `sdk-pipeline/<run-id>` branch)
   - Testing
   - **Documentation (Phase 3.5)** — runs only on Testing PASS; produces README/USAGE/ARCHITECTURE/CHANGELOG (Keep-a-Changelog format) per target declared in `intake/docs-manifest.json`, MIGRATION.md on MAJOR/breaking; applies semver to per-language version artifacts (`intake/version-decision.json`); proposes optional root-README patch (never auto-applied). Skipped on `--skip-docs` or TPRD `§Docs-Manifest: skip: true`. Failures degrade rather than halt.
   - Feedback (learning-engine patches to existing skills + user notification file for H10 review)
6. Emit `runs/<run-id>/run-summary.md` with metrics, decisions, branch name, next steps
7. H10: user decides merge / keep branch / delete branch

## Safety rails (enforced)

- Never commits to `main` or pushes
- Writes ONLY to `$SDK_TARGET_DIR/<new-pkg>/` and `runs/<run-id>/`
- `--dry-run` blocks all target writes
- Every HITL gate respects timeout (conservative default: reject / revise / keep branch)
- Marker protocol (CLAUDE.md rule #29) enforced at impl phase

## Delegates to

`sdk-intake-agent` → (if B/C) `sdk-existing-api-analyzer-go` + `sdk-marker-scanner` → `sdk-design-lead` → `sdk-impl-lead` → `sdk-testing-lead` → `sdk-doc-writer` ‖ `sdk-version-applier` → `learning-engine`

Each lead orchestrates its phase per the phase doc in `phases/<PHASE>-PHASE.md`.

## Exit codes (conceptual)

- 0: all phases PASS, branch created, ready for user review
- 1: HITL gate declined
- 2: guardrail BLOCKER unresolved after review-fix loop
- 4: supply-chain REJECT (govulncheck/osv-scanner or license violation)
- 5: target dir invalid or not a git repo
- 6: TPRD §Guardrails-Manifest validation FAIL (human action required before re-run). Missing skills do NOT trigger exit 6 — they emit a WARN and the pipeline continues; misses are filed to `docs/PROPOSED-SKILLS.md`.
- 7: H0 preflight HARD blocker — infra-tier or resolved-language toolchain missing. Run `bash scripts/preflight-check.sh` locally; install missing tools per `PREREQUISITES.md`; re-run.
