#!/usr/bin/env bash
# tests/ast-hash/test-g95.sh — integration test for G95 marker-ownership
# guardrail under both the AST-hash (preferred) and byte-hash (legacy) paths.
#
# Fixture strategy: copy the live Dragonfly cache.go into a temp target dir,
# synthesize an ownership-map.json, run G95, assert expected outcome.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
G95="$ROOT/scripts/guardrails/G95.sh"
HASH="$ROOT/scripts/ast-hash/ast-hash.sh"
DRAGONFLY="${DRAGONFLY:-/home/prem-modha/projects/nextgen/motadata-go-sdk/src/motadatagosdk/core/l2cache/dragonfly}"
CACHE="$DRAGONFLY/cache.go"
TMP=$(mktemp -d -t g95-XXXXXX)
export TMP
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert_exit() {
    local name="$1" expected="$2"; shift 2
    "$@" >"$TMP/out.txt" 2>&1; local got=$?
    if [ "$expected" = "$got" ]; then
        printf 'PASS  %-60s\n' "$name"; PASS=$((PASS+1))
    else
        printf 'FAIL  %-60s expected_exit=%s got=%s\n' "$name" "$expected" "$got"
        echo "       output: $(head -1 "$TMP/out.txt")"
        FAIL=$((FAIL+1))
    fi
}

# ---- Fixture: clean target with matching AST-hash ----
mkdir -p "$TMP/target-clean" "$TMP/run/impl"
cp "$CACHE" "$TMP/target-clean/cache.go"
H_NEW=$("$HASH" go "$TMP/target-clean/cache.go" 'New')
H_CACHE=$("$HASH" go "$TMP/target-clean/cache.go" 'Cache')
cat > "$TMP/run/impl/ownership-map.json" <<EOF
{
  "manual_symbols": [
    { "symbol": "New",   "file": "cache.go", "language": "go", "ast_hash": "$H_NEW" },
    { "symbol": "Cache", "file": "cache.go", "language": "go", "ast_hash": "$H_CACHE" }
  ]
}
EOF

assert_exit 'G95 AST path — clean target → PASS (exit 0)' 0 bash "$G95" "$TMP/run" "$TMP/target-clean"

# ---- Fixture: modified target (variable renamed inside New) → FAIL ----
cp "$CACHE" "$TMP/target-modified/cache.go" 2>/dev/null || { mkdir -p "$TMP/target-modified"; cp "$CACHE" "$TMP/target-modified/cache.go"; }
python3 - <<'PY'
import re, os
p = os.environ["TMP"] + "/target-modified/cache.go"
src = open(p).read()
m = re.search(r'func New\(', src)
i = src.find('{', m.start()); body_start = i; depth = 0
while i < len(src):
    if src[i]=='{': depth += 1
    elif src[i]=='}':
        depth -= 1
        if depth == 0: body_end = i; break
    i += 1
body = src[body_start:body_end+1]
body_new = re.sub(r'\bopts\b', 'optsRenamedXYZ', body)
open(p, 'w').write(src[:body_start] + body_new + src[body_end+1:])
PY
mkdir -p "$TMP/run-fail/impl"
cp "$TMP/run/impl/ownership-map.json" "$TMP/run-fail/impl/ownership-map.json"
assert_exit 'G95 AST path — modified target → FAIL (exit 1)' 1 bash "$G95" "$TMP/run-fail" "$TMP/target-modified"
grep -q 'MANUAL symbol modified (AST)' "$TMP/run-fail/impl/marker-ownership-check.md" && {
    printf 'PASS  %-60s\n' 'G95 AST path — failure report mentions AST modification'; PASS=$((PASS+1))
} || {
    printf 'FAIL  %-60s\n' 'G95 AST path — failure report missing expected message'; FAIL=$((FAIL+1))
}

# ---- Fixture: comment-only change must NOT fail (gofmt invariance) ----
mkdir -p "$TMP/target-cosmetic"
cp "$CACHE" "$TMP/target-cosmetic/cache.go"
sed -i '90i\	// XXXXX added comment — should not trip G95 XXXXX' "$TMP/target-cosmetic/cache.go"
mkdir -p "$TMP/run-cosmetic/impl"
cp "$TMP/run/impl/ownership-map.json" "$TMP/run-cosmetic/impl/ownership-map.json"
assert_exit 'G95 AST path — comment-only change → PASS (invariance)' 0 bash "$G95" "$TMP/run-cosmetic" "$TMP/target-cosmetic"

# ---- Fixture: legacy byte-hash path still works ----
mkdir -p "$TMP/target-legacy" "$TMP/run-legacy/impl"
cp "$CACHE" "$TMP/target-legacy/cache.go"
# Pick a stable byte range (first 100 bytes of the file)
python3 - <<PY
import hashlib, json, os
p = os.environ["TMP"] + "/target-legacy/cache.go"
data = open(p, "rb").read()
region = data[:100]
h = hashlib.sha256(region).hexdigest()
om = {"manual_symbols": [
    {"symbol": "_header", "file": "cache.go", "byte_start": 0, "byte_end": 100, "sha256": h}
]}
json.dump(om, open(os.environ["TMP"] + "/run-legacy/impl/ownership-map.json", "w"), indent=2)
PY
assert_exit 'G95 byte-hash legacy path — matching hash → PASS' 0 bash "$G95" "$TMP/run-legacy" "$TMP/target-legacy"

# Modify the legacy region → FAIL
mkdir -p "$TMP/target-legacy-mod"
cp "$TMP/target-legacy/cache.go" "$TMP/target-legacy-mod/cache.go"
python3 - <<PY
import os
p = os.environ["TMP"] + "/target-legacy-mod/cache.go"
data = bytearray(open(p, "rb").read())
data[10] = ord('X')  # mutate one byte in the header region
open(p, "wb").write(bytes(data))
PY
mkdir -p "$TMP/run-legacy-mod/impl"
cp "$TMP/run-legacy/impl/ownership-map.json" "$TMP/run-legacy-mod/impl/ownership-map.json"
assert_exit 'G95 byte-hash legacy path — mutated byte → FAIL' 1 bash "$G95" "$TMP/run-legacy-mod" "$TMP/target-legacy-mod"
grep -q 'MANUAL symbol modified (byte)' "$TMP/run-legacy-mod/impl/marker-ownership-check.md" && {
    printf 'PASS  %-60s\n' 'G95 byte-hash legacy path — error message tagged (byte)'; PASS=$((PASS+1))
} || {
    printf 'FAIL  %-60s\n' 'G95 byte-hash legacy path — missing (byte) tag'; FAIL=$((FAIL+1))
}

# ---- Mode A (no ownership-map) → exit 0 (skip) ----
mkdir -p "$TMP/run-mode-a"   # no impl/ownership-map.json
assert_exit 'G95 Mode A — no ownership-map → skip (exit 0)' 0 bash "$G95" "$TMP/run-mode-a" "$TMP/target-clean"

echo
echo "=========================================="
echo "  $PASS passed, $FAIL failed"
echo "=========================================="
[ $FAIL -eq 0 ]
