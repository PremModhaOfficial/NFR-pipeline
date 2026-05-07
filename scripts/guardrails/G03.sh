#!/usr/bin/env bash
# phases: feedback
# severity: BLOCKER
# lifecycle started+completed matched per agent
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
LOG="$RUN_DIR/decision-log.jsonl"
[ -f "$LOG" ] || exit 0
python3 - "$LOG" <<'PY'
import json,sys,collections
evs=collections.defaultdict(set)
for ln in open(sys.argv[1]):
    ln=ln.strip();
    if not ln: continue
    try: d=json.loads(ln)
    except: continue
    if d.get("type")=="lifecycle":
        e=d.get("event") or d.get("lifecycle_event")
        a=d.get("agent")
        if a and e: evs[a].add(e)
bad=[a for a,s in evs.items() if "started" in s and not ({"completed","failed","skipped"} & s)]
if bad: print("unclosed lifecycle: "+",".join(bad)); sys.exit(1)
PY
