#!/usr/bin/env bash
# phases: impl testing
# severity: BLOCKER
# G104-py — alloc-budget gate (CLAUDE.md rule 32 axis 3).
# Parses sdk-profile-auditor-python's report; every measured symbol must report
# allocs/op (or B/call proxy) <= declared budget from design/perf-budget.md.
# Owner: sdk-profile-auditor-python (Wave M3.5).
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/testing/profile-auditor-report.md"
[ -f "$F" ] || { echo "G104-py INCOMPLETE: profile-auditor-report.md missing at $F"; exit 1; }

# Look for an explicit FAIL verdict in the alloc-budget block.
if grep -E "G104.*\bFAIL\b|alloc.*\bFAIL\b" "$F" | grep -v "FAIL-CALIBRATION" >/dev/null 2>&1; then
  echo "G104-py FAIL: alloc-budget breach found in $F"
  grep -E "G104.*\bFAIL\b|alloc.*\bFAIL\b" "$F" | head -5
  exit 1
fi

# Require an explicit PASS marker (any verdict line containing PASS in G104 block).
if grep -E "G104.*PASS" "$F" >/dev/null 2>&1; then
  PCT=$(grep -E "G104.*PASS" "$F" | head -1)
  echo "G104-py PASS: $PCT"
  exit 0
fi

echo "G104-py INCOMPLETE: no G104 verdict found in $F"
exit 1
