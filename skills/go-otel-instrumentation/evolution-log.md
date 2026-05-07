# Evolution Log — go-otel-instrumentation

## 1.0.0 — bootstrap-seed — 2026-04-17
Initial wrapper; SDK-mode wiring via motadatagosdk/otel specified.

- v1.1.0 (2026-05-06) — purged tenant_id references throughout (G38 compliance fix); deleted "Service Bootstrap" + "Standard Metrics Per Service" sections (out-of-scope for client SDK pipeline); reframed title from service-flavor → client-SDK-flavor; added "Tenant attribution at runtime — consumer baggage" section explaining W3C baggage pattern. Cross-link to go-sdk-otel-hook-integration as canonical SDK lifecycle reference.
