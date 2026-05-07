#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# G108-py — oracle-margin sanity (CLAUDE.md rule 20 + rule 32 axis 5).
# Each §7 hot-path symbol declares an `oracle.measured_p50_us` and
# `margin_multiplier` in design/perf-budget.md. Measured p50 must stay within
# margin_multiplier × oracle. Breach is NOT waivable via --accept-perf-regression
# — only by updating perf-budget.md margin with rationale at H8.
# Owner: sdk-benchmark-devil-python (Wave T5).
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/testing/bench-compare.md"
[ -f "$F" ] || { echo "G108-py INCOMPLETE: bench-compare.md missing at $F"; exit 1; }

# Explicit oracle margin FAIL.
if grep -E "G108.*\bFAIL\b|oracle.*\bFAIL\b|margin.*\bFAIL\b" "$F" | grep -vi "PASS\|CALIBRATION" >/dev/null 2>&1; then
  echo "G108-py FAIL: oracle margin breach"
  grep -E "G108.*\bFAIL\b|oracle.*\bFAIL\b" "$F" | head -3
  exit 1
fi

# Need at least one PASS marker on oracle margin.
if grep -E "G108.*PASS|oracle margin.*PASS|Oracle Verdict.*PASS" "$F" >/dev/null 2>&1; then
  N=$(grep -cE "PASS \\(0\\.[0-9]+|PASS \\([0-9]+\\.[0-9]+x?\\)" "$F")
  [ "$N" -eq 0 ] && N=$(grep -cE "Oracle Verdict.*PASS" "$F")
  echo "G108-py PASS: oracle-bearing symbol(s) within declared margin"
  exit 0
fi

echo "G108-py INCOMPLETE: no G108 verdict found in $F"
exit 1
