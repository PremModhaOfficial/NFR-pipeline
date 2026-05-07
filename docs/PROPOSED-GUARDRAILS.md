<!-- cross_language_ok: true — pipeline design/decision doc references per-pack tooling. Multi-tenant SaaS platform context preserved per F-008. -->

# Proposed Guardrails (Human-Review Backlog)

Entries from pipeline runs are auto-filed here by `improvement-planner` (Wave F6). They never block a run and are never promoted at runtime. Promotion to `scripts/guardrails/G<NN>.sh` is a human PR action.

## Workflow

1. Entry lands here with `status: proposed` + motivation + source run + suggested phase + check pseudocode.
2. Human author drafts `scripts/guardrails/G<NN>.sh` following the existing guardrail script conventions (exit 0 = PASS, exit 1 = FAIL, exit 2 = WARN).
3. Human opens PR; reviewers include the phase-owner-agent owner and one devil-agent owner.
4. On merge: entry flipped to `status: promoted` with commit SHA + link to script.
5. Any TPRD §Guardrails-Manifest may then reference the new guardrail.

## Existing proposals

| ID | Guardrail | Phase | Motivation | Source run | Status |
|---|---|---|---|---|---|
| G25 | Perf-constraint vs dep-floor check | Intake (I3) | Catches aspirational TPRD §10 numeric constraints before Phase 3 | sdk-dragonfly-s2 | proposed |
| G35 | Tool preflight (govulncheck + osv-scanner + benchstat + staticcheck) | Pre-intake / H0 | Eliminates PENDING verdicts caused by tool absence at D2 | sdk-dragonfly-s2 | proposed |
| G36 | MVS simulation vs real target go.mod | Design (D2) | Surfaces forced dep bumps before impl phase | sdk-dragonfly-s2 | proposed |
| G44 | OTel static conformance test exists | Impl (M6 or M9) | Catches OTel wiring drift without live exporter | sdk-dragonfly-s2 | proposed |
| G66 | Bench constraint calibration warning | Testing (T5) | Pre-classifies mechanically unachievable constraints as CALIBRATION-WARN | sdk-dragonfly-s2 | proposed |
| G67 | Integration matrix completeness | Testing (T2) | Surfaces integration TLS/ACL matrix gaps vs TPRD §11.2 | sdk-dragonfly-s2 | proposed |
| G68 | TPRD §11.1 fake-client-exclusion enumeration | Intake (I2) | Requires TPRD §11.1 to list commands not covered by miniredis/fake | sdk-dragonfly-s2 | proposed |

## Policy

- **No auto-promotion.** Pipeline emits entries; does not write guardrail scripts.
- **No runtime creation.** `new_guardrails_per_run = 0` per `settings.json § safety_caps`.
- **Devil-fleet gate on first use.** Newly promoted guardrails should be exercised on the next pipeline run before counting as stable (pipeline does not run golden-corpus full-replay regression).

---

## Auto-filed from run `sdk-dragonfly-s2` on 2026-04-18

Source: `improvement-planner` Wave F6, derived from retro patterns P1/P2/P4/P5 and anomaly flags A1/A2/A3.

### G25 — Perf-constraint dep-floor check (HIGH confidence)

- **Phase**: Intake (Wave I3 — before H1 closes).
- **Motivation**: TPRD §10 declared `allocs_per_GET ≤ 3`. go-redis v9 floor is ~25-30. The constraint reached Phase 3 unverified and triggered an H8 waiver. Cost: ~30 min of H8 loop that could have closed at H1.
- **Check logic**:
  ```
  For each TPRD §10 constraint marker [constraint: <metric> <op> <value> | bench/<name>]:
    - Resolve the underlying dep from TPRD §6 (e.g. go-redis v9.18).
    - Look up baselines/go/performance-baselines.json[<dep>][<metric>] or dep release-notes floor.
    - If target < floor * 0.9: emit WARN with constraint, target, floor, reference.
    - If target > 2 * floor: emit INFO (over-specified; not a problem).
    - Else: PASS.
  ```
