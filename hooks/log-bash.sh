#!/usr/bin/env bash
# PostToolUse hook for Bash. Appends one JSONL line per Bash invocation to
# .claude/audit/bash-events.jsonl. Phase leads slice this file per-run via
# the start/end timestamps recorded in runs/<id>/state/run-manifest.json.
#
# Stdin: Claude Code hook payload (JSON; see https://docs.claude.com/en/docs/claude-code/hooks).
# Stdout: empty on success (any output is treated as advisory by the harness).
# Exit code: always 0 — failures must NEVER block the run.

set -euo pipefail

AUDIT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/audit"
AUDIT_FILE="${AUDIT_DIR}/bash-events.jsonl"
mkdir -p "${AUDIT_DIR}"

# Read raw payload; fall back to "{}" if stdin closed.
PAYLOAD="$(cat - 2>/dev/null || echo '{}')"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Best-effort field extraction. If jq unavailable or payload malformed, write the raw line.
if command -v jq >/dev/null 2>&1; then
  printf '%s' "${PAYLOAD}" | jq -c \
    --arg ts "${TS}" \
    '{
       ts: $ts,
       session_id: (.session_id // null),
       hook_event_name: (.hook_event_name // null),
       tool_name: (.tool_name // null),
       command: (.tool_input.command // null),
       description: (.tool_input.description // null),
       exit_code: (.tool_response.exitCode // .tool_response.exit_code // null),
       stdout_bytes: ((.tool_response.stdout // "") | length),
       stderr_bytes: ((.tool_response.stderr // "") | length),
       interrupted: (.tool_response.interrupted // false)
     }' >> "${AUDIT_FILE}" 2>/dev/null || \
  printf '{"ts":"%s","raw":%s}\n' "${TS}" "$(printf '%s' "${PAYLOAD}" | jq -Rs . 2>/dev/null || echo '"<unparsable>"')" >> "${AUDIT_FILE}"
else
  printf '{"ts":"%s","raw":"jq-missing"}\n' "${TS}" >> "${AUDIT_FILE}"
fi

exit 0
