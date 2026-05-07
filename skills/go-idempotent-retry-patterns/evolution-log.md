# evolution-log.md — go-idempotent-retry-patterns

## 1.0.0 — v0.6.0-rc.0-sanitization — 2026-05-01
Triggered by: v0.5.0 → v0.6.0 sanitization migration (Batch 2)
Change: created. Body extracted from `motadata-sdk-pipeline-v0.5.0/skills/idempotent-retry-safety/SKILL.md` Go content — `IsRetryable` predicate using `errors.Is`/`errors.As`, `RetryMiddleware.executeWithRetry` with `select` on `ctx.Done()`, `crypto/rand` jitter math, JetStream `WithMsgID` idempotency envelope. Source skill `idempotent-retry-safety` retained the cross-language taxonomy and decision criteria.
Applied by: human-PR via migration script
