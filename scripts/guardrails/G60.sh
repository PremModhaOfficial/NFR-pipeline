#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# toolchain.test passes in $TARGET
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export ACTIVE_PACKAGES_JSON="$RUN_DIR/context/active-packages.json"
(cd "$TARGET" && bash "$PIPELINE_ROOT/scripts/run-toolchain.sh" test) 2>&1 || { echo "test fail"; exit 1; }
