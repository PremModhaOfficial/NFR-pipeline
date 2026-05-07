# Evolution Log — python-asyncio-patterns

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. Covers TaskGroup-as-default (3.11+), strong-ref to Tasks, no `asyncio.run` in library, cancellation safety, `asyncio.timeout` over `wait_for`, sync primitives forbidden in async, `asyncio.to_thread` for blocking work, and `__aenter__` / `__aexit__` for clients holding resources. Cross-referenced from conventions.yaml `async_ownership` + `cancellation_primitive`.
