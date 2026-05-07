#!/usr/bin/env bash
# validate-packages.sh — check .claude/package-manifests/ against filesystem reality.
#
# v0.4.0 scaffolding pass. No runtime consumer of the manifests exists yet; this
# script exists to keep the manifests honest as artifacts are added/removed.
#
# Enforces:
#   - every .claude/agents/*.md file is referenced in exactly one manifest
#   - every .claude/skills/*/ directory is referenced in exactly one manifest
#   - every scripts/guardrails/G*.sh file is referenced in exactly one manifest
#   - no manifest entry refers to a non-existent artifact
#   - no artifact appears in two manifests
#
# Exit codes:
#   0 — clean
#   1 — drift detected (orphan, duplicate, or dangling reference)
#   2 — infra problem (missing jq, missing manifest dir, etc.)
#
# Usage: bash scripts/validate-packages.sh

set -o pipefail
# v0.6.0 fix: dropped `-u` because the success-path counters dereference associative
# arrays that may be empty when manifests are stubs (Batch 0 state). The existing
# code already uses the `${VAR[$key]+x}` idiom for key-existence checks, so strict
# undefined-variable mode added no safety — only false failures on empty stubs.
PIPELINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST_DIR="$PIPELINE_ROOT/.claude/package-manifests"

if ! command -v jq >/dev/null 2>&1; then
  echo "INFRA: jq is required (install via package manager)" >&2
  exit 2
fi

if [ ! -d "$MANIFEST_DIR" ]; then
  echo "INFRA: manifest dir missing at $MANIFEST_DIR" >&2
  exit 2
fi

