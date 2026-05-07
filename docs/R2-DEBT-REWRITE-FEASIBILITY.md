<!-- cross_language_ok: true — pipeline design/decision doc references per-pack tooling. Multi-tenant SaaS platform context preserved per F-008. -->

# R2 — Generalization-Debt Rewrite Feasibility Study

**Date**: 2026-04-27
**Pipeline version**: 0.4.0 (study output informs v0.5.0)
**Spike scope**: ~half-day. Read three shared-core debt-bearers, attempt language-neutral rewrites, judge whether the result is useful or vacuous.

---

## Question (verbatim from `docs/LANGUAGE-AGNOSTIC-DECISIONS.md` §4)

> Take ONE shared-core agent with debt (e.g., `sdk-design-devil`) and try to author a language-neutral version of its prompt body. Is the result genuinely useful for both Go and Python design review? Or does it become so abstract it's vacuous?

**Why it matters**: governs **D2** (cross-language fairness for debt-bearers) and **D6** (debt-rewrite timing — Eager vs Lazy vs Split).

---

## Method

Picked three of the four shared-core agents in `generalization_debt`:

1. **`sdk-design-devil`** — small body, direct review rules, easiest to reason about
2. **`sdk-overengineering-critic`** — closest to "code-shape critique" → most concrete examples → highest neutralization risk
3. **`sdk-semver-devil`** — semver itself is policy, but per-language semver conventions diverge sharply (Go `/v2` module path suffix; Python PEP 440 pre-release semantics; Rust `^` operator) → genuinely hard case

For each: enumerated Go-leakage by line, attempted neutral rewrite of every rule + example, then judged against two criteria:

- **Did the rule survive?** Is the abstract form still a recognizable check, or did it dissolve into "be tasteful"?
- **Did the example survive?** Or do you need a per-language form to give the LLM a pattern to match?

---

## Findings

### Pattern observed across all three: **rule generalizes; example + a small subset of rules don't**

Every body had three types of content:

| Content type | Example (Go) | Survives neutralization? |
|---|---|---|
| **Universal rule** | "Functions with >4 params → propose Config struct" | YES — applies to any language |
| **Universal rule + Go-named primitive** | "Goroutine ownership ambiguity" | YES with rename — "concurrency primitive ownership" |
| **Universal rule + Go-syntax example** | "Stuttering: `dragonfly.DragonflyClient` — REJECT" | YES rule, NO example — needs per-lang anchor |
| **Genuinely language-specific rule** | "Acronym casing: `Id` → `ID`, `Http` → `HTTP`" | NO — Go-only style; Python/Rust disagree |
| **Genuinely language-specific tooling** | "Go generics where concrete type suffices" | NO — Python has no static generics |

The two failing categories are **examples** and **a small minority of rules**. Everything else neutralizes cleanly.

### Per-agent breakdown

#### `sdk-design-devil` — 11 rules total

| Rule | Verdict | Note |
|---|---|---|
| Parameter count >4 → Config struct | NEUTRAL ✓ | |
| Exposed internals | NEUTRAL ✓ | |
| Mutable shared state | NEUTRAL ✓ | "fields writable post-construction" — universal |
| Stuttering naming | NEUTRAL ✓ for rule, **example needs per-lang** | Java/Python/Rust all suffer namespace-stutter |
| `-er` suffix on non-actor | **Go-specific** — Java embraces `-er`/`-or` (Manager, Handler, Controller) | Move to `go/conventions.yaml` |
| Acronym casing (`Id`/`HTTP`) | **Go-specific** — PEP 8 ambiguous, Rust prefers `Id` | Move to `go/conventions.yaml` |
| Unchecked error propagation | NEUTRAL ✓ | "swallow errors silently" — universal |
| Goroutine ownership | NEUTRAL ✓ with rename → "concurrency primitive ownership" | |
| Missing context.Context | NEUTRAL ✓ with rename → "missing cancellation/deadline carrier" | |
| `init()` / global state | NEUTRAL ✓ with rename → "module-load-time side effects" | |
| Inconsistent error types | NEUTRAL ✓ | "consistent error model across the API" — universal |
| Interface bloat (>5 methods) | NEUTRAL ✓ | |
| Hidden complexity | NEUTRAL ✓ | |

