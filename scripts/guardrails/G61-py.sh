#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# Coverage >= 90% on src/ as reported by coverage.py JSON output.
# Reads $TARGET/coverage.json (produced by `pytest --cov=src --cov-report=json`).
# Threshold (90) read from python.json toolchain.coverage_min_pct, default 90.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
F="$TARGET/coverage.json"
[ -f "$F" ] || { echo "coverage.json missing at $F (run pytest --cov=src --cov-report=json first)"; exit 1; }

PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ACTIVE="$RUN_DIR/context/active-packages.json"
THRESHOLD=90
if [ -f "$ACTIVE" ]; then
  LANG=$(jq -r '.target_language // "go"' "$ACTIVE")
  MANIFEST="$PIPELINE_ROOT/.claude/package-manifests/$LANG.json"
  if [ -f "$MANIFEST" ]; then
    T=$(jq -r '.toolchain.coverage_min_pct // empty' "$MANIFEST")
    [ -n "$T" ] && THRESHOLD="$T"
  fi
fi

PCT=$(python3 -c "
import json, sys
data = json.load(open('$F'))
totals = data.get('totals', {})
pct = totals.get('percent_covered', 0.0)
print(f'{pct:.2f}')
")

python3 -c "import sys; sys.exit(0 if float('$PCT') >= float('$THRESHOLD') else 1)" || {
  echo "coverage $PCT% < $THRESHOLD% threshold"
  exit 1
}
echo "coverage $PCT% (>= $THRESHOLD%)"
