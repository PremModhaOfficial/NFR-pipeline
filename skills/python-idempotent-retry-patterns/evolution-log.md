# evolution-log.md — python-idempotent-retry-patterns

## 1.0.0 — v0.6.0-rc.0-sanitization — 2026-05-01
Triggered by: v0.5.0 → v0.6.0 sanitization migration (Batch 2). Symmetry pair to `go-idempotent-retry-patterns`.
Change: created. Body covers Python realization of the rules in shared-core `idempotent-retry-safety` — exception-class predicate with `__cause__` walk, `tenacity` decorator usage, manual `await asyncio.sleep` backoff loop, `Idempotency-Key` header on httpx, aiokafka idempotent producer config. Authored fresh against Python idioms; no direct copy.
Applied by: human-PR via migration script
