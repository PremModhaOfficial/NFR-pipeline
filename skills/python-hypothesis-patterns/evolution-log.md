# Evolution Log — python-hypothesis-patterns

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. @given strategies (st.text/integers/floats/lists/dicts/composite/from_type/builds); @settings (max_examples, deadline, profiles dev/ci/release); @example for edge seeds + regression; @reproduce_failure for replay (remove after fix); @assume vs strategy.filter() (assume only for cross-input constraints); common property templates (round-trip, idempotence, monotonic, bound, preservation); @st.composite for related-field generation; RuleBasedStateMachine + @rule + @invariant for state machines; target() for guided search; .hypothesis/ db caching in CI; never deadline=None.
