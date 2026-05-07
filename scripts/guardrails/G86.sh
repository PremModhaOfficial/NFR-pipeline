#!/usr/bin/env bash
# phases: feedback
# severity: BLOCKER
# Any-agent quality_score regressed >=5% vs baseline, with >=3 prior data points.
# Tightened threshold replaces the retired golden-corpus gate — see CLAUDE.md rule 28.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
REPO_ROOT="$RUN_DIR/../.."
BASELINES="$REPO_ROOT/baselines/shared/quality-baselines.json"
CURRENT="$RUN_DIR/feedback/metrics.json"
[ -f "$BASELINES" ] || exit 0
[ -f "$CURRENT" ]   || { echo "feedback/metrics.json missing"; exit 1; }

command -v jq >/dev/null || { echo "jq required for G86"; exit 1; }

# Only enforce once we have ≥3 prior runs (avoid false positives on small samples).
PRIOR_RUNS=$(jq -r '.sample_size // 0' "$BASELINES" 2>/dev/null || echo 0)
if [ "$PRIOR_RUNS" -lt 3 ]; then
  echo "G86: skipped (only $PRIOR_RUNS prior run(s); need 3+)"
  exit 0
fi

# Compare per-agent quality_score current vs baseline
REGRESSIONS=$(jq -r --slurpfile base "$BASELINES" '
  .agents[] as $a |
  ($base[0].agents[] | select(.name == $a.name)) as $b |
  if ($b and ($a.quality_score < ($b.quality_score - 0.05)))
  then "\($a.name): \($b.quality_score) -> \($a.quality_score)"
  else empty end
' "$CURRENT" 2>/dev/null)

if [ -n "$REGRESSIONS" ]; then
  echo "FAIL G86: quality regression ≥5% detected on:"
  echo "$REGRESSIONS"
  exit 1
fi
echo "PASS G86: no agent regressed ≥5%"
