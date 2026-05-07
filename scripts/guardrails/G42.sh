#!/usr/bin/env bash
# phases: impl testing
# severity: BLOCKER
# go vet clean
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
(cd "$TARGET" && go vet ./...) 2>&1 || { echo "vet fail"; exit 1; }