- **Pass criteria**: All constraints either pass floor check or have explicit `accept-aspirational: true` annotation in TPRD §10.
- **Fail criteria**: BLOCKER only if TPRD has an `accept-aspirational` annotation that was falsified by baselines data. Otherwise WARN (non-blocking, filed to intake report).
- **Consumer**: `sdk-intake-agent` (runs the check), `sdk-benchmark-devil-go` (honors the calibration at T5 per G66).

### G35 — Tool preflight (MEDIUM confidence)

- **Phase**: Pre-intake / H0.
- **Motivation**: `govulncheck` and `osv-scanner` were absent at D2 execution, causing G32/G33 PENDING for 2 waves until H6. Mid-run tooling installation is a process smell.
- **Check logic**:
  ```
  For each required tool in [govulncheck, osv-scanner, benchstat, staticcheck, go-mutesting-or-gremlins]:
    if not on PATH and not a null-fallback tool:
      emit WARN (or BLOCKER if tool is used by a declared BLOCKER guardrail this run).
  ```
- **Pass criteria**: All tools required by the TPRD §Guardrails-Manifest's BLOCKER entries are on PATH.
- **Fail criteria**: BLOCKER if a tool used by a BLOCKER guardrail is absent. WARN otherwise.
- **Consumer**: Pre-intake H0 preflight.

### G36 — MVS simulation vs real target go.mod (HIGH confidence)

- **Phase**: Design (D2, before H5).
- **Motivation**: `testcontainers-go@v0.42.0` forced otel × 3 + klauspost/compress bumps that were only discovered at impl wave M3. HITL re-opening + run-driver option-decision at H6 cost ~45 min of unplanned loop.
- **Check logic**:
  ```
  Clone target_repo/go.mod to runs/<run-id>/design/mvs-scratch/
  For each proposed new dep in design/dependencies.md:
    cd mvs-scratch && go get <dep>@<version> && go mod tidy -json > mvs-diff-<dep>.json
    diff vs baseline go.sum, record every existing-direct-dep forced bump.
  Cross-reference bumped list vs H1 dep-untouchable list:
    if intersection non-empty: emit BLOCKER with DEP-POLICY-CONFLICT-AT-DESIGN.
    if non-empty but no untouchable policy: emit WARN (must be explicitly approved at H6).
    if empty: PASS.
  ```
- **Pass criteria**: Forced-bump list is empty OR all bumps are explicitly approved at H6.
- **Fail criteria**: BLOCKER when bumped dep is on untouchable list; WARN otherwise.
- **Consumer**: `sdk-dep-vet-devil-go` (D2), `sdk-design-lead` (H6 prep).

### G44 — OTel static conformance (MEDIUM confidence)

- **Phase**: Impl (M6 Docs wave or M9 Mechanical wave — owner is `sdk-impl-lead`).
- **Motivation**: In sdk-dragonfly-s2 the static OTel conformance test was authored by `sdk-testing-lead` at T9 instead of by `sdk-impl-lead` at M6. Shift-left to impl ownership and catch wiring drift without needing a live exporter.
- **Check logic**:
  ```
  Scan <pkg>/*.go for all call sites of the instrumentation helper (instrumentedCall / runCmd / similar).
  Assert (via AST or grep with AST backup):
    - cmd arg is a compile-time string literal (reject identifiers, struct-field access, fmt.Sprintf).
    - span attribute names are NOT in forbidden-attr list {"password","secret","token","key","value","payload"}.
    - span names use the package's declared stable prefix (e.g. dfly., s3., kafka.).
    - error recording goes through motadatagosdk/otel wrapper, not raw go.opentelemetry.io/otel.
  Require existence of <pkg>/observability_test.go containing TestObservability_* functions covering above.
  ```
- **Pass criteria**: All assertions pass + `observability_test.go` exists and is part of `go test` run.
- **Fail criteria**: BLOCKER if wiring violates invariants; WARN if observability_test.go is missing but invariants hold in source.
- **Consumer**: `sdk-impl-lead`, `sdk-testing-lead` (read-only validation).

### G66 — Bench constraint calibration (MEDIUM confidence)

