#!/usr/bin/env bash
# phases: intake
# severity: INFO
# clarifications ≤3 — info-only, never blocks; flags spec quality to improvement-planner
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
LOG="$RUN_DIR/intake/clarifications.jsonl"
[ -f "$LOG" ] || exit 0  # no Q&A log = no clarifications asked
N=$(grep -c '^{' "$LOG" 2>/dev/null || echo 0)
if [ "$N" -gt 3 ]; then
  echo "INFO: $N clarifying questions asked (target ≤3). TPRD may need tightening — flagged to improvement-planner."
fi
exit 0
