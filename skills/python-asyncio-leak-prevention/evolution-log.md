# Evolution Log — python-asyncio-leak-prevention

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. Leak categories L-A through L-E (asyncio task / unclosed session / unclosed file or socket / custom executor / subprocess pipes); 5 test gates (asyncio_task_tracker autouse fixture, unclosed_session_tracker via warnings.simplefilter, fd_tracker via psutil, pytest-repeat --count=5, tracemalloc snapshot diff); thread_tracker via threading.enumerate; full leak-clean shutdown test pattern. Python pack analog of goroutine-leak-prevention. Cited from sdk-asyncio-leak-hunter-python.

- v1.1.0 (run sdk-resourcepool-py-pilot-v1, defect SKD-001): strengthen Gate 1 — make `autouse=True` decoration non-negotiable. Add explicit BAD example (non-autouse fixture, mirror of conftest.py:26 defect, 59/62 tests ran unguarded) + GOOD example (autouse=True with `@pytest.mark.no_task_tracker` opt-out plumbing + pyproject markers entry) + anti-pattern caption "A non-autouse leak fixture is a no-op for every test that does not name it; the leak guarantee is forfeited." Applied by learning-engine; user-notified at H10 via runs/sdk-resourcepool-py-pilot-v1/feedback/learning-notifications.md.