- **Phase**: Testing (T5).
- **Motivation**: allocs-per-GET ≤ 3 vs go-redis v9 floor of ~25-30 forced a reactive H8. Pre-classifying unachievable constraints at T5 converts reactive H8 into a CALIBRATION-WARN with Option A pre-recommended.
- **Check logic**:
  ```
  For each TPRD §10 constraint that just FAILED bench:
    look up dep floor from baselines/go/performance-baselines.json or G25's intake report.
    if measured ≈ floor AND target << floor:
      reclassify as CALIBRATION-WARN (not FAIL);
      emit H8 with Option A (baseline update) recommended.
    if measured >> floor:
      classify as FAIL (wrapper overhead is the defect).
  ```
- **Pass criteria**: N/A — this guardrail reclassifies, it does not add a new BLOCKER.
- **Fail criteria**: N/A.
- **Consumer**: `sdk-benchmark-devil-go`, `sdk-testing-lead`.

### G67 — Integration matrix completeness (LOW-MEDIUM confidence)

- **Phase**: Testing (T2).
- **Motivation**: TPRD §11.2 declared TLS/ACL matrix; actual integration covered basic-flow + HExpire only. Chaos-kill, TLS on/off, ACL on/off remain skeleton/skip. H9 accepted the gap but it is still a spec-coverage miss.
- **Check logic**:
  ```
  Parse TPRD §11.2 matrix cells. Count test functions in <pkg>/<pkg>_integration_test.go whose name or t.Run sub-name references each cell.
  Emit WARN if any cell has 0 test functions.
  ```
- **Pass criteria**: Every declared matrix cell has ≥1 integration test.
- **Fail criteria**: WARN (not BLOCKER) when a cell is empty.
- **Consumer**: `integration-test-agent`, `sdk-testing-lead`.

### G68 — TPRD §11.1 fake-client-exclusion enumeration (LOW confidence)

- **Phase**: Intake (I2, §Skills-Manifest validation adjacency).
- **Motivation**: `miniredis/v2` does not support Redis 7.4 HEXPIRE-family commands. TPRD §11.1 did not document this exclusion; the skip surprised the test phase.
- **Check logic**:
  ```
  If TPRD §11.1 references a fake-client (miniredis, localstack, etc.):
    require a subsection "not-covered-by-fake-client:" enumerating unsupported commands/APIs
    AND a "coverage-strategy:" line (integration | skip-with-comment | accept-gap).
  ```
- **Pass criteria**: Both subsections present.
- **Fail criteria**: WARN if TPRD references a fake without either subsection.
- **Consumer**: `sdk-intake-agent`.

---

## Cap respected

Per `settings.json § safety_caps.new_guardrails_per_run = 0`, none of the above are created at runtime. All entries are filed here for human PR promotion only.

---

## Auto-filed from run `sdk-dragonfly-p1-v1` on 2026-04-22 (G24 BLOCKER halt)

Source: `sdk-intake-agent` Wave I3. G24 BLOCKER-failed on 10 declared guardrails whose scripts do not exist at `scripts/guardrails/<id>.sh`. Pipeline halted with exit 6 before Phase 0.5. Each entry below maps to pipeline `CLAUDE.md` rule-set 28 (learning-engine safeguards) and rule-set 32 (Performance-Confidence Regime) and requires human PR authorship before this TPRD (or any TPRD referencing these IDs) can clear intake.

