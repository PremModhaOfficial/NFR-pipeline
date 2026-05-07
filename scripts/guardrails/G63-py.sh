#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# No flakes under pytest --count=3 (pytest-repeat plugin).
# Any test that fails on at least one of the 3 repeats = flaky = BLOCKER.
# Skips integration-marked tests by default; uncomment the env override to include them.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0

# Verify pytest-repeat is available; if not, fall back to running 3 sequential pytest invocations
if (cd "$TARGET" && python3 -c "import pytest_repeat" 2>/dev/null); then
  (cd "$TARGET" && pytest --count=3 -m "not integration" -p no:randomly -q 2>&1) || {
    echo "flake detected under pytest --count=3"; exit 1;
  }
else
  echo "pytest-repeat not installed; running 3 sequential pytest invocations as fallback"
  for i in 1 2 3; do
    (cd "$TARGET" && pytest -m "not integration" -p no:randomly -q 2>&1) || {
      echo "flake detected on iteration $i"; exit 1;
    }
  done
fi
