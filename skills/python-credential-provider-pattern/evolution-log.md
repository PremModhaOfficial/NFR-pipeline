# Evolution Log — python-credential-provider-pattern

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. CredentialProvider Protocol with `async def get()`; SecretStr opaque container with redacted str/repr/__format__ + hmac.compare_digest equality; provider implementations (Static / Env / File / CachedFile mtime-based / OAuth with refresh-lock + double-check + clock-skew); Client takes Provider keyword-only, NOT credential literal; token fetched per-request, never cached on instance; never log token in messages, span attrs, or exceptions; OAuthProvider has aclose(); FakeProvider for tests; .env / .env.example convention.
