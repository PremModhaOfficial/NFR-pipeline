#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# Required markers present on pipeline-authored .go files — every file touched
# by this run must contain at least one [traces-to: TPRD-<section>-<id>] marker.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || { echo "no target dir"; exit 0; }

MANIFEST="$RUN_DIR/impl/manifest.json"
OWNERSHIP="$RUN_DIR/impl/ownership-map.json"

python3 - "$TARGET" "$RUN_DIR" "$MANIFEST" "$OWNERSHIP" <<'PY'
import json, pathlib, re, sys
target, run_dir, manifest_path, ownership_path = sys.argv[1:5]
target_p = pathlib.Path(target)

authored = None
if pathlib.Path(manifest_path).is_file():
    try:
        m = json.load(open(manifest_path))
        if isinstance(m.get("pipeline_authored_files"), list):
            authored = set(m["pipeline_authored_files"])
    except Exception:
        authored = None

manual_files = set()
if pathlib.Path(ownership_path).is_file():
    try:
        own = json.load(open(ownership_path))
        for e in own.get("manual_symbols", []):
            manual_files.add(e.get("file", ""))
        for f in own.get("manual_files", []):
            manual_files.add(f)
    except Exception:
        pass

candidates = []
if authored is not None:
    for f in authored:
        p = target_p / f
        if p.suffix == ".go" and not p.name.endswith("_test.go") and p.is_file():
            candidates.append(p)
else:
    for p in target_p.rglob("*.go"):
        if p.name.endswith("_test.go"):
            continue
        rel = str(p.relative_to(target_p))
        if rel in manual_files:
            continue
        candidates.append(p)

marker_re = re.compile(r'\[traces-to:\s*TPRD-[^\]]+\]')
missing = []
for p in candidates:
    text = p.read_text(errors="ignore")
    if not marker_re.search(text):
        missing.append(str(p.relative_to(target_p)))

out = pathlib.Path(run_dir) / "impl" / "required-markers-check.md"
out.parent.mkdir(parents=True, exist_ok=True)
if missing:
    out.write_text("# Required markers: FAIL\n\n" +
                   "\n".join(f"- {m}" for m in missing) + "\n")
    print(f"FAIL: {len(missing)} file(s) missing [traces-to:] marker")
    for m in missing:
        print(f"  {m}")
    sys.exit(1)
out.write_text(f"# Required markers: PASS ({len(candidates)} files scanned)\n")
sys.exit(0)
PY
