# evolution-log.md — python-tdd-patterns

## 1.0.0 — v0.6.0-rc.0-sanitization — 2026-05-01
Triggered by: v0.5.0 → v0.6.0 sanitization migration (Batch 2). Symmetry pair to `go-tdd-patterns`.
Change: created. Body covers Python realization of the cycle in shared-core `tdd-patterns` — Protocol skeletons with `NotImplementedError`, AsyncMock + `create_autospec(Protocol, instance=True)`, `pytest.parametrize` tables, `pytest.raises` for error-path assertions, and async fixture composition. No direct copy from the v0.5 source; authored fresh against Python idioms.
Applied by: human-PR via migration script
