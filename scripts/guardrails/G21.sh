#!/usr/bin/env bash
# phases: intake
# severity: BLOCKER
# §Non-Goals populated — at least 3 bullet points under a Non-Goals section
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
TPRD="$RUN_DIR/tprd.md"
[ -f "$TPRD" ] || { echo "missing $TPRD"; exit 1; }

# Find any header matching "Non-Goals" (case-insensitive), count following bullets until next header
python3 - "$TPRD" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
m = re.search(r'^#+\s*(?:§?\d+[.]?\s*)?(?:Non[- ]Goals?)\b.*?$(.*?)(?=^#+\s|\Z)',
              text, re.IGNORECASE | re.MULTILINE | re.DOTALL)
if not m:
    print("§Non-Goals section not found")
    sys.exit(1)
body = m.group(1)
bullets = re.findall(r'^\s*[-*]\s+\S', body, re.MULTILINE)
if len(bullets) < 3:
    print(f"§Non-Goals has only {len(bullets)} bullets; need ≥3")
    sys.exit(1)
PY
