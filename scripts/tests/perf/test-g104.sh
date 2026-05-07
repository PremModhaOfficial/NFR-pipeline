#!/usr/bin/env bash
# tests/perf/test-g104.sh — verifies G104 picks the right metric per pack.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
G104="$ROOT/scripts/guardrails/G104.sh"
TMP=$(mktemp -d -t g104-XXXXXX); export TMP; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

assert_exit() {
    local name="$1" expected="$2"; shift 2
    "$@" >"$TMP/out.txt" 2>&1; local got=$?
    if [ "$expected" = "$got" ]; then
        printf 'PASS  %-65s\n' "$name"; PASS=$((PASS+1))
    else
        printf 'FAIL  %-65s expected=%s got=%s\n' "$name" "$expected" "$got"
        head -3 "$TMP/out.txt" | sed 's/^/        /'
        FAIL=$((FAIL+1))
    fi
}

# ---- Go pack: allocs_per_op (default behavior) ----
mkdir -p "$TMP/run-go/design" "$TMP/run-go/impl"
cat > "$TMP/run-go/design/perf-budget.md" <<'EOF'
| Symbol | allocs_per_op |
|--------|---------------|
| Get    | 3             |
| Set    | 5             |
EOF
echo '{"Get": 2, "Set": 4}' > "$TMP/run-go/impl/bench-allocs.json"
PACK=go assert_exit 'G104 go pack — under budget → PASS' 0 bash "$G104" "$TMP/run-go" ""

echo '{"Get": 99, "Set": 4}' > "$TMP/run-go/impl/bench-allocs.json"
PACK=go assert_exit 'G104 go pack — overrun → FAIL'      1 bash "$G104" "$TMP/run-go" ""
grep -q 'measured 99 > budget 3' "$TMP/run-go/impl/alloc-budget-check.md" && {
    printf 'PASS  %-65s\n' 'G104 go pack — overrun report mentions actual numbers'; PASS=$((PASS+1))
} || { printf 'FAIL  %-65s\n' 'G104 go pack — overrun report missing detail'; FAIL=$((FAIL+1)); }

# ---- Python pack: heap_bytes_per_call (parameterized) ----
mkdir -p "$TMP/run-py/design" "$TMP/run-py/impl"
cat > "$TMP/run-py/design/perf-budget.md" <<'EOF'
- symbol: get
  heap_bytes_per_call: 1024
- symbol: set
  heap_bytes_per_call: 2048
EOF
echo '[{"symbol": "get", "heap_bytes_per_call": 800}, {"symbol": "set", "heap_bytes_per_call": 1500}]' > "$TMP/run-py/impl/bench-allocs.json"
PACK=python assert_exit 'G104 python pack — under budget → PASS' 0 bash "$G104" "$TMP/run-py" ""
grep -q 'metric=heap_bytes_per_call' "$TMP/run-py/impl/alloc-budget-check.md" && {
    printf 'PASS  %-65s\n' 'G104 python pack — report tagged with python metric name'; PASS=$((PASS+1))
} || { printf 'FAIL  %-65s\n' 'G104 python pack — report missing python metric tag'; FAIL=$((FAIL+1)); }

echo '[{"symbol": "get", "heap_bytes_per_call": 99999}]' > "$TMP/run-py/impl/bench-allocs.json"
PACK=python assert_exit 'G104 python pack — overrun + missing → FAIL' 1 bash "$G104" "$TMP/run-py" ""

# ---- Rust pack: instructions_per_call ----
mkdir -p "$TMP/run-rs/design" "$TMP/run-rs/impl"
cat > "$TMP/run-rs/design/perf-budget.md" <<'EOF'
- symbol: get
  instructions_per_call: 500
EOF
echo '{"get": 450}' > "$TMP/run-rs/impl/bench-allocs.json"
PACK=rust assert_exit 'G104 rust pack — instructions_per_call under budget → PASS' 0 bash "$G104" "$TMP/run-rs" ""

# ---- Backward compat: no PACK env, no perf-budget → PASS ----
mkdir -p "$TMP/run-empty"
assert_exit 'G104 default pack (no PACK env) — no perf-budget → PASS' 0 bash "$G104" "$TMP/run-empty" ""

# ---- Default pack = go ----
mkdir -p "$TMP/run-default/design" "$TMP/run-default/impl"
cp "$TMP/run-go/design/perf-budget.md" "$TMP/run-default/design/"
echo '{"Get": 2, "Set": 4}' > "$TMP/run-default/impl/bench-allocs.json"
unset PACK
assert_exit 'G104 default (no PACK env) — Go-shaped budget → PASS' 0 bash "$G104" "$TMP/run-default" ""
grep -q 'pack=go' "$TMP/run-default/impl/alloc-budget-check.md" && {
    printf 'PASS  %-65s\n' 'G104 default — report says pack=go'; PASS=$((PASS+1))
} || { printf 'FAIL  %-65s\n' 'G104 default — pack=go tag missing'; FAIL=$((FAIL+1)); }

echo
echo "=========================================="
echo "  $PASS passed, $FAIL failed"
echo "=========================================="
[ $FAIL -eq 0 ]
