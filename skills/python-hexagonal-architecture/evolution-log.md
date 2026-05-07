# Evolution Log — python-hexagonal-architecture

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. src/<pkg>/{domain,ports,application,adapters}/ layout; pure-function domain (no I/O, no async, no third-party); Protocol-typed ports for structural typing; application layer async-but-minimal (no library imports); adapters wrap external libs; client.py as composition root; per-layer test pyramid (domain ms, use case ms, adapter integration s); when to skip hexagonal (thin SDK <30 lines); import-linter for layered enforcement.
