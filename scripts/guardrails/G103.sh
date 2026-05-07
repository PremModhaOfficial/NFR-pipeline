#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# No forged MANUAL markers — every [traces-to: MANUAL-*] or [owned-by: MANUAL]
# in a symbol's godoc must correspond to an entry in ownership-map.manual_symbols.
# AST-based as of pipeline 0.3.0 — godoc associated with each symbol via the
# symbols enumerator instead of regex scan-ahead.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || { echo "no target dir"; exit 0; }
OWNERSHIP="$RUN_DIR/impl/ownership-map.json"
[ -f "$OWNERSHIP" ] || { echo "no ownership-map (Mode A — skipped)"; exit 0; }

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SYMBOLS="$REPO_ROOT/scripts/ast-hash/symbols.sh"
PACK="${PACK:-go}"

python3 - "$TARGET" "$OWNERSHIP" "$RUN_DIR" "$SYMBOLS" "$PACK" <<'PY'
import json, pathlib, re, subprocess, sys
target, ownership_path, run_dir, symbols_dispatcher, pack = sys.argv[1:6]

own = json.load(open(ownership_path))
allowed = {(e.get("file", ""), e.get("symbol", "")) for e in own.get("manual_symbols", [])}
manual_files = set(own.get("manual_files", []))
for e in own.get("manual_symbols", []):
    manual_files.add(e.get("file", ""))

r = subprocess.run([symbols_dispatcher, pack, "-dir", target], capture_output=True, text=True, timeout=60)
if r.returncode != 0:
    print(f"FAIL: symbols enumerator exit {r.returncode}: {r.stderr.strip()}")
    sys.exit(2)
data = json.loads(r.stdout) if r.stdout else {}

manual_marker_re = re.compile(r'\[(?:traces-to:\s*MANUAL-[^\]]+|owned-by:\s*MANUAL)\]')

forged = []
for rel, fs in data.items():
    for s in fs.get("symbols", []):
        godoc = "\n".join(s.get("godoc") or [])
        if not manual_marker_re.search(godoc):
            continue
        # The symbol carries a MANUAL marker — it must be in the allowed set
        if (rel, s["name"]) not in allowed:
            forged.append(f"{rel}:{s.get('line')} MANUAL marker on pipeline symbol '{s['name']}'")

# Also catch file-level MANUAL markers (e.g., package-level comments) that
# point at non-manual files. Scan files for markers not on a known symbol.
import re as _re
for rel, fs in data.items():
    if rel in manual_files:
        continue
    p = pathlib.Path(target) / rel
    text = p.read_text(errors="ignore")
    # Find markers NOT inside a symbol's godoc (those were checked above)
    symbol_godoc_lines = set()
    for s in fs.get("symbols", []):
        for g in s.get("godoc") or []:
            symbol_godoc_lines.add(g.strip())
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not manual_marker_re.search(line):
            continue
        if line.strip() in symbol_godoc_lines:
            continue  # already covered
        forged.append(f"{rel}:{lineno} MANUAL marker on non-manual file (file-level)")

out = pathlib.Path(run_dir) / "impl" / "forged-manual-check.md"
out.parent.mkdir(parents=True, exist_ok=True)
if forged:
    out.write_text("# Forged MANUAL markers: FAIL\n\n" +
                   "\n".join(f"- {f}" for f in forged) + "\n")
    print(f"FAIL: {len(forged)} forged MANUAL marker(s)")
    for f in forged[:20]:
        print(f"  {f}")
    sys.exit(1)
out.write_text("# Forged MANUAL markers: PASS\n")
sys.exit(0)
PY
