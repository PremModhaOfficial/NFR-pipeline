#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# [do-not-regenerate] hard lock — any file whose first 1024 bytes contain the
# marker must be byte-identical to its baseline SHA-256 hash.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || { echo "no target dir"; exit 0; }

BASELINE_DIR="$(dirname "$0")/../../baselines"
BASELINE="$BASELINE_DIR/do-not-regenerate-hashes.json"
OWNERSHIP="$RUN_DIR/impl/ownership-map.json"

python3 - "$TARGET" "$RUN_DIR" "$BASELINE" "$OWNERSHIP" <<'PY'
import hashlib, json, pathlib, sys
target, run_dir, baseline_path, ownership_path = sys.argv[1:5]
target_p = pathlib.Path(target)
baseline_p = pathlib.Path(baseline_path)

# Files to consider: any .go under target whose first 1024 bytes contain marker.
locked = {}
for p in target_p.rglob("*.go"):
    try:
        head = p.read_bytes()[:1024]
    except Exception:
        continue
    if b"[do-not-regenerate]" in head:
        rel = str(p.relative_to(target_p))
        locked[rel] = hashlib.sha256(p.read_bytes()).hexdigest()

# Also consider ownership-map entries if available
if pathlib.Path(ownership_path).is_file():
    try:
        own = json.load(open(ownership_path))
        for f in own.get("do_not_regenerate", []):
            p = target_p / f
            if p.is_file():
                locked[f] = hashlib.sha256(p.read_bytes()).hexdigest()
    except Exception:
        pass

if not baseline_p.is_file():
    baseline_p.parent.mkdir(parents=True, exist_ok=True)
    baseline_p.write_text(json.dumps(locked, indent=2, sort_keys=True) + "\n")
    print(f"baseline created ({len(locked)} locked files) — first run, skipped")
    sys.exit(0)

baseline = json.loads(baseline_p.read_text())
mismatches = []
for f, h in locked.items():
    if f in baseline and baseline[f] != h:
        mismatches.append(f)
    elif f not in baseline:
        # new locked file — record, don't fail
        baseline[f] = h

if mismatches:
    print(f"FAIL: {len(mismatches)} [do-not-regenerate] file(s) modified")
    for f in mismatches:
        print(f"  {f}")
    sys.exit(1)
# persist any new locked files
baseline_p.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n")
sys.exit(0)
PY
