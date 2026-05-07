#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# pack: shared-core
# G68 — every test file in the new package must carry at least one
# [traces-to: TPRD-§7-<id>] marker, proving the test maps to a declared
# §7 symbol. (R16, R29.)
set -uo pipefail

RUN_DIR="${1:?}"
TARGET="${2:-}"
[ -n "$TARGET" ] && [ -d "$TARGET" ] || { echo "G68 FAIL: TARGET dir missing"; exit 1; }

test_files=$(find "$TARGET" -type f \( -name '*_test.go' -o -path '*/tests/*.py' -o -name 'test_*.py' \) 2>/dev/null)
[ -z "$test_files" ] && { echo "G68 PASS: no test files in TARGET (pre-impl phase)"; exit 0; }

fail=0
for f in $test_files; do
    if ! grep -E '\[traces-to:[[:space:]]*TPRD-' "$f" >/dev/null 2>&1; then
        echo "G68 FAIL: $f missing [traces-to: TPRD-...] marker"
        fail=$((fail+1))
    fi
done

if [ $fail -gt 0 ]; then
    echo "G68 FAIL: $fail test files missing traces-to marker"
    exit 1
fi
echo "G68 PASS"
exit 0
