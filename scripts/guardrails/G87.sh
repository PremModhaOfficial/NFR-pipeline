#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# Validates baselines/<lang>/performance-baselines.json conforms to the canonical
# schema in docs/PERFORMANCE-BASELINE-SCHEMA.md (envelope + per-language extension).
# U15 Phase 6 (Gap C closure). Skips gracefully if no baseline file exists yet.
set -uo pipefail
RUN_DIR="${1:?Usage: G87.sh <run-dir> [target]}"
TARGET="${2:-}"
REPO_ROOT="$RUN_DIR/../.."

# --- Resolve target language from active-packages.json ----------------------
ACTIVE="$RUN_DIR/context/active-packages.json"
if [ ! -f "$ACTIVE" ]; then
  echo "G87: active-packages.json missing; cannot validate language match"
  exit 1
fi
command -v jq >/dev/null || { echo "G87 FAIL: jq required"; exit 1; }
LANG=$(jq -r '.target_language // empty' "$ACTIVE")
if [ -z "$LANG" ]; then
  echo "G87 FAIL: target_language not set in active-packages.json"
  exit 1
fi

BASELINE="$REPO_ROOT/baselines/$LANG/performance-baselines.json"
if [ ! -f "$BASELINE" ]; then
  echo "G87: skipped ($BASELINE does not exist; first run for this language)"
  exit 0
fi

# --- Validate JSON parses ----------------------------------------------------
if ! jq empty "$BASELINE" 2>/dev/null; then
  echo "G87 FAIL: $BASELINE is not valid JSON"
  exit 1
fi

# --- Envelope checks (both languages) ----------------------------------------
ENVELOPE_OK=$(jq 'has("schema_version") and has("language") and has("scope") and has("packages")' "$BASELINE")
if [ "$ENVELOPE_OK" != "true" ]; then
  echo "G87 FAIL: envelope missing required keys (schema_version, language, scope, packages)"
  echo "  per docs/PERFORMANCE-BASELINE-SCHEMA.md § Required envelope"
  exit 1
fi

FILE_LANG=$(jq -r '.language' "$BASELINE")
case "$FILE_LANG" in
  go|python) ;;
  *) echo "G87 FAIL: language='$FILE_LANG' not in {go, python}"; exit 1 ;;
esac

if [ "$FILE_LANG" != "$LANG" ]; then
  echo "G87 FAIL: file language='$FILE_LANG' does not match active-packages target_language='$LANG'"
  exit 1
fi

SCOPE=$(jq -r '.scope' "$BASELINE")
if [ "$SCOPE" != "per-language" ]; then
  echo "G87 FAIL: scope='$SCOPE' must be 'per-language'"
  exit 1
fi

PKG_TYPE=$(jq -r '.packages | type' "$BASELINE")
if [ "$PKG_TYPE" != "object" ]; then
  echo "G87 FAIL: packages must be a JSON object, got $PKG_TYPE"
  exit 1
fi

# Known schema versions — keep in sync with docs/PERFORMANCE-BASELINE-SCHEMA.md Changelog
SCHEMA_VER=$(jq -r '.schema_version' "$BASELINE")
case "$SCHEMA_VER" in
  "1.0") ;;
  *) echo "G87 FAIL: schema_version='$SCHEMA_VER' not in known versions {1.0}"
     echo "  see docs/PERFORMANCE-BASELINE-SCHEMA.md § Changelog to add a new version"
     exit 1 ;;
esac

