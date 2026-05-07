#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# no hardcoded creds
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
BAD=$(grep -rniE "(AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|-----BEGIN.*PRIVATE KEY-----|password\s*[:=]\s*\"[^\"]+\")" "$TARGET" --include="*.go" 2>/dev/null || true)
[ -z "$BAD" ] || { echo "$BAD"; exit 1; }