**Score**: 11 of 13 rules neutralize. 2 of 13 (`-er` suffix, acronym casing) genuinely belong in `go/conventions.yaml`. ~85% of body is shareable.

#### `sdk-overengineering-critic` — 10 checks

| Rule | Verdict |
|---|---|
| Unused Config fields | NEUTRAL ✓ |
| Speculative interfaces (1 impl, no test double) | NEUTRAL ✓ |
| Premature optimization (sync.Pool example) | NEUTRAL ✓ rule, **example needs per-lang** (Python: `weakref` pool; Rust: `typed_arena`) |
| Ceremonial wrappers | NEUTRAL ✓ rule, **example needs per-lang** (`StringWrapper struct` is Go syntax) |
| Options pattern misuse | NEUTRAL ✓ ("Builder pattern abused for single required field" — universal) |
| Dead flags | NEUTRAL ✓ |
| Over-parametrized generic code | **Conditional** — applies to Go, Rust, Java; Python skips |
| Dead imports | NEUTRAL ✓ rule, **`_ "foo"` syntax is Go-specific** (Python has no underscore-import; just bare `import` with side-effect detected by execution) |
| God types (>10 fields) | NEUTRAL ✓ |
| Error wrap chains deeper than 3 levels | NEUTRAL ✓ rule, **`fmt.Errorf("%w", ...)` syntax is Go-specific** (Python: `raise X from Y`; Rust: `?` operator + `thiserror`) |

**Score**: 9 of 10 checks neutralize. 1 of 10 (over-parametrized generics) is conditionally applicable. Examples need per-lang form throughout.

#### `sdk-semver-devil` — Mode A logic (4 lines of substantive review)

| Rule | Verdict |
|---|---|
| Mode-A: no pre-existing API → no breaking-change vector | NEUTRAL ✓ |
| All new exports follow naming conventions | NEUTRAL ✓ rule, **delegates to per-lang `conventions.yaml`** |
| Version 1.0.0 reasonable (or v0.x.y experimental) | NEUTRAL ✓ rule, **`v` prefix is Go module convention** (PEP 440 has no `v` prefix; npm uses `1.0.0` directly) |
| `[stable-since: vX]` markers proposed | **Per-lang marker syntax** — `[stable-since: 1.0.0]` (no `v`) for Python; `[stable-since: v1.0.0]` for Go |

Plus the Go-specific rules NOT yet in the body but lurking nearby:

- Go's v2+ module path suffix requirement (`example.com/foo/v2` vs `example.com/foo`) — **Go-only**, no Python/Rust analog
- PEP 440 pre-release ordering (`1.0.0a1 < 1.0.0b1 < 1.0.0rc1 < 1.0.0`) — **Python-only**
- Rust semver crate strict comparator semantics — **Rust-only**

**Score**: rule body neutralizes 100%; **but** the per-language convention layer gets nontrivial. This agent is the strongest argument for an externalized `conventions.yaml` per language pack (touchpoint T2-5).

---

## Side-by-side: `sdk-design-devil` (~85% case)

### A. Original (Go-flavored — current shared-core/sdk-design-devil.md)

```md
### Goroutine ownership ambiguity
Design starts a goroutine without documenting: who owns it, when does it stop, what signals shutdown. BLOCKER.

### Missing context.Context
Any I/O method not taking ctx as first param. BLOCKER.

### Non-idiomatic naming
- Stuttering: `dragonfly.DragonflyClient` — REJECT
- `-er` suffix on non-actor: `ConfigManager` — REJECT
- Acronym casing: `Id` should be `ID`, `Http` should be `HTTP` — REJECT
```

### B. Fully neutralized (vacuous-risk version)

```md
### Concurrency primitive ownership ambiguity
Design starts a concurrency primitive without documenting ownership. BLOCKER.

### Missing cancellation propagation
Any I/O method not propagating cancellation/deadline. BLOCKER.

### Non-idiomatic naming
- Namespace stuttering: REJECT
- Anti-pattern naming: REJECT (see conventions for language)
```

