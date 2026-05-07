#!/usr/bin/env bash
# phases: design
# severity: BLOCKER
# license allowlist MIT/Apache-2.0/BSD/ISC/0BSD/MPL-2.0
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/design/dependencies.md"
[ -f "$F" ] || exit 0
BAD=$(grep -iE "license:\s*(GPL|AGPL|LGPL|SSPL|Proprietary)" "$F" || true)
[ -z "$BAD" ] || { echo "forbidden license: $BAD"; exit 1; }