| ID | Guardrail | Phase | Severity | Motivation | Source run | Status |
|---|---|---|---|---|---|---|
| G81 | Baselines updated or rationale | Feedback | BLOCKER | Rule 28 compensating baselines (1, 2, 4) require per-run updates to `baselines/go/output-shape-history.jsonl`, `baselines/go/devil-verdict-history.jsonl`, `baselines/go/coverage-baselines.json`. Guardrail asserts either the baseline file advanced or the feedback report carries a rationale for the skip. | sdk-dragonfly-p1-v1 | proposed |
| G83 | Every patch logged in skill evolution-log.md | Feedback | BLOCKER | Per Rule 23, any body-patch `learning-engine` applies to an existing skill must append a line to that skill's adjacent `evolution-log.md` with minor-bump semantics. Guardrail diffs the skill's git-HEAD version frontmatter against its log and fails if patches landed without a matching log entry. | sdk-dragonfly-p1-v1 | proposed |
| G84 | Per-run safety caps respected | Feedback | BLOCKER | Mechanical check against `settings.json § safety_caps` — counts of `prompt_patches`, `existing_skill_patches`, `new_skills`, `new_guardrails`, `new_agents` applied in the current run must not exceed the declared cap. Catches a runaway learning-engine before F-phase exit. | sdk-dragonfly-p1-v1 | proposed |
| G104 | Alloc-budget per declared `allocs_per_op` | Impl (M3.5) | BLOCKER | Rule 32 axis 3 (allocation). `sdk-profile-auditor-go` runs declared benches with `b.ReportAllocs()`, reads `design/perf-budget.md` per-symbol `allocs_per_op`, fails the gate on any symbol whose measured allocs exceeds budget. Runs BEFORE T5 so alloc overruns never reach testing phase. | sdk-dragonfly-p1-v1 | proposed |
| G105 | Soak-MMD (minimum-measurable-duration) enforcement | Testing (T-SOAK) | BLOCKER | Rule 32 axis 6 + rule 33 verdict taxonomy. Any soak verdict marked PASS must satisfy `actual_duration_s ≥ mmd_seconds` from `design/perf-budget.md`. Shorter runs return INCOMPLETE, not PASS. Prevents silent timeout-to-PASS promotion. P1 no-ops this gate (no soak-enabled symbol declared in TPRD). | sdk-dragonfly-p1-v1 | proposed |
| G106 | Soak-drift detector | Testing (T-SOAK) | BLOCKER | Rule 32 axis 6. `sdk-drift-detector` curve-fits declared soak signals (e.g. RSS, goroutine count, pool-checkout latency p99) over the soak window and fails on a statistically significant positive trend. P1 no-ops (no soak enabled). | sdk-dragonfly-p1-v1 | proposed |
| G107 | Complexity scaling sweep | Testing (T5) | BLOCKER | Rule 32 axis 4. `sdk-complexity-devil-go` runs each declared hot-path symbol at `N ∈ {10, 100, 1k, 10k}`, curve-fits measured latency vs N, and compares to the declared big-O in `perf-budget.md`. Catches accidental quadratic paths that pass wall-clock gates at microbench sizes. This TPRD declares `ZRangeWithScores` O(log N + M) and the `Scan` iterator O(N) amortized. | sdk-dragonfly-p1-v1 | proposed |
| G109 | Profile-no-surprise hotspot check | Impl (M3.5) | BLOCKER | Rule 32 axis 2. `sdk-profile-auditor-go` reads CPU/heap/block/mutex pprof output; top-10 CPU samples must cover ≥0.8 of the declared hot paths in `perf-budget.md`; any hot function not in the declared set is a surprise hotspot and a BLOCKER. Catches design-reality drift before testing. TPRD declares hot paths: `instrumentedCall`, `mapErr`, keyprefix concat. | sdk-dragonfly-p1-v1 | proposed |
| G110 | `[perf-exception:]` marker ↔ `perf-exceptions.md` pairing | Impl (M7+M9) | BLOCKER | Rule 32 axis 7 + rule 29 marker protocol. Any source-line bearing `[perf-exception: <reason> bench/BenchmarkX]` must have a matching entry in `runs/<run-id>/design/perf-exceptions.md` declaring the exception at design time AND a profile-auditor-measured bench win. Orphan markers (no matching entry) fail the gate. P1 expects zero `[perf-exception:]` markers (no hand-optimized paths). | sdk-dragonfly-p1-v1 | proposed |

### Halt contract

