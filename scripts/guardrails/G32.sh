#!/usr/bin/env bash
# phases: design testing
# severity: BLOCKER
# govulncheck clean on TARGET
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
command -v govulncheck >/dev/null || { echo "govulncheck not installed"; exit 1; }
(cd "$TARGET" && govulncheck ./... 2>&1) | grep -qE "No vulnerabilities|vulnerabilities found: 0" || { echo "vulns found"; exit 1; }
