#!/usr/bin/env bash
# symbols.sh — language-neutral dispatcher for the symbol enumerator.
# Sibling of ast-hash.sh. Emits JSON describing every top-level declaration
# in a file or directory tree. See scripts/ast-hash/go-symbols.go for the
# Go implementation and schema.
#
# Usage:
#   symbols.sh <pack> -file <path>
#   symbols.sh <pack> -dir <root> [-include-tests]
#
# Exit codes mirror the backend.

set -uo pipefail

if [ $# -lt 2 ]; then
    echo "usage: $0 <pack> -file <path> | -dir <root>" >&2
    exit 2
fi

PACK="$1"; shift
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

case "$PACK" in
    go)
        if [ -x "$ROOT/packs/go/symbols-backend" ]; then
            exec "$ROOT/packs/go/symbols-backend" "$@"
        elif [ -x "$ROOT/scripts/ast-hash/go-symbols" ]; then
            exec "$ROOT/scripts/ast-hash/go-symbols" "$@"
        elif [ -f "$ROOT/scripts/ast-hash/go-symbols.go" ]; then
            if go build -o "$ROOT/scripts/ast-hash/go-symbols" "$ROOT/scripts/ast-hash/go-symbols.go"; then
                exec "$ROOT/scripts/ast-hash/go-symbols" "$@"
            fi
            go run "$ROOT/scripts/ast-hash/go-symbols.go" "$@"
        else
            echo "go symbols backend missing" >&2
            exit 4
        fi
        ;;
    python)
        # Prefer packs/python/ when it exists; fall back to in-tree script.
        if [ -f "$ROOT/packs/python/symbols-backend.py" ]; then
            exec python3 "$ROOT/packs/python/symbols-backend.py" "$@"
        elif [ -f "$ROOT/scripts/ast-hash/python-symbols.py" ]; then
            exec python3 "$ROOT/scripts/ast-hash/python-symbols.py" "$@"
        else
            echo "python symbols backend missing" >&2
            exit 4
        fi
        ;;
    *)
        echo "unknown pack: $PACK" >&2
        exit 6
        ;;
esac
