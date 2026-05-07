# Evolution Log — python-client-rate-limiting

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. aiolimiter as default (MIT, async-native, leaky bucket); per-method scoping; Retry-After parsing (delta-seconds AND HTTP-date); adaptive shaping via AIMD (multiplicative decrease on 429, additive increase on success streak); X-RateLimit-* proactive header parsing; combine with retry but never exponential-backoff a 429; OTel rate_limited counter + throttle_wait histogram; Config-driven with rate=0 disable.
