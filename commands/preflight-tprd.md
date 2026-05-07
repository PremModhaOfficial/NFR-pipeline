---
name: preflight-tprd
description: Validate a TPRD against the current skill + guardrail library WITHOUT running the pipeline. Confirms every §Skills-Manifest entry exists at ≥ required version (WARN only; non-blocking) and every §Guardrails-Manifest entry has an executable script (BLOCKER on miss). Reports every miss with an actionable remediation note. Safe to run any time — makes no writes to target SDK.
user-invocable: true
---

# /preflight-tprd

Pre-run validation for a TPRD. Runs the same checks the real pipeline would run in Intake Wave I2 + I3, but in isolation. No state mutation, no target-dir writes.

## Arguments

| Flag | Default | Description |
|------|---------|-------------|
| `--spec <file>` | — (required) | Path to the TPRD markdown file |
| `--strict` | false | Treat warnings (e.g., skill version ≥ required but < latest) as FAIL |
| `--output <path>` | stdout | Write the preflight report to a file |

## What it checks

1. **TPRD structure** — all 14 core sections present + §Skills-Manifest + §Guardrails-Manifest non-empty
2. **§Skills-Manifest** — every declared skill (WARN only; never blocks a run):
   - Exists under `skills/<name>/SKILL.md`
   - Exists in `skills/skill-index.json`
   - Is at version ≥ the min-version declared in the manifest
   - Any miss is reported as WARN and auto-filed to `docs/PROPOSED-SKILLS.md`; the pipeline (and preflight) exit 0 regardless
3. **§Guardrails-Manifest** — every declared guardrail (BLOCKER on miss):
   - Has a script at `scripts/guardrails/<G-id>.sh`
   - Script is executable (`chmod +x`)
   - Script declares the phase(s) it applies to via `# phases:` header
4. **Mode coherence** — TPRD §1 Request Type matches §12 Breaking-Change Risk (Mode A → no breakage; Mode C → breakage allowed with semver declaration)
5. **Open questions** — §14 Pre-Phase-1 Clarifications — any `ANSWER REQUIRED` with `Blocker: YES` = FAIL

## Output

Writes (or prints) a report:

```markdown
# Preflight report — runs/my-tprd.md

Status: PASS | WARN | FAIL
(FAIL only if §Guardrails-Manifest has misses; §Skills-Manifest misses are WARN-only)

## §Skills-Manifest — 12/13 WARN (non-blocking)
- go-sdk-config-struct-pattern: declared ≥1.0.0, found 1.0.0   ✓
- goroutine-leak-prevention: declared ≥1.0.0, found 1.0.0   ✓
- redis-streams-patterns: declared ≥1.0.0  MISSING  ← WARN (filed to docs/PROPOSED-SKILLS.md)
- ...

## §Guardrails-Manifest — 9/9 PASS
- G01: scripts/guardrails/G01.sh ✓ (phases: intake design impl testing feedback meta)
- G23: scripts/guardrails/G23.sh ✓ (phases: intake; severity: WARN)
- G24: scripts/guardrails/G24.sh ✓ (phases: intake; severity: BLOCKER)
- ...

## Open questions — 0 blockers
(all resolved)

## Recommendation
TPRD is ready for /run-sdk-addition (skill WARNs will not halt the run)
```

On FAIL (§Guardrails-Manifest miss) or WARN (§Skills-Manifest miss), the report enumerates every miss with the precise action required:

```markdown
## Missing skills (2) — WARN (non-blocking; auto-filed to docs/PROPOSED-SKILLS.md)
- `redis-streams-patterns` declared ≥1.0.0 — not in skill-index.json
  ACTION (optional, off-pipeline): author skills/redis-streams-patterns/SKILL.md and update skill-index.json; pipeline will proceed either way
- `sdk-eviction-policy` declared ≥1.2.0 — found 1.0.0 (under-versioned)
  ACTION (optional): edit skills/sdk-eviction-policy/SKILL.md, bump to ≥1.2.0 (human PR), update skill-index.json

## Missing guardrails (1) — BLOCKER (exit 3)
- G42 — no script at scripts/guardrails/G42.sh
  ACTION (required before re-run): author the script; ensure it prints PASS/FAIL and declares phases
```

## Examples

```bash
# Standard pre-flight before a run
/preflight-tprd --spec runs/s3-v1-tprd.md

# Strict mode (flags under-latest-but-valid versions)
/preflight-tprd --spec runs/s3-v1-tprd.md --strict

# Save report to file for review
/preflight-tprd --spec runs/s3-v1-tprd.md --output runs/s3-v1-preflight.md
```

## Exit codes

- **0**: TPRD passes — ready for `/run-sdk-addition`. Also exit 0 when §Skills-Manifest has WARN-level misses (missing or under-versioned skill); the report prints the WARN and lists the misses, but preflight does NOT fail the run on skill gaps. Skill authorship is a human PR concern.
- **1**: TPRD structure FAIL (missing sections / empty manifests)
- **3**: §Guardrails-Manifest FAIL (missing or non-executable script) — BLOCKER; the real pipeline would halt at Wave I3 with exit 6
- **4**: Open-question blocker unresolved in §14

(Exit code 2 is intentionally unused — what used to be "§Skills-Manifest FAIL" is now collapsed into exit 0 with a WARN.)

## When to use

- **Recommended** before `/run-sdk-addition` — surfaces Skills-Manifest WARNs early so you can decide whether to author missing skills, and catches Guardrails-Manifest BLOCKERs that would halt Intake Wave I3
- After authoring a new skill — confirms the TPRD that needed it now reports PASS instead of WARN
- After editing `skills/skill-index.json` — sanity check the catalog + on-disk match
- In CI — optional; a Skills-Manifest miss alone is not grounds to fail a PR, but a Guardrails-Manifest miss is

## Delegates to

`sdk-intake-agent` (I1 + I2 + I3 waves only, `--dry-run` flag set). No other agents, no branch creation, no target-dir writes.
