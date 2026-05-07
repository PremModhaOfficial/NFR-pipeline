# Evolution Log — python-dependency-vetting

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. Per-dep checks V-1 through V-11 (license / pip-audit / safety / size / age / transitives / PyPI adoption / GitHub maintenance / Sigstore PEP 740 / typosquat Levenshtein / native-code provenance / Python version compat); license allowlist + conditional + reject sets; aggregate verdict logic ACCEPT/CONDITIONAL/REJECT/INCOMPLETE; common alternatives table for rejected deps; TPRD §10 template. Drives sdk-dep-vet-devil-python verdicts. Python pack analog of go-dependency-vetting.

## 1.1.0 — v0.6.0 — 2026-05-04 — run motadata-nats-v1
Triggered by: B1-B4 root-cause trace (runs/motadata-nats-v1/feedback/root-cause-trace-B-series.md).
Change: added V-12 library-API-shape verification check. Materializes a scratch venv at the highest-pinnable minor of the declared range, reflects via `inspect.signature` over each SDK-cited class/function, surfaces kwarg-rename / kwarg-removed CONDITIONAL verdicts at H6. Catches class of "library evolved since TPRD floor was authored" defects at design time. Cross-referenced with `python-mock-strategy` v1.1.0.
Devil verdict: this run had B-series at T2 traceable to absence of V-12; v1.1.0 closes that gap.
Applied by: learning-engine. Append-only patch (V-12 added below V-11; aggregate-verdict table extended; existing V-checks unchanged).
