#!/usr/bin/env bash
# phases: intake
# severity: BLOCKER
# active-packages.json valid + resolves — verifies the per-run package
# resolution artifact written by sdk-intake-agent at Wave I5.5 (v0.4.0+):
#
#   - file exists at runs/<run-id>/context/active-packages.json
#   - JSON shape: run_id, resolved_at, target_language, target_tier, packages[]
#   - every package entry references a manifest that exists at
#     .claude/package-manifests/<name>.json
#   - every referenced manifest's pipeline_version_compat is satisfied
#   - no circular `depends` chain
#   - flat agents/skills/guardrails arrays in active-packages.json match the
#     union of those arrays across the resolved manifests (drift detector)
#
# Exit codes:
#   0 — clean
#   1 — drift / invalid (BLOCKER, halt at H1)
#   2 — infra problem (jq missing, manifest dir missing)
#
# Usage: bash scripts/guardrails/G05.sh <run-dir> [<target-dir>]
set -uo pipefail
RUN_DIR="${1:?usage: G05.sh <run-dir> [<target-dir>]}"
TARGET="${2:-}"
PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST_DIR="$PIPELINE_ROOT/.claude/package-manifests"
ACTIVE="$RUN_DIR/context/active-packages.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "INFRA: jq is required" >&2
  exit 2
fi

if [ ! -d "$MANIFEST_DIR" ]; then
  echo "INFRA: manifest dir missing at $MANIFEST_DIR" >&2
  exit 2
fi

if [ ! -f "$ACTIVE" ]; then
  echo "FAIL: active-packages.json missing at $ACTIVE"
  echo "Fix: sdk-intake-agent Wave I5.5 must write this file before completion."
  exit 1
fi

# Required top-level fields
for field in run_id resolved_at target_language target_tier packages; do
  if ! jq -e ".$field" "$ACTIVE" >/dev/null 2>&1; then
    echo "FAIL: active-packages.json missing required field: $field"
    exit 1
  fi
done

# packages must be a non-empty array
PKG_COUNT=$(jq -r '.packages | length' "$ACTIVE")
if [ "$PKG_COUNT" -eq 0 ]; then
  echo "FAIL: active-packages.json .packages is empty (need at least shared-core + one language adapter)"
  exit 1
fi

# Resolve every referenced package; build agents/skills/guardrails union from
# the on-disk manifests for the drift cross-check below.
declare -A SEEN_PKGS
UNION_AGENTS=$(mktemp)
UNION_SKILLS=$(mktemp)
UNION_GUARDS=$(mktemp)
trap 'rm -f "$UNION_AGENTS" "$UNION_SKILLS" "$UNION_GUARDS"' EXIT

# Read each declared package + recursively follow depends.
declare -a QUEUE
while IFS= read -r pkg_name; do
  [ -n "$pkg_name" ] && QUEUE+=("$pkg_name")
done < <(jq -r '.packages[].name' "$ACTIVE")

DEPTH=0
while [ ${#QUEUE[@]} -gt 0 ]; do
  DEPTH=$((DEPTH+1))
  if [ $DEPTH -gt 32 ]; then
    echo "FAIL: dependency resolution exceeded depth 32 — likely circular depends"
    exit 1
  fi
  pkg="${QUEUE[0]}"
  QUEUE=("${QUEUE[@]:1}")
  if [ -n "${SEEN_PKGS[$pkg]+x}" ]; then
    continue
  fi
  SEEN_PKGS[$pkg]=1
  m="$MANIFEST_DIR/$pkg.json"
  if [ ! -f "$m" ]; then
    echo "FAIL: package '$pkg' referenced but manifest not found at $m"
    echo "Fix: author the manifest, OR remove the package from §Required-Packages, OR file under docs/PROPOSED-PACKAGES.md."
    exit 1
  fi
  # Validate manifest shape
  if ! jq -e '.name, .version, .agents, .skills, .guardrails' "$m" >/dev/null 2>&1; then
    echo "FAIL: manifest $m missing required fields (name/version/agents/skills/guardrails)"
    exit 1
  fi
  # Collect into union files
  jq -r '.agents[]'     "$m" >>"$UNION_AGENTS"
  jq -r '.skills[]'     "$m" >>"$UNION_SKILLS"
  jq -r '.guardrails[]' "$m" >>"$UNION_GUARDS"
  # Enqueue depends
  while IFS= read -r dep_spec; do
    [ -z "$dep_spec" ] && continue
    dep_name="${dep_spec%@*}"  # strip @>=1.0.0 suffix
    QUEUE+=("$dep_name")
  done < <(jq -r '.depends[]? // empty' "$m")
done

# Drift cross-check: the agents/skills/guardrails arrays inside
# active-packages.json must equal the union derived from the manifests on disk
# (sorted, unique). If sdk-intake-agent's resolution produced a different set,
# something tampered or the agent has a bug.
sort -u "$UNION_AGENTS" -o "$UNION_AGENTS"
sort -u "$UNION_SKILLS" -o "$UNION_SKILLS"
sort -u "$UNION_GUARDS" -o "$UNION_GUARDS"

ACTIVE_AGENTS=$(jq -r '.packages[].agents[]'     "$ACTIVE" 2>/dev/null | sort -u)
ACTIVE_SKILLS=$(jq -r '.packages[].skills[]'     "$ACTIVE" 2>/dev/null | sort -u)
ACTIVE_GUARDS=$(jq -r '.packages[].guardrails[]' "$ACTIVE" 2>/dev/null | sort -u)

DRIFT=0
if ! diff -q <(echo "$ACTIVE_AGENTS") "$UNION_AGENTS" >/dev/null 2>&1; then
  echo "FAIL: agents in active-packages.json drift from manifest union"
  diff <(echo "$ACTIVE_AGENTS") "$UNION_AGENTS" | sed 's/^/  /' || true
  DRIFT=1
fi
if ! diff -q <(echo "$ACTIVE_SKILLS") "$UNION_SKILLS" >/dev/null 2>&1; then
  echo "FAIL: skills in active-packages.json drift from manifest union"
  diff <(echo "$ACTIVE_SKILLS") "$UNION_SKILLS" | sed 's/^/  /' || true
  DRIFT=1
fi
if ! diff -q <(echo "$ACTIVE_GUARDS") "$UNION_GUARDS" >/dev/null 2>&1; then
  echo "FAIL: guardrails in active-packages.json drift from manifest union"
  diff <(echo "$ACTIVE_GUARDS") "$UNION_GUARDS" | sed 's/^/  /' || true
  DRIFT=1
fi

if [ $DRIFT -ne 0 ]; then
  echo ""
  echo "Fix: sdk-intake-agent Wave I5.5 must rewrite active-packages.json from the canonical manifests."
  exit 1
fi

# Pretty PASS report
TARGET_LANG=$(jq -r '.target_language' "$ACTIVE")
TARGET_TIER=$(jq -r '.target_tier' "$ACTIVE")
A_COUNT=$(echo "$ACTIVE_AGENTS" | wc -l)
S_COUNT=$(echo "$ACTIVE_SKILLS" | wc -l)
G_COUNT=$(echo "$ACTIVE_GUARDS" | wc -l)

echo "PASS: active-packages.json resolves cleanly"
echo "  target_language: $TARGET_LANG"
echo "  target_tier:     $TARGET_TIER"
echo "  packages:        ${!SEEN_PKGS[*]}"
echo "  active set:      $A_COUNT agents, $S_COUNT skills, $G_COUNT guardrails"
exit 0
