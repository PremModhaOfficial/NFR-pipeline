# Deprecated concepts registry

Retired concepts + the commit that retired them + what replaced them. Guardrail `G116` scans non-deprecated docs for the **retired term** column and fails if any match is found outside this file, `improvements.md` §DROPPED, or historical `runs/`. Add a row when you retire a concept; remove it (and its scan exception) when all live references are gone.

## How to use this file

- **Adding a retirement**: append a row to the table, include the commit SHA where the replacement landed, and update any live docs that still use the retired term.
- **Removing an entry**: only do this when you're certain the retired concept has no lingering external references (e.g., in other repos that point here). Running `bash scripts/guardrails/G116.sh` should stay clean after removal.
- **Scope**: retirements that affected pipeline behavior (agents, guardrails, phases, rules, flags, artifacts). Not routine bug fixes.

---

## Retired concepts

| Retired term | Retired in | Replacement | Notes |
|---|---|---|---|
| `golden-corpus regression` | `f809317` (retirement) + `69751a2` (replacement) — 2026-04-XX | CLAUDE.md rule 28: four compensating baselines (output-shape hash, devil-verdict stability, tightened quality threshold via G86, example-count per package) + learning-notifications loop via G85 | Full-replay golden-corpus was ~1.5–3M tokens per run and caught almost nothing the devil fleet wasn't already catching on the live run. |
| `sdk-golden-regression-runner` | `f809317` | Baseline-manager (for the 4 compensating baselines) + user H10 review of `learning-notifications.md` | Agent file deleted alongside the mechanic it implemented. |
| `G82 golden-corpus PASS gate` | `f809317` | G85 (notifications written) + G86 (quality regression BLOCKER at 5%) | Script may remain in `scripts/guardrails/` as a retired no-op; do not invoke. |
| `Phase -1 bootstrap` | `b28405a` — 2026-04-14 | Human-PR skill/agent authorship per CLAUDE.md rule 23; skill-creation-guide owns the offline authoring flow | Phase -1 was runtime synthesis of skills/agents. Removed to keep the pipeline's permission surface tight. |
| `sdk-skill-synthesizer` (agent) | `b28405a` | Human author; draft proposals file to `docs/PROPOSED-SKILLS.md` | Never re-introduce runtime skill synthesis — see rule 23 rationale. |
| `sdk-skill-devil` (agent) | `b28405a` | Human PR review covers the "devil" role for skills; existing skill-content devil agents still review runtime skill use | — |
| `sdk-bootstrap-lead` (agent) | `b28405a` | No replacement; bootstrap was the wave this agent led. Intake-agent owns manifest validation now | — |
| `HITL gate H2` (skills approval) | `b28405a` | Removed with Phase -1. Current live gates: H0 / H1 / H5 / H7 / H7b / H9 / H10 | — |
| `HITL gate H3` (agents approval) | `b28405a` | Same as H2 | — |
| `--auto-approve-bootstrap` (CLI flag) | `b28405a` | Flag removed; no replacement needed (Phase -1 gone) | Flag no longer parsed by `/run-sdk-addition`. |
| `Phase -1 synthesis prompt hint` (skill-body boilerplate) | v0.3.0 straighten — 2026-04-24 | 19 skill bodies authored from target SDK conventions + community Go patterns; no more synthesis indirection | Any skill still containing "will be synthesized on first Phase -1 use" is drift. |
| `docs/MISSING-SKILLS-BACKLOG.md` | v0.2.0 refactor (`b28405a`) | `docs/PROPOSED-SKILLS.md` (current) | Renamed; legacy filename should not appear in live docs. |
| `Rule 15` (in CLAUDE.md) | Deleted pre-v0.2.0; numbering gap intentional | No replacement — content folded into surrounding rules during the NFR-driven refactor | Do not renumber downstream rules to fill the gap. |
| `bootstrap-seed` (skill frontmatter value for `created-in-run`) | v0.3.0 straighten | New skills ship with `authored-in: vX.Y.Z-<release-slug>` in frontmatter | Historical skill frontmatter retains `bootstrap-seed` for provenance; not drift. |

---

## Per-entry verification

For each retired term, `scripts/guardrails/G116.sh` runs:

1. Grep the term across `**/*.md`, `**/*.html`, `**/*.json` (excluding `docs/DEPRECATED.md`, `improvements.md` §DROPPED, `runs/**`, `.git/**`).
2. If any live reference remains, FAIL with file path + line.
3. If clean, PASS.

A fresh retirement should be paired with a grep-and-clean of live docs before being added here. Adding a row while live references remain will cause G116 to fail on every intake until cleaned.

---

## Audit trail

v0.3.0 straighten added this file. Prior to v0.3.0 there was no central registry; retirements were documented only in commit messages + scattered rule comments (e.g., "H2 and H3 removed" in `CLAUDE.md` line 194, "Phase -1 bootstrap" in `improvements.md` §DROPPED).
