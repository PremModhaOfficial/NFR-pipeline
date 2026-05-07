#!/usr/bin/env bash
# phases: intake meta
# severity: BLOCKER
# skill-index.json ↔ filesystem STRICT EQUALITY (was subset; tightened in v0.3.0 straighten — runtime synthesis is removed so FS extras always = drift)
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
ROOT="$(dirname "$0")/../../.claude/skills"
python3 - <<PY
import json, pathlib, sys
root = pathlib.Path("$ROOT")
idx_path = root / "skill-index.json"
if not idx_path.is_file():
    print("FAIL: skill-index.json missing at", idx_path)
    sys.exit(1)

idx = json.loads(idx_path.read_text())
declared = set()
for section in ("ported_verbatim","ported_with_delta","sdk_native"):
    for e in idx.get("skills",{}).get(section,[]):
        declared.add(e["name"])

fs = {p.name for p in root.iterdir() if p.is_dir()}

missing_on_fs = declared - fs
missing_in_idx = fs - declared

if missing_on_fs or missing_in_idx:
    print("FAIL: skill-index.json and filesystem diverge")
    if missing_on_fs:
        print("  Declared in index but missing on fs:")
        for n in sorted(missing_on_fs):
            print(f"    - {n}")
    if missing_in_idx:
        print("  Present on fs but not indexed:")
        for n in sorted(missing_in_idx):
            print(f"    - {n}")
    print("")
    print("Fix: either author the missing SKILL.md OR add an entry to skill-index.json.")
    print("     (Runtime skill synthesis is removed; every on-disk skill must be indexed.)")
    sys.exit(1)

print(f"PASS: skill-index.json matches filesystem ({len(declared)} skills)")
PY
