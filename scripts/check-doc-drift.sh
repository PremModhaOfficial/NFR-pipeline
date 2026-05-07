#!/usr/bin/env bash
# check-doc-drift.sh — meta-check that runs all drift guardrails + stat counts.
#
# Purpose: catch "partial propagation" drift — changes that updated some files
# and not others. Runs at intake so the pipeline refuses to operate on a
# drifted repo. Also runnable standalone for PR checks.
#
# Checks:
#   G06  — pipeline_version consistency (settings.json is SOT)
#   G90  — skill-index.json ↔ filesystem strict equality
#   G116 — retired-term scanner (docs/DEPRECATED.md entries absent from live docs)
#   Stat — reports live counts of agents / skills / guardrails for human review
#
# Usage:
#   ./scripts/check-doc-drift.sh              standalone (no run dir)
#   ./scripts/check-doc-drift.sh <run-dir>    inside a pipeline run
#
# Exit codes:
#   0 — clean
#   1 — drift detected (one or more BLOCKER guardrails failed)
#   2 — infrastructure problem (missing script, python3 not found, etc.)

set -uo pipefail
PIPELINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GR_DIR="$PIPELINE_ROOT/scripts/guardrails"

# Resolve a run-dir (caller-provided or temp). Drift guardrails write reports
# into the run-dir but for a standalone run we point them at a disposable tmp.
if [ $# -ge 1 ] && [ -n "$1" ]; then
  RUN_DIR="$1"
else
  RUN_DIR="$(mktemp -d -t check-doc-drift.XXXXXX)"
  TRAP_CLEANUP=1
  trap '[ "${TRAP_CLEANUP:-0}" = 1 ] && rm -rf "$RUN_DIR"' EXIT
fi
mkdir -p "$RUN_DIR/intake" "$RUN_DIR/meta"

FAIL=0
REPORT="$RUN_DIR/meta/drift-check.md"
{
  echo "# Doc-drift check"
  echo ""
  echo "Run at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Pipeline root: $PIPELINE_ROOT"
  echo ""
} > "$REPORT"

run_check() {
  local id="$1"; shift
  local script="$GR_DIR/${id}.sh"
  if [ ! -x "$script" ]; then
    echo "INFRA_MISSING $id: $script not executable or missing" | tee -a "$REPORT"
    return 2
  fi
  local output
  if output="$("$script" "$RUN_DIR" "" 2>&1)"; then
    echo "PASS $id" | tee -a "$REPORT"
    return 0
  else
    local rc=$?
    echo "" >> "$REPORT"
    echo "## FAIL $id (exit $rc)" >> "$REPORT"
    echo '```' >> "$REPORT"
    echo "$output" >> "$REPORT"
    echo '```' >> "$REPORT"
    echo "" >> "$REPORT"
    echo "FAIL $id"
    printf '%s\n' "$output" | head -40
    return $rc
  fi
}

echo "=== Drift guardrails ==="
for id in G06 G90 G116; do
  if ! run_check "$id"; then
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "=== Stat counts (for human review) ==="
AGENT_COUNT=$(ls "$PIPELINE_ROOT"/.claude/agents/*.md 2>/dev/null | wc -l)
SKILL_COUNT=$(ls -d "$PIPELINE_ROOT"/.claude/skills/*/ 2>/dev/null | wc -l)
GR_COUNT=$(ls "$PIPELINE_ROOT"/scripts/guardrails/G*.sh 2>/dev/null | wc -l)
PIPELINE_VERSION=$(python3 -c "import json; print(json.load(open('$PIPELINE_ROOT/.claude/settings.json'))['pipeline_version'])" 2>/dev/null || echo "unknown")

{
  echo ""
  echo "## Stat counts"
  echo ""
  echo "- pipeline_version (.claude/settings.json): $PIPELINE_VERSION"
  echo "- agents (.claude/agents/*.md): $AGENT_COUNT"
  echo "- skills (.claude/skills/*/): $SKILL_COUNT"
  echo "- guardrails (scripts/guardrails/G*.sh): $GR_COUNT"
} | tee -a "$REPORT"

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "=== drift check FAILED ($FAIL guardrail(s)) ==="
  echo "Report: $REPORT"
  exit 1
fi
echo "=== drift check PASSED ==="
echo "Report: $REPORT"
exit 0
