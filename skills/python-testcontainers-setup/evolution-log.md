# Evolution Log — python-testcontainers-setup

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. Session-scoped fixture default; @pytest.mark.integration marker registration; state isolation patterns A/B/C (truncate, transactional rollback, per-test schema); Docker availability gate via pytest_collection_modifyitems; healthcheck wait policy; container log capture on failure; image version pinning (no :latest); reuse mode for dev / fresh on CI; cross-platform DOCKER_HOST discovery. Per-service recipes: PostgreSQL, Redis, Kafka, MinIO, NATS, MongoDB.
