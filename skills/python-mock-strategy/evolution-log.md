# Evolution Log — python-mock-strategy

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. Decision tree Fake vs Mock with Fake-first default; Protocol-typed seam pattern for dependency injection; AsyncMock(spec=Class) for call-pattern assertions when needed; respx for httpx HTTP mocking, aioresponses for aiohttp; freezegun for time; pyfakefs vs tmp_path; pytest-mock mocker fixture; never mock the class under test; patch where USED not where defined; spec= mandatory; assert_awaited_once_with vs assert_called_once_with.

## 1.1.0 — v0.6.0 — 2026-05-04 — run motadata-nats-v1
Triggered by: B1-B4 sister cause (runs/motadata-nats-v1/feedback/skill-drift.md python-mock-strategy entry).
Change: added Rule 11.5 — strict-signature mocking when wrapping a real library API. Prescribes `inspect.signature(real_class).bind(**kwargs)` over permissive `**kwargs` to fail-fast on kwarg-rename / kwarg-removed drift. Includes BAD vs GOOD example, caveats around reflection cost + per-version conditionals, cross-reference to `python-dependency-vetting` v1.1.0 V-12 check.
Devil verdict: this run had FakeNats / FakeJs / FakeKVStore / FakeObjectStore accept `**kwargs` which hid the same nats-py 2.7→2.14 kwarg drift that the dep-vet skill missed. Strict-signature mocking would have surfaced B1-B4 at unit test time instead of T2 integration.
Applied by: learning-engine. Append-only patch (Rule 11.5 inserted between existing Rule 11 and Rule 12 anchor; existing rules unchanged).