Per command spec §Exit codes and `commands/run-sdk-addition.md`, this is an **exit 6** halt. The run-summary marks intake BLOCKED and H1 is not asked. The remaining waves (I4 clarifications, I5 mode detection, I6 completeness, I7 H1 gate) are skipped; Phase 0.5 extension-analyze does not run. Re-run requires either (a) human-authored scripts at `scripts/guardrails/G{81,83,84,104,105,106,107,109,110}.sh` + `chmod +x`, or (b) a TPRD revision that drops the unresolved IDs from §Guardrails-Manifest (not recommended — rule 32 remaining axes are load-bearing for the TPRD's declared perf targets in §10).

---

## Auto-filed from audit `multi-lang-correctness-2026-04-29` (Python sibling guardrails for marker protocol)

Source: end-to-end multi-language correctness audit (Phase R2 finding F9). The provenance-marker guardrails G95–G103 currently exist as Go-only scripts that scan `*.go` files via `rglob("*.go")` (verified at `scripts/guardrails/G{97,98,100,102}.sh`). The marker concept (`[traces-to:]`, `[constraint:]`, `[stable-since:]`, `[deprecated-in:]`, `[do-not-regenerate]`, `[owned-by:]`, `[perf-exception:]`) is **language-neutral** — markers live in source-code comments, and the syntax (`# [traces-to: ...]` in Python, `// [traces-to: ...]` in Go) is identical post-comment-prefix-strip. But the scanner needs per-language file-extension wiring + per-language test-file exclusion logic. Without Python siblings, a Phase B Python pilot run cannot enforce rule 29 (Code Provenance Markers) on any Python file.

Promotion to a real `scripts/guardrails/G<NN>-py.sh` is human PR action per CLAUDE.md rule 23.

| ID | Guardrail | Phase | Severity | Motivation | Source | Status |
|---|---|---|---|---|---|---|
| G95-py | MANUAL ownership preserved (Python AST-hash) | Impl (M-late) | BLOCKER | Python sibling of G95. Compute AST hash on Python `MANUAL`-owned symbols at Mode B/C entry; assert byte parity at exit. The AST hasher pack ships in v0.5.0; needs Python-specific tokenize-driven hasher (handles f-strings + decorators). | multi-lang-audit | proposed |
| G96-py | MANUAL byte-hash belt-and-suspenders (Python) | Impl (M-late) | BLOCKER | Python sibling of G96. SHA256 of normalized source bytes (whitespace-collapsed, trailing-newline-normalized) on every `[owned-by: MANUAL]` symbol. Complements G95-py's AST hash. | multi-lang-audit | proposed |
| G97-py | `[constraint:]` matching pytest-benchmark target (Python) | Testing (T5) | BLOCKER | Python sibling of G97. Greps `*.py` (via `pathlib.rglob("*.py")` — mirror of existing G97 Go logic) for `[constraint: <metric>:bench/<target>]` markers, asserts `<target>` appears in `testing/bench-raw.txt` (pytest-benchmark JSON-to-text dump). The marker payload format is identical across packs. | multi-lang-audit | proposed |
| G98-py | No marker deletions without HITL ack (Python) | Impl | BLOCKER | Python sibling of G98. Diff `*.py` files between Mode B/C entry-snapshot and exit; assert no marker line was removed without an explicit HITL acknowledgement entry in `runs/<run-id>/impl/marker-deletions.md`. | multi-lang-audit | proposed |
| G99-py | Pipeline-authored `*.py` carries `[traces-to:]` (Python) | Impl (M-mid) | BLOCKER | Python sibling of G99. Every pipeline-authored Python file MUST carry ≥1 `# [traces-to: TPRD-...]` marker in its first ~30 lines (module docstring or top-level comment). Test files (`tests/test_*.py` and `tests/conftest.py`) excluded — sibling rule. | multi-lang-audit | proposed |
| G100-py | `[do-not-regenerate]` whole-file lock (Python) | Impl | BLOCKER | Python sibling of G100. Scan first 1024 bytes of each `*.py` for `# [do-not-regenerate]`; if present, hash the whole file and compare to `baselines/python/do-not-regenerate-hashes.json`. Any byte change is BLOCKER until baseline refreshed via human PR. | multi-lang-audit | proposed |
| G101 (already language-aware) | `[stable-since:]` signature change requires TPRD §12 MAJOR | Impl | BLOCKER | **Already done** in R1.4 — G101.sh resolves `target_language` from `active-packages.json` and reads `baselines/<lang>/stable-signatures.json`. The Python signature-extraction body (replacing the Go AST-via-go-parser path) still needs to be authored — currently G101 only renders a useful diff for Go. **Sub-proposal: G101-python-body** to wire Python AST signature extraction. | multi-lang-audit | partial-promoted |
| G102-py | Marker syntax validity (Python) | Impl | BLOCKER | Python sibling of G102. Grep every `*.py` for `# [<key>: <value>]` markers; validate each `<key>` against the 7-key taxonomy (rule 29) AND the per-key value grammar (TPRD-id regex, vX.Y.Z regex, `bench/X` regex). Identical regex to G102 Go — only the file-extension scope changes. | multi-lang-audit | proposed |
| G103-py | No forged MANUAL markers on pipeline `*.py` symbols | Impl | BLOCKER | Python sibling of G103. Pipeline-authored Python files MAY NOT contain `# [traces-to: MANUAL-*]` or `# [owned-by: MANUAL]` on a symbol the pipeline just emitted. Mirrors G103 Go's logic against the per-run authorship manifest. | multi-lang-audit | proposed |

### Implementation note for the Python sibling drafts

When a human author drafts `G<NN>-py.sh`, the recommended pattern is:

1. Copy `G<NN>.sh` (Go version).
2. Replace `pathlib.Path(target).rglob("*.go")` with `pathlib.Path(target).rglob("*.py")`.
3. Replace test-file exclusion `endswith("_test.go")` with `name.startswith("test_") or name == "conftest.py" or "/tests/" in str(p)`.
4. Replace marker-comment prefix `// ` with `# ` (comment-prefix is the only per-language byte difference in the marker line).
5. For G95-py / G96-py: swap Go AST hasher for Python AST hasher (the v0.5.0 ast-hash toolkit ships both — the language-pluggable hasher dispatches on file extension).
6. For G101 Python body: parse signatures via the `ast` module's `FunctionDef` / `AsyncFunctionDef` / `ClassDef` walk, normalize through type-hint canonicalization (e.g., `list[int]` ≡ `List[int]` post-PEP 585), serialize, hash, diff against `baselines/python/stable-signatures.json`.
7. Register the new script in `.claude/package-manifests/python.json` `guardrails` array (move out of `aspirational_guardrails` if applicable).
8. Run `bash scripts/validate-packages.sh` to confirm manifest consistency.

### Cap respected

Per `settings.json § safety_caps.new_guardrails_per_run = 0`, none of the above are created at runtime. All entries are filed here for human PR promotion only.


---

## Auto-filed from run `sdk-resourcepool-py-pilot-v1` on 2026-04-29 (F6 improvement-planner → learning-engine)

Source: `improvement-planner` Wave F6, derived from root-cause-traces "TOOLCHAIN-ABSENCE" (highest-leverage trace in the run) + retrospective Process Changes row 1 + Guardrail Additions row 1.

### Proposed: G-toolchain-probe — language-agnostic toolchain preflight at H0
<!-- Run: sdk-resourcepool-py-pilot-v1 | Date: 2026-04-30 | Confidence: HIGH -->

- **scope**: shared-core
- **phase header**: intake
- **rationale**: TOOLCHAIN-ABSENCE was the single-largest cost driver in the Python pilot run — 3 impl sub-runs, 2 user re-engagements, full M3.5/M5/M7/M9 INCOMPLETE cascade. H0 currently checks only that the target dir is a git repo; no per-language toolchain assertion runs. Reading `toolchain.<command>` from the active language manifest and probing each declared command with `--version` would have surfaced the gap before any Phase 1 design work.
- **source_evidence**: root-cause-traces "TOOLCHAIN-ABSENCE" (highest-leverage trace in the run); retrospective Process Changes row 1; retrospective Guardrail Additions row 1
- **confidence**: HIGH
- **check_logic**:
  1. Read `runs/<run-id>/context/active-packages.json` to resolve active language manifest
  2. For each manifest with a `toolchain.<command>` block, iterate declared commands
  3. For each command, exec `<command> --version` (or manifest-declared probe form, e.g. `python -c 'import sys; print(sys.version)'`)
  4. Pass: every probe returns exit 0; capture and log version strings
  5. Fail (BLOCKER): any probe fails; emit list of missing commands + suggested install hint per manifest
- **pass_criteria**: all toolchain commands probe successfully
- **fail_criteria**: any toolchain command absent or unversioned
- **why_shared_core**: every language pack inherits the check by manifest declaration alone — no need for `G-py-toolchain-probe.sh`, `G-go-toolchain-probe.sh`, etc. The retrospective initially proposed `G-py-toolchain-probe`; root-cause-tracer confirmed the shared-core form is correct.
- **suggested_path**: `scripts/guardrails/G-toolchain-probe.sh`
- **manifest_action**: add to `shared-core.json` `aspirational_guardrails` until script lands; promote to `guardrails` array on PR-merge.
