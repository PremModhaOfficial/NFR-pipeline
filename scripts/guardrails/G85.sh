#!/usr/bin/env bash
# phases: feedback
# severity: BLOCKER
# learning-notifications.md written when any patch applied
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
EVO_LOG="$RUN_DIR/../../evolution/knowledge-base/prompt-evolution-log.jsonl"
[ -f "$EVO_LOG" ] || exit 0
# Any entries for this run?
RUN_ID=$(basename "$RUN_DIR")
grep -q "\"run_id\":\s*\"$RUN_ID\"" "$EVO_LOG" 2>/dev/null || exit 0
# Patches were applied → notifications file must exist + be non-empty
NOTIF="$RUN_DIR/feedback/learning-notifications.md"
[ -s "$NOTIF" ] || { echo "patches applied but learning-notifications.md missing or empty"; exit 1; }
