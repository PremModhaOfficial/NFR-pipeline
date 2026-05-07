#!/usr/bin/env bash
# phases: impl testing
# severity: BLOCKER
# mypy --strict clean (resolved through run-toolchain.sh `vet` dispatch).
# Static type-check is the Python pack's correctness gate equivalent to compile-time
# interface assertions.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export ACTIVE_PACKAGES_JSON="$RUN_DIR/context/active-packages.json"
(cd "$TARGET" && bash "$PIPELINE_ROOT/scripts/run-toolchain.sh" vet) 2>&1 || { echo "type-check fail"; exit 1; }
