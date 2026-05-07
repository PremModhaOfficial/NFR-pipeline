#!/usr/bin/env bash
# phases: intake design impl testing feedback meta
# severity: BLOCKER
# decision-log.jsonl valid JSONL
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
LOG="$RUN_DIR/decision-log.jsonl"
[ -f "$LOG" ] || { echo "missing $LOG"; exit 1; }
while IFS= read -r line; do [ -z "$line" ] && continue; echo "$line" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null || { echo "invalid JSON: $line"; exit 1; }; done < "$LOG"
