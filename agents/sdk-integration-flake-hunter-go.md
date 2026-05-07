---
name: sdk-integration-flake-hunter-go
description: READ-ONLY (runs tests). Re-runs integration tests -count=3. Any failure = flaky; BLOCKER until investigated.
model: sonnet
tools: Read, Glob, Grep, Bash, Write
---

# sdk-integration-flake-hunter-go

## Input
Target branch with integration tests (tagged `//go:build integration`).

## Procedure

```bash
cd "$SDK_TARGET_DIR"
go test -tags=integration -count=3 -timeout 600s ./<new-pkg>/... 2>&1 | tee /tmp/flake-hunt.txt
```

Parse output:
- Full PASS on all 3 runs → CLEAN
- Any FAIL → FLAKY; capture which test, which iteration, what error

If flaky, re-run isolating the flaky test with `-count=10` to get flake rate.

## Output
`runs/<run-id>/testing/reviews/flake-hunter.md`:
```md
# Flake Hunt

**Verdict**: CLEAN | FLAKY

## Run summary
- Total tests: 42
- Passed all 3 runs: 41
- Flaky: 1 (TestCache_SetAfterClose)

## Flaky test detail
```
TestCache_SetAfterClose — failed 2/10 in isolation
Error: timeout waiting for close signal
Likely cause: race between Close() and Set(); add synchronization barrier
```

## Recommendation
Fix race in Close(); route to sdk-impl-lead + sdk-leak-hunter-go.
```

Log event with flake count. BLOCKER on any flake.
