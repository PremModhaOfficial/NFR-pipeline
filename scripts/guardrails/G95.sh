#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# Marker ownership — [owned-by: MANUAL] symbols MUST NOT be modified by the
# pipeline. Uses AST-hash via scripts/ast-hash/ast-hash.sh when the
# ownership-map entry has `ast_hash` + `language` fields (preferred); falls
# back to the legacy byte-range SHA256 for older ownership maps.
#
# Pipeline versions:
#   0.2.0 and earlier — byte-range hash only
#   0.3.0 — AST-hash preferred, byte-hash fallback still honored
#   0.4.0+ — byte-hash fallback removed (plan: C-refactor P1 exit criterion)
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
OWNERSHIP="$RUN_DIR/impl/ownership-map.json"
[ -f "$OWNERSHIP" ] || { echo "no ownership-map (Mode A — skipped)"; exit 0; }
[ -n "$TARGET" ] || { echo "no target dir"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AST_HASH="$REPO_ROOT/scripts/ast-hash/ast-hash.sh"

python3 - "$OWNERSHIP" "$TARGET" "$RUN_DIR" "$AST_HASH" <<'PY'
import json, sys, pathlib, hashlib, subprocess
ownership_path, target, run_dir, ast_hash_dispatcher = sys.argv[1:5]
own = json.load(open(ownership_path))

bad = []
for entry in own.get("manual_symbols", []):
    path = pathlib.Path(target) / entry["file"]
    if not path.is_file():
        bad.append(f"MANUAL file removed: {entry['file']}")
        continue

    # Preferred: AST-hash (ownership-map has ast_hash + language)
    if "ast_hash" in entry and "language" in entry:
        try:
            r = subprocess.run(
                [ast_hash_dispatcher, entry["language"], str(path), entry["symbol"]],
                capture_output=True, text=True, timeout=30,
            )
        except Exception as e:
            bad.append(f"MANUAL ast-hash dispatcher error: {entry['file']} — {entry.get('symbol','?')} ({e})")
            continue
        if r.returncode != 0:
            bad.append(f"MANUAL ast-hash failed (exit {r.returncode}): {entry['file']} — {entry.get('symbol','?')}")
            continue
        actual = r.stdout.strip()
        if actual != entry["ast_hash"]:
            bad.append(f"MANUAL symbol modified (AST): {entry['file']} — {entry.get('symbol','?')}")
        continue  # handled via AST path; skip legacy check

    # Legacy: byte-range SHA256 (pre-0.3.0 ownership maps)
    text = path.read_text(errors="ignore")
    start, end = entry.get("byte_start", 0), entry.get("byte_end", 0)
    if end <= start:
        continue
    region = text.encode("utf-8", errors="ignore")[start:end]
    h = hashlib.sha256(region).hexdigest()
    if h != entry.get("sha256", ""):
        bad.append(f"MANUAL symbol modified (byte): {entry['file']} — {entry.get('symbol', '?')}")

out = pathlib.Path(run_dir) / "impl" / "marker-ownership-check.md"
out.parent.mkdir(parents=True, exist_ok=True)
if bad:
    out.write_text("# Marker ownership: FAIL\n\n" + "\n".join(f"- {b}" for b in bad) + "\n")
    print(f"FAIL: {len(bad)} MANUAL symbol(s) modified — BLOCKER")
    for b in bad:
        print(f"  {b}")
    sys.exit(1)
out.write_text("# Marker ownership: PASS\n")
sys.exit(0)
PY
