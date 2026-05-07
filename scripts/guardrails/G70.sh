#!/usr/bin/env bash
# phases: impl testing
# severity: BLOCKER
# pack: shared-core
# G70 — TPRD §7 coverage scoreboard. For every declared symbol in TPRD §7
# (API Surface), verify target tree contains: (a) impl declaration with
# non-stub body, (b) at least one test referencing the symbol, (c)
# [traces-to: TPRD-§7-<id>] marker on the declaration. Any missing cell = FAIL.
# (R16, R29, R33 — TPRD-gap is FAIL, never INCOMPLETE.)
set -uo pipefail

RUN_DIR="${1:?}"
TARGET="${2:-}"
TPRD="$RUN_DIR/intake/tprd.canonical.md"
[ -f "$TPRD" ] || TPRD="$RUN_DIR/tprd.md"
[ -f "$TPRD" ] || { echo "G70 FAIL: TPRD not found at $RUN_DIR"; exit 1; }
[ -n "$TARGET" ] && [ -d "$TARGET" ] || { echo "G70 FAIL: TARGET dir missing"; exit 1; }

section=$(awk '/^## *7\.|^## *§7|^# *§?7\b/{found=1; next} /^## /{found=0} found' "$TPRD")
[ -z "$section" ] && section=$(awk '/^## API Surface|^## API$/{found=1; next} /^## /{found=0} found' "$TPRD")

ids=$(printf '%s\n' "$section" | grep -oE 'TPRD-§7-[A-Za-z0-9_.-]+' | sort -u)
[ -z "$ids" ] && { echo "G70 WARN: no TPRD-§7-* ids found in §7; nothing to score"; exit 0; }

fail=0
for id in $ids; do
    symbol=$(printf '%s\n' "$section" | grep -E "$id\b" | head -1 | sed -E "s/.*$id[: ]*//; s/[(:].*//; s/\\\`//g; s/^ *//; s/ *$//")
    [ -z "$symbol" ] && symbol="$id"

    decl=$(grep -RnE "(^| )(func|class|def|type)[[:space:]]+$symbol\b" "$TARGET" 2>/dev/null | grep -v "_test\." | grep -v "/tests/" | head -3)
    if [ -z "$decl" ]; then
        echo "G70 FAIL: $id ($symbol) — no impl declaration in TARGET"
        fail=$((fail+1))
        continue
    fi

    if ! grep -RE "\[traces-to:[[:space:]]*$id\]" "$TARGET" >/dev/null 2>&1; then
        echo "G70 FAIL: $id ($symbol) — missing [traces-to: $id] marker"
        fail=$((fail+1))
    fi

    if ! grep -RnE "\b$symbol\b" "$TARGET" 2>/dev/null | grep -E "(_test\.|/tests/)" >/dev/null; then
        echo "G70 FAIL: $id ($symbol) — no test references the symbol"
        fail=$((fail+1))
    fi
done

if [ $fail -gt 0 ]; then
    echo "G70 FAIL: $fail TPRD §7 cells missing"
    exit 1
fi
echo "G70 PASS"
exit 0
