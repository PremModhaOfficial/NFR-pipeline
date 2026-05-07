#!/usr/bin/env bash
# phases: impl testing
# severity: BLOCKER
# G109-py — profile-no-surprise (CLAUDE.md rule 32 axis 2).
# sdk-profile-auditor-python captures CPU profile (py-spy / scalene); top-10
# CPU samples must match design/perf-budget.md hot-path declarations
# (coverage >= 0.8). Surprise hotspots = BLOCKER. INCOMPLETE if no profiler.
# Owner: sdk-profile-auditor-python (Wave M3.5).
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/testing/profile-auditor-report.md"
[ -f "$F" ] || { echo "G109-py INCOMPLETE: profile-auditor-report.md missing at $F"; exit 1; }

# Read only the explicit verdict line.
VERDICT=$(grep -E "Verdict.*G109.*profile-no-surprise" "$F" | head -1)

case "$VERDICT" in
  *PASS*)   echo "G109-py PASS: $VERDICT"; exit 0 ;;
  *FAIL*)   echo "G109-py FAIL: $VERDICT"; exit 1 ;;
  *INCOMPLETE*) echo "G109-py INCOMPLETE: $VERDICT"; exit 1 ;;
esac

# No verdict line found.
if grep -E "G109.*PASS" "$F" >/dev/null 2>&1; then
  echo "G109-py PASS: top-10 CPU samples covered by declared hot paths"
  exit 0
fi

echo "G109-py INCOMPLETE: no G109 verdict found in $F"
exit 1
