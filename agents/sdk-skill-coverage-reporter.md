---
name: sdk-skill-coverage-reporter
description: Phase 4. Reports which skills were actually invoked by agents this run, vs. which were expected (based on TPRD tech signals). Unused-but-relevant = triggers gap.
model: sonnet
tools: Read, Glob, Grep, Write
cross_language_ok: true
---

# sdk-skill-coverage-reporter

## Input
- `runs/<run-id>/decision-log.jsonl`
- `runs/<run-id>/context/active-packages.json` (for `target_language` resolution + the per-language skill set actually loaded for this run)
- `runs/<run-id>/tprd.md` (for expected skills via §Skills-Manifest + tech signals)
- `runs/<run-id>/intake/skills-manifest-check.md` (declared-required set)

## Procedure

0. Resolve `TARGET_LANGUAGE = jq -r '.target_language' runs/<run-id>/context/active-packages.json`. All per-language baseline writes resolve through `${TARGET_LANGUAGE}`. Drift / coverage analysis NEVER unions cross-language data — a skill's invocation rate in Go runs is not directly comparable to the same skill's rate in Python runs (different agent fleet invokes it; different evidence base).
1. Extract "skill invocations" from decision log — entries where an agent cites a skill name in `decision.rationale` or `communication.tags`
2. Cross-reference with TPRD tech signals AND `active-packages.json:packages[].skills[]` (the skills actually loaded for this run) to build the expected skill set
3. Find:
   - Invoked skills (used this run)
   - Expected-but-unused (signal matched, skill exists IN THE ACTIVE PACK SET, yet no agent cited it) — TRIGGERS-GAP
   - Invoked-but-unexpected (used but signal didn't match) — either good lateral transfer OR over-invocation
   - Expected-but-not-loaded (TPRD signal expected the skill but it's not in any active pack) — TRIGGERS-MANIFEST-GAP (different gap class; surface to improvement-planner with `scope: NEEDS-CLASSIFICATION` so a human resolves whether the skill should be authored in the active language pack OR in shared-core)

## Devil-verdict stability (compensating baseline for retired golden-corpus)

After (3), for each invoked skill compute:
- `devil_fix_rate` = (NEEDS-FIX findings whose `fix_agent` cites a symbol in a region the skill prescribes) / (total exported symbols the skill's rules apply to). Read findings from `runs/<run-id>/{design,impl,testing}/reviews/*.findings.json`.
- `devil_block_rate` = same numerator, BLOCKER-severity only / total.

Append one line per invoked skill to `baselines/${TARGET_LANGUAGE}/devil-verdict-history.jsonl`:
```json
{"run_id":"<uuid>","timestamp":"<ISO>","language":"<TARGET_LANGUAGE>","skill":"<name>","skill_version":"<X.Y.Z>","devil_fix_rate":0.12,"devil_block_rate":0.02,"symbols_scoped":<N>,"pipeline_version":"<ver>"}
```

The `language` field MUST be present so future cross-language analytics (if ever wired per Decision D2-Progressive trigger) can partition without re-resolving from run-manifest.

If the skill was NOT auto-patched this run, this is a pure trend signal (baseline-manager raises). If the skill WAS auto-patched (check `evolution/knowledge-base/prompt-evolution-log.jsonl` for a matching entry this run), flag `regression_candidate: true` on the line so `learning-engine` can surface the jump in `learning-notifications.md` before user H10 review.

For SHARED-CORE skills that are invoked across multiple languages over time, the `devil_fix_rate` trend is computed per-language (each language has its own history file). A shared skill's quality is acceptable if its rate stays stable WITHIN each language partition; cross-language comparison is NOT used to flag the skill (per Decision D4=native).

Also backfill `skills_invoked` on this run's `baselines/${TARGET_LANGUAGE}/output-shape-history.jsonl` entry (metrics-collector leaves it `[]` if it ran first).

## Output
`runs/<run-id>/feedback/skill-coverage.md`:
```md
# Skill Coverage Report

## Expected (from TPRD signals)
- sdk-cache-client-patterns
- go-circuit-breaker-policy
- network-error-classification
- go-sdk-config-struct-pattern
- go-otel-instrumentation
- go-testcontainers-setup

## Invoked
- go-sdk-config-struct-pattern ✓
- go-otel-instrumentation ✓
- go-testcontainers-setup ✓
- sdk-cache-client-patterns ✓
- go-concurrency-patterns (unexpected — OK, agents generalized)

## Expected-but-unused
- **go-circuit-breaker-policy** — TRIGGERS-GAP: skill exists (v1.0.0) but no agent invoked it despite TPRD §9 Resilience requesting CB thresholds. Investigate: skill description keywords too narrow?
- **network-error-classification** — TRIGGERS-GAP: skill exists (v1.0.0) but impl uses generic fmt.Errorf wrapping without classification. Investigate.

## Recommendations for improvement-planner
- Enhance `go-circuit-breaker-policy` description to include tech-signal keywords ("retry", "resilience", "retries")
- Add trigger to `network-error-classification` description referencing "error handling" domain
```

Feeds `improvement-planner`.
