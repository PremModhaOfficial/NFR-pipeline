#!/usr/bin/env bash
# phases: feedback
# severity: HIGH
# every agent has >=1 communication entry
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
LOG="$RUN_DIR/decision-log.jsonl"
[ -f "$LOG" ] || exit 0
python3 - "$LOG" <<'PY'
import json,sys,collections
agents=set(); comms=collections.Counter()
for ln in open(sys.argv[1]):
    ln=ln.strip()
    if not ln: continue
    try: d=json.loads(ln)
    except: continue
    a=d.get("agent");
    if a: agents.add(a)
    if d.get("type")=="communication" and a: comms[a]+=1
missing=[a for a in agents if comms[a]==0]
if missing: print("no communication from: "+",".join(missing)); sys.exit(1)
PY
