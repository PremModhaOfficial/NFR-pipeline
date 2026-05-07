#!/usr/bin/env bash
# phases: impl testing
# severity: BLOCKER
# G110-py — [perf-exception:] marker pairing (CLAUDE.md rule 29).
# Every [perf-exception: <reason> bench/BenchmarkX] marker in src/ MUST be paired
# with an entry in runs/<id>/design/perf-exceptions.md AND a profile-auditor
# bench-justification line. Orphan markers = BLOCKER. Vacuously PASS if 0 markers.
# Owner: sdk-marker-hygiene-devil (Waves M7 + M9).
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || { echo "G110-py INCOMPLETE: no target dir"; exit 1; }
SRC="$TARGET/src"
[ -d "$SRC" ] || { echo "G110-py INCOMPLETE: no src/ at $TARGET"; exit 1; }

# Find every [perf-exception:] marker in src/. Format: # [perf-exception: reason bench/<NAME>]
MARKERS=$(grep -rEoh "\[perf-exception:[^]]+\]" "$SRC" 2>/dev/null | sort -u)

if [ -z "$MARKERS" ]; then
  echo "G110-py PASS: 0 [perf-exception:] markers in src/ (vacuously satisfied)"
  exit 0
fi

PE_DOC="$RUN_DIR/design/perf-exceptions.md"
if [ ! -f "$PE_DOC" ]; then
  echo "G110-py FAIL: $(echo "$MARKERS" | wc -l) [perf-exception:] marker(s) in src but no design/perf-exceptions.md"
  echo "$MARKERS" | head -10
  exit 1
fi

UNPAIRED=0
while IFS= read -r marker; do
  # Extract the bench name from the marker (last token after bench/).
  bench_name=$(echo "$marker" | grep -oE "bench/[A-Za-z0-9_]+" | head -1 | sed 's|bench/||')
  if [ -z "$bench_name" ]; then
    echo "G110-py FAIL: marker missing bench/<NAME> token: $marker"
    UNPAIRED=$((UNPAIRED + 1))
    continue
  fi
  if ! grep -F "$bench_name" "$PE_DOC" >/dev/null 2>&1; then
    echo "G110-py FAIL: marker $marker has no entry in design/perf-exceptions.md"
    UNPAIRED=$((UNPAIRED + 1))
  fi
done <<< "$MARKERS"

if [ "$UNPAIRED" -gt 0 ]; then
  echo "G110-py FAIL: $UNPAIRED orphan [perf-exception:] marker(s)"
  exit 1
fi

N=$(echo "$MARKERS" | wc -l)
echo "G110-py PASS: $N [perf-exception:] marker(s) all paired in design/perf-exceptions.md"
exit 0
