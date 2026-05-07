#!/usr/bin/env bash
# scripts/run-toolchain.sh — manifest-aware toolchain dispatcher.
#
# Reads runs/<id>/context/active-packages.json (resolved by sdk-intake-agent
# Wave I5.5) and execs the requested toolchain.<command> from the active
# language adapter manifest at .claude/package-manifests/<lang>.json.
#
# Goal: callers (guardrails, agents) say `bash scripts/run-toolchain.sh test`
# without knowing whether the active language is Go (`go test ./... -race -count=1`)
# or Python (`pytest -x --no-header`). The manifest is the single source of
# truth for what each command resolves to per language.
#
# Usage:
#   bash scripts/run-toolchain.sh <command> [extra-args...]
#
# Examples:
#   bash scripts/run-toolchain.sh build
#   bash scripts/run-toolchain.sh test ./pkg/foo/...
#   bash scripts/run-toolchain.sh supply_chain
#
# Active-packages discovery (in order):
#   1. $ACTIVE_PACKAGES_JSON env var (explicit path; highest precedence)
#   2. $RUN_ID env var → runs/$RUN_ID/context/active-packages.json
#   3. Most-recent runs/*/context/active-packages.json (fallback)
#
# Working directory:
#   This script does NOT cd anywhere. Callers manage cwd. Guardrails that
#   need to run inside $SDK_TARGET_DIR should:
#     (cd "$SDK_TARGET_DIR" && bash $PIPELINE_ROOT/scripts/run-toolchain.sh test)
#
# Exit codes:
#   0 — command exec'd cleanly (or all sub-commands cleanly for arrays)
#   2 — usage / config error (missing args, missing manifest, bad manifest)
#   3 — command not declared in active manifest's toolchain block
#   N — propagated exit from the underlying tool

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
PIPELINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST_DIR="$PIPELINE_ROOT/.claude/package-manifests"

usage() {
  cat >&2 <<EOF
Usage: $SCRIPT_NAME <command> [extra-args...]

Resolves toolchain.<command> from the active language adapter manifest and
execs it (with extra args appended for string-typed commands).

Discovery: \$ACTIVE_PACKAGES_JSON > \$RUN_ID > most-recent runs/*/context/active-packages.json.

Exit codes: 0=ok, 2=config error, 3=command not declared, N=tool exit.
See script header for full reference.
EOF
}

if [ $# -lt 1 ]; then
  usage
  exit 2
fi

CMD=$1; shift

# Reject non-runnable manifest keys that look like commands.
case "$CMD" in
  coverage_min_pct)
    echo "$SCRIPT_NAME: '$CMD' is a numeric config value, not a runnable command" >&2
    exit 2
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "$SCRIPT_NAME: jq is required (install via package manager)" >&2
  exit 2
fi

# Step 1 — locate active-packages.json.
APJ=""
if [ -n "${ACTIVE_PACKAGES_JSON:-}" ]; then
  APJ="$ACTIVE_PACKAGES_JSON"
elif [ -n "${RUN_ID:-}" ]; then
  APJ="$PIPELINE_ROOT/runs/$RUN_ID/context/active-packages.json"
else
  CANDIDATE=$(ls -1t "$PIPELINE_ROOT"/runs/*/context/active-packages.json 2>/dev/null | head -1 || true)
  if [ -n "$CANDIDATE" ]; then
    APJ="$CANDIDATE"
  fi
fi

if [ -z "$APJ" ] || [ ! -f "$APJ" ]; then
  cat >&2 <<EOF
$SCRIPT_NAME: cannot locate active-packages.json
  Tried: \$ACTIVE_PACKAGES_JSON (unset), \$RUN_ID (unset), most-recent run (none).
  Either set \$ACTIVE_PACKAGES_JSON to a path, set \$RUN_ID, or run sdk-intake-agent
  Wave I5.5 first to produce runs/<run-id>/context/active-packages.json.
EOF
  exit 2
fi

# Step 2 — resolve target language from active-packages.json.
LANG=$(jq -r '.target_language // empty' "$APJ")
if [ -z "$LANG" ]; then
  echo "$SCRIPT_NAME: $APJ does not declare .target_language" >&2
  exit 2
fi

MANIFEST="$MANIFEST_DIR/$LANG.json"
if [ ! -f "$MANIFEST" ]; then
  echo "$SCRIPT_NAME: package manifest missing: $MANIFEST" >&2
  exit 2
fi

# Step 3 — look up toolchain.<CMD> in the language manifest.
# Value is either a string (single command) or an array (sequence of commands).
TYPE=$(jq -r --arg c "$CMD" '.toolchain[$c] | type' "$MANIFEST")

case "$TYPE" in
  "string")
    RESOLVED=$(jq -r --arg c "$CMD" '.toolchain[$c]' "$MANIFEST")
    if [ -z "$RESOLVED" ]; then
      echo "$SCRIPT_NAME: toolchain.$CMD is empty in $MANIFEST" >&2
      exit 3
    fi
    if [ $# -gt 0 ]; then
      RESOLVED="$RESOLVED $*"
    fi
    echo "+ ($LANG) $RESOLVED" >&2
    eval "$RESOLVED"
    ;;
  "array")
    COUNT=$(jq --arg c "$CMD" '.toolchain[$c] | length' "$MANIFEST")
    if [ "$COUNT" -eq 0 ]; then
      echo "$SCRIPT_NAME: toolchain.$CMD is empty array in $MANIFEST" >&2
      exit 3
    fi
    if [ $# -gt 0 ]; then
      echo "$SCRIPT_NAME: extra args not supported for array-typed command '$CMD'" >&2
      exit 2
    fi
    for i in $(seq 0 $((COUNT - 1))); do
      SUB=$(jq -r --arg c "$CMD" --argjson i "$i" '.toolchain[$c][$i]' "$MANIFEST")
      echo "+ ($LANG) [$((i + 1))/$COUNT] $SUB" >&2
      eval "$SUB"
    done
    ;;
  "null")
    AVAILABLE=$(jq -r '.toolchain | keys | join(", ")' "$MANIFEST")
    cat >&2 <<EOF
$SCRIPT_NAME: toolchain.$CMD not declared in $MANIFEST
  Available commands: $AVAILABLE
EOF
    exit 3
    ;;
  *)
    echo "$SCRIPT_NAME: toolchain.$CMD has unsupported type=$TYPE in $MANIFEST" >&2
    exit 2
    ;;
esac
