# Evolution Log — go-error-handling-patterns

## 1.0.0 — bootstrap-seed — 2026-04-17
Initial wrapper; archive ported.

## 1.0.1 — sdk-dragonfly-s2 — 2026-04-18
Triggered by: COV TRIGGERS-GAP (sdk-skill-coverage-reporter F4) + SKD-005 MODERATE (sdk-skill-drift-detector F3).
Change: Added trigger-keywords frontmatter field with activation phrases `mapErr`, `sentinel switch`, `precedence order`, `errors.Is`, `fmt.Errorf %w chain`. No body change; patch-level (trigger expansion only) per F5 advisory pending golden-corpus seed.
Devil verdict: auto-accept for patch-level trigger expansion (no semantic change; no body change).
Deferred to minor-bump (v1.1.0): SDK-client sentinel-only mode branch (body split) — blocked on golden-corpus/dragonfly-v1/ seed post-H10.
Applied by: learning-engine (F7).
Pipeline version: 0.2.0.
