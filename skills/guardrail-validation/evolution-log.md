# Evolution Log — guardrail-validation

## 1.1.0 — bootstrap-seed — 2026-04-17
Extended 28-check archive catalog to G01–G103. Inverted multi-tenancy checks (now BLOCK presence). Dropped SQL/migration/inter-service checks. Added supply-chain (G32–G34), benchmark-regression (G65), marker-ownership (G95–G103).

28-check multi-tenant platform catalog (tenant_id mandatory, schema-per-tenant, stream-per-service, MsgPack-only NATS, etc.).
