#!/usr/bin/env bash
# phases: design impl
# severity: BLOCKER
# no tenant_id / TenantID in generated code
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
# only scan new package(s) — placeholder: entire target
BAD=$(grep -rlE "\bTenantID\b|\btenant_id\b" "$TARGET" --include="*.go" 2>/dev/null || true)
[ -z "$BAD" ] || { echo "tenancy leak in: $BAD"; exit 1; }
