#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# coverage >=90% on new package
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/testing/coverage.out"
[ -f "$F" ] || { echo "coverage.out missing"; exit 1; }
PCT=$(go tool cover -func="$F" 2>/dev/null | awk "/total:/ {sub(/%/,\"\",\$3); print \$3}")
python3 -c "import sys; sys.exit(0 if float(\"$PCT\") >= 90 else 1)" || { echo "coverage $PCT < 90"; exit 1; }
