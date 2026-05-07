# Evolution log

## v1.0.0 — 2026-04-24 (pipeline v0.3.0 straighten)

Initial authored body. Prior state was a `bootstrap-seed` skeleton containing placeholder text ("will be synthesized on first Phase -1 use"). Phase -1 was removed in commit `b28405a`, leaving the file as a non-functional placeholder. This release authors the real body from target SDK conventions + relevant community Go patterns + the devil agents this skill pairs with.

Primary source files cited:
- `motadatagosdk/events/jetstream/publisher.go` (deadline probe + default-timeout bridge)
- `motadatagosdk/events/jetstream/requester.go` (same bridge pattern on the request path)
- `motadatagosdk/events/connection.go` (Close with scoped deadline + poll loop)
- `motadatagosdk/events/middleware/retry.go` (ctx-aware waitBackoff)
- `motadatagosdk/events/corenats/publisher.go` (deadline → timeout derivation)

Covers the three MUST items from the authoring spec:
1. `ctx.Deadline()` probe → only bridge when caller didn't declare one
2. Shortest-deadline-wins (documented as a property of `context.WithTimeout`, not manual)
3. `context.WithTimeout` pattern for stacked clients (GOOD 1)

Promoted from `draft` to `stable`. Priority preserved as MUST. Author: human PR.

## 0.1.0 — bootstrap-seed — 2026-04-17
Skeleton created. Full body to be synthesized by `sdk-skill-synthesizer` on first Phase -1 use.
