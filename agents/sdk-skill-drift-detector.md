---
name: sdk-skill-drift-detector
description: Phase 4. Compares what each invoked skill PRESCRIBED against what the generated code ACTUALLY does. Writes drift findings to feedback for improvement-planner.
model: opus
tools: Read, Glob, Grep, Write
cross_language_ok: true
---

# sdk-skill-drift-detector

## Input
- `runs/<run-id>/decision-log.jsonl` (mine for which skills were invoked by which agents)
- `runs/<run-id>/context/active-packages.json` (resolve `target_language` and the per-pack `file_extensions` for code-grep scope)
- Generated code on branch (file-extension scope from the active language pack's `file_extensions` field — Go: `.go`; Python: `.py`)
- Skills from `skills/<name>/SKILL.md`

## Procedure

0. Resolve `TARGET_LANGUAGE = jq -r '.target_language' runs/<run-id>/context/active-packages.json`. Resolve `EXTENSIONS = jq -r '.packages[] | select(.target == true) | .file_extensions[]' active-packages.json` — typically `.go` for Go, `.py` for Python. All code greps below are scoped to these extensions.
1. For each skill invoked this run, parse SKILL.md for explicit prescriptions (MUST/MUST NOT clauses, code patterns in GOOD/BAD examples).
2. Grep generated code (limited to `EXTENSIONS`) for violation patterns. Patterns are language-specific and live IN THE SKILL itself — a Go skill's BAD examples grep against `.go` files; a Python skill's BAD examples grep against `.py` files.
3. Record findings with file:line references AND a `language` tag.

### Examples (per language)

**Go example**: skill `go-sdk-config-struct-pattern` prescribes:
> MUST: Config struct fields are immutable post-construction.

```bash
# Scoped to ${EXTENSIONS} (.go for Go runs)
grep -nE "func.*\) Set[A-Z].*\(.*\) " "$SDK_TARGET_DIR" -r --include="*.go"
# Finds: func (c *Config) SetRetries(n int)
```

**Python example**: skill `python-sdk-config-pattern` prescribes:
> MUST: Config is `@dataclass(frozen=True)`; never expose post-construction setters.

```bash
# Scoped to ${EXTENSIONS} (.py for Python runs)
grep -nE "def set_[a-z_]+\(self, " "$SDK_TARGET_DIR/src" -r --include="*.py"
# Finds: def set_retries(self, n: int) -> None:  (mutable setter on what should be frozen Config)
```

The drift-detection RULE is the same across languages ("immutable Config"); the GREP PATTERN comes from the skill body, which is per-language. A shared skill (e.g., `idempotent-retry-safety`) supplies its own language-overlay greps via examples in its SKILL.md.

## Output
`runs/<run-id>/feedback/skill-drift.md`:
```md
# Skill Drift Report

**language**: <go|python>   # MUST be present so improvement-planner can route fixes correctly

## Invoked skills (this run)
- <skill-name> v<X.Y.Z>  (scope: <go|python|shared-core>)
- ...

## Drift findings

### SKD-001: <skill-name> violated
**Language**: <go|python>
**Skill scope**: <pack-that-owns-it>
Skill prescribes: <one-line summary>
Code has: <violation in {file}:{line}>
Severity: HIGH | MEDIUM | LOW
Recommendation: <fix>

(Each finding carries the language tag so when `improvement-planner` consumes this file at Step 1, it can group findings by `language` and apply scope classification per Step 2.4.)
```

Feeds `improvement-planner` in next wave. The `language` field on every finding lets the planner skip cross-language consolidation (a Go finding never merges with a Python finding even if they cite the same shared skill — they may have different fix paths in the per-language adapter).
