#!/usr/bin/env bash
# phases: intake
# severity: BLOCKER
# TPRD completeness — every required topic area is covered. Header naming is
# flexible (TPRDs may use "Purpose" instead of "Request Type", "Goals" instead
# of "Scope", etc).
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/tprd.md"
[ -f "$F" ] || { echo "tprd.md missing at $F"; exit 1; }

# Each entry: a pipe-separated list of acceptable header keywords for the topic.
REQUIRED=(
  "Request Type|Purpose|Overview"
  "Scope|Goals"
  "Motivation|Rationale|Purpose"
  "Functional Requirement|API Surface|API"
  "Non-Functional|Perf Target|NFR"
  "Dependencies|Compat Matrix"
  "Config"
  "Observability|OTel|Tracing|Metrics"
  "Resilience|Error Model|Reliability"
  "Security"
  "Testing|Test Strategy"
  "Breaking-Change|Semver"
  "Rollout|Milestone|Deployment"
  "Clarification|Open Question|Risk"
)

FAIL=0
for topic in "${REQUIRED[@]}"; do
  if ! grep -qiE "^#+[[:space:]]*[§0-9.[:space:]]*($topic)" "$F"; then
    echo "MISSING topic: $topic"
    FAIL=$((FAIL+1))
  fi
done

# Manifests
if ! grep -qiE "^#+[[:space:]]*[§0-9.[:space:]]*Skills-?Manifest" "$F"; then
  echo "NOTE: §Skills-Manifest absent (G23 will WARN, non-blocking)"
fi
if ! grep -qiE "^#+[[:space:]]*[§0-9.[:space:]]*Guardrails-?Manifest" "$F"; then
  echo "MISSING section: §Guardrails-Manifest"
  FAIL=$((FAIL+1))
fi

# ---------------------------------------------------------------------------
# §OTel — observability contract completeness check
# ---------------------------------------------------------------------------

OTEL_AMBIGUOUS_RE='\b(TBD|tbd|maybe|idk|varies|see\s+standards)\b|^\s*$'

# Required fields with their allowed values (enum) — bash assoc array
declare -A OTEL_FIELDS_ENUM=(
    [signals.traces]='on|off'
    [signals.metrics]='on|off'
    [signals.logs]='on|off'
    [consumer_provider_optin]='yes|no'
    [log_correlation]='required|consumer-side|off'
    [nats_surface]='yes|no'
    [tenant_attribution]='consumer-baggage|consumer-resource-attr|none'
)

# Required fields that are lists (must be present, may be empty)
OTEL_LIST_FIELDS=(
    forbidden_attributes
    declared_metric_ids
    declared_span_names
)

# Required fields that are free-form strings (must be present, non-ambiguous)
OTEL_STRING_FIELDS=(
    facade_used_go
    facade_used_python
)

# Find §OTel section in TPRD
TPRD_FILE="$RUN_DIR/intake/tprd-canonical.md"
[ -f "$TPRD_FILE" ] || { echo "G20 FAIL: TPRD canonical missing"; exit 1; }

if ! grep -qE '^##\s+§?OTel|^##\s+Observability\s+Contract' "$TPRD_FILE"; then
    echo "G20 FAIL: §OTel section missing from TPRD"
    FAIL=1
else
    # Extract §OTel block (from header to next ## header)
    OTEL_BLOCK=$(awk '/^##\s+§?OTel|^##\s+Observability\s+Contract/{flag=1; next} /^##\s+/{if(flag){exit}} flag' "$TPRD_FILE")

    # Check enum fields
    for field in "${!OTEL_FIELDS_ENUM[@]}"; do
        allowed="${OTEL_FIELDS_ENUM[$field]}"
        line=$(echo "$OTEL_BLOCK" | grep -E "^\s*-?\s*\`?${field}\`?\s*:" | head -1)
        if [ -z "$line" ]; then
            echo "G20 FAIL: §OTel field missing: $field"
            FAIL=1
            continue
        fi
        value=$(echo "$line" | sed -E "s/.*${field}\`?\s*:\s*//" | sed -E 's/^[`"]//; s/[`"]\s*$//' | tr -d ' ')
        # ambiguity check
        if echo "$value" | grep -qiE "$OTEL_AMBIGUOUS_RE"; then
            echo "G20 FAIL: §OTel field '$field' has ambiguous value: '$value' (allowed: $allowed)"
            FAIL=1
        elif ! echo "$value" | grep -qE "^($allowed)$"; then
            echo "G20 FAIL: §OTel field '$field' has invalid value: '$value' (allowed: $allowed)"
            FAIL=1
        fi
    done

    # Check list fields (presence + non-ambiguous)
    for field in "${OTEL_LIST_FIELDS[@]}"; do
        if ! echo "$OTEL_BLOCK" | grep -qE "^\s*-?\s*\`?${field}\`?\s*:"; then
            echo "G20 FAIL: §OTel list field missing: $field"
            FAIL=1
        else
            # if value is on same line and ambiguous, fail
            line_value=$(echo "$OTEL_BLOCK" | grep -E "^\s*-?\s*\`?${field}\`?\s*:" | head -1 | sed -E "s/.*${field}\`?\s*:\s*//")
            if [ -n "$line_value" ] && echo "$line_value" | grep -qiE "$OTEL_AMBIGUOUS_RE"; then
                echo "G20 FAIL: §OTel list field '$field' ambiguous: '$line_value'"
                FAIL=1
            fi
        fi
    done

    # Check string fields
    for field in "${OTEL_STRING_FIELDS[@]}"; do
        line=$(echo "$OTEL_BLOCK" | grep -E "^\s*-?\s*\`?${field}\`?\s*:" | head -1)
        if [ -z "$line" ]; then
            echo "G20 FAIL: §OTel string field missing: $field"
            FAIL=1
            continue
        fi
        value=$(echo "$line" | sed -E "s/.*${field}\`?\s*:\s*//" | tr -d ' ')
        if echo "$value" | grep -qiE "$OTEL_AMBIGUOUS_RE"; then
            echo "G20 FAIL: §OTel string field '$field' ambiguous: '$value'"
            FAIL=1
        fi
    done

    # Cross-field validation: if signals.traces=on, declared_span_names must be non-empty
    traces_on=$(echo "$OTEL_BLOCK" | grep -E "signals\.traces\s*:" | grep -oE "(on|off)" | head -1)
    if [ "$traces_on" = "on" ]; then
        # count list items under declared_span_names
        span_count=$(echo "$OTEL_BLOCK" | awk '/declared_span_names/{flag=1; next} /^\s*-?\s*[a-z_.]+\s*:/{flag=0} flag && /^\s*-\s+[a-z]/' | wc -l)
        if [ "$span_count" -lt 1 ]; then
            echo "G20 FAIL: signals.traces=on but declared_span_names empty"
            FAIL=1
        fi
    fi

    [ "$FAIL" -eq 0 ] && echo "G20 PASS: §OTel section complete + non-ambiguous"
fi

[ $FAIL -eq 0 ] || exit 1
exit 0
