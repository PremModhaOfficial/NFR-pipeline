#!/usr/bin/env bash
# phases: impl
# severity: HIGH
# gofmt -l empty
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
OUT=$(cd "$TARGET" && gofmt -l .)
[ -z "$OUT" ] || { echo "unformatted: $OUT"; exit 1; }