**Verdict**: rule survived but example dissolved. The LLM has no pattern to match against. This is the vacuous-risk shape and **is in fact too abstract** to be useful at review time.

### C. Split (rule shared, examples + language-specific rules per-lang)

`shared-core/sdk-design-devil.md` (rule body — used by every adapter):

```md
### Concurrency primitive ownership ambiguity
Design starts a concurrency primitive (goroutine / async task / OS thread / actor) without
documenting: who owns it, when does it stop, what signals shutdown. BLOCKER.

See `<active-language>/conventions.yaml` → `concurrency_primitives` for the language-native form
and example shapes the reviewer should pattern-match.

### Missing cancellation/deadline propagation
Any I/O method that does not accept the language's cancellation/deadline carrier as its primary
mechanism. BLOCKER.

See `<active-language>/conventions.yaml` → `cancellation_carrier` for the canonical type.

### Non-idiomatic naming
Apply rules from `<active-language>/conventions.yaml` → `naming_rules`. The shared rule:
namespace stuttering is REJECT in every language. Acronym casing, suffix conventions, and other
language-specific style rules live in the per-language conventions file.
```

`go/conventions.yaml`:

```yaml
concurrency_primitives:
  - goroutine
  - "channel send/receive"
  - sync.WaitGroup-tracked
example_anchors:
  - "go func() { ... }() launched without ctx capture"

cancellation_carrier:
  type: "context.Context"
  position: "first parameter on every I/O method"
  doc_note: "Idiom: ctx context.Context as first param; never embed in struct."

naming_rules:
  - "Stuttering: package.PackageType (e.g. dragonfly.DragonflyClient) — REJECT"
  - "-er suffix on non-actor: ConfigManager — REJECT"
  - "Acronym casing: Id → ID, Http → HTTP, Url → URL — REJECT"
```

`python/conventions.yaml`:

```yaml
concurrency_primitives:
  - "asyncio.Task created via asyncio.create_task or ensure_future"
  - "threading.Thread"
  - "multiprocessing.Process"
example_anchors:
  - "asyncio.create_task(...) without storing reference and without except in await"

cancellation_carrier:
  type: "asyncio.timeout / asyncio.wait_for / passed-in CancellationScope"
  position: "context manager wrapping the I/O method body"
  doc_note: "Idiom: each I/O method wrappable in asyncio.timeout(); fire-and-forget tasks must register cleanup."

naming_rules:
  - "Stuttering: pkg.PkgClient (e.g. dragonfly.DragonflyClient) — REJECT"
  - "snake_case for functions/variables, PascalCase for classes"
  - "Acronym casing: PEP 8 ambiguous; project chooses 'Id' (lowercase tail) — declare and stick"
```

**Verdict**: this shape is simultaneously concrete enough for the LLM to pattern-match (the Go reviewer sees Go anchors, the Python reviewer sees Python anchors) AND keeps the rule logic in one place (every fix to the universal rule benefits both languages).

---

## Judgment calls

### D6 — Generalization-debt resolution timing → **Split**

**Decision**: rule body is shared; examples + a small minority of rules go per-language via `conventions.yaml`. Reject Eager (vacuous risk) and Lazy (delays the structural decision).

**Rationale**:
- Fully Eager (rewrite all 7 debt-bearers into pure abstract prose before Python pilot) produces vacuous text. Demonstrated in §B above for design-devil.
- Fully Lazy (wait until Python pilot fails) keeps shared agents Go-leaky in the meantime, polluting any cross-language metrics.
- Split is the only shape where the rule layer stays DRY, the example layer pattern-matches per language, and per-lang `conventions.yaml` is the externalization seam (already proposed as T2-5).

**Confidence**: high. Pattern held across all three sampled debt-bearers (~85–95% of rules neutralize cleanly; the rest are genuinely per-language).

### D2 — Cross-language fairness for shared-core debt-bearers → **Lenient (default), with Progressive fallback**

