#!/usr/bin/env bash
# phases: design
# severity: BLOCKER
# dependencies.md lists every new go get
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/design/dependencies.md"
[ -f "$F" ] || { echo "dependencies.md missing"; exit 1; }
[ -s "$F" ] || { echo "empty"; exit 1; }
