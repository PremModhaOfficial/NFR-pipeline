# Evolution Log — review-fix-protocol

## 1.0.0 — bootstrap-seed — 2026-04-17
Initial wrapper; protocol reused verbatim.

## 1.1.0 — deterministic-first-gate — 2026-04-20
Added the deterministic-first gate between fix-agent batch completion and reviewer-fleet re-run.

**Change**: Step 3f now branches on guardrail result. BLOCKER-level script-driven checks (go build/vet/fmt/staticcheck, -race, goleak, govulncheck/osv-scanner, marker byte-hash, constraint bench proofs, license allowlist) gate the expensive reviewer fleet.

**Behavior**:
- Guardrails fail BLOCKER → synthesize as findings (prefix `GR-<Gxx>-<iter>`), route to fix agents, skip reviewer fleet this iteration.
- Guardrails green → reviewer fleet re-runs (unchanged from 1.0.0).
- WARNING-only failures do not gate.

**Invariant preserved**: Rule 13 (Post-Iteration Review Re-Run) still holds — every iteration whose output a reviewer would meaningfully evaluate gets reviewed. Iterations skipped by the gate have known mechanical defects that would dominate reviewer findings and get superseded on the next iteration anyway.

**Why this is a free win**: reviewer-fleet spawn costs are multiplicative (N reviewers × full-artifact input × per-agent logging). Gating on deterministic PASS avoids paying for reviews of code that doesn't compile. Savings track with the fraction of iterations that introduce a mechanical regression (~30–40% in typical runs).

**Rollback**: set `deterministic_gate_enabled: false` in run manifest to restore 1.0.0 behavior. Phase lead may override per-run for determinism-sensitive experiments.

## 1.2.0 — cross-llm-ensemble-dedup — 2026-05-04
Added ensemble dedup rules + the `XL-CONFLICT-*` synthesized finding category to support the cross-LLM-devil POC (Claude + Gemini-2.5-Pro siblings reviewing in parallel).

**Change**: New `## Ensemble (Cross-LLM) Deduplication` section runs AFTER the standard dedup. Two new optional finding fields documented (`reviewers: [string]`, `ensemble_signal: "agree" | "claude-only" | "gemini-only" | "conflict"`). Two new ID-prefix conventions (`<phase>-G-NNN` for Gemini siblings, `XL-CONFLICT-NNN` for synthesized contradictions). Conflict heuristic uses a small antonym set (POC v1); semantic similarity deferred to v2.

**Behavior**:
- Both reviewers agree on `(file, title)` → keep higher severity, set `ensemble_signal: agree`, populate `reviewers[]`.
- One side only → kept verbatim with `ensemble_signal` set (union = strict).
- Both reviewers fire ≥HIGH on same file with opposing titles → synthesize `XL-CONFLICT-NNN` (severity=blocker, category=cross-llm-conflict), retain both source findings, route to phase-lead for HITL.
- All ensemble outcomes log a `decision-logging` event (`cross-llm-agreement` / `cross-llm-call` / `cross-llm-conflict`) — pairs with `decision-logging` v1.2.0+.

**Invariant preserved**: existing readers that don't know about `reviewers[]` / `ensemble_signal` ignore them — fields are additive. Non-ensemble runs are byte-identical to v1.1.0 behavior.

**Rollback**: ensemble mode is opt-in (gated by sibling agents being present in the active package set). Remove the `*-gemini` agents from `shared-core.json:waves.*_devils` to revert; the dedup section becomes a no-op when only a single-source reviewer family fires.

## 1.3.0 — removed-cross-llm-ensemble — 2026-05-06
Removed the cross-LLM ensemble layer added in v1.2.0. Per user direction, the pipeline no longer carries cross-LLM devil support.

**Change**: Deleted the `## Ensemble (Cross-LLM) Deduplication` section, the `#### Optional fields used by ensemble (cross-LLM) mode` subsection, and all references to `reviewers[]` / `ensemble_signal` / `XL-CONFLICT-*` finding category. The skill body returns to its v1.1.0 surface (deterministic-first gate retained, ensemble dedup removed).

**Coordinated removals**: also dropped the two sibling Claude-Code agents (`sdk-overengineering-critic-gemini`, `sdk-security-devil-gemini`), the `cross-llm-devil` MCP server entry from `.mcp.json`, the `mcp-servers/cross-llm-devil/` source tree, the `GEMINI_API_KEY` env var from `.env.example`, the `mcp__cross-llm-devil__*` permissions from `.claude/settings.local.json`, and the corresponding agents from `shared-core.json:waves.D3_devils` + `M7_devils` + `agents[]`. `decision-logging` skill bumped to 1.4.0 in the same removal.

**Rollback**: revert this commit and the coordinated removals listed above; restore the v1.2.0 ensemble section verbatim. No data migration required — ensemble fields were always additive and historical run logs that still carry them remain valid (readers ignore unknown fields).
