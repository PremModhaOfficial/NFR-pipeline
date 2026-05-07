#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# no flakes under -count=3
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
(cd "$TARGET" && go test ./... -count=3 -race) 2>&1 || { echo "flake detected"; exit 1; }
