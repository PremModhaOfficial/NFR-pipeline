#!/usr/bin/env bash
# phases: intake meta
# severity: BLOCKER
# retired-term scanner: retired concepts in docs/DEPRECATED.md must not appear in live docs
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPRECATED="$PIPELINE_ROOT/docs/DEPRECATED.md"

if [ ! -f "$DEPRECATED" ]; then
  echo "WARN: docs/DEPRECATED.md not found; skipping retired-term scan"
  exit 0
fi

# Extract retired terms from the first column of the "Retired concepts" markdown table.
# The table has this shape:
#   | Retired term | Retired in | Replacement | Notes |
#   |---|---|---|---|
#   | `golden-corpus regression` | ... | ... | ... |
# We want the backtick-quoted strings or bare strings in column 1 only.
TERMS="$(python3 - "$DEPRECATED" <<'PY'
import re, pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
in_table = False
saw_header = False
terms = []
for line in text.splitlines():
    if line.startswith("| Retired term"):
        in_table = True
        saw_header = True
        continue
    if in_table and line.startswith("|---"):
        continue
    if in_table and not line.startswith("|"):
        # Table ended
        in_table = False
        continue
    if in_table and saw_header:
        # Row: | term | retired_in | replacement | notes |
        cols = [c.strip() for c in line.split("|")[1:-1]]
        if len(cols) < 4:
            continue
        term = cols[0].strip()
        # Strip surrounding backticks if present
        m = re.match(r'^`([^`]+)`$', term)
        if m:
            term = m.group(1)
        if term:
            terms.append(term)
print("\n".join(terms))
PY
)"

if [ -z "$TERMS" ]; then
  echo "WARN: no retired terms parsed from docs/DEPRECATED.md"
  exit 0
fi

# Directories excluded via --exclude-dir (grep honors these).
# Per-file exclusions are applied via a post-filter because GNU grep's --exclude
# interacts oddly with --include in some versions (include wins).
DIR_EXCLUDES=(
  --exclude-dir=runs
  --exclude-dir=.git
  --exclude-dir=.serena
  --exclude-dir=.omc
  --exclude-dir=evolution-reports
  --exclude-dir=knowledge-base
)
# Files whose matches are legitimate historical or self-referential:
FILE_EXCLUDE_PATTERN='docs/DEPRECATED\.md|improvements\.md|improvement-plan-sdk-dragonfly-s2\.md|scripts/guardrails/G116\.sh|evolution-reports/pipeline-v0\.3\.0\.md'

# Lines that explicitly mark themselves as historical-context (retirement rationale,
# "removed", "previously", "retired") are allowed to cite the retired term — that's
# how you explain what the replacement replaces. Drift = active-voice reference.
CONTEXT_ALLOW='retired|[Rr]emoved|[Pp]reviously|deprecated in|no longer|been replaced|superseded|was the'

VIOLATIONS=""
while IFS= read -r term; do
  [ -z "$term" ] && continue
  # Use fixed-string grep to avoid regex-interpreting terms like "Phase -1"
  hits="$(grep -rFHn "$term" "${DIR_EXCLUDES[@]}" --include="*.md" --include="*.json" --include="*.html" --include="*.sh" "$PIPELINE_ROOT" 2>/dev/null \
    | grep -Ev "$FILE_EXCLUDE_PATTERN" \
    | grep -Ev "$CONTEXT_ALLOW" || true)"
  if [ -n "$hits" ]; then
    VIOLATIONS+="=== retired: $term ==="$'\n'"$hits"$'\n\n'
  fi
done <<< "$TERMS"

if [ -n "$VIOLATIONS" ]; then
  echo "FAIL: retired terms still appear in live docs — each must be removed, rephrased, or the excluding file added to G116.sh EXCLUDES."
  echo ""
  printf '%s' "$VIOLATIONS"
  exit 1
fi

echo "PASS: no retired DEPRECATED.md terms appear in live docs"
exit 0
