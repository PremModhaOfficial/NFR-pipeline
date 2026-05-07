#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# pack: shared-core
# G45 — every exported Go symbol (func/type/var/const) must have a
# preceding doc-comment that begins with the symbol name (godoc convention).
# Python: every public class/function (no leading underscore) must have a
# non-empty docstring. (R14, R16.)
set -uo pipefail

RUN_DIR="${1:?}"
TARGET="${2:-}"
[ -n "$TARGET" ] && [ -d "$TARGET" ] || { echo "G45 FAIL: TARGET dir missing"; exit 1; }

fail=0

# Go: scan exported decls; check preceding line is `// <Name>` or block comment
while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    name=$(echo "$match" | sed -E 's/.*(func|type|var|const)[[:space:]]+\(?[^)]*\)?[[:space:]]*([A-Z][A-Za-z0-9_]*).*/\2/')
    [ -z "$name" ] && continue
    prev=$(sed -n "$((lineno-1))p" "$file" 2>/dev/null)
    if ! echo "$prev" | grep -qE "^//[[:space:]]*$name\b"; then
        if ! echo "$prev" | grep -qE "^[[:space:]]*\*/"; then
            echo "G45 FAIL: $file:$lineno — exported symbol $name missing godoc"
            fail=$((fail+1))
        fi
    fi
done < <(grep -RnE '^(func( \([^)]+\))?|type|var|const)[[:space:]]+[A-Z]' "$TARGET" --include='*.go' 2>/dev/null | grep -v '_test\.go')

# Python: public symbols must have docstring (very lightweight check — first line after def/class is """ or ''')
while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    next=$(sed -n "$((lineno+1))p" "$file" 2>/dev/null | sed 's/^[[:space:]]*//')
    if ! echo "$next" | grep -qE '^("""|'\'''\'''\'')'; then
        decl=$(echo "$match" | cut -d: -f3-)
        echo "G45 FAIL: $file:$lineno — public symbol missing docstring: ${decl:0:60}"
        fail=$((fail+1))
    fi
done < <(grep -RnE '^(def|class) [a-z][A-Za-z0-9_]*' "$TARGET" --include='*.py' 2>/dev/null | grep -v '/tests/' | grep -v 'test_' | grep -v ': _')

if [ $fail -gt 0 ]; then
    echo "G45 FAIL: $fail exported symbols missing doc-comment"
    exit 1
fi
echo "G45 PASS"
exit 0
