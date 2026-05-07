#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# Lint + format check: ruff check + ruff format --check on the SDK.
# Unformatted or lint-failing code blocks impl progress.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export ACTIVE_PACKAGES_JSON="$RUN_DIR/context/active-packages.json"

# `lint` resolves to `ruff check .` per python.json toolchain
(cd "$TARGET" && bash "$PIPELINE_ROOT/scripts/run-toolchain.sh" lint) 2>&1 || { echo "lint fail"; exit 1; }

# `fmt` resolves to `ruff format --check .`
(cd "$TARGET" && bash "$PIPELINE_ROOT/scripts/run-toolchain.sh" fmt) 2>&1 || { echo "format fail (run `ruff format .` to fix)"; exit 1; }