# --- Per-language extension validation ---------------------------------------
if [ "$FILE_LANG" = "go" ]; then
  # Per-package: required generated, run_id, package, scope, language, symbols
  MISSING_PKG=$(jq -r '
    .packages | to_entries[] | .key as $k | .value |
    [
      (if has("generated")    | not then "\($k).generated"    else empty end),
      (if has("run_id")       | not then "\($k).run_id"       else empty end),
      (if has("package")      | not then "\($k).package"      else empty end),
      (if has("scope")        | not then "\($k).scope"        else empty end),
      (if has("language")     | not then "\($k).language"     else empty end),
      (if has("symbols")      | not then "\($k).symbols"      else empty end)
    ] | .[]
  ' "$BASELINE")
  if [ -n "$MISSING_PKG" ]; then
    echo "G87 FAIL (Go): missing required per-package fields:"
    echo "$MISSING_PKG" | sed 's/^/  /'
    exit 1
  fi
  # Per-symbol: required ns_per_op_median, bytes_per_op_median, allocs_per_op_median, samples
  MISSING_SYM=$(jq -r '
    .packages | to_entries[] | .key as $pk | .value.symbols // {} |
    to_entries[] | .key as $bk | .value |
    [
      (if has("ns_per_op_median")    | not then "\($pk).symbols.\($bk).ns_per_op_median"    else empty end),
      (if has("bytes_per_op_median") | not then "\($pk).symbols.\($bk).bytes_per_op_median" else empty end),
      (if has("allocs_per_op_median")| not then "\($pk).symbols.\($bk).allocs_per_op_median"else empty end),
      (if has("samples")             | not then "\($pk).symbols.\($bk).samples"             else empty end)
    ] | .[]
  ' "$BASELINE")
  if [ -n "$MISSING_SYM" ]; then
    echo "G87 FAIL (Go): missing required per-symbol fields:"
    echo "$MISSING_SYM" | sed 's/^/  /'
    exit 1
  fi

elif [ "$FILE_LANG" = "python" ]; then
  # Per-package: required first_seen_run, first_seen_at, history
  MISSING_PKG=$(jq -r '
    .packages | to_entries[] | .key as $k | .value |
    [
      (if has("first_seen_run") | not then "\($k).first_seen_run" else empty end),
      (if has("first_seen_at")  | not then "\($k).first_seen_at"  else empty end),
      (if has("history")        | not then "\($k).history"        else empty end)
    ] | .[]
  ' "$BASELINE")
  if [ -n "$MISSING_PKG" ]; then
    echo "G87 FAIL (Python): missing required per-package fields:"
    echo "$MISSING_PKG" | sed 's/^/  /'
    exit 1
  fi
  # history must be a non-empty array
  EMPTY_HIST=$(jq -r '
    .packages | to_entries[] |
    select(.value.history | type != "array" or length == 0) |
    .key
  ' "$BASELINE")
  if [ -n "$EMPTY_HIST" ]; then
    echo "G87 FAIL (Python): packages with empty or non-array history:"
    echo "$EMPTY_HIST" | sed 's/^/  /'
    exit 1
  fi
  # Per-history-entry: required run_id, recorded_at, symbols
  MISSING_HIST=$(jq -r '
    .packages | to_entries[] | .key as $pk | .value.history // [] |
    to_entries[] | .key as $hi | .value |
    [
      (if has("run_id")      | not then "\($pk).history[\($hi)].run_id"      else empty end),
      (if has("recorded_at") | not then "\($pk).history[\($hi)].recorded_at" else empty end),
      (if has("symbols")     | not then "\($pk).history[\($hi)].symbols"     else empty end)
    ] | .[]
  ' "$BASELINE")
  if [ -n "$MISSING_HIST" ]; then
    echo "G87 FAIL (Python): missing required per-history-entry fields:"
    echo "$MISSING_HIST" | sed 's/^/  /'
    exit 1
  fi
  # Per-symbol: required p50_us, rounds, iterations
  MISSING_SYM=$(jq -r '
    .packages | to_entries[] | .key as $pk | .value.history // [] |
    to_entries[] | .key as $hi | .value.symbols // {} |
    to_entries[] | .key as $sk | .value |
    [
      (if has("p50_us")     | not then "\($pk).history[\($hi)].symbols.\($sk).p50_us"     else empty end),
      (if has("rounds")     | not then "\($pk).history[\($hi)].symbols.\($sk).rounds"     else empty end),
      (if has("iterations") | not then "\($pk).history[\($hi)].symbols.\($sk).iterations" else empty end)
    ] | .[]
  ' "$BASELINE")
  if [ -n "$MISSING_SYM" ]; then
    echo "G87 FAIL (Python): missing required per-symbol fields:"
    echo "$MISSING_SYM" | sed 's/^/  /'
    exit 1
  fi
  # Verdict-typed fields must match canonical pattern (allow composite forms)
  # Pattern: ^(PASS|FAIL|INCOMPLETE)(-[a-z][a-z-]*)?$
  BAD=$(jq -r '
    .packages | to_entries[] | .key as $pk | .value.history // [] |
    to_entries[] | .key as $hi | .value |
    [
      (if has("regression_verdict") and (.regression_verdict | test("^(PASS|FAIL|INCOMPLETE)(-[a-z][a-z-]*)?$") | not)
       then "\($pk).history[\($hi)].regression_verdict=\"\(.regression_verdict)\"" else empty end),
      (if has("g108_oracle_verdict") and (.g108_oracle_verdict | test("^(PASS|FAIL|INCOMPLETE)(-[a-z][a-z-]*)?$") | not)
       then "\($pk).history[\($hi)].g108_oracle_verdict=\"\(.g108_oracle_verdict)\"" else empty end)
    ] | .[]
  ' "$BASELINE" 2>/dev/null)
  if [ -n "$BAD" ]; then
    echo "G87 FAIL (Python): verdict fields do not match canonical pattern ^(PASS|FAIL|INCOMPLETE)(-[a-z][a-z-]*)?\$:"
    echo "$BAD" | sed 's/^/  /'
    echo "  see docs/PERFORMANCE-BASELINE-SCHEMA.md § Verdict enums"
    exit 1
  fi
fi

# Note: G87 deliberately does NOT enforce parent-child keying between
# symbols / alloc_audit_g104 / complexity_sweep_g107 (sub-gap C.1 declared
# intentional in docs/PERFORMANCE-BASELINE-SCHEMA.md). Those siblings use
# different naming conventions because they measure different scopes.

echo "G87 PASS: $BASELINE conforms to canonical schema (schema_version=$SCHEMA_VER, language=$FILE_LANG)"
exit 0
