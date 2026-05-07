#!/usr/bin/env bash
# tests/ast-hash/test.sh — P1 verification suite for the AST-hash protocol.
#
# Exercises the Go backend against the live Dragonfly source tree
# (motadata-go-sdk/src/motadatagosdk/core/l2cache/dragonfly/cache.go).
#
# Each assertion prints PASS / FAIL. Exit 0 if all pass, 1 if any fail.
#
# Usage: bash tests/ast-hash/test.sh
#   DRAGONFLY=/custom/path bash tests/ast-hash/test.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HASH="$ROOT/scripts/ast-hash/ast-hash.sh"
DRAGONFLY="${DRAGONFLY:-/home/prem-modha/projects/nextgen/motadata-go-sdk/src/motadatagosdk/core/l2cache/dragonfly}"
CACHE="$DRAGONFLY/cache.go"
TMP=$(mktemp -d -t ast-hash-XXXXXX)
export TMP  # so Python heredocs can read it via os.environ
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
assert() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        printf 'PASS  %-55s\n' "$name"
        PASS=$((PASS+1))
    else
        printf 'FAIL  %-55s expected=%s got=%s\n' "$name" "$expected" "$actual"
        FAIL=$((FAIL+1))
    fi
}

assert_ne() {
    local name="$1" a="$2" b="$3"
    if [ "$a" != "$b" ]; then
        printf 'PASS  %-55s (hashes differ as expected)\n' "$name"
        PASS=$((PASS+1))
    else
        printf 'FAIL  %-55s (both=%s, should have differed)\n' "$name" "$a"
        FAIL=$((FAIL+1))
    fi
}

assert_exit() {
    local name="$1" expected_exit="$2"; shift 2
    "$@" >/dev/null 2>&1
    local got=$?
    assert "$name (exit code)" "$expected_exit" "$got"
}

[ -f "$CACHE" ] || { echo "ERROR: $CACHE not found — set DRAGONFLY env"; exit 2; }

# --- basic hashing ---
H_NEW=$("$HASH" go "$CACHE" 'New')
H_CACHE=$("$HASH" go "$CACHE" 'Cache')
H_PING=$("$HASH" go "$CACHE" 'Cache.Ping')

# Basic sanity: each is a 64-char hex string
[[ ${#H_NEW}   -eq 64 ]] && echo "PASS  T1a basic hash — New fn is 64 hex chars"       && PASS=$((PASS+1)) || { echo "FAIL T1a"; FAIL=$((FAIL+1)); }
[[ ${#H_CACHE} -eq 64 ]] && echo "PASS  T1b basic hash — Cache type is 64 hex chars"   && PASS=$((PASS+1)) || { echo "FAIL T1b"; FAIL=$((FAIL+1)); }
[[ ${#H_PING}  -eq 64 ]] && echo "PASS  T1c basic hash — Cache.Ping method is 64 hex"  && PASS=$((PASS+1)) || { echo "FAIL T1c"; FAIL=$((FAIL+1)); }

# Distinct symbols produce distinct hashes
assert_ne 'T1d distinct symbols → distinct hashes (New vs Cache)' "$H_NEW" "$H_CACHE"

# --- determinism ---
H2=$("$HASH" go "$CACHE" 'New')
assert 'T2 determinism — same input → same hash' "$H_NEW" "$H2"

# --- comment invariance ---
cp "$CACHE" "$TMP/comment.go"
sed -i '90i\	// ADDED COMMENT SHOULD NOT AFFECT HASH' "$TMP/comment.go"
H=$("$HASH" go "$TMP/comment.go" 'New')
assert 'T3 comment invariance' "$H_NEW" "$H"

# --- whitespace invariance ---
cp "$CACHE" "$TMP/ws.go"
python3 - <<PY
import re
src = open("$TMP/ws.go").read()
src = re.sub(r'(\bfunc [^{]+\{)\n', r'\1\n\n\n\n', src)
open("$TMP/ws.go","w").write(src)
PY
H=$("$HASH" go "$TMP/ws.go" 'New')
assert 'T4 whitespace / blank-line invariance' "$H_NEW" "$H"

# --- semantic sensitivity: rename identifier in body ---
cp "$CACHE" "$TMP/rename.go"
python3 - <<'PY'
import re, os, sys
p = os.environ["TMP"] + "/rename.go"
src = open(p).read()
m = re.search(r'func New\(', src)
if not m: sys.exit('no New')
i = src.find('{', m.start()); body_start = i; depth = 0
while i < len(src):
    if src[i]=='{': depth += 1
    elif src[i]=='}':
        depth -= 1
        if depth == 0: body_end = i; break
    i += 1
body = src[body_start:body_end+1]
body_new = re.sub(r'\bopts\b', 'optsRenamedXYZ', body)
open(p,'w').write(src[:body_start] + body_new + src[body_end+1:])
PY
H=$("$HASH" go "$TMP/rename.go" 'New')
assert_ne 'T5 semantic sensitivity — identifier rename' "$H_NEW" "$H"

# --- semantic sensitivity: add a statement ---
cp "$CACHE" "$TMP/stmt.go"
python3 - <<'PY'
import re, os
p = os.environ["TMP"] + "/stmt.go"
src = open(p).read()
m = re.search(r'func New\(', src)
i = src.find('{', m.start())
open(p,'w').write(src[:i+1] + '\n\t_ = 42' + src[i+1:])
PY
H=$("$HASH" go "$TMP/stmt.go" 'New')
assert_ne 'T6 semantic sensitivity — added statement' "$H_NEW" "$H"

# --- error handling ---
assert_exit 'T7 unknown symbol → exit 4' 4 "$HASH" go "$CACHE" 'DoesNotExist'
assert_exit 'T8 missing file → exit 3'   3 "$HASH" go /nonexistent.go 'Foo'
assert_exit 'T9 unknown pack → exit 6'   6 "$HASH" elixir "$CACHE" 'Foo'

# --- gofmt round-trip ---
cp "$CACHE" "$TMP/gf.go"
python3 -c "
src = open('$TMP/gf.go').read(); src = src.replace('\\t', '    '); open('$TMP/gf.go','w').write(src)
"
gofmt -w "$TMP/gf.go"
H=$("$HASH" go "$TMP/gf.go" 'New')
assert 'T10 gofmt round-trip — detab then regofmt' "$H_NEW" "$H"

# --- combined cosmetic changes ---
cp "$CACHE" "$TMP/cb.go"
sed -i '90i\	// comment X' "$TMP/cb.go"
python3 - <<PY
import re
src = open("$TMP/cb.go").read()
src = re.sub(r'(\bfunc [^{]+\{)\n', r'\1\n\n\n', src)
open("$TMP/cb.go","w").write(src)
PY
H=$("$HASH" go "$TMP/cb.go" 'New')
assert 'T11 combined cosmetic — comment + blank lines' "$H_NEW" "$H"

# --- generic function (runCmd uses generics) ---
H_GENERIC=$("$HASH" go "$CACHE" 'runCmd')
[[ ${#H_GENERIC} -eq 64 ]] && echo "PASS  T12 generic top-level function (runCmd)" && PASS=$((PASS+1)) || { echo "FAIL T12"; FAIL=$((FAIL+1)); }

# --- summary ---
echo
echo "=========================================="
echo "  $PASS passed, $FAIL failed"
echo "=========================================="
[ $FAIL -eq 0 ]
