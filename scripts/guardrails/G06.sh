#!/usr/bin/env bash
# phases: intake meta
# severity: BLOCKER
# pipeline_version consistency: every file that asserts a pipeline_version must match .claude/settings.json
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SETTINGS="$PIPELINE_ROOT/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
  echo "FAIL: settings.json missing at $SETTINGS"
  exit 1
fi

AUTH_VERSION="$(python3 -c "import json; print(json.load(open('$SETTINGS'))['pipeline_version'])" 2>/dev/null)"
if [ -z "$AUTH_VERSION" ]; then
  echo "FAIL: pipeline_version not set in $SETTINGS"
  exit 1
fi

# Directories/files excluded from the scan:
#   - runs/  historical run artifacts (immutable; pipeline_version of the version that produced the run)
#   - .git/  git internals
#   - .serena/ .omc/ local tool caches
#   - evolution/evolution-reports/  per-release reports legitimately cite prior versions
#   - evolution/improvement-plan-sdk-dragonfly-s2.md  pre-straighten improvement doc citing historical drift
#   - evolution/knowledge-base/neo4j-seed.json  historical run observations
#   - evolution/knowledge-base/*.jsonl  append-only per-run history; each line stamps the version of its originating run
#   - scripts/guardrails/G06.sh  this file (quoted AUTH_VERSION in a message)
#   - multi-lang-plan.md  frozen v0.4.0 planning narrative; cites historical step "0.2.0 → 0.3.0"
#   - multi-lang-pipeline-strategy.md  same era; planning prose, not live config
#   - multi-lang-remaining.md  same era
EXCLUDES=(
  --exclude-dir=runs
  --exclude-dir=.git
  --exclude-dir=.serena
  --exclude-dir=.omc
  --exclude-dir=evolution-reports
  --exclude-dir=knowledge-base
  --exclude=improvement-plan-sdk-dragonfly-s2.md
  --exclude=G06.sh
  --exclude=migration-log.jsonl
  --exclude=multi-lang-plan.md
  --exclude=multi-lang-pipeline-strategy.md
  --exclude=multi-lang-remaining.md
)

# Pattern: pipeline_version="X.Y.Z" or pipeline_version: "X.Y.Z" or sdk-pipeline@X.Y.Z
#                          capture X.Y.Z from any of those forms
HITS="$(grep -rHn -E '(pipeline_version["'\'':= ]*|sdk-pipeline@)[0-9]+\.[0-9]+\.[0-9]+' "${EXCLUDES[@]}" "$PIPELINE_ROOT" 2>/dev/null || true)"

VIOLATIONS=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  # Extract X.Y.Z from the line
  found="$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  [ -z "$found" ] && continue
  # Allow placeholder/template strings
  if echo "$line" | grep -qE 'X\.Y\.Z|<version>|0\.0\.0|sdk-pipeline@"?$'; then
    continue
  fi
  if [ "$found" != "$AUTH_VERSION" ]; then
    VIOLATIONS+="$line"$'\n'
  fi
done <<< "$HITS"

if [ -n "$VIOLATIONS" ]; then
  echo "FAIL: pipeline_version divergence — settings.json declares $AUTH_VERSION but these files assert a different value:"
  echo ""
  printf '%s' "$VIOLATIONS"
  echo ""
  echo "Fix: update each line to '$AUTH_VERSION' OR move the file to runs/* (historical) OR add it to EXCLUDES in G06.sh if legitimately version-agnostic."
  exit 1
fi

echo "PASS: all live references to pipeline_version match $AUTH_VERSION"
exit 0
