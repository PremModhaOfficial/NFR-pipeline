#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# Pipeline-authored exported symbols MUST carry a [traces-to:] marker in their
# godoc. AST-based as of pipeline 0.3.0 (was regex-based) — uses the symbols
# enumerator for language-neutral parsing.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || { echo "no target dir"; exit 0; }

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SYMBOLS="$REPO_ROOT/scripts/ast-hash/symbols.sh"
PACK="${PACK:-go}"   # P3 will wire this from the active pack-manifest

MANIFEST="$RUN_DIR/impl/manifest.json"
OWNERSHIP="$RUN_DIR/impl/ownership-map.json"

python3 - "$TARGET" "$RUN_DIR" "$MANIFEST" "$OWNERSHIP" "$SYMBOLS" "$PACK" <<'PY'
import json, pathlib, subprocess, sys
target, run_dir, manifest_path, ownership_path, symbols_dispatcher, pack = sys.argv[1:7]
target_p = pathlib.Path(target)

# Determine which files to scan.
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
        for f in own.get("manual_files", []):
            manual_files.add(f)
    except Exception:
        pass

# Run the symbols enumerator over the whole target tree.
r = subprocess.run([symbols_dispatcher, pack, "-dir", target], capture_output=True, text=True, timeout=60)
if r.returncode != 0:
    print(f"FAIL: symbols enumerator exit {r.returncode}: {r.stderr.strip()}")
    sys.exit(2)
data = json.loads(r.stdout) if r.stdout else {}

# data: { "rel/path.go": { "file": ..., "package": ..., "symbols": [...] } }
missing = []
for rel, fs in data.items():
    if authored is not None and rel not in authored:
        continue
    if rel in manual_files:
        continue
    for s in fs.get("symbols", []):
        if not s.get("exported"):
            continue
        # interface assertion convention: `var _ X = (*Y)(nil)` — name is "_", skip
        if s.get("name") == "_":
            continue
        godoc = s.get("godoc") or []
        joined = "\n".join(godoc)
        if "[traces-to:" not in joined:
            missing.append(f"{rel}:{s.get('line')} {s.get('name')}")

out = pathlib.Path(run_dir) / "impl" / "symbol-markers-check.md"
out.parent.mkdir(parents=True, exist_ok=True)
if missing:
    out.write_text("# Symbol markers: FAIL\n\n" + "\n".join(f"- {m}" for m in missing) + "\n")
    print(f"FAIL: {len(missing)} exported symbol(s) missing [traces-to:] marker")
    for m in missing[:20]:
        print(f"  {m}")
    sys.exit(1)
out.write_text("# Symbol markers: PASS\n")
sys.exit(0)
PY
