#!/usr/bin/env bash
# compute-shape-hash.sh — emits SHA256 over the sorted exported-symbol
# signatures of a package. Used as an output-shape baseline (rule 28): silent
# API drift between runs that invoked overlapping skills changes this hash.
#
# AST-based as of pipeline 0.3.0 — was grep+sed of `^(func|type|var|const) [A-Z]`
# which broke for generic functions, multi-line signatures, and was Go-only.
# Now language-pluggable via scripts/ast-hash/symbols.sh.
#
# Usage:   compute-shape-hash.sh <package-dir> [pack]
# Output:  <sha256>  <export_count>
# Exit:    0 on success; 1 on missing dir or no exported symbols
set -uo pipefail
PKG="${1:?package-dir required}"
PACK="${2:-go}"

[ -d "$PKG" ] || { echo "no such dir: $PKG" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYMBOLS="$REPO_ROOT/scripts/ast-hash/symbols.sh"

JSON=$("$SYMBOLS" "$PACK" -dir "$PKG" 2>/dev/null) || {
    echo "symbols enumerator failed for pack=$PACK dir=$PKG" >&2
    exit 1
}

SIGS=$(printf '%s' "$JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
sigs = []
for fs in d.values():
    for s in fs.get('symbols', []):
        if s.get('exported') and s.get('name') != '_':
            sigs.append(s.get('signature_text', ''))
sigs = sorted(set(filter(None, sigs)))
print('\n'.join(sigs))
")

if [ -z "$SIGS" ]; then
    echo "no exported symbols found in $PKG" >&2
    exit 1
fi

COUNT=$(printf '%s\n' "$SIGS" | wc -l | tr -d ' ')
HASH=$(printf '%s\n' "$SIGS" | sha256sum | awk '{print $1}')
echo "$HASH  $COUNT"
