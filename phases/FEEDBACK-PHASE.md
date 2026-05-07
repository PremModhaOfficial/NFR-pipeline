# Phase 4: Feedback & Self-Learning

## Purpose

Close the loop. Collect telemetry, trace defects, detect drift, apply safe improvements, notify the user of each applied patch. Every run leaves the pipeline smarter.

**Core sequence ported verbatim from archive**:
`metrics-collector → phase-retrospector → root-cause-tracer → improvement-planner → learning-engine → baseline-manager`

New SDK agents plug in as INPUTS to `improvement-planner` — they don't replace the ported chain.

Golden-corpus regression replay has been retired. It dominated Phase 4 token spend without providing signal the devil fleet was not already catching; safety now comes from append-only semantics, minor-bump versioning, and a user notification file reviewed at H10.

## Input

- `runs/<run-id>/decision-log.jsonl` (all 8 entry types)
- `runs/<run-id>/testing/*`
- `runs/<run-id>/impl/*`
- `runs/<run-id>/design/*`
- `runs/<run-id>/intake/*`
- `baselines/*.json` (previous)
- `evolution/knowledge-base/*.jsonl`

## Waves

### Wave F1 — Metrics Collection
**Agent**: `metrics-collector`
- Computes per-agent `quality_score` (formula in CLAUDE.md)
- Per-phase metrics (duration, tokens, rework, devil-block-rate, skill-coverage-pct)
- Per-run metrics (pipeline_quality, coverage, bench-delta, vuln-count, leak-count, flake-rate, determinism-diff)
- **Output-shape hash + Example_* count (SDK-mode, compensating for retired golden-corpus)** — runs `scripts/compute-shape-hash.sh` on the generated package, counts `Example_*` functions, appends one line to `baselines/go/output-shape-history.jsonl`.
- Output: `runs/<run-id>/feedback/metrics.json` + `metrics-summary.md`
- Persists per-agent quality_score as `(Agent)-[:OBSERVED_IN {score}]->(Run)` observation in neo4j-memory (fallback: agent-performance.jsonl).

### Wave F2 — Phase Retrospectives
**Agent**: `phase-retrospector`
- For each phase (intake, design, impl, testing), produce `runs/<run-id>/feedback/retro-<phase>.md`
- What went well / recurring patterns / surprises / coordination issues
- Cross-phase pattern detection (if this is run ≥2)

### Wave F3 — Root-Cause Tracing (if defects)
**Agent**: `root-cause-tracer`
- For each HIGH/CRITICAL defect from testing phase, trace backward through phases
- Where was the defect introduced? Which phase should have caught it?
- Output: `runs/<run-id>/feedback/root-causes.md` + backpatch-log entries

### Wave F4 — SDK-Specific Drift + Coverage (NEW)
Parallel:

| Agent | Role |
|-------|------|
| `sdk-skill-drift-detector` | Compare what each invoked skill PRESCRIBED vs. what the code actually DOES. Example: `go-sdk-config-struct-pattern` says Config is immutable — code has exported mutable fields. Output: `feedback/skill-drift.md`. |
| `sdk-skill-coverage-reporter` | Which skills got invoked per phase? Which were expected-but-unused (based on TPRD tech signals)? Also computes per-skill `devil_fix_rate` + `devil_block_rate` and appends to `baselines/go/devil-verdict-history.jsonl` (compensating baseline for retired golden-corpus). Output: `feedback/skill-coverage.md`. |

Writes drift + coverage observations to neo4j-memory via `mcp-knowledge-graph` skill when available; falls back to markdown artifacts if MCP is down.

### Wave F5 — (retired)
Previously: golden-corpus regression replay. Removed because the full-pipeline replay was the single largest Phase 4 token consumer and caught almost nothing the devil fleet (api-ergonomics-devil, leak-hunter, overengineering-critic, marker-hygiene-devil, code-reviewer-go, constraint-devil, semver-devil, benchmark-devil, security-devil, convention-devil) was not already catching on the live run. Safety net is now: append-only patches + minor-bump versioning + `learning-notifications.md` (user reviews at H10, reverts individual patches if needed).

### Wave F6 — Improvement Planning
**Agent**: `improvement-planner`
Reads: metrics, retros, root-causes, drift, coverage, knowledge-base
Outputs categorized improvements in `evolution/improvement-plan-<run-id>.md`:
- Prompt-patch candidates → `evolution/prompt-patches/<agent>.md` (draft)
- Existing-skill body-patch candidates → marked for `learning-engine` (auto-apply with minor bump + per-patch notification in `learning-notifications.md`)
- **New-skill proposals** → appended to `docs/PROPOSED-SKILLS.md` with `status: proposed`, source `run-id` (human-authored only; never drafted by pipeline)
- **New-guardrail proposals** → appended to `docs/PROPOSED-GUARDRAILS.md` (human-authored only)
- Process / threshold proposals (plan only, not auto-applied)
Confidence levels: high / medium / low.

