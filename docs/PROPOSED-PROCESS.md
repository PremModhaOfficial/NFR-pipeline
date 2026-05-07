# Proposed Process / Threshold Changes (Human-Review Backlog)

Entries from pipeline runs are auto-filed here by `improvement-planner` (Wave F6, Category D) and consumed by `learning-engine`. They never block a run and are never promoted at runtime. Promotion to actual schema / threshold / agent-prompt changes is a human PR action.

## Workflow

1. Entry lands here with `status: proposed` + motivation + source run + suggested owner / target-file.
2. Human author drafts the schema PR / agent-prompt patch / threshold update.
3. Human opens PR; reviewers include the relevant phase-owner agent's owner.
4. On merge: entry flipped to `status: promoted` with commit SHA + link.

## Policy

- **No auto-promotion.** Pipeline emits entries; does not change CLAUDE.md, agent prompts, manifest schemas, or `settings.json` at runtime.
- **Drift accountability.** Every entry must cite a defect / retrospective row / root-cause trace from the source run.

---

## Auto-filed from run `sdk-resourcepool-py-pilot-v1` on 2026-04-29 (F6 improvement-planner → learning-engine, Category D)

Source: `improvement-planner` Wave F6, derived from Phase 4 backlog + retrospective Process Changes section + per-agent-scorecard D2 progressive-trigger response.

### Proposed: D1 — Promote `toolchain.<command>.min_version` from informational to enforced (manifest schema)
<!-- Run: sdk-resourcepool-py-pilot-v1 | Date: 2026-04-30 | Confidence: HIGH -->

- **current**: `python.json` `toolchain.lint.min_version` is informational only; mismatches surface at M9 as G43-py INCOMPLETE
- **proposed**: any `min_version` declared in a manifest's `toolchain` block becomes enforced; G43-py treats version-below-min as `INCOMPLETE-by-tooling` from intake (not at M9)
- **justification**: PA-004 exhibited a structural false-negative — the ruff 0.4 vs PEP 639 mismatch fired late and cost a M9 round-trip. Min-version enforcement is mechanical at intake.
- **confidence**: HIGH
- **owner**: shared-core schema PR (manifest authoring guide §toolchain)
- **target files**: `docs/PACKAGE-AUTHORING-GUIDE.md` (§toolchain schema doc), `.claude/package-manifests/python.json` + `go.json` (declare min_versions are enforced), `scripts/guardrails/G43-py.sh` (read at intake time, not impl time)

### Proposed: D2 — Guardrail header schema: add `mode_skip` and `min_phase` predicates
<!-- Run: sdk-resourcepool-py-pilot-v1 | Date: 2026-04-30 | Confidence: HIGH -->

- **current**: G200-py and G32-py have only `phase: design` headers; they fire at design phase for Mode A greenfield where pyproject.toml does not exist yet, requiring lead waivers
- **proposed**: add `mode_skip: [A]` (skip in Mode A entirely) and/or `min_phase: impl` (skip until impl phase) predicates to guardrail header schema. Patch G200-py and G32-py headers in same PR.
- **justification**: prevents false-BLOCKER + waiver overhead on every future Python Mode A run; one-time schema fix
- **confidence**: HIGH
- **owner**: package-authoring-guide doc owner (schema PR) + python pack maintainer (header patches)
- **target files**: `docs/PACKAGE-AUTHORING-GUIDE.md` (§guardrail header schema), `scripts/guardrails/G200-py.sh` + `scripts/guardrails/G32-py.sh` (header lines), `scripts/run-guardrails.sh` (predicate evaluator)

### Proposed: D3 — Pipeline impl-lead halt policy: ≥2 INCOMPLETE-by-tooling in same wave → halt + user-ask
<!-- Run: sdk-resourcepool-py-pilot-v1 | Date: 2026-04-30 | Confidence: MEDIUM -->

- **current**: TOOLCHAIN-CASCADE — sdk-impl-lead correctly tagged each gate INCOMPLETE during run-2 but kept marching, accumulating M3.5/M5/M7/M9 INCOMPLETEs before user re-engagement
- **proposed**: amend `agents/sdk-impl-lead.md` (general; not python-specific) — halt policy: when ≥2 INCOMPLETE-by-tooling verdicts accumulate within a single wave, halt and request user re-engagement; do NOT continue to subsequent waves
- **justification**: Rule 33 disambiguates verdicts but does not prescribe escalation policy. The cascade was technically correct but cost three sub-runs of pipeline work.
- **confidence**: MEDIUM (impl-lead is a general agent; per-language overlays may need to add their own halt clauses)
- **owner**: sdk-impl-lead author (prompt PR)
- **target files**: `agents/sdk-impl-lead.md` (new §INCOMPLETE-cascade halt policy section)

### Generalization-debt items recorded (NOT counted in the 14-item plan total)

These two items were surfaced in the run but are out-of-scope for learning-engine's auto-apply rules. Filed here for tracking; no action required by learning-engine.

- **PA-006 — CLAUDE.md rules 20, 24, 28, 32 prose names Go-specific agents** (defect-log DEF-006). Replace `sdk-perf-architect-go`, `sdk-benchmark-devil-go`, `sdk-profile-auditor-go` etc. in language-neutral rule prose with `<lang>`-parameterized notation. Out-of-scope for learning-engine (touches CLAUDE.md); filed for human PR by docs owner.
- **PA-014 — `scripts/compute-shape-hash.sh` not authored for Python pack**. Tracked in python pack `generalization_debt`. Pipeline-infra maintainer authors `scripts/compute-shape-hash.sh` with `--lang python|go` switch reading active-packages.json.
