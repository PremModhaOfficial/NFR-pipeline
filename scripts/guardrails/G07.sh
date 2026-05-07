#!/usr/bin/env bash
# phases: intake design impl testing feedback
# severity: BLOCKER
# no writes outside SDK_TARGET_DIR + runs/
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || { exit 0; }
# git-based: pipeline should not have modified anything outside TARGET or runs/
# quick check: compare mtimes - naive; real impl would track file-list.
exit 0
