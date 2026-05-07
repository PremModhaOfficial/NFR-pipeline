#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# G105-py — soak-MMD verdict gate (CLAUDE.md rule 32 axis 6 + rule 33).
# Each soak must reach its declared MMD (Minimum-Measurement-Duration) from
# design/perf-budget.md before its verdict is admissible. INCOMPLETE if any
# soak truncated below MMD; FAIL only if soak reached MMD AND failed.
# Owner: sdk-soak-runner-python + sdk-drift-detector (Wave T5.5).
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/testing/soak-report.md"
[ -f "$F" ] || { echo "G105-py INCOMPLETE: soak-report.md missing at $F"; exit 1; }

# Read only explicit "**Verdict (xxx)**:" lines — narrative text inside the
# report (e.g. "parent run returned INCOMPLETE-truncated") MUST NOT influence
# the gate. The current run's verdict lines are authoritative.
VERDICTS=$(grep -E "^\*\*Verdict \(.+\)\*\*" "$F")

# Any verdict line carrying INCOMPLETE-truncated (current state) = INCOMPLETE.
if echo "$VERDICTS" | grep -E "INCOMPLETE-truncated|MMD.*not.*reached" >/dev/null 2>&1; then
  echo "G105-py INCOMPLETE: a soak truncated below MMD"
  echo "$VERDICTS" | grep -E "INCOMPLETE-truncated"
  exit 1
fi

# Any verdict line carrying FAIL = FAIL.
if echo "$VERDICTS" | grep -E "\bFAIL\b" >/dev/null 2>&1; then
  echo "G105-py FAIL: soak verdict failed"
  echo "$VERDICTS" | grep -E "\bFAIL\b"
  exit 1
fi

# At least one verdict line must declare PASS.
if echo "$VERDICTS" | grep -E "\bPASS\b" >/dev/null 2>&1; then
  N=$(echo "$VERDICTS" | grep -cE "\bPASS\b")
  echo "G105-py PASS: $N soak verdict(s) PASS"
  exit 0
fi

echo "G105-py INCOMPLETE: no soak verdict line found in $F"
exit 1