### Wave F7 — Learning Engine (auto-apply safe; draft risky)
**Agent**: `learning-engine`
Safety gates (preserved from archive, narrowed post-Phase-1-removal):
- confidence=high required for auto-apply
- 2+ run recurrence (except CRITICAL)
- never deletes (append-only; `status: deprecated`)
- resets baselines every 5 runs
- caps per run: ≤10 prompt patches, ≤3 **existing-skill** body patches, **0 new skills / 0 new guardrails / 0 new agents** (all human-authored via PR)

**NEW delta** — for every applied patch, append a line to `runs/<run-id>/feedback/learning-notifications.md` and emit a single NOTIFY Teammate message to the lead agent. User reviews this file at H10 and may revert individual patches (`git revert <commit>` or restore from the skill's evolution-log.md predecessor block). Never creates new `SKILL.md` files — only patches bodies of existing skills with a minor version bump.

Reads recurring-pattern signals from neo4j-memory when available; falls back to grepping `evolution/knowledge-base/*.jsonl`.
Writes every applied patch as a `Patch` entity with `(Patch)-[:APPLIED_TO]->(Agent|Skill)` and `(Patch)-[:MOTIVATED_BY]->(Pattern)` relations.

Actions:
- Apply high-confidence prompt patches → `evolution/prompt-patches/<agent>.md` (append)
- Apply existing-skill body patches → bump minor version, append to `evolution-log.md`
- Append one notification line per applied patch to `runs/<run-id>/feedback/learning-notifications.md`
- File new-skill proposals → `docs/PROPOSED-SKILLS.md` (status: proposed)
- File new-guardrail proposals → `docs/PROPOSED-GUARDRAILS.md` (status: proposed)
- Log applied patches in `evolution/knowledge-base/prompt-evolution-log.jsonl`

### Wave F8 — Baseline Manager
**Agent**: `baseline-manager`
- First-run: create baselines
- Subsequent: raise if improved by >10%, keep if regressed, reset every 5 runs
- Update shared baselines: `baselines/shared/{quality,skill-health,skill-health-baselines}.json` and per-language (Go): `baselines/go/{coverage,performance}-baselines.json`
- Output: `baselines/go/regression-report-<run-id>.md` (per-language), `baselines/shared/baseline-history.jsonl` append (shared)
- Creates `(Baseline)-[:UPDATED_IN]->(Run)` with new value as observation (fallback: baseline-history.jsonl).

### Wave F9 — HITL Gate H10 (merge rec)
**H10**: Final merge recommendation with run-summary. User reviews `runs/<run-id>/feedback/learning-notifications.md` and may revert any individual applied patch before approving merge. Major skill bumps and new-skill proposals are always human PR decisions (no runtime gate needed — pipeline cannot author them).

## Exit artifacts

- `runs/<run-id>/feedback/metrics.json`
- `runs/<run-id>/feedback/retro-<phase>.md` × 5
- `runs/<run-id>/feedback/root-causes.md` (if defects)
- `runs/<run-id>/feedback/skill-drift.md`
- `runs/<run-id>/feedback/skill-coverage.md`
- `runs/<run-id>/feedback/learning-notifications.md` (one line per applied patch; reviewed at H10)
- `evolution/improvement-plan-<run-id>.md`
- `evolution/evolution-reports/<run-id>.md` — summary of applied + drafted changes
- Updated `baselines/*.json`
- Updated `evolution/knowledge-base/*.jsonl`
- `runs/<run-id>/run-summary.md` — top-level roll-up for user

## Guardrails (exit gate)

G80 (evolution-report written), G81 (baselines updated or rationale), G83 (every patch logged in skill evolution-log.md with devil verdict), G84 (per-run safety caps respected), G85 (learning-notifications.md written when any patch applied), G86 (no agent quality_score regressed ≥5% vs baseline when ≥3 prior runs exist — tightened post-golden-corpus retirement).

## Metrics

- `learning_patches_applied`
- `learning_patches_drafted`
- `skills_evolved`
- `learning_patches_reverted_by_user` (signal for over-aggressive patching; target trending down)
- `baseline_improvements` / `baseline_regressions_caught`

## Pipeline-maturity signals

Longitudinal (across runs):
- `existing_skill_patch_accept_rate` (target ≥0.8 after 5 runs)
- `skill_stability` (patches per skill per run; target <0.3 after 10 runs)
- `manifest_miss_rate` (target 0 after library stabilizes)
- `mean_time_to_green` (trending down)
- `user_intervention_rate` (trending down)

## Typical durations

- First few runs: 30–60 min (drafts, baseline creation, many learnings)
- Mature runs: 10–20 min (stable, small deltas)
