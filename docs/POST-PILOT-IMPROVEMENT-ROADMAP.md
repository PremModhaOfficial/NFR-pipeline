<!-- Source: post-pilot synthesis of sdk-resourcepool-py-pilot-v1 -->
<!-- Pipeline: 0.5.0 → 0.5.1 → 0.5.2 → 0.6.0 -->
<!-- Generated: 2026-04-30 -->

# Post-Pilot Improvement Roadmap

A conducive, sequenced plan to evolve the SDK pipeline from v0.5.0 to v0.6.0 based on empirical findings from the first Python adapter pilot run (`sdk-resourcepool-py-pilot-v1`).

Read top-to-bottom. Execute in the order presented. Each shipping unit is one PR's worth of work — independently reviewable, independently revertible.

---

## TL;DR

- **14 shipping units across 4 sprints** (~3 weeks full-time, ~6 weeks at 50% allocation)
- **Drop T2 domain packs** (multi-language × multi-domain complexity not justified at current scale)
- **Skills + Guardrails manifests stay REQUIRED** in TPRD (asymmetry: skills can become optional later; guardrails never can — they're enforcement, not advisory)
- **Add I2.5 advisory skill auto-discovery** to close the manifest gap without removing the manifest
- **Close the toolchain-cascade failure class** with `G-toolchain-probe.sh` + `min_version` enforcement
- **Fix CLAUDE.md generalization debt** — rules 20/24/28/32 still name Go agents in language-neutral prose
- **One concurrent maintenance run** (Mode C) on `motadata-sdk` to close v1.0.0 → v1.0.1 backlog (PA-001/002/004/009/013)

---

## Why This Roadmap Exists

The first end-to-end Python pipeline run (`sdk-resourcepool-py-pilot-v1`) shipped clean at quality 0.959 — but surfaced 14 backlog items (PA-001 through PA-014) and 3 systemic patterns:

1. **TOOLCHAIN-ABSENCE** caused 3 impl sub-runs (single largest cost driver in the run)
2. **CV-001** (typing module not imported) was a real runtime bug classified LOW at design — caught only by mypy-strict at M5b. Severity rubric needs a `runtime-impact-unknown` bucket.
3. **Generalization debt**: CLAUDE.md rules 20/24/28/32 still name Go agents (`sdk-perf-architect-go` etc.) despite the pipeline now dispatching per-language siblings via `active-packages.json`.

Plus 7 process gaps surfaced in the Phase 4 retrospective and improvement-plan. This roadmap operationalizes the fix.

**Source documents**:
- `runs/sdk-resourcepool-py-pilot-v1/run-summary.md`
- `runs/sdk-resourcepool-py-pilot-v1/feedback/improvement-plan.md`
- `runs/sdk-resourcepool-py-pilot-v1/feedback/retrospective.md`
- `runs/sdk-resourcepool-py-pilot-v1/feedback/defect-log.jsonl`
- `runs/sdk-resourcepool-py-pilot-v1/feedback/root-cause-traces.md`

---

## Architectural Decisions (Locked)

These decisions were made during post-pilot review. Don't reopen them without the empirical triggers listed in the "When to Revisit" section.

### Decision 1 — Drop T2 (domain packs)

**Decision**: The pipeline stays language-pluggable, NOT domain-pluggable. No `domain-packs/` directory. No `§Domain` field in TPRD. No domain-specific skills/guardrails.

**Rationale**: Multi-language × multi-domain is a 2D combinatorial space (each cell costs maintenance, baselining, devil agent updates). At current scale (1 Python TPRD, 0 evidence of cross-TPRD domain pattern recurrence), the abstraction is premature. Domain knowledge stays in TPRDs (`§7 API`, `§10 NFRs`, `§3 Non-Goals`).

**What this means concretely**:
- TPRDs do NOT declare `§Domain`
- No `domain-packs/<name>/` directory exists
- I2.5 skill auto-discovery (U5 below) operates against T1 catalog only
- Domain-specific guardrails: if you ever need one (e.g., Redis-only BLOCKER), enumerate it in `§Guardrails-Manifest` for THAT TPRD; lives in `scripts/guardrails/` like any other guardrail. The TPRD activates it; absence of the TPRD declaration means absence of the guardrail.

### Decision 2 — Skills & Guardrails manifests stay REQUIRED in TPRD

**Decision**: `§Skills-Manifest` and `§Guardrails-Manifest` remain REQUIRED at intake. I2.5 auto-discovery SUPPLEMENTS the declared set; it never replaces it.

**Rationale (the asymmetry)**:

| Manifest | Capability | Failure mode | Discovery substitute? |
|---|---|---|---|
| §Skills-Manifest | Advisory — agents *consult* skills | Missed skill → drift → caught in Phase 4 | Yes, safely (worst case = noisy H1 supplement) |
| §Guardrails-Manifest | Enforcement — guardrails *gate* the run | False-positive → BLOCKER → run halts | **No** — heuristic enforcement breaks runs |

**Future evolution path**: at v0.6.0+, `§Skills-Manifest` MAY become optional once empirical data shows discovery accuracy is high (≥3 runs of clean advisory data, `auto_supplemented_actually_cited_pct ≥ 60%`). `§Guardrails-Manifest` never becomes optional.

### Decision 3 — `learning-engine` cap stays at 3 existing-skill patches per run

**Decision**: `safety_caps.existing_skill_patches_per_run = 3` in `.claude/settings.json` is correct. Don't bump.

**Rationale**: This run hit the cap exactly (A1/A2/A3 applied; A4-A7 deferred to next run). The cap forced prioritization, which produced the right 3 picks (the highest-leverage MEDIUM skill drift findings). Bumping the cap would dilute prioritization rigor.

### Decision 4 — No new agents at runtime; ever

**Decision**: `safety_caps.{new_skills,new_guardrails,new_agents}_per_run = 0` is permanent. Pipeline NEVER creates these at runtime. All new artifacts are human-PR authored.

**Rationale**: Already in CLAUDE.md rule 23. Reaffirmed because U11 (`sdk-feedback-lead` agent below) is a one-time human-PR addition, not a pipeline-runtime create.

---

## Out of Scope (explicit, do NOT do)

| Item | Why excluded |
|---|---|
| T2 domain packs / `§Domain` field / `domain-packs/` directory | Decision 1 above |
| Cross-language skill comparison (D2 partition flip) | Defer until ≥3 Python runs (statistical precondition unmet) |
| Pipeline-runtime artifact creation (skills, guardrails, agents) | Decision 4 above |
| Golden-corpus regression replay | Deprecated per CLAUDE.md rule 28 (compensating baselines do this job) |
| Severity-parameterized guardrails | YAGNI — fewer than 3 cases need this |
| Promote `§Skills-Manifest` to optional | Defer to v0.6.0+ pending empirical evidence |
| Bump `existing_skill_patches_per_run` cap | Decision 3 above |

---

## Sprint Plan Overview

| Sprint | Theme | Units | Total effort | Calendar |
|---|---|---|---|---|
| **S1** — Quick wins | Documentation drift, one-liners, spec hygiene | U1–U4 | ~5 hours | Week 1 |
| **S2** — Discovery & guardrail tightening | Close manifest gap; toolchain safety net | U5–U7 | ~4 days | Weeks 2–3 |
| **S3** — Devil rubric & resilience | Severity bucket, halt policy, mode-aware guardrails | U8–U10 | ~2.5 days | Weeks 4–5 |
| **S4** — Phase 4 orchestration & resilience | Feedback lead agent, checkpointing, Python shape hash | U11–U13 | ~5 days | Week 6 |
| **Parallel** | Author 3 missing skills (human-PR) | U14 | ~3 days | Weeks 2–6 |
| **Parallel maintenance** | Mode C run on `motadata-sdk` | M1 | ~2 hours pipeline + review | After U14 + S2 |

---

## Step-by-Step Sequence

If you want a single linear sequence, follow this order. Otherwise, treat each unit as independent (most have no hard dependencies).

| Day | Unit(s) | Effort | Cumulative scope |
|---|---|---|---|
| Day 1 (morning) | U1, U3, U4 | 50 min | Quick wins shipping |
| Day 1 (afternoon) | U2 | 4 hours | Documentation cleanup complete |
| Days 2–3 | U5 | 2 days | I2.5 advisory live |
| Day 4 | U6 + U7 (paired) | 1 day | Toolchain probe + version enforcement live |
| Day 5 | U8 | 4 hours | New severity bucket live |
| Day 6 | U9 | 1 day | Mode-aware guardrails live |
| Day 7 | U10 + U13 (am/pm) | 1 day | Halt policy + Python shape hash live |
| Days 8–9 | U11 | 1.5 days | Phase 4 lead agent live |
| Days 10–11 | U12 | 2 days | Mid-wave checkpointing live |
| Days 12–14 (parallel) | U14 (B1, B3, B4) | 3 days (parallelizable) | 3 new skills live |
| Day 15 | M1 — Mode C maintenance run | 2 hours + review | v1.0.1 wheel ready |

**Total**: ~3 weeks full-time, ~6 weeks at 50% allocation.

### If you have one day this week (highest payoff)

1. **U1** (5 min) — close the realpath landmine in `scripts/run-guardrails.sh`
2. **U2** (4 hours) — CLAUDE.md generalization debt cleanup (rules 20/24/28/32)
3. **U3 + U4** (45 min) — slash command spec + decision-log identity protocol
4. Read U5's I2.5 design and start sketching the algorithm

Skip U5–U14 until you can give them dedicated focus. They're each independent shipping units.

---

# Sprint S1 — Quick Wins

## U1 — `scripts/run-guardrails.sh` realpath one-liner (PA-005)

> Closes a path-resolution landmine that breaks every child guardrail when it `cd`s into TARGET.

**Effort**: 5 minutes  
**Risk**: trivial  
**Depends**: none  
**Source defect**: PA-005 from improvement-plan.md

### Files to touch
- `scripts/run-guardrails.sh`

### Change
At the top of the script, before the per-guardrail loop:
```bash
ACTIVE_PACKAGES_JSON=$(realpath "$ACTIVE_PACKAGES_JSON")
RUN_DIR=$(realpath "$RUN_DIR")
TARGET=$(realpath "$TARGET")
```

### Acceptance criteria
- Run a guardrail that does `cd "$TARGET"` and references `$ACTIVE_PACKAGES_JSON` — must resolve correctly post-cd
- Run `scripts/run-guardrails.sh intake` from a non-pipeline working directory; G05 still passes

### Rollback
Single commit revert.

---

## U2 — CLAUDE.md Generalization Debt Cleanup (PA-006)

> Replace Go-named agent references in language-neutral rule prose so readers don't conclude Go agents run on Python TPRDs.

**Effort**: 4 hours  
**Risk**: low (docs only)  
**Depends**: none  
**Source defect**: PA-006

### Files to touch
- `CLAUDE.md` rules 20, 24, 28, 32

### Specific replacements

| Current text | Replace with |
|---|---|
| `sdk-perf-architect-go` | `sdk-perf-architect-<lang>` |
| `sdk-profile-auditor-go` | `sdk-profile-auditor-<lang>` |
| `sdk-benchmark-devil-go` | `sdk-benchmark-devil-<lang>` |
| `sdk-complexity-devil-go` | `sdk-complexity-devil-<lang>` |
| `sdk-soak-runner-go` | `sdk-soak-runner-<lang>` |
| `b.ReportAllocs()` (rule 32 axis 3) | "language-native alloc reporting (Go: `b.ReportAllocs()`; Python: `tracemalloc` per `python-floor-bound-perf-budget`)" |
| `goroutines` (rule 33 verdict examples) | "language-native concurrency primitives (goroutines / asyncio tasks / etc.)" |
| `Example_*` (rule 28) | "language-native runnable examples (Go `Example_*`; Python doctest blocks)" |
| `govulncheck + osv-scanner` (rule 24) | "active language's vulnerability scanner (Go: govulncheck + osv-scanner; Python: pip-audit + safety)" |

### Add this paragraph at the end of rule 32

> **Per-language dispatch**: every agent named in this rule resolves to its language sibling via `active-packages.json` at run time. The Python pack uses `sdk-perf-architect-python`, `sdk-profile-auditor-python`, etc. — the `<lang>` placeholder is illustrative.

### Acceptance criteria
- `scripts/check-doc-drift.sh` continues to PASS
- `grep -E 'sdk-(perf|profile|benchmark|complexity|soak)-go' CLAUDE.md` returns 0 occurrences
- A reader doing a fresh read of CLAUDE.md doesn't conclude "Go agents run on Python TPRDs"

### Rollback
Docs revert.

---

## U3 — `commands/run-sdk-addition.md` Flag Table Addition

> Spec hygiene: `--run-id` was used in this pilot but isn't documented.

**Effort**: 15 minutes  
**Risk**: trivial  
**Depends**: none

### Files to touch
- `commands/run-sdk-addition.md` (flag table)

### Change
Add row to the flag table:
```markdown
| `--run-id <id>` | auto-UUID | Override generated run-id with a deterministic name (used by pilot runs and resume scenarios; must match TPRD-internal references if any) |
```

### Acceptance criteria
Documented flag matches what `sdk-resourcepool-py-pilot-v1` actually used.

---

## U4 — Decision-Log Identity Protocol for Resumed Agents

> Codify the resume-after-timeout convention used in this pilot (`sdk-impl-lead-toolchain-rerun`) so future runs do it consistently.

**Effort**: 30 minutes  
**Risk**: trivial  
**Depends**: none

### Files to touch
- `skills/decision-logging/SKILL.md` (minor body addition)
- `skills/decision-logging/evolution-log.md` (append entry)

### Change
Add a new section to the skill body:

```markdown
## §Resume-Identity

When a phase lead is resumed (either from stream-idle timeout or after toolchain provisioning mid-run), the resumed agent MUST mint a distinct in-log `agent` field — append a suffix like `-rerun-N` or `-toolchain-rerun` to the canonical agent name (e.g. `sdk-impl-lead-toolchain-rerun`). The 15-entry-per-agent cap then applies separately to each identity. The `phase` and `run_id` fields stay identical.

**Rationale**: a single phase lead's work split across two physical agent invocations was hand-coded in `sdk-resourcepool-py-pilot-v1` as `sdk-impl-lead-toolchain-rerun`. Codifying the convention prevents per-run divergence.
```

Bump `decision-logging` skill from current → minor version bump (e.g., 1.0.0 → 1.1.0). Append evolution-log entry.

### Acceptance criteria
- Skill version bumped, evolution-log entry present
- Future runs that resume a phase lead use the documented suffix convention

---

# Sprint S2 — Discovery & Guardrail Tightening

## U5 — I2.5 Advisory Skill Auto-Discovery (T1 ONLY) — THE BIG ONE

> Closes the manifest gap. TPRD authors can no longer be expected to memorize 61 skills. Discovery scans TPRD content + active-packages skill catalog, surfaces skills the author may have missed, but does NOT auto-supplement (advisory only — supplements promoted in v0.5.2).

**Effort**: 2 days  
**Risk**: low (advisory; no auto-supplement; HITL veto at H1)  
**Depends**: none  
**Source defect**: 2 unused-but-relevant skills surfaced in Phase 4 (`python-client-shutdown-lifecycle`, `python-dependency-vetting`)  
**Architectural note**: T1 ONLY (no domain awareness — see Decision 1)

### Files to touch
- `agents/sdk-intake-agent.md` (add Wave I2.5 section to prompt)
- `phases/INTAKE-PHASE.md` (insert I2.5 description between I2 and I3)
- `.claude/settings.json` (add config block — see below)
- `skills/skill-auto-discovery/SKILL.md` (NEW — codifies the scoring algorithm)
- `.claude/skill-index.json` (register new skill)
- `.claude/package-manifests/shared-core.json` `skills` array (add)

### Settings config to add

```json
"skill_auto_discovery": {
  "enabled": true,
  "mode": "advisory",
  "auto_supplement_threshold": 0.5,
  "advisory_threshold": 0.3,
  "max_supplements_per_run": 10,
  "scope": "T1-only",
  "_note": "T1 = pipeline skills (shared-core + language pack). NO domain awareness — see CLAUDE.md decision-log entry rejecting T2."
}
```

### Algorithm specification

5-signal scoring per candidate skill:

| Signal | Weight | Match logic |
|---|---:|---|
| trigger-keyword | 0.30 | `keyword.lower() in tprd.full_text.lower()` for each keyword in skill frontmatter `trigger-keywords` |
| tag | 0.20 | tag in extracted TPRD tech-signals (asyncio, pytest, etc.) |
| activation-signal | 0.25 | semantic match to TPRD section content |
| cross-reference | 0.15 | skill cites another skill that's in declared §Skills-Manifest |
| agent-citation | 0.10 | skill is cited by an agent in active-packages |

Thresholds:
- `score ≥ 0.5` → auto-supplement candidate (in advisory mode: surface for review only; no manifest mutation)
- `0.3 ≤ score < 0.5` → advisory entry
- `score < 0.3` → excluded
- §Non-Goals filter: any skill matching content in TPRD §3 (Non-Goals) is excluded regardless of score
- Hard-skip list: `["decision-logging", "lifecycle-events", "context-summary-writing", "conflict-resolution"]` (omnipresent plumbing)
- Tie-break: alphabetical by skill name (deterministic per CLAUDE.md rule 25)

### Output file: `runs/<run-id>/intake/skill-auto-discovery.md`

```markdown
# Skill Auto-Discovery (Wave I2.5)

## Auto-supplement candidates (score ≥ 0.5)
[Advisory in v0.5.1; promoted to actual supplement in v0.5.2]

| Skill | Score | Reasons | TPRD §-match |
|---|---|---|---|
| python-client-shutdown-lifecycle | 0.85 | trigger-keyword "aclose" in §5.2; trigger-keyword "__aexit__" in §5.1; tag "lifecycle" matches; cross-references python-asyncio-patterns (declared) | §5.2 |
| ... | ... | ... | ... |

## Advisory (0.3 ≤ score < 0.5)
[For TPRD author awareness only — no action required]

| Skill | Score | Reasons | Note |
|---|---|---|---|

## Excluded
| Skill | Reason |
|---|---|
| python-otel-instrumentation | §3 Non-Goal: "v1.0.0 ships without OTel" |
```

### `active-packages.json` schema bump

Add `effective_skills_manifest` field (in advisory mode, equal to declared until v0.5.2 promotion):

```json
"effective_skills_manifest": {
  "declared": [...],
  "advisory_supplements": [...],
  "effective": [...]
}
```

### Acceptance criteria
- Run intake on `motadata-sdk/TPRD.md` (or a synthetic test TPRD)
- Output file `runs/<run-id>/intake/skill-auto-discovery.md` exists with all 3 sections
- Reports `python-client-shutdown-lifecycle` (score ≥ 0.7 from keyword match on "aclose"/"__aexit__"), `python-doctest-patterns` (≥ 0.7 from "Examples"), `python-dependency-vetting` (≥ 0.6 from "pip-audit")
- `effective_skills_manifest.effective` equals `declared` (advisory mode — manifest unchanged)
- H1 surface includes one-line summary: "I2.5 surfaced N advisory supplements; review at intake/skill-auto-discovery.md"
- Determinism: same TPRD twice produces identical `skill-auto-discovery.md`

### Phase 4 metric to add

`auto_supplemented_actually_cited_pct` — track per run; raise WARN if < 40% over 3 runs (signals threshold too aggressive). Lives in `baselines/shared/auto-discovery-effectiveness.jsonl`.

### Rollback
Set `skill_auto_discovery.enabled: false` in settings.json — wave skips entirely.

### Promotion path
- **v0.5.2**: promote auto-supplement at score ≥ 0.5 (HITL veto still at H1)
- **v0.5.3**: tune thresholds based on 2-3 runs of empirical data
- **v0.6.0+**: consider promoting `§Skills-Manifest` to optional once `auto_supplemented_actually_cited_pct ≥ 60%` over ≥3 runs

---

## U6 — `min_version` Enforcement in `toolchain.<command>` (D1)

> Promote `toolchain.<command>.min_version` from informational to BLOCKER at intake. Closes PA-004 (ruff 0.4 vs PEP 639) and PA-009 (pytest 8.4.2 CVE) class of failures.

**Effort**: 4 hours  
**Risk**: low (BLOCKER promotion at intake; was previously WARN at M9)  
**Depends**: none

### Files to touch
- `.claude/package-manifests/python.json` — `toolchain.lint.min_version`, `toolchain.test.min_version`, `toolchain.typecheck.min_version`
- `.claude/package-manifests/go.json` — same
- `scripts/run-toolchain.sh` — extend to compare `--version` output against `min_version` and exit non-zero on miss
- `scripts/guardrails/G-toolchain-version.sh` (NEW) — calls `run-toolchain.sh --check-versions`, BLOCKER on miss
- `.claude/package-manifests/shared-core.json` `guardrails` array — add `G-toolchain-version`

### Acceptance criteria
- Set ruff to `min_version: 0.6.5` in python.json. Run intake. With ruff 0.4.10 installed → BLOCKER at intake (not M9)
- Bump ruff to 0.6.5 → intake PASSES
- Old TPRDs without `min_version` declared → guardrail no-ops (backward-compatible)

### Rollback
Drop `min_version` fields; guardrail no-ops automatically.

---

## U7 — `G-toolchain-probe.sh` (THE TOOLCHAIN SAFETY NET)

> Closes the entire TOOLCHAIN-ABSENCE failure class. Caught at intake instead of cascading through M3.5/M5/M7/M9 INCOMPLETE markers.

**Effort**: 1 day  
**Risk**: low (BLOCKER at intake on a clear failure mode)  
**Depends**: none, but pairs naturally with U6  
**Source defect**: TOOLCHAIN-ABSENCE root cause — single largest cost driver in this pilot

### Files to touch
- `scripts/guardrails/G-toolchain-probe.sh` (NEW)
- `.claude/package-manifests/shared-core.json` `guardrails` array (add)
- Removed from `aspirational_guardrails`

### Header
```bash
# phases: intake
# severity: BLOCKER
# rationale: Per-language toolchain preflight; closes TOOLCHAIN-ABSENCE cascade
```

### Script logic
```bash
# 1. Read $ACTIVE_PACKAGES_JSON to find active language pack
# 2. For each pack with toolchain.<command> declared, exec "<command> --version"
# 3. BLOCKER on any non-zero exit
# 4. Output a clear install hint per missing tool:
#    "MISSING: ruff (declared in python.json toolchain.lint)"
#    "  install: .venv/bin/pip install 'ruff>=0.6.5,<0.8'"
# 5. PASS reports: "all N declared toolchain commands probed successfully"
```

If `min_version` is declared (U6), check version compatibility; otherwise just check presence.

### Acceptance criteria
- On a host with no Python toolchain (mimic this pilot's initial state): G-toolchain-probe BLOCKER at intake; specific install hints for missing tools
- On the venv-provisioned host: PASS
- After the apt failure pattern from this pilot: clear actionable error message

### Combined effect with U6
At v0.5.2 ship, the TOOLCHAIN-CASCADE failure class is closed. Future runs catch toolchain absence at intake/H0/H1, not at M9.

### Rollback
Move back to `aspirational_guardrails`; intake skips it.

---

# Sprint S3 — Devil Rubric & Resilience

## U8 — `runtime-impact-unknown` Severity Bucket (CV-001 Class)

> Add a severity bucket that says "this looks LOW but may be HIGH at runtime — must be re-validated by dynamic verification before close." Closes the CV-001 class of bugs (typing import missing → `cast()` broken at runtime).

**Effort**: 4 hours  
**Risk**: low (additive severity; existing rubrics still apply)  
**Depends**: none  
**Source defect**: CV-001 — convention-devil classified missing-import as LOW; only mypy-strict at M5b caught it

### Files to touch
- `agents/sdk-convention-devil-python.md` (devil prompt — add the new bucket)
- `agents/sdk-convention-devil-go.md` (mirror)
- `agents/sdk-design-devil.md` (design-phase mirror)
- `skills/review-fix-protocol/SKILL.md` (acknowledge new bucket; route differently)
- `skills/review-fix-protocol/evolution-log.md` (append entry)

### New rubric entry (add to each devil prompt)

```markdown
### LOW (runtime-impact-unknown)

A finding tagged `runtime-impact-unknown` is treated as LOW for review-fix scheduling but **must be re-validated by the impl-phase dynamic-verification toolchain** (mypy / pytest / runtime probe) before close. If dynamic verification surfaces a runtime symptom, severity escalates to HIGH retroactively.

**Canonical example**: missing import for a name used in `cast(...)` or `typing.<X>` annotations. Static patterns flag it as a style nit; runtime verification catches it as a `NameError` or `cast()` failure.

**When to use this tag**:
- Type-annotation-related issues that may interact with runtime (Python's `from __future__ import annotations` defers evaluation but `typing.cast` is eager)
- Import-order issues that may interact with import-time side effects
- Decorator parameter changes whose runtime semantics aren't fully captured by type checkers
```

### Acceptance criteria
- Synthesize a test TPRD with a typing-import LOW finding
- Verify the convention-devil tags it `runtime-impact-unknown`
- Verify mypy-strict in M5b would have caught it
- Verify the new severity routes through review-fix without short-circuiting closure at iter-1

---

## U9 — Guardrail Header Schema: `mode_skip` + `min_phase` Predicates (D2)

> Add header predicates so guardrails can skip themselves cleanly per Mode (A/B/C) or per minimum phase. Closes G200-py / G32-py false-fires at design phase for Mode A.

**Effort**: 1 day  
**Risk**: low (header parsing is additive)  
**Depends**: none

### Files to touch
- `scripts/run-guardrails.sh` (parse new headers, filter accordingly)
- `scripts/guardrails/G200-py.sh` header — add `mode_skip: [A]`
- `scripts/guardrails/G32-py.sh` header — add `min_phase: implementation`
- `docs/PACKAGE-AUTHORING-GUIDE.md` — document the new header fields

### New header schema
```bash
# phases: design implementation testing
# mode_skip: A B          # optional; skip in these modes
# min_phase: implementation # optional; skip until this phase
# severity: BLOCKER WARN INFO
```

### Acceptance criteria
- Re-run intake on Mode A TPRD: G200-py and G32-py do NOT fire at design phase (currently they fire and require lead waivers)
- They DO fire at implementation phase
- Hypothetical Mode B TPRD: G200-py runs at design (Mode B has existing pyproject.toml)

---

## U10 — `sdk-impl-lead` Halt Policy on Cumulative INCOMPLETE (D3)

> Codify the cascade pattern this pilot exhibited: ≥2 INCOMPLETE-by-tooling in same wave or ≥3 across phase = mandatory halt. Independent of severity rubric — INCOMPLETE-by-tooling is treated as a process blocker for cumulative-flow purposes.

**Effort**: 4 hours  
**Risk**: low (changes prompt text; reversible)  
**Depends**: U7 (toolchain-probe at intake catches the problem earlier; halt policy is a backstop)

### Files to touch
- `agents/sdk-impl-lead.md` (add §Halt-on-Cumulative-INCOMPLETE clause)
- `agents/sdk-testing-lead.md` (mirror, if applicable)

### Add to impl-lead prompt
```markdown
## §Halt-on-Cumulative-INCOMPLETE

**Cumulative-INCOMPLETE halt policy**: When ≥2 INCOMPLETE-by-tooling verdicts accumulate within a single wave OR ≥3 across the impl phase, the impl-lead MUST halt the wave, log a `BLOCKER: cumulative-incomplete` decision-log entry, and surface to the orchestrator. Do NOT continue to subsequent waves. This is independent of severity rubric — INCOMPLETE-by-tooling is treated as a blocker for cumulative-flow purposes only.

**Rationale**: this pilot run's TOOLCHAIN-CASCADE pattern marched through M3.5 → M5 → M7 → M9 accumulating INCOMPLETEs because each individual gate verdict was technically correct. Halt policy provides escalation logic that individual gate logic doesn't.
```

### Acceptance criteria
- Synthesize scenario with ≥2 INCOMPLETE in M3.5 → impl-lead halts, doesn't proceed to M4
- Surface message includes count + classification breakdown ("M3.5: 2 INCOMPLETE-by-tooling on G104; M4 not started")

---

# Sprint S4 — Phase 4 Orchestration & Resilience

## U11 — `sdk-feedback-lead` Agent (M3)

> Replace orchestrator manual wiring of Phase 4 (F1/F2/F3 waves) with a dedicated feedback-lead agent, parallel to existing design/impl/testing leads.

**Effort**: 1.5 days  
**Risk**: medium (new agent; refactor of Phase 4 dispatch)  
**Depends**: none, but improves durability of U12 below  
**Source observation**: in `sdk-resourcepool-py-pilot-v1`, the orchestrator (Claude in this conversation) had to hand-wire all of Phase 4. That's brittle and run-specific.

### Files to touch
- `agents/sdk-feedback-lead.md` (NEW — agent prompt)
- `phases/FEEDBACK-PHASE.md` (refactor to delegate to feedback-lead)
- `commands/run-sdk-addition.md` execution flow §5 — update Phase 4 step
- `.claude/package-manifests/shared-core.json` `agents` array (add)

### Agent responsibility
Orchestrates:
- **F1** (parallel): metrics-collector + sdk-skill-coverage-reporter + sdk-skill-drift-detector + baseline-manager + phase-retrospector
- **F2** (parallel): defect-analyzer + root-cause-tracer
- **F3** (sequential): improvement-planner → learning-engine
- Surfaces H10 to user

### Acceptance criteria
- Re-run Phase 4 of `sdk-resourcepool-py-pilot-v1` (using `--phases feedback --resume sdk-resourcepool-py-pilot-v1`) with sdk-feedback-lead as orchestrator
- All artifacts produced (metrics, retrospective, defect-log, root-cause-traces, improvement-plan, learning-notifications)
- Output equivalent to what F1/F2/F3 produced manually

---

## U12 — Mid-Wave Checkpointing Protocol (M1)

> Codify the resume-after-timeout / resume-after-toolchain-bootstrap pattern. Phase leads write per-wave summaries that survive stream-idle timeouts.

**Effort**: 2 days  
**Risk**: medium (touches all phase-lead agents)  
**Depends**: U11 if both ship same sprint (they're complementary)

### Files to touch
- `skills/pipeline-resume-protocol/SKILL.md` (NEW — codifies the resume contract)
- `agents/sdk-{intake,design,impl,testing,feedback}-lead.md` (each adds a §Checkpoint clause)
- `runs/<run-id>/state/run-manifest.json` schema — add per-wave `checkpointed_at` field
- `.claude/skill-index.json` (register new skill)

### Checkpoint contract
After each wave completes (M1, M2, M3, M3.5, etc.), the phase lead writes:
- `runs/<run-id>/<phase>/wave-<wave-id>-summary.md` — what was produced this wave
- Updates `state/run-manifest.json` with `phases.<phase>.waves.<wave-id> = { status: completed, checkpointed_at: <timestamp>, artifacts: [...] }`

On resume after stream-idle or toolchain provisioning:
1. Read manifest first
2. See which waves are `completed`
3. Start at the first non-completed wave
4. Mint distinct decision-log identity per U4 protocol

### Acceptance criteria
- Synthesize a resume scenario (e.g., kill impl-lead mid-M5)
- Resume from manifest — verifies M1/M2/M3/M3.5/M4 are NOT re-run
- M5 starts fresh; M6/M7/etc. complete normally

---

## U13 — `scripts/compute-shape-hash.sh` for Python (PA-014)

> Today only Go has a compute-shape-hash implementation. Extend with `--lang` switch so per-language `output-shape-history.jsonl` baselines can be computed properly.

**Effort**: 1 day  
**Risk**: low (script-only)  
**Depends**: none

### Files to touch
- `scripts/compute-shape-hash.sh` — extend with `--lang <X>` switch
- `agents/baseline-manager.md` — invoke with `--lang $TARGET_LANG` from active manifest

### Logic
- For Python: parse `api.py.stub` (or actual `src/` if running post-impl), extract sorted exported-symbol signatures (functions, classes, dataclasses, Protocols, exceptions), SHA256 the canonical sorted form
- For Go: existing logic
- Other languages: emit "not yet implemented for <lang>" warning, no hash

### Acceptance criteria
- Run on `sdk-resourcepool-py-pilot-v1` impl tree → produces hash matching what was synthesized manually (`d2f7c9e5...`)
- Re-run on identical tree → same hash (deterministic)
- Modify a symbol signature → different hash (sensitive)

---

# Parallel Track — U14 — Author 3 Missing Skills (Human-PR)

> The 3 Cat-B skill proposals filed in `docs/PROPOSED-SKILLS.md` need human-authored skill bodies before they can be referenced by any TPRD or used by Mode C maintenance run.

**Effort**: 3 days total (parallelizable across reviewers)  
**Risk**: low (skill content; reversible by un-merging)  
**Depends**: none for authoring; B1 + B3 needed for Mode C maintenance run (M1)

### Skills to author

| ID | Skill name | Scope | Source proposal |
|---|---|---|---|
| **B1** | `python-bench-harness-shapes` | python | docs/PROPOSED-SKILLS.md §"Proposed: python-bench-harness-shapes" |
| **B3** | `python-floor-bound-perf-budget` | python | docs/PROPOSED-SKILLS.md §"Proposed: python-floor-bound-perf-budget" |
| **B4** | `soak-sampler-cooperative-yield` | shared-core | docs/PROPOSED-SKILLS.md §"Proposed: soak-sampler-cooperative-yield" |

### Files to create per skill
- `skills/<skill-name>/SKILL.md` (NEW)
- `skills/<skill-name>/evolution-log.md` (initial v1.0.0 entry)

### Files to update
- `.claude/skill-index.json` — register the 3 new skills
- `.claude/package-manifests/python.json` `skills` array — add B1 and B3
- `.claude/package-manifests/shared-core.json` `skills` array — add B4
- `docs/PROPOSED-SKILLS.md` — remove the 3 proposal entries (now landed)

### Skill body source
Copy from `docs/PROPOSED-SKILLS.md` proposal blocks (already drafted by improvement-planner) and elaborate per the `proposed_body_outline` of each.

### Acceptance criteria
- `scripts/check-doc-drift.sh` PASSES (skill-index.json ↔ filesystem in sync, G90)
- `scripts/validate-packages.sh` PASSES (every skill belongs to exactly one manifest)
- Skill bodies have version `1.0.0` frontmatter, evolution-log.md, runnable Examples (where applicable)
- Mode C run (M1) can cite these skills

### Note: B2 was the G-toolchain-probe guardrail
B2 ships as U7 (a guardrail script, not a skill). It's already accounted for. The 4-Cat-B set is B1 + B2 + B3 + B4; B2 is U7's content.

---

# Maintenance Run — M1 — Mode C Run on `motadata-sdk` (After U14 + S2 Land)

> A small, scoped maintenance run that closes the v1.0.0 → v1.0.1 backlog (PA-001/002/004/009/013). Validates that Mode C works end-to-end on a Python package.

**Effort**: ~2 hours pipeline run + review  
**Risk**: low (Mode C honors existing impl; merge-planner preserves v1.0.0 surface)  
**Depends**: U14 (specifically B1 + B3) and S2 (U6 + U7)

### Trigger
```bash
export SDK_TARGET_DIR=/home/meet-dadhania/Documents/motadata-ai-pipeline/motadata-sdk
/run-sdk-addition --spec motadata-sdk/TPRD.md --run-id sdk-resourcepool-py-maintenance-v1
```

### Expected pipeline behavior
1. **Intake**: detects existing API → Mode C
2. **Phase 0.5**: `sdk-existing-api-analyzer-python` snapshots the v1.0.0 surface
3. **Design**: `sdk-perf-architect-python` reads B3 skill → amends `design/perf-budget.md` with `floor_type: language-floor` for `PoolConfig.__init__` + `AcquiredResource.__aenter__`
4. **Impl**: `sdk-merge-planner` honors v1.0.0 impl as preserve-as-is. Touches:
   - `tests/bench/bench_try_acquire.py` (rewrite using B1 sync-fast-path-in-async harness — closes PA-001)
   - `tests/bench/bench_aclose.py` (rewrite using B1 bulk-teardown harness — closes PA-002)
   - `pyproject.toml` (bump pytest>=9.0.3 — closes PA-009; bump ruff>=0.6.5 — closes PA-004; triage 26 ruff findings)
5. **Testing**:
   - G104 + absolute target check: 8/8 PASS (no INCOMPLETE rows)
   - G43-py PASS (ruff parses pyproject.toml)
   - G32-py PASS (pytest 9 has CVE fix)
6. **Outcome**: bumps wheel version to v1.0.1; branch `sdk-pipeline/sdk-resourcepool-py-maintenance-v1` ready for merge

### Acceptance criteria
- v1.0.1 wheel: 64+ tests PASS, 0 INCOMPLETE, ≥92% coverage
- Phase 4 backlog reduced from 14 → ~5 items (PA-001/002/004/009/013 closed; PA-003/005/006/007/008/010/011/012/014 remain or transformed)
- D2 cross-language quality: this is run #2 for Python; rolling-3 still unmet but baseline strengthens

---

# Cross-Cutting Concerns

## Validation Strategy

- **Each unit ships with a test TPRD** that exercises the new behavior. Reuse `motadata-sdk/TPRD.md` where possible; synthesize synthetic ones (`runs/<id>/synthetic-tprd.md`) for negative cases.
- **Backward compatibility check** for every unit: an old run should still be replayable without the new feature firing.
- **Determinism check** for U5 (auto-discovery): same TPRD twice in a fresh run must produce identical `skill-auto-discovery.md` per CLAUDE.md rule 25.

## Baseline Impact

| Unit | Baseline change |
|---|---|
| U5 | New `baselines/shared/auto-discovery-effectiveness.jsonl` (tracks `auto_supplemented_actually_cited_pct` per run) |
| U11 | Per-phase orchestration time newly measurable (was implicit when orchestrated by hand) |
| U13 | `baselines/python/output-shape-history.jsonl` becomes accurate (was synthesized manually before) |
| Others | None |

## Documentation Updates Accumulated

| Doc | Updated by |
|---|---|
| `CLAUDE.md` rules 20/24/28/32 | U2 |
| `phases/INTAKE-PHASE.md` | U5 (Wave I2.5 insertion) |
| `phases/FEEDBACK-PHASE.md` | U11 (lead refactor) |
| `docs/PACKAGE-AUTHORING-GUIDE.md` | U9 (header schema) |
| `commands/run-sdk-addition.md` | U3 (--run-id flag) |
| `docs/PROPOSED-SKILLS.md` | U14 (remove landed proposals) |

## Pipeline Version Bumps

- v0.5.0 → v0.5.1 after S1 ships (quick wins)
- v0.5.1 → v0.5.2 after S2 ships (discovery + toolchain safety net)
- v0.5.2 → v0.6.0 after S3 + S4 ship (S3 changes guardrail header schema = minor breaking change → minor bump)
- Update `.claude/settings.json` `pipeline_version` and propagate per CLAUDE.md G06 rule

---

# Newly Identified — Post-v0.7.0 Audit (2026-05-06)

These items were surfaced by a fact-based audit on 2026-05-06 — independent of the original v0.5→v0.6 roadmap above. They target v0.7.0 (already shipped) running cleanly today; the items below close documented gaps the audit confirmed exist.

## U15 — Performance-baseline schema canonicalization (Gap C)

**Status**: ✅ **CLOSED 2026-05-06** — commits `a21841f..00f5b6b` on branch `v6`. All 7 phases complete; G87 guardrail wired; existing on-disk Go and Python baselines validated as canonical reference.

**Why this exists**: an audit found four different schemas describing the same file `baselines/<lang>/performance-baselines.json`:

| # | Source | Shape |
|---|---|---|
| 1 | `agents/baseline-manager.md:142-172` (DOCUMENTED owner) | Flat `entries: [{endpoint, baseline_p99_ns, history}]` + `units` map |
| 2 | `agents/sdk-benchmark-devil-go.md:23` (DOCUMENTED reader) | Per-package text file `baselines/perf-<pkg>.txt` (benchstat format) |
| 3 | `baselines/go/performance-baselines.json` (ACTUAL) | `packages.<pkg>.symbols.<bench>: {ns_per_op_median, bytes_per_op_median, allocs_per_op_median, samples}` — no time-series |
| 4 | `baselines/python/performance-baselines.json` (ACTUAL) | `packages.<pkg>.history[].{run_id, pipeline_version, recorded_at, regression_verdict, g108_oracle_verdict, alloc_audit_g104, complexity_sweep_g107, symbols.<sym>.{p50_us, budget_status, headroom, oracle_*, ...}}` — full time-series + verdict trail |

The Python schema is intentionally richer (history + per-run verdicts G104/G107/G108 + cross-language oracle + budget tracking + headroom). **Decision (locked 2026-05-06): preserve divergence honestly. Do NOT promote Go to Python's shape.**

**Owner clarity** (verified 2026-05-06 via `tools:` declarations): `baseline-manager` is the SOLE writer; `sdk-benchmark-devil-{go,python}` are read-only proposers via `runs/<id>/testing/proposed-baseline-{lang}.json` which `baseline-manager` merges post-H8. The drift is purely documentation: the writer's prompt describes a flat-entries shape that nothing on disk uses.

**Phases** (~6-8 hours total):
1. **DISCOVER** ✅ DONE 2026-05-06 (owner map confirmed; `baseline-manager` is sole writer).
2. **DECIDE** — formalize "shared envelope (`schema_version`, `language`, `scope`, `packages`) + per-language extension" decision in writing.
3. **AUTHOR** new file `docs/PERFORMANCE-BASELINE-SCHEMA.md` — single source of truth: envelope, per-language packages structure (Go vs Python, both intentional), schema_version semver rules, validation rules, owner declaration, consumer declarations, why divergence is preserved.
4. **REWRITE** stale agent prompts:
   - `agents/baseline-manager.md:140-172` — replace flat-entries block with stub pointing to canonical doc; rewrite to match shared envelope
   - `agents/sdk-benchmark-devil-go.md:12,23,42` — replace `baselines/perf-<pkg>.txt` (text) with rich JSON path + key access (`packages.<pkg>.symbols.<bench>`)
   - `agents/sdk-benchmark-devil-python.md` — verify alignment + add cross-ref
   - `agents/sdk-soak-runner-{go,python}.md`, `agents/sdk-drift-detector.md`, `agents/sdk-complexity-devil-{go,python}.md`, `agents/sdk-profile-auditor-{go,python}.md` — add one-line cross-refs if they touch this file
5. **DECLARE writer** — add `**Schema owner**: baseline-manager` to canonical doc + reciprocal claim in `baseline-manager.md`.
6. **GUARDRAIL G70.sh** (next free G-number; verify before claiming) — validates envelope + per-language extension at Phase 3 exit. BLOCKER on schema mismatch. WARN-only initially, escalate to BLOCKER after 2 clean runs.
7. **TEST + COMMIT** — single commit covering Phases 3-6.

**Risk**: low. All edits are documentation/prompt level; no baseline data migration; no benchmarking-code changes; existing on-disk files become canonical reference (they ARE the truth).

**Deliverables**:
- 1 new doc: `docs/PERFORMANCE-BASELINE-SCHEMA.md`
- 1 new guardrail: `scripts/guardrails/G70.sh`
- 2 substantive prompt rewrites: `agents/baseline-manager.md`, `agents/sdk-benchmark-devil-go.md`
- ~6 cross-ref additions across consumer agents
- 2 manifest updates: `.claude/package-manifests/{shared-core.json,go.json,python.json}` to register G70

**Out of scope for U15** (deliberately):
- Migrating Go baseline to Python's richer history+verdict shape (locked: divergence preserved)
- Authoring G108 oracle for Go (separate future concern)
- Touching benchmarking code in either language

## U16 — Real-client coverage signaling (Gap D)

**Why this exists**: testcontainers cover ~90% of integration testing, but tests *skipped* under the fake (because the fake doesn't implement the operation) currently pass silently. No guardrail catches "TPRD §7 symbol has no integration coverage at all."

**Documented evidence**: `agents/sdk-testing-lead.md:140-142` records the dragonfly-s2 incident — miniredis v2.37 didn't implement Redis 7.4's HEXPIRE family; tests for `HExpire`, `HExpireAt`, `HPExpire`, `HPersist` were skipped under the fake. Pipeline reported PASS. Only a real Dragonfly cluster proves those four methods work.

**Other categories where containers are insufficient** (general): auth flows (IAM/STS, OAuth refresh, mTLS with private CA), cluster topology (Redis Cluster MOVED/ASK, Kafka rebalance, NATS JetStream failover), real server load (real 5xx storms, real `Retry-After`), eventual consistency (real S3 read-after-write, real DynamoDB), vendor-specific quirks.

**Today**: `agents/sdk-testing-lead.md:140-142` only RECOMMENDS that TPRD §11.1 lists `not-covered-by-fake-client:` methods. No guardrail enforces it; no artifact is emitted for downstream consumers.

**Two missing pieces**:
1. **Guardrail** (e.g. `G71.sh`): fails Phase 3 if any TPRD §7 symbol has no integration test AND no `not-covered-by-fake-client: <reason>` annotation in TPRD §11.1.
2. **Artifact** `runs/<id>/testing/REAL-CLIENT-SMOKE.md`: lists each fake-skipped/fake-uncovered method with copy-pasteable real-backend invocation (e.g. `MOTADATA_S3_REAL_ENDPOINT=… go test -tags=integration -run RealS3 ./…`).

**Scope is signaling, NOT execution**. The pipeline NEVER runs real-cloud tests itself (cost, creds, blast radius, flake). The pipeline's job is only to TELL the consumer-team-owned smoke job which methods need real-cloud follow-up.

**Phases** (~4-6 hours total):
1. Audit TPRD template — add canonical `§11.1.fake-client-gaps:` schema.
2. Author `G71.sh` (validate every §7 symbol has integration coverage OR a fake-client-gap annotation).
3. Extend `agents/sdk-testing-lead.md` to emit `runs/<id>/testing/REAL-CLIENT-SMOKE.md` whenever any §7 symbol is fake-uncovered.
4. Wire G71 into testing-phase exit + manifest.
5. Test + commit.

**Risk**: low. Pure addition; no behavior change for SDKs that already have full integration coverage.

---

# When to Revisit Locked Decisions

Don't reopen these decisions until **at least one** empirical trigger fires.

## Decision 1 — Drop T2 domain packs

Triggers to revisit:

1. Same domain pattern surfaces in ≥3 separate TPRDs, and each TPRD re-derives it (visible as repeated `learning-engine` proposals across runs that all say "add X for redis use case")
2. Discovery noise rate exceeds 30% (auto-supplemented skills that turn out to be irrelevant) — would suggest discovery needs domain context to disambiguate
3. A specific guardrail needs to be BLOCKER in some TPRDs and silent in others AND the same logical check appears in ≥3 TPRDs
4. TPRD §7/§10 sections balloon past ~3000 lines because they keep restating domain semantics — would suggest knowledge accretion is genuinely needed

If none fire over the next 6 months and 10+ runs, T2 was correctly avoided. If 2+ fire, you have real evidence to motivate adding T2 with calibrated scope.

## Decision 2 — Skills/Guardrails Manifests REQUIRED

Triggers to revisit (`§Skills-Manifest` only — `§Guardrails-Manifest` never moves to optional):

1. `auto_supplemented_actually_cited_pct ≥ 60%` over ≥3 runs (I2.5 is reliably picking the right skills)
2. ≥3 TPRDs in a row where declared §Skills-Manifest exactly matches I2.5's auto-supplement set (declaration is now redundant)
3. TPRD authoring time visibly bottlenecks on §Skills-Manifest research (qualitative; ask the team)

When these fire, demote `§Skills-Manifest` to OPTIONAL: intake I2 emits WARN-not-BLOCKER on absence; discovery fills the gap.

---

# Glossary

- **T1** — Pipeline skills (shared-core + per-language). Today's catalog.
- **T2** — Domain packs (S3, Redis, Kafka, etc.). REJECTED per Decision 1.
- **T3** — TPRD-embedded specifics (inline in §7/§10/§3). Stays as today.
- **Cat A** — `learning-engine` auto-applies (existing-skill body patches; cap=3/run).
- **Cat B** — Human-PR new artifact (new skill / guardrail / agent; cap=0/run at runtime).
- **Cat C** — Next-run target-SDK changes (rides Mode C maintenance run).
- **Cat D** — Process / threshold proposals (filed to docs/PROPOSED-PROCESS.md).
- **PA-NNN** — Phase 4 backlog item identifier; populated by improvement-planner.
- **D6=Split** — Pilot decision: rule shared, examples per-lang. Empirically confirmed by pilot.
- **D2=Lenient** — Pilot decision: cross-language quality baseline uses lenient comparison; partition flip on rolling-3 evidence.

---

# Quick Start — What to Do Right Now

If you have one day:
1. Run U1 (`scripts/run-guardrails.sh` realpath fix) — 5 minutes
2. Read this whole doc carefully
3. Start U2 (CLAUDE.md cleanup) — 4 hours
4. Skim U5 design and start sketching the I2.5 algorithm in a draft skill body

If you have one week:
1. Complete S1 (U1 + U2 + U3 + U4) — Day 1
2. Complete U5 (I2.5 advisory) — Days 2–3
3. Complete U6 + U7 (toolchain enforcement + probe) — Day 4
4. Complete U8 + U9 (severity bucket + guardrail header) — Days 5–6
5. Stop and validate with a synthetic test run — Day 7

If you have a month:
- Complete all 14 units + M1
- Pipeline at v0.6.0 with toolchain-cascade closed, manifest gap closed, devil rubric tightened, mid-wave checkpointing live

---

# Reference

- This roadmap was synthesized from: `runs/sdk-resourcepool-py-pilot-v1/feedback/improvement-plan.md`, `retrospective.md`, `defect-log.jsonl`, `root-cause-traces.md`, plus orchestration-level observations from the pilot.
- Authored: 2026-04-30
- Pipeline version at authoring: 0.5.0
- Target end-state: 0.6.0
- Prior baselines impacted: `baselines/shared/quality-baselines.json` (D2 progressive trigger on `sdk-impl-lead`), `baselines/python/{performance,coverage,output-shape-history,devil-verdict-history}.json` (all SEED — first run)

---

> **Working principle**: ship small. Each unit is one PR. Each PR can roll back independently. The pipeline gets better one shipping unit at a time.
