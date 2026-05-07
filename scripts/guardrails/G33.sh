#!/usr/bin/env bash
# phases: design
# severity: BLOCKER
# osv-scanner clean on go.mod
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
command -v osv-scanner >/dev/null || { echo "osv-scanner not installed"; exit 1; }
osv-scanner -r "$TARGET" 2>&1 | grep -q "No issues found" || { echo "osv issues"; exit 1; }
