<!-- cross_language_ok: true — top-level pipeline doc references per-pack tooling and the multi-tenant SaaS platform context (per F-008 in migration-findings.md). Authoritative project description: SDK is built FOR multi-tenant SaaS consumers; multi-tenant guardrails (TenantID, JetStream, MsgPack, schema-per-tenant) are in-scope. -->

# Pipeline Lifecycle & Usage

Operational guide for the NFR-driven `motadata-sdk-pipeline`. Covers the two nested loops, HITL gates, per-request workflow, artifacts, exit codes, resume behavior, and a concrete walkthrough.

---

## 1. Two loops, not one

The pipeline has two nested feedback loops:

```
┌─────────────────────────────────────────────────────────────────┐
│  CROSS-RUN LOOP (self-evolution across TPRDs)                   │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  SINGLE-RUN LOOP (one TPRD → one branch)               │    │
│  │                                                          │    │
│  │   TPRD → Intake → Design → Impl → Testing → Docs → Feedback   │
│  │                ↑                                         │    │
│  │                └── review-fix sub-loop (per phase)      │    │
│  │                                                          │    │
│  └────────────────────────────────────────────────────────┘    │
│                              │                                   │
│              baselines + evolution-reports                       │
│                              │                                   │
│              learning-engine patches existing skills             │
│              drift/coverage reporters file proposals             │
│                              │                                   │
│              (humans author new skills offline → PR)             │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Prerequisites (one-time setup)

```bash
# 1. Target SDK must be a git repo
cd $SDK_TARGET_DIR/.. && git status

# 2. Export the target dir
export SDK_TARGET_DIR=~/projects/nextgen/<sdk-target>/<src-root>

# 3. Verify toolchain (matches environment-prerequisites-check skill)
go version                  # 1.26+
<vuln-scanner> --version
<lockfile-scanner> --version
<bench-comparator> --version
docker --version            # for testcontainers
jq --version

# 4. Verify skill library + guardrail scripts are intact
python3 -c "import json; json.load(open('skills/skill-index.json'))"
ls scripts/guardrails/G*.sh
```

---

## 3. Per-request workflow (human-authored, off-pipeline)

Before `/run-sdk-addition` fires, **you** do this:

### 3a — Author the TPRD

`runs/my-feature-tprd.md` must contain **all 14 sections** plus the two manifests:

```markdown
## §1 Request Type  (Mode A | B | C)
## §2 Scope         (in-scope + non-goals)
## §3 Motivation
## §4 Functional Requirements      ← FR-*-NN table
## §5 Non-Functional Requirements  ← numeric gates (p50/p99, throughput, allocs)
## §6 Dependencies + Config validation
## §7 Config + API                 ← Go code block (signatures + sentinel errors)
## §8 Observability                ← OTel spans + metrics catalog
## §9 Resilience                   ← CB + retry + reconnect
## §10 Security
## §11 Testing                     ← unit + integration + bench + fuzz
## §12 Breaking-Change Risk
## §13 Rollout                     ← phase gate sequence
## §14 Pre-Phase-1 Clarifications  ← known open questions (OQ-*)

## §Skills-Manifest                ← REQUIRED
| Skill | Min version | Why required |
| go-sdk-config-struct-pattern | 1.0.0 | FR-CON-07 |
| ...

## §Guardrails-Manifest            ← REQUIRED
| Guardrail | Applies to | Enforcement |
| G01 | all | BLOCKER |
| G23 | intake | WARN (§Skills-Manifest; non-blocking) |
| G24 | intake | BLOCKER (§Guardrails-Manifest) |
| G95-G103 | impl | BLOCKER |
| ...
```

See `send.md` for a full worked example (NATS client, 781 lines).

### 3b — Pre-flight check the manifests yourself

Use the slash command (recommended):

```bash
/preflight-tprd --spec runs/my-feature-tprd.md
```

Or by hand:

```bash
# Are all declared skills in the library at ≥ required version?
jq -r '.skills[] | .[].name' skills/skill-index.json | sort > /tmp/have.txt
# Extract §Skills-Manifest skill names from your TPRD into /tmp/need.txt
comm -23 /tmp/need.txt /tmp/have.txt   # any output = WARN (non-blocking; filed to docs/PROPOSED-SKILLS.md)

