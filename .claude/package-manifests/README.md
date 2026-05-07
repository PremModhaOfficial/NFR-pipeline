# Package manifests (v0.5.0 Phase A — Python adapter scaffold)

**Status**: dispatch refactor live (v0.4.0); Python adapter scaffold added (v0.5.0 Phase A).
**Pipeline version**: 0.5.0
**Scope this pass**: Python language-adapter manifest authored as scaffold (empty agents/skills/guardrails arrays — those land in Phase B as the first Python TPRD exposes need). Toolchain + baselines + marker syntax declared. Validator passes 3-pack consistency.

## What a manifest is

A manifest is a JSON file that lists which artifacts (agents, skills, guardrails) belong to one logical package. Manifests are **descriptive**, not prescriptive — at this pass, no pipeline code reads them. They exist so that:

1. **Orphan detection** — `scripts/validate-packages.sh` confirms every on-disk agent/skill/guardrail is accounted for in exactly one manifest. New artifacts added without manifest entries are caught at pre-commit / intake.
2. **Ownership clarity** — reviewers can see at a glance which artifacts are language-neutral (`shared-core`) vs. Go-specific (`go`).
3. **Future dispatch** — a later v0.4.x pass will teach `sdk-intake-agent` to write `active-packages.json` and have phase-leads / guardrail-validator filter invocations through it. That lives in a separate release.

## Why manifest-only (not physical packaging)

Claude Code's harness discovers agents at `agents/*.md` and skills at `skills/*/SKILL.md`. Moving files into `.claude/packages/<pkg>/agents/` breaks discovery — the agents become uninvokable. Manifest-only keeps the canonical file layout intact and adds the package layer as metadata. See `runs/package-layer-reconciliation.md` for the full decision record and the fate of the earlier `core/` + `packs/` physical-packaging attempt.

## Directory layout

```
.claude/package-manifests/
├── README.md           # this file
├── shared-core.json    # language-agnostic orchestration, meta-skills, governance
├── go.json             # Go SDK language adapter (production)
└── python.json         # Python SDK language adapter (v0.5.0 scaffold; runtime exercise pending Phase B)
```

Manifest format: see `shared-core.json` for the canonical shape. Every manifest declares `name`, `version`, `type` (`core` | `language-adapter`), `depends`, and three artifact arrays: `agents`, `skills`, `guardrails`. Language adapters additionally declare `toolchain`, `file_extensions`, `marker_comment_syntax`, `module_file`.

## Current counts (v0.5.0 Phase A)

| Package | Agents | Skills | Guardrails |
|---|---:|---:|---:|
| shared-core | 22 | 16 | 22 |
| go | 16 | 25 | 31 |
| python | 0 | 0 | 0 |
| **total** | **38** | **41** | **53** |

`python` ships empty in Phase A — the manifest declares the toolchain, baselines, and marker syntax, but Python-specific agents/skills/guardrails are authored lazily in Phase B (first Python TPRD). Enforced by `scripts/validate-packages.sh` (exits non-zero on orphan / duplicate / missing).

## What's NOT in this pass

- No agent prompt edits. `sdk-intake-agent`, phase-leads, and `guardrail-validator` still behave exactly as they did in v0.3.0.
- No `active-packages.json` resolution. No TPRD `§Target-Language` field parsing.
- No G05 or any new intake guardrail tied to package resolution.
- No deletion of the `core/` and `packs/` directories present from the earlier physical-packaging attempt. Those are left as-is for separate review; their `core/agents/` and `core/skills/` subdirectories are duplicates of the canonical `.claude/` locations and can be removed safely once confirmed.

## Generalization debt

Several artifacts in `shared-core` have prompts/bodies that reference Go-specific idioms today. They're placed in shared-core because their **role** is language-neutral (semver governance, design review, security review, over-engineering review); their **content** will need a generalization pass when the second language lands. Each manifest's `generalization_debt` array lists these explicitly. Treat that list as the backlog for "v0.5.0 — second-language pilot".

## Validator

Run `bash scripts/validate-packages.sh` to check:

- Every file in `agents/*.md` is in exactly one manifest
- Every directory in `skills/*/` is in exactly one manifest
- Every file in `scripts/guardrails/G*.sh` is in exactly one manifest
- No manifest references a non-existent file
- No duplicate entries across manifests

Non-zero exit = drift. Fix the manifest before committing.
