#!/usr/bin/env bash
# phases: feedback
# severity: BLOCKER
# evolution-report written
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
ls "$RUN_DIR/feedback/"*.md >/dev/null 2>&1 || { echo "no feedback/*.md"; exit 1; }
grep -rqi "evolution" "$RUN_DIR/feedback/" || { echo "no evolution report"; exit 1; }