# Are all declared guardrails implemented? (BLOCKER if any missing)
ls scripts/guardrails/G*.sh | xargs -n1 basename | sed 's/.sh//' | sort > /tmp/have-g.txt
```

If anything is missing, **author it via PR first**. The pipeline will not synthesize it for you.

---

## 4. Invocation

```bash
# Standard (detailed TPRD provided)
/run-sdk-addition --target $SDK_TARGET_DIR --spec runs/my-feature-tprd.md

# Preview only (no writes to target)
/run-sdk-addition --dry-run --spec runs/my-feature-tprd.md

# NL one-liner (DISCOURAGED — forces heavy clarification loop at intake)
/run-sdk-addition --target $SDK_TARGET_DIR "add Redis streams consumer client"

# Subset of phases (iterate on a single phase)
/run-sdk-addition --spec runs/my-tprd.md --phases intake,design

# Resume a halted run from its last checkpoint
/run-sdk-addition --resume <run-id>

# Determinism verification (two runs → byte-compare)
/run-sdk-addition --spec runs/my-tprd.md --seed 42
```

---

## 5. Single-run lifecycle (phase by phase)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                           │
│  [human] Author TPRD + Skills-Manifest + Guardrails-Manifest             │
│      │                                                                    │
│      ▼                                                                    │
│  /run-sdk-addition --spec runs/my-tprd.md                                │
│      │                                                                    │
│      ▼                                                                    │
│  H0  target-dir preflight (git repo? clean?)               AUTO          │
│      │                                                                    │
│      ▼                                                                    │
│  Phase 0   Intake    I1: ingest TPRD                                      │
│                      I2: §Skills-Manifest validation    ← WARN on miss   │
│                          (non-blocking; filed to PROPOSED-SKILLS.md)     │
│                      I3: §Guardrails-Manifest validation ← BLOCKER on miss│
│                      I4: clarifying-Q loop (max 5 Qs; 0 expected)        │
│                      I5: mode detection (A|B|C)                           │
│                      I6: completeness guardrail                           │
│                      I7: ═══ HITL H1 ═══  approve TPRD + manifest checks │
│      │                                                                    │
│      ▼ (if Mode B or C)                                                   │
│  Phase 0.5 Analyze   Snapshot existing API + tests + benches              │
│                      Build ownership-map (MANUAL vs. pipeline)           │
│      │                                                                    │
│      ▼                                                                    │
│  Phase 1   Design    api.go.stub, interfaces.md, algorithms.md,          │
│                      concurrency.md, dependencies.md                      │
│                      Devil review: design + dep-vet + semver +           │
│                        convention + security + overengineering + API-    │
│                        ergonomics                                         │
│                      Review-fix loop (≤5/finding; ≤10 global)            │
│                      ═══ HITL H5 ═══  approve design                     │
│      │                                                                    │
│      ▼                                                                    │
│  Phase 2   Impl      git checkout -b sdk-pipeline/<run-id>               │
│                      TDD: red → green → refactor → docs                   │
│                      Marker-aware merge (preserve MANUAL-* + markers)    │
│                      Impl devils: marker-hygiene + constraint + leak     │
│                      ═══ HITL H7b ═══  mid-impl checkpoint (long runs)   │
│                      ═══ HITL H7 ═══   approve final diff                │
│      │                                                                    │
│      ▼                                                                    │
│  Phase 3   Testing   Unit coverage (≥90%)                                 │
│                      Integration (testcontainers, real backends)          │
│                      Benchmarks + comparator vs. baseline (per pack)                  │
│                      leak-detection + vulnerability scan + lockfile scan                   │
│                      Fuzz targets                                         │
│                      Flake hunt (-count=3)                                │
│                      ═══ HITL H9 ═══  approve test results               │
│      │                                                                    │
│      ▼                                                                    │
│  Phase 3.5 Docs      D1: sdk-doc-writer  (parallel with V1)               │
│                          README.md / USAGE.md / ARCHITECTURE.md /         │
│                          CHANGELOG.md (Keep-a-Changelog) /                │
│                          MIGRATION.md (only on MAJOR or §12 breaking)     │
│                      V1: sdk-version-applier (parallel with D1)           │
│                          per-language artifacts (git tag, pyproject.toml, │
│                          package.json, Cargo.toml, ...) + module-path     │
│                          rewrite on Go MAJOR                              │
│                      D2: cross-ref reconciliation (install snippets)      │
│                      D3: root README diff proposal (NEVER auto-applied)   │
│                      ═══ HITL H9.5 ═══  approve docs + version + (opt)   │
│                                          root README patch               │
│      │                                                                    │
│      ▼                                                                    │
│  Phase 4   Feedback  F1: metrics-collector                                │
│                      F2: phase-retrospector                               │
│                      F3: root-cause-tracer                                │
│                      F4: drift-detector + coverage-reporter (parallel)    │
│                      F5: (retired — full-replay golden regression         │
│                           dropped; safety now comes from append-only      │
│                           patches + learning-notifications.md review)    │
│                      F6: improvement-planner                              │
│                      F7: learning-engine  (patches existing skills;      │
│                          writes one line per applied patch to            │
│                          feedback/learning-notifications.md;              │
│                          files new-skill proposals to PROPOSED-SKILLS.md)│
│                      F8: baseline-manager                                 │
│                      ═══ HITL H10 ═══  review notifications + diff;      │
│                                         merge / revert patch / keep-branch│
│      │                                                                    │
│      ▼                                                                    │
│  runs/<run-id>/run-summary.md    Exit code                               │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 6. HITL gates — what you see, what you decide

| Gate | Phase | What you review | Options | Timeout action |
|---|---|---|---|---|
| **H0** | pre-run | target-dir git status | auto-pass if clean | — |
| **H1** | Intake | `runs/<id>/tprd.md` + manifest checks | Approve / Revise / Cancel | Revise (24h) |
| **H5** | Design | `design/api.go.stub`, `design/interfaces.md`, devil verdicts | Approve / Revise / Reject | Revise (24h) |
| **H7b** | Impl mid | partial diff (long runs only) | Continue / Halt | Continue (48h) |
| **H7** | Impl | final diff on `sdk-pipeline/<run-id>` | Approve / Revise / Reject | Revise (24h) |
| **H9** | Testing | `testing/coverage.txt`, `testing/bench-compare.md`, flake report | Approve / Revise / Reject | Revise (24h) |
| **H9.5** | Docs | `docs/diff.md`, `docs/regen-guard-report.md`, `docs/version-applied.md`, `docs/root-readme-proposal.md` (if any) | Approve all / Approve docs+version, skip root / Revise / Reject | Revise (24h) |
| **H10** | Feedback | `run-summary.md` + final diff | Merge rec / Keep branch / Delete | Keep branch (72h) |

Each gate emits `AskUserQuestion` with structured options + a link to the review artifacts. You are never asked to read the whole TPRD again — only the delta since the last gate.

---

## 7. Review-fix sub-loop (inside every phase)

When a devil agent emits `NEEDS-FIX`:

```
  devil: NEEDS-FIX (finding F-42)
        │
        ▼
  phase-lead routes back to owner agent
        │
        ▼
  owner attempts fix
        │
        ├─ passes re-review → resume
        │
        └─ still NEEDS-FIX?
              ├─ retries < 5 → loop
              ├─ stuck (2 non-improving) → escalate to phase-lead
              └─ global 10 iters hit → halt run, emit BLOCKER
