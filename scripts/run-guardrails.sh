#!/usr/bin/env bash
# scripts/run-guardrails.sh — manifest-aware guardrail runner.
#
# Replaces wholesale "run all G*.sh" patterns. Filters on two axes:
#   1. Active-packages.json guardrail union (skips guardrails that belong to
#      a non-active language pack — e.g., G30 doesn't run on a Python TPRD).
#   2. Per-guardrail `# phases:` header (skips guardrails not applicable to
#      the requested phase — e.g., G60 only runs at testing).
#
# The two filters compose: a guardrail runs iff it's in the active union
# AND its phases header includes the requested phase.
#
# Usage:
#   bash scripts/run-guardrails.sh <phase> <run-dir> [target-dir]
#
# <phase>      one of: intake, design, impl, testing, feedback, meta
# <run-dir>    path to runs/<run-id>
# <target-dir> optional; passed as $2 to each guardrail (typically $SDK_TARGET_DIR)
#
# Active-packages discovery: $RUN_DIR/context/active-packages.json (required).
# If absent, falls back to shared-core ∪ <target_language> manifests.
#
# Outputs:
#   stdout                              human-readable line-per-guardrail report
#   $RUN_DIR/<phase>/guardrail-report.json   machine-readable verdict aggregate
#
# Severity treatment (parsed from `# severity:` header):
#   BLOCKER, HIGH       FAIL blocks the wave (script exits 1)
#   WARN, INFO, LOW,
#   MEDIUM, (missing)   FAIL is recorded but does not block
#
# Exit codes:
#   0 — no blocking failures
#   1 — at least one BLOCKER/HIGH guardrail FAILed
#   2 — config / usage error

set -uo pipefail

SCRIPT_NAME=$(basename "$0")
PIPELINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARDRAIL_DIR="$PIPELINE_ROOT/scripts/guardrails"
MANIFEST_DIR="$PIPELINE_ROOT/.claude/package-manifests"

usage() {
  cat >&2 <<EOF
Usage: $SCRIPT_NAME <phase> <run-dir> [target-dir]

phase: intake | design | impl | testing | feedback | meta
run-dir: path to runs/<run-id> (must contain context/active-packages.json)
target-dir: optional, passed to each guardrail as \$2

Filters guardrails by:
  1. Active-packages union (\$RUN_DIR/context/active-packages.json)
  2. Per-guardrail '# phases:' header

Exits 0 on full PASS, 1 on BLOCKER/HIGH FAIL, 2 on config error.
See script header for full reference.
EOF
}

if [ $# -lt 2 ]; then
  usage
  exit 2
fi

PHASE=$1; RUN_DIR=$2; TARGET=${3:-}

case "$PHASE" in
  intake|design|impl|testing|feedback|meta) ;;
  *)
    echo "$SCRIPT_NAME: invalid phase '$PHASE'. Allowed: intake, design, impl, testing, feedback, meta" >&2
    exit 2
    ;;
esac

if [ ! -d "$RUN_DIR" ]; then
  echo "$SCRIPT_NAME: run-dir '$RUN_DIR' does not exist" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "$SCRIPT_NAME: jq is required" >&2
  exit 2
fi

# Step 1 — compute active-guardrails union.
APJ="$RUN_DIR/context/active-packages.json"
ACTIVE_GUARDRAILS=""

if [ -f "$APJ" ]; then
  # Preferred: read pre-resolved union from active-packages.json:packages[].guardrails.
  ACTIVE_GUARDRAILS=$(jq -r '.packages[]?.guardrails[]?' "$APJ" 2>/dev/null | sort -u || true)

  # Fallback: if active-packages.json is the v0.4.0 minimal shape (no .packages
  # array), recompute from manifests using target_language.
  if [ -z "$ACTIVE_GUARDRAILS" ]; then
    LANG=$(jq -r '.target_language // empty' "$APJ")
    if [ -n "$LANG" ] && [ -f "$MANIFEST_DIR/$LANG.json" ]; then
      ACTIVE_GUARDRAILS=$(jq -r '.guardrails[]?' \
        "$MANIFEST_DIR/shared-core.json" \
        "$MANIFEST_DIR/$LANG.json" 2>/dev/null | sort -u || true)
    fi
  fi
fi

if [ -z "$ACTIVE_GUARDRAILS" ]; then
  echo "$SCRIPT_NAME: cannot compute active-guardrails union from $APJ" >&2
  echo "  Either active-packages.json is missing/malformed or target_language is unset." >&2
  exit 2
fi

