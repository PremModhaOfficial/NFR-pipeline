#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# G106-py — soak drift detection (CLAUDE.md rule 32 axis 6).
# sdk-drift-detector fits a linear regression over the soak's drift_signals
# (rss_bytes, asyncio_pending_tasks, gc_count_gen2, etc.) and fails on a
# statistically significant positive slope (p<0.05). Negative slope = no drift.
# Owner: sdk-drift-detector (Wave T5.5 observe phase).
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/testing/soak-report.md"
[ -f "$F" ] || { echo "G106-py INCOMPLETE: soak-report.md missing at $F"; exit 1; }

# Explicit drift FAIL marker (positive trend p<0.05).
if grep -E "G106.*\bFAIL\b|positive trend.*p<0\.05|drift.*\bFAIL\b" "$F" >/dev/null 2>&1; then
  echo "G106-py FAIL: positive drift trend detected (p<0.05)"
  grep -E "G106.*\bFAIL\b|positive trend" "$F" | head -3
  exit 1
fi

# At least one drift PASS line required (NEGATIVE / no drift).
if grep -E "G106.*PASS|drift detector PASS|No drift detected|NEGATIVE" "$F" >/dev/null 2>&1; then
  echo "G106-py PASS: no positive drift trend detected"
  exit 0
fi

echo "G106-py INCOMPLETE: no G106 verdict found in $F"
exit 1
