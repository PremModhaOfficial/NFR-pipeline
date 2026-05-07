#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# no TODO/ErrNotImplemented in new package
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
BAD=$(grep -rnE "TODO|FIXME|ErrNotImplemented" "$TARGET" --include="*.go" 2>/dev/null || true)
[ -z "$BAD" ] || { echo "$BAD"; exit 1; }
