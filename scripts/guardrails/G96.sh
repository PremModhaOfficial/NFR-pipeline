#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# MANUAL byte-hash match — SHA-256 of each [owned-by: MANUAL] symbol region
# matches the hash recorded in ownership-map.json. Belt-and-suspenders to G95.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
OWNERSHIP="$RUN_DIR/impl/ownership-map.json"
[ -f "$OWNERSHIP" ] || exit 0  # Mode A — no MANUAL entries
[ -n "$TARGET" ] || exit 1

python3 - "$OWNERSHIP" "$TARGET" <<'PY'
import json, hashlib, pathlib, sys
own = json.load(open(sys.argv[1]))
target = pathlib.Path(sys.argv[2])
fail = 0
for e in own.get("manual_symbols", []):
    p = target / e["file"]
    if not p.is_file():
        print(f"MISSING: {e['file']}"); fail += 1; continue
    data = p.read_bytes()
    start, end = e.get("byte_start", 0), e.get("byte_end", len(data))
    h = hashlib.sha256(data[start:end]).hexdigest()
    if h != e.get("sha256", ""):
        print(f"HASH MISMATCH: {e['file']} {e.get('symbol','?')}")
        fail += 1
sys.exit(1 if fail else 0)
PY
