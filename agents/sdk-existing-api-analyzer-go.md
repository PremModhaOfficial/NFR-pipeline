---
name: sdk-existing-api-analyzer-go
description: Phase 0.5 (Mode B/C only). Snapshots existing API surface, test baseline, benchmark baseline, and caller map of target package(s) before any design/impl work.
model: sonnet
tools: Read, Glob, Grep, Bash, Write
---

# sdk-existing-api-analyzer-go

## Startup
Read `runs/<run-id>/intake/mode.json`. If mode ∉ {B, C}, log skipped + exit.
Read target files from TPRD §2.

## Snapshots (via Bash)

### API surface
```bash
cd "$SDK_TARGET_DIR"
for pkg in <target-pkgs>; do
  go doc -all ./$pkg > /tmp/api-$pkg.txt
done
```
Parse into structured JSON: exported types, funcs, methods, fields, signatures, `[stable-since:]` markers.
Write `runs/<run-id>/extension/current-api.json` with this top-level shape:

```json
{
  "schema_version": "1.0",
  "language": "go",
  "snapshot_run_id": "<uuid>",
  "snapshot_at": "<ISO-8601>",
  "packages": [
    { "path": "core/dragonfly", "exports": [...] }
  ]
}
```

The `language` field MUST be sourced from `runs/<run-id>/context/active-packages.json:target_language` (today: `go`; future: `python` requires its own analyzer agent — `sdk-existing-api-analyzer-python` per the naming convention). `sdk-breaking-change-devil-go` reads this field and rejects diffs across mismatched languages.

### Test baseline
```bash
go test -v -cover ./<target-pkgs>/... > /tmp/test-baseline.txt
```
Parse into `runs/<run-id>/extension/test-baseline.json`: test names, status, coverage %.

### Benchmark baseline
```bash
go test -bench=. -benchmem -count=5 -run=^$ ./<target-pkgs>/... > /tmp/bench-baseline.txt
```
Copy to `runs/<run-id>/extension/bench-baseline.txt` (raw benchstat-compatible).

### Caller map (best-effort)
```bash
grep -r "import.*<target-pkg-import-path>" "$SDK_TARGET_DIR"
```
Parse importers into `runs/<run-id>/extension/caller-map.md`. Useful for breaking-change-devil to assess blast radius.

## Output

- `runs/<run-id>/extension/current-api.json`
- `runs/<run-id>/extension/test-baseline.json`
- `runs/<run-id>/extension/bench-baseline.txt`
- `runs/<run-id>/extension/caller-map.md`
- `runs/<run-id>/extension/context/sdk-existing-api-analyzer-summary.md`

## Decision Logging

- Log: snapshot counts (exports, tests, benchmarks)
- Log: any test failures in baseline (= pre-existing broken test; flag to user)

Log completion. Notify `sdk-marker-scanner` (runs next in Phase 0.5) and `sdk-design-lead`.
