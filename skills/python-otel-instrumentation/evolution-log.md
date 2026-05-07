# Evolution Log — python-otel-instrumentation

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. Module-scope tracer/meter/counters; start_as_current_span context manager; static low-cardinality span names; OTel semconv attribute keys; record_exception + set_status pairing; cancellation NOT marked ERROR; Counter/Histogram reuse; async context propagation via contextvars; LoggingHandler bridge for stdlib logging; library uses OTel API not SDK (consumer wires providers); graceful shutdown helper. Python pack analog of go-otel-instrumentation. Cited from sdk-convention-devil-python C-7.