shopt -s nullglob
MANIFESTS=("$MANIFEST_DIR"/*.json)
if [ ${#MANIFESTS[@]} -eq 0 ]; then
  echo "INFRA: no *.json manifests found in $MANIFEST_DIR" >&2
  exit 2
fi

# Build flat "manifest:artifact" lists with associative tracking for dupe detection.
declare -A AGENT_OWNER SKILL_OWNER GUARDRAIL_OWNER
DUPES=""
DANGLING=""

declare -A ASPIRATIONAL_OWNER
SHAPE_FAIL=""

for m in "${MANIFESTS[@]}"; do
  pkg=$(basename "$m" .json)

  # Validate JSON shape first.
  if ! jq -e '.name, .version, .agents, .skills, .guardrails' "$m" >/dev/null 2>&1; then
    echo "FAIL: $m missing required fields (name/version/agents/skills/guardrails)"
    exit 1
  fi

  # NEW: validate waves shape (object whose values are arrays of strings).
  if jq -e '.waves' "$m" >/dev/null 2>&1; then
    if ! jq -e '.waves | type == "object" and (to_entries | all(.value | type == "array" and all(. | type == "string")))' "$m" >/dev/null 2>&1; then
      SHAPE_FAIL+="  manifest=$pkg .waves shape invalid (must be object with string-array values)"$'\n'
    fi
  fi

  # NEW: validate tier_critical shape (3 phase keys, each with T1/T2 string-arrays).
  if jq -e '.tier_critical' "$m" >/dev/null 2>&1; then
    if ! jq -e '.tier_critical | type == "object" and (to_entries | all(.value | type == "object" and (to_entries | all(.value | type == "array" and all(. | type == "string")))))' "$m" >/dev/null 2>&1; then
      SHAPE_FAIL+="  manifest=$pkg .tier_critical shape invalid (must be {phase: {tier: [strings]}})"$'\n'
    fi
  fi

  # NEW: language-adapter packs MUST carry toolchain.{build,test} + file_extensions + marker_comment_syntax.
  PKG_TYPE=$(jq -r '.type // empty' "$m")
  if [ "$PKG_TYPE" = "language-adapter" ]; then
    for required in '.toolchain.build' '.toolchain.test' '.file_extensions' '.marker_comment_syntax.line'; do
      if ! jq -e "$required" "$m" >/dev/null 2>&1; then
        SHAPE_FAIL+="  manifest=$pkg language-adapter missing required field: $required"$'\n'
      fi
    done
  fi

  while IFS= read -r a; do
    [ -z "$a" ] && continue
    if [ ! -f "$PIPELINE_ROOT/.claude/agents/$a.md" ]; then
      DANGLING+="  manifest=$pkg agent=$a (not on filesystem)"$'\n'
    fi
    if [ -n "${AGENT_OWNER[$a]+x}" ]; then
      DUPES+="  agent=$a in both $pkg and ${AGENT_OWNER[$a]}"$'\n'
    else
      AGENT_OWNER[$a]=$pkg
    fi
  done < <(jq -r '.agents[]' "$m")

  while IFS= read -r s; do
    [ -z "$s" ] && continue
    if [ ! -d "$PIPELINE_ROOT/.claude/skills/$s" ]; then
      DANGLING+="  manifest=$pkg skill=$s (not on filesystem)"$'\n'
    fi
    if [ -n "${SKILL_OWNER[$s]+x}" ]; then
      DUPES+="  skill=$s in both $pkg and ${SKILL_OWNER[$s]}"$'\n'
    else
      SKILL_OWNER[$s]=$pkg
    fi
  done < <(jq -r '.skills[]' "$m")

  while IFS= read -r g; do
    [ -z "$g" ] && continue
    if [ ! -f "$PIPELINE_ROOT/scripts/guardrails/$g.sh" ]; then
      DANGLING+="  manifest=$pkg guardrail=$g (not on filesystem)"$'\n'
    fi
    if [ -n "${GUARDRAIL_OWNER[$g]+x}" ]; then
      DUPES+="  guardrail=$g in both $pkg and ${GUARDRAIL_OWNER[$g]}"$'\n'
    else
      GUARDRAIL_OWNER[$g]=$pkg
    fi
  done < <(jq -r '.guardrails[]' "$m")

  # NEW: aspirational_guardrails — forward-declared; tracked but not required on disk.
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    if [ -n "${ASPIRATIONAL_OWNER[$g]+x}" ]; then
      DUPES+="  aspirational guardrail=$g in both $pkg and ${ASPIRATIONAL_OWNER[$g]}"$'\n'
    else
      ASPIRATIONAL_OWNER[$g]=$pkg
    fi
    # If the script DOES exist on disk, it should be in `guardrails`, not `aspirational_guardrails`.
    if [ -f "$PIPELINE_ROOT/scripts/guardrails/$g.sh" ]; then
      SHAPE_FAIL+="  manifest=$pkg aspirational_guardrail=$g has script on disk — promote to .guardrails"$'\n'
    fi
    # An aspirational guardrail must NOT also appear in the regular guardrails array.
    if [ -n "${GUARDRAIL_OWNER[$g]+x}" ]; then
      DUPES+="  guardrail=$g declared as both regular and aspirational in $pkg"$'\n'
    fi
  done < <(jq -r '.aspirational_guardrails // {} | keys[]?' "$m")
done

# Orphan check: is every filesystem artifact referenced by some manifest?
ORPHANS=""
for f in "$PIPELINE_ROOT"/.claude/agents/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  if [ -z "${AGENT_OWNER[$name]+x}" ]; then
    ORPHANS+="  agent=$name (on fs, in no manifest)"$'\n'
  fi
done

for d in "$PIPELINE_ROOT"/.claude/skills/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  if [ -z "${SKILL_OWNER[$name]+x}" ]; then
    ORPHANS+="  skill=$name (on fs, in no manifest)"$'\n'
  fi
done

for f in "$PIPELINE_ROOT"/scripts/guardrails/G*.sh; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .sh)
  if [ -z "${GUARDRAIL_OWNER[$name]+x}" ] && [ -z "${ASPIRATIONAL_OWNER[$name]+x}" ]; then
    ORPHANS+="  guardrail=$name (on fs, in no manifest)"$'\n'
  fi
done

# Results
FAIL=0

if [ -n "$DUPES" ]; then
  echo "FAIL: duplicate ownership (an artifact in 2+ manifests):"
  printf '%s' "$DUPES"
  FAIL=1
fi

if [ -n "$DANGLING" ]; then
  echo "FAIL: dangling references (manifest points at missing file):"
  printf '%s' "$DANGLING"
  FAIL=1
fi

if [ -n "$ORPHANS" ]; then
  echo "FAIL: orphans (on filesystem but in no manifest):"
  printf '%s' "$ORPHANS"
  FAIL=1
fi

if [ -n "$SHAPE_FAIL" ]; then
  echo "FAIL: manifest shape errors:"
  printf '%s' "$SHAPE_FAIL"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "Fix: update .claude/package-manifests/*.json so every on-disk artifact is in exactly one manifest."
  exit 1
fi

# Pretty report on success
AGENT_COUNT=${#AGENT_OWNER[@]}
SKILL_COUNT=${#SKILL_OWNER[@]}
GR_COUNT=${#GUARDRAIL_OWNER[@]}
# v0.6.0 fix: replaced `ls glob | wc -l` with `find` — when nullglob is set
# and the glob matches nothing, ls runs with no args and lists CWD, falsely
# inflating the count. find returns 0 lines on empty correctly.
FS_AGENTS=$(find "$PIPELINE_ROOT/.claude/agents" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l)
FS_SKILLS=$(find "$PIPELINE_ROOT/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
FS_GUARDRAILS=$(find "$PIPELINE_ROOT/scripts/guardrails" -maxdepth 1 -type f -name 'G*.sh' 2>/dev/null | wc -l)

ASP_COUNT=${#ASPIRATIONAL_OWNER[@]}

echo "PASS: manifests consistent with filesystem"
echo "  agents:     $AGENT_COUNT manifested / $FS_AGENTS on fs"
echo "  skills:     $SKILL_COUNT manifested / $FS_SKILLS on fs"
echo "  guardrails: $GR_COUNT manifested / $FS_GUARDRAILS on fs ($ASP_COUNT aspirational/forward-declared)"
echo ""
echo "Package breakdown:"
for m in "${MANIFESTS[@]}"; do
  pkg=$(basename "$m" .json)
  a=$(jq -r '.agents | length' "$m")
  s=$(jq -r '.skills | length' "$m")
  g=$(jq -r '.guardrails | length' "$m")
  asp=$(jq -r '.aspirational_guardrails // {} | length' "$m")
  printf "  %-16s  %2d agents   %2d skills   %2d guardrails  (+%d aspirational)\n" "$pkg" "$a" "$s" "$g" "$asp"
done
exit 0