# Step 2 — set up output dir + temp results file.
PHASE_DIR="$RUN_DIR/$PHASE"
mkdir -p "$PHASE_DIR"
REPORT="$PHASE_DIR/guardrail-report.json"
RAW=$(mktemp)
trap 'rm -f "$RAW"' EXIT

PASS_COUNT=0
WARN_FAIL_COUNT=0
BLOCKER_FAIL_COUNT=0
SKIP_NOT_ACTIVE=0
SKIP_PHASE_MISMATCH=0

ACTIVE_COUNT=$(echo "$ACTIVE_GUARDRAILS" | grep -c '^G' || true)
echo "[$SCRIPT_NAME] phase=$PHASE  run-dir=$RUN_DIR  active-guardrails=$ACTIVE_COUNT"

# Step 3 — iterate guardrails.
for f in "$GUARDRAIL_DIR"/G*.sh; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .sh)

  # Filter 1: active-packages union.
  if ! grep -qx "$name" <<< "$ACTIVE_GUARDRAILS"; then
    echo "  SKIP $name  (not in active packages)"
    SKIP_NOT_ACTIVE=$((SKIP_NOT_ACTIVE + 1))
    jq -n --arg name "$name" \
      '{name:$name, status:"skipped", reason:"not-in-active-packages"}' >> "$RAW"
    continue
  fi

  # Filter 2: phase header.
  PHASES=$(grep -m1 '^# phases:' "$f" | sed 's/^# phases:[[:space:]]*//')
  if ! grep -wq "$PHASE" <<< "$PHASES"; then
    echo "  SKIP $name  (phases='$PHASES'; not applicable to '$PHASE')"
    SKIP_PHASE_MISMATCH=$((SKIP_PHASE_MISMATCH + 1))
    jq -n --arg name "$name" --arg phases "$PHASES" --arg requested "$PHASE" \
      '{name:$name, status:"skipped", reason:"phase-mismatch", phases:$phases, requested_phase:$requested}' >> "$RAW"
    continue
  fi

  # Severity (default WARN if missing).
  SEVERITY=$(grep -m1 '^# severity:' "$f" | sed 's/^# severity:[[:space:]]*//')
  SEVERITY=${SEVERITY:-WARN}

  # Run it.
  printf "  RUN  %s  (%s)..." "$name" "$SEVERITY"
  OUTPUT=$(bash "$f" "$RUN_DIR" "$TARGET" 2>&1) && RC=0 || RC=$?

  if [ $RC -eq 0 ]; then
    echo " PASS"
    PASS_COUNT=$((PASS_COUNT + 1))
    jq -n --arg name "$name" --arg severity "$SEVERITY" \
      '{name:$name, status:"PASS", severity:$severity}' >> "$RAW"
  else
    echo " FAIL ($RC)"
    SHORT=$(printf '%s' "$OUTPUT" | head -c 500)
    jq -n --arg name "$name" --arg severity "$SEVERITY" \
          --argjson exit "$RC" --arg output "$SHORT" \
      '{name:$name, status:"FAIL", severity:$severity, exit:$exit, output:$output}' >> "$RAW"
    case "$SEVERITY" in
      BLOCKER|HIGH) BLOCKER_FAIL_COUNT=$((BLOCKER_FAIL_COUNT + 1)) ;;
      *)            WARN_FAIL_COUNT=$((WARN_FAIL_COUNT + 1)) ;;
    esac
  fi
done

# Step 4 — assemble report.
jq -s \
  --arg phase "$PHASE" \
  --arg run_dir "$RUN_DIR" \
  --argjson p "$PASS_COUNT" \
  --argjson w "$WARN_FAIL_COUNT" \
  --argjson b "$BLOCKER_FAIL_COUNT" \
  --argjson sn "$SKIP_NOT_ACTIVE" \
  --argjson sp "$SKIP_PHASE_MISMATCH" \
  '{
    phase: $phase,
    run_dir: $run_dir,
    summary: {
      pass: $p,
      warn_fail: $w,
      blocker_fail: $b,
      skipped_not_active: $sn,
      skipped_phase_mismatch: $sp
    },
    results: .
  }' \
  "$RAW" > "$REPORT"

echo ""
echo "[$SCRIPT_NAME] phase=$PHASE  PASS=$PASS_COUNT  WARN_FAIL=$WARN_FAIL_COUNT  BLOCKER_FAIL=$BLOCKER_FAIL_COUNT  SKIP(not-active)=$SKIP_NOT_ACTIVE  SKIP(phase)=$SKIP_PHASE_MISMATCH"
echo "[$SCRIPT_NAME] report=$REPORT"

if [ "$BLOCKER_FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
