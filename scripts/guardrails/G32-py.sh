#!/usr/bin/env bash
# phases: design testing
# severity: BLOCKER
# Vulnerability scan: pip-audit + safety must be clean on the SDK target.
# Python pack security supply-chain gate.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
[ -f "$TARGET/pyproject.toml" ] || { echo "no pyproject.toml at $TARGET — Python pack target expected"; exit 1; }

command -v pip-audit >/dev/null 2>&1 || { echo "pip-audit not installed"; exit 1; }

# pip-audit on the project's installed deps.
# --skip-editable skips the SDK package itself (it's installed editable from
# the local checkout and wouldn't resolve on PyPI). pip-audit returns
# non-zero only on actual CVE matches; the editable-skip notice is informational.
(cd "$TARGET" && pip-audit --skip-editable 2>&1) || { echo "pip-audit found vulnerabilities"; exit 1; }

# safety is optional secondary cross-check
if command -v safety >/dev/null 2>&1; then
  (cd "$TARGET" && safety check --full-report 2>&1) || { echo "safety found vulnerabilities"; exit 1; }
fi
