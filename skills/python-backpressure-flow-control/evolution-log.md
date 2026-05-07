# Evolution Log — python-backpressure-flow-control

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. Drop vs block decision tree; asyncio.BoundedSemaphore for inflight cap; asyncio.Queue(maxsize=N) for bounded buffer; never unbounded queue; submit (block) + submit_or_drop (drop) public methods on bounded publisher; BackpressureError extends MotadataError; task_done() in finally; worker pool; queue-depth observable gauge + drop counter; drop-newest vs drop-oldest vs block strategies; sizing heuristic.