```

**After any rework iteration**, `phase-lead` re-runs **all** review agents (CLAUDE.md rule 13, no exceptions). This prevents fix-one-break-another.

### Loop caps summary

| Limit | Value | Source |
|---|---|---|
| Review-fix retries per finding | 5 | `review-fix-protocol` skill |
| Stuck detection | 2 non-improving iterations | same |
| Global review-fix cap | 10 iterations per run | CLAUDE.md rule 11 |
| Agent retry per wave | 1 retry, then degraded | CLAUDE.md rule 10 |
| Context summary | ≤200 lines | rule 11 |
| Decision log | ≤15 entries per agent per run | rule 11 |
| Budget caps | soft → warn; hard → user confirm | rule 22 |
| Intake clarifying-Qs | ≤5 (target 0 with detailed TPRD) | INTAKE-PHASE.md |
| Doc additive-regen retries | 3 per modified file | DOCUMENTATION-PHASE.md |
| Doc revision retries (H9.5 Revise) | 3 | DOCUMENTATION-PHASE.md |

---

## 8. Cross-run loop (self-evolution, narrowed)

Each completed run writes to `baselines/` and `evolution/knowledge-base/`. The next run reads them for context.

```
Run N completes → Feedback phase:
      │
      ▼
  metrics-collector      quality-scores-per-agent.jsonl
  drift-detector         which skills diverge from code reality?
  coverage-reporter      which declared skills never got invoked?
  root-cause-tracer      which phase should have caught defect X?
  improvement-planner    categorize findings into patch/propose
      │
      ▼
  learning-engine (Phase 4 wave F7):
      │
      ├─ prompt patches (≤10/run)           → auto-apply
      │                                       writes: evolution/prompt-patches/<agent>.md
      │
      ├─ existing-skill body patches (≤3)    → auto-apply IF:
      │                                         - confidence=high
      │                                         - 2+ run recurrence
      │                                       writes: skills/<name>/SKILL.md
      │                                               bump version MINOR
      │                                               append evolution-log.md
      │                                               append notification line
      │                                                 to feedback/
      │                                                 learning-notifications.md
      │                                       (no golden-corpus gate — the
      │                                        user reviews notifications at
      │                                        H10 and can revert any patch)
      │
      ├─ new-skill proposals                 → NEVER auto-apply
      │                                       files: docs/PROPOSED-SKILLS.md
      │                                               status: proposed
      │                                       ⇒ HUMAN PR required to author SKILL.md
      │
      ├─ new-guardrail proposals             → NEVER auto-apply
      │                                       files: docs/PROPOSED-GUARDRAILS.md
      │                                       ⇒ HUMAN authors scripts/guardrails/G*.sh
      │
      └─ new-agent proposals                 → NEVER auto-apply (same pattern)

  baseline-manager (wave F8):
      - raise baselines if improved >10%
      - keep on regression (don't lower)
      - reset every 5 runs
```

**The contract**: skills, agents, and guardrails are **data**. Only humans can add new ones. Learning-engine can only edit existing ones (and never delete).

---

## 9. Artifacts map (where things land)

```
runs/<run-id>/
├── state/run-manifest.json        ← wave/agent status (checkpoint source)
├── decision-log.jsonl              ← every agent's entries (8 types)
├── intake/
│   ├── skills-manifest-check.md    ← I2 verdict
│   ├── guardrails-manifest-check.md← I3 verdict
│   ├── clarifications.jsonl        ← Q&A (usually empty)
│   └── mode.json                   ← {mode: A|B|C, target_package}
├── extension/                      ← Mode B/C only: existing-api-snapshot
├── design/
│   ├── api.go.stub
│   ├── interfaces.md
│   ├── algorithms.md
│   ├── dependencies.md
│   └── reviews/<devil>.md
├── impl/
│   ├── merge-plan.md
│   ├── ownership-map.json
│   └── reviews/
├── testing/
│   ├── coverage.txt
│   ├── bench-raw.txt
│   ├── bench-compare.md
│   ├── leak-report.txt
│   └── vuln-report.txt
├── docs/
│   ├── manifest.json            ← targets + files written + skip reasons
│   ├── diff.md                  ← per-file doc diff (review artifact)
│   ├── regen-guard-report.md    ← additive-regen verdict
│   ├── version-applied.md       ← list of version artifacts touched
│   ├── version-artifacts.json   ← { tag, artifacts: [...] }
│   ├── xref-patch.md            ← D2 cross-ref reconciliation
│   └── root-readme-proposal.md  ← (conditional) D3 root patch diff
├── feedback/
│   ├── metrics.json
│   ├── retro-<phase>.md × 4
│   ├── root-causes.md
│   ├── skill-drift.md
│   ├── skill-coverage.md
│   └── learning-notifications.md
└── run-summary.md                  ← your top-level readout

$SDK_TARGET_DIR                     ← branch sdk-pipeline/<run-id>
└── <new-or-modified-pkg>/          ← the actual deliverable

baselines/                          ← persistent across runs
├── quality-baselines.json
├── coverage-baselines.json
├── performance-baselines.json
└── skill-health.json

evolution/                          ← persistent, learning state
├── knowledge-base/*.jsonl
├── prompt-patches/<agent>.md
└── evolution-reports/<run-id>.md

docs/
├── PROPOSED-SKILLS.md              ← human-review backlog
└── PROPOSED-GUARDRAILS.md          ← (not yet created; first proposal creates it)
```

---

## 10. Exit codes & halt semantics

| Code | Meaning | Your next action |
|---|---|---|
| **0** | All phases PASS; branch `sdk-pipeline/<run-id>` ready | Review diff; merge or iterate |
| **1** | HITL gate declined | Read rejection reason; revise; re-run subset with `--phases` |
| **2** | Guardrail BLOCKER unresolved after review-fix | Read `reviews/<devil>.md`; fix root cause or mark `[constraint-exception]` |
| **4** | Supply-chain REJECT (vuln / license) | Read `design/dependencies.md`; swap or justify dep |
| **5** | Target dir invalid | Set `SDK_TARGET_DIR`; `git init` if needed |
| **6** | §Guardrails-Manifest validation FAIL (missing script) | Author missing guardrail script via PR; re-run. (Missing skills do NOT trigger exit 6 — they emit a WARN and the pipeline continues; misses land in `docs/PROPOSED-SKILLS.md`.) |

---

## 11. Resume behavior (restart after failure)

The pipeline checkpoints after every wave. On restart:

```bash
/run-sdk-addition --resume <run-id>
```

Reads `runs/<run-id>/state/run-manifest.json`:
- `in-progress` waves → resume from last completed checkpoint
- `completed` waves → skip
- `failed` waves → retry once, then degrade + proceed with warning (CLAUDE.md rule 10)

---

## 12. Concrete walkthrough — "add S3 client"

```bash
# 1. Author TPRD offline
vim runs/s3-v1-tprd.md
# (14 sections + §Skills-Manifest + §Guardrails-Manifest)

# 2. Pre-flight: verify required skills + guardrails exist
/preflight-tprd --spec runs/s3-v1-tprd.md

# 3. Launch
/run-sdk-addition --target $SDK_TARGET_DIR --spec runs/s3-v1-tprd.md
```

Terminal timeline (typical Mode A, mature pipeline, ~45 min wall-clock):

```
[00:00] H0 preflight ............................... PASS
[00:05] Phase 0 Intake
        I1 ingest .................................. done
        I2 Skills-Manifest ......................... PASS (13/13 present)
        I3 Guardrails-Manifest ..................... PASS (9/9 present)
        I4 clarifications .......................... 0 questions
        I6 completeness ............................ PASS
        I7 ═══ H1 ═══ [user approves TPRD]
[00:45] Phase 1 Design (~8 min)
        api.go.stub written
        devils: design/dep-vet/semver/convention/security/overeng/ergonomics
        1 NEEDS-FIX: overeng-critic flagged unused PoolSize field → fixed
        ═══ H5 ═══ [user approves]
[09:00] Phase 2 Impl (~18 min)
        Branch sdk-pipeline/s3-v1 created
        31 files written; 14 tests (TDD red→green→refactor→docs)
        marker-hygiene: PASS (all [traces-to: TPRD-*] markers present)
        constraint-devil: PASS (bench constraints proven)
        ═══ H7 ═══ [user reviews diff, approves]
[27:00] Phase 3 Testing (~12 min)
        Unit coverage 92.4%    ✓ (≥90%)
        Integration: 8/8 PASS on MinIO + LocalStack testcontainers
        Benchmarks: 4 regressions within tolerance (<5%)
        leak-detection: clean
        vulnerability + lockfile scans: clean
        Flake hunt -count=3: 0 failures
        ═══ H9 ═══ [user approves]
[39:00] Phase 4 Feedback (~6 min)
        metrics: quality_score 0.94 (baseline 0.91)
        drift: 0 skills drifted
        coverage: 12/13 declared skills invoked (1 unused flagged optional in TPRD)
        learning-engine: 2 prompt patches applied; 0 skill patches; 0 proposals
        learning-notifications.md: 2 entries (user can revert at H10)
        baseline-manager: raised coverage baseline 91% → 92%
        ═══ H10 ═══ [user: merge recommendation]
[45:00] Exit 0. Branch sdk-pipeline/s3-v1 ready.
         See runs/s3-v1/run-summary.md for full readout.
```

---

## 13. What you do between runs

After a successful run, skim `evolution/evolution-reports/<run-id>.md` — it summarizes:
- Which existing skills got patched (bump history)
- Which proposals were filed (action items for you)
- Which baselines moved

Your between-run responsibilities:

1. **Review `docs/PROPOSED-SKILLS.md`** — author the ones worth adding; merge via PR
2. **Review `evolution/skill-candidates/<name>/`** — promote drafts you like; delete ones you don't
3. **Monitor `baselines/shared/skill-health.json`** — `manifest_miss_rate` rising = TPRDs referencing non-existent skills; `skill_stability` rising = learning-engine churning existing skills too hard

---

## 14. Summary — when in doubt

| I want to... | Do this |
|---|---|
| Add a new client | Author TPRD → `/run-sdk-addition --spec ...` |
| Tighten an existing client | Same, Mode C. Pipeline preserves `[owned-by: MANUAL]` markers |
| Try without writing | `--dry-run` |
| Redo a single phase | `--phases design` (or comma list) |
| Resume a halted run | `/run-sdk-addition --resume <run-id>` |
| Check a TPRD before running | `/preflight-tprd --spec runs/my-tprd.md` |
| Check determinism | `--seed 42` twice, diff outputs |
| Add a new skill | Write `skills/<name>/SKILL.md` offline, PR, merge. Then reference it in next TPRD |
| Patch an existing skill | Let `learning-engine` do it (auto, Phase 4) OR edit + bump version + append evolution-log |
| Audit what's stale | `/run-sdk-addition --phases feedback` reruns drift + coverage |
| Skip docs entirely | `--skip-docs` (CI escape; Phase 3.5 not run, no version stamped) |
| Re-author docs only | `--phases docs` (re-runs sdk-doc-writer + sdk-version-applier from existing intake artifacts) |
| Override inferred version | Add `§Versioning: { bump, next, confirmed: true }` to TPRD before run |
| Pin doc target paths | Add `§Docs-Manifest: { targets: [...] }` to TPRD before run |
| Skip docs for one run | TPRD `§Docs-Manifest: { skip: true }` |
| Revert a learning-engine patch | Open `runs/<run-id>/feedback/learning-notifications.md`; follow the per-patch revert pointer (git revert or restore from evolution-log.md predecessor) |
| Emergency halt | Decline any HITL gate → exit 1 |

The design bet: humans author the contract (TPRD + manifests + skills), the pipeline produces the code against it deterministically.
