#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# pack: shared-core
# G67 — every exported area in the new package must have at least one
# Example_* (Go) or runnable example doctest (Python). Per IMPLEMENTATION-PHASE.md
# exit gate + R14.
set -uo pipefail

RUN_DIR="${1:?}"
TARGET="${2:-}"
[ -n "$TARGET" ] && [ -d "$TARGET" ] || { echo "G67 FAIL: TARGET dir missing"; exit 1; }

# Detect language by toolchain
go_files=$(find "$TARGET" -type f -name '*.go' ! -name '*_test.go' 2>/dev/null | head -1)
py_files=$(find "$TARGET" -type f -name '*.py' 2>/dev/null | head -1)

fail=0

if [ -n "$go_files" ]; then
    # For each exported area (file with exported types/funcs), require ≥1 Example_*
    areas=$(grep -RlE '^(func|type) [A-Z]' "$TARGET" --include='*.go' 2>/dev/null | grep -v '_test\.go' | xargs -I{} dirname {} | sort -u)
    for dir in $areas; do
        examples=$(grep -RhE '^func Example[A-Z_]' "$dir" --include='*_test.go' 2>/dev/null | wc -l)
        if [ "$examples" -eq 0 ]; then
            echo "G67 FAIL: $dir — no Example_* func found for exported area"
            fail=$((fail+1))
        fi
    done
fi

if [ -n "$py_files" ]; then
    # Python: examples/ dir or doctest in docstrings
    if [ -d "$TARGET/examples" ]; then
        ex_count=$(find "$TARGET/examples" -type f -name '*.py' | wc -l)
        if [ "$ex_count" -eq 0 ]; then
            echo "G67 FAIL: $TARGET/examples exists but is empty"
            fail=$((fail+1))
        fi
    else
        # No examples dir: require at least one >>> doctest in src
        if ! grep -REn '>>> ' "$TARGET" --include='*.py' >/dev/null 2>&1; then
            echo "G67 FAIL: no examples/ dir and no doctest >>> in source"
            fail=$((fail+1))
        fi
    fi
fi

if [ $fail -gt 0 ]; then
    echo "G67 FAIL: $fail areas missing runnable examples"
    exit 1
fi
echo "G67 PASS"
exit 0