**Decision**: one shared `quality-baselines.json` per agent for now (current `baselines/shared/` shape). DO NOT pre-partition per-language. If first Python pilot run shows ≥3pp systematic quality_score divergence on any debt-bearer between Go and Python runs, **then** flip that specific agent to Progressive (track per-language) until the next debt-rewrite.

**Rationale**:
- Once D6 = Split lands, the rule layer will be genuinely shared. The agent's reasoning is the same; only the example anchors differ. There's no reason to expect quality_score systematic divergence after Split lands.
- BUT: the Split layer doesn't ship in v0.4.0. It ships incrementally during v0.5.0 Phase B as the Python pilot exposes which `conventions.yaml` entries actually matter. So during v0.5.0 we may briefly have one or two debt-bearers running on Go-leaky bodies in Python runs.
- **Lenient default + Progressive fallback** = cheapest reasonable shape: don't pay partition cost up front; pay it only for the specific debt-bearers that empirically show divergence; remove the per-language partition once the Split rewrite lands.

**Confidence**: medium-high. Could be wrong if, say, sdk-security-devil systematically misses Python attack vectors despite the Split — in which case Progressive may need to escalate to Strict. The whole point of the fallback is that the data tells us.

---

## Implementation shape for v0.5.0

### What lands in Phase A (scaffold)

1. `.claude/package-manifests/python.json` — toolchain, baselines, file extensions, marker syntax
2. `python/conventions.yaml` — initial empty-ish template; populates lazily during Phase B
3. `baselines/python/` — empty dir, `.gitkeep`
4. **No** debt-bearer rewrites yet. Bodies stay Go-flavored. Phase A is just scaffold.

### What lands in Phase B (first Python TPRD)

5. As each debt-bearer fires on the first Python TPRD, observe what fails:
   - If the agent flags a bogus Go-style finding on Python code → that's Split-evidence. Lift the body, write the missing `python/conventions.yaml` entry, update `shared-core/<agent>.md` to reference the per-lang file.
   - If the agent simply produces a useful review on Python code → no rewrite needed yet.
6. Update `generalization_debt` array in `shared-core.json` as each debt item is resolved (entry removed).

### What gets archived post-pilot (Phase D)

7. This document moves to `evolution/spike-archives/R2-debt-rewrite-feasibility.md`.

---

## What this changes in `LANGUAGE-AGNOSTIC-DECISIONS.md`

| Section | Change |
|---|---|
| §1 row "Convention layer" (T2-5) | Reframe: the `conventions.yaml` plan is now the **load-bearing seam** for D6 = Split. |
| §1 row "shared-core agents/skills with generalization_debt" | D2 resolution: **Lenient default + Progressive fallback**. |
| §1 row "Generalization-debt rewrite timing" | D6 resolution: **Split** (rule shared; examples + per-lang rules go in `conventions.yaml`). |
| §0 + §Decisions taken | Promote D2 + D6 to "Decisions taken" with v0.5.0 reference. |
| §4 R2 row | Mark complete; link to this file. |
| §5 Pre-flight | R2 → DONE. R1 remains pending (independent question). Phase A unblocked. |

---

## Limitations of this study

- N=3 agents sampled. The pattern was consistent across them, but `sdk-security-devil` (TLS / credential / log-PII checks) was not sampled and could plausibly contain more genuinely-language-specific rules (e.g., Python's pickle-deserialization attack surface has no Go analog). Sample at Phase B start.
- "Useful or vacuous" was judged by the author, not measured against actual reviewer behavior on real Python code. Phase B Python TPRD is the empirical test.
- The Split shape assumes `conventions.yaml` per-pack is a usable externalization seam. T2-5 (decide convention-layer location) is still open in `LANGUAGE-AGNOSTIC-DECISIONS.md`. If T2-5 chooses a different seam (e.g. inline inside `python.json`), the Split shape adapts but the per-pack file path changes.

---

## TL;DR for the v0.5.0 driver

**D6 = Split. D2 = Lenient with Progressive escape hatch. Phase A is unblocked.** Don't pre-rewrite; ship the seam (`conventions.yaml`) in Phase A, populate it lazily in Phase B as the Python pilot exposes friction.
