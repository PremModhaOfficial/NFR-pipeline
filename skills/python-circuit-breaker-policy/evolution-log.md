# Evolution Log — python-circuit-breaker-policy

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. purgatory as Python pack default (async-native, MIT, typed); aiocircuitbreaker fallback; pybreaker only for sync; CLOSED → OPEN → HALF-OPEN state machine; per-endpoint scoping (one breaker per logical method, NOT global); excluded_exceptions for ValidationError-class caller errors; CircuitOpenError wraps library OpenedState; pair with retry but bubble CircuitOpenError immediately; OTel state-transition counter + span; Config-driven thresholds with 0=disabled. Cited by code-reviewer-python and idempotent-retry-safety.
