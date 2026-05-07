#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# G107-py — complexity-mismatch gate (CLAUDE.md rule 32 axis 4).
# sdk-complexity-devil-python sweeps N ∈ {10, 100, 1k, 10k}, curve-fits log-log
# slope, compares to declared big-O in design/perf-budget.md. Mismatch (e.g.
# declared O(n) but measured slope >= 1.4 indicating super-linear) = FAIL.
# Owner: sdk-complexity-devil-python (Wave T5).
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/testing/bench-compare.md"
[ -f "$F" ] || { echo "G107-py INCOMPLETE: bench-compare.md missing at $F"; exit 1; }

# Explicit complexity FAIL.
if grep -E "G107.*\bFAIL\b|complexity.*mismatch|super-linear" "$F" | grep -vi "PASS\|cap\|tolerance" >/dev/null 2>&1; then
  echo "G107-py FAIL: declared big-O does not match measured curve"
  grep -E "G107.*\bFAIL\b|complexity.*mismatch" "$F" | head -3
  exit 1
fi

# Need explicit PASS line.
if grep -E "G107.*PASS|complexity.*PASS" "$F" >/dev/null 2>&1; then
  N=$(grep -cE "G107.*PASS|complexity.*PASS|\\(linear\\)" "$F")
  echo "G107-py PASS: $N symbol(s) within declared big-O band"
  exit 0
fi

echo "G107-py INCOMPLETE: no G107 verdict found in $F"
exit 1
