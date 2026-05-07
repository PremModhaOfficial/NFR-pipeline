#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# [stable-since: vX.Y.Z] signature-change guard — any change to a stable
# signature requires TPRD §12 Breaking-Change Risk section to declare MAJOR.
# AST-based as of pipeline 0.3.0 — uses canonical signature_text from the
# symbols enumerator (formatter-resilient, language-pluggable).
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || { echo "no target dir"; exit 0; }

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SYMBOLS="$REPO_ROOT/scripts/ast-hash/symbols.sh"

# Resolve target language from the run's active-packages.json (set by sdk-intake-agent
# Wave I5.5; G05 enforces presence). Falls back to "go" only if the file is absent
# (legacy run replays); fresh runs always have it.
APJ="$RUN_DIR/context/active-packages.json"
if [ -f "$APJ" ]; then
  PACK="${PACK:-$(jq -r '.target_language // "go"' "$APJ")}"
else
  PACK="${PACK:-go}"
fi

BASELINE="$REPO_ROOT/baselines/$PACK/stable-signatures.json"
TPRD="$RUN_DIR/tprd.md"

python3 - "$TARGET" "$RUN_DIR" "$BASELINE" "$TPRD" "$SYMBOLS" "$PACK" <<'PY'
import json, pathlib, re, subprocess, sys
target, run_dir, baseline_path, tprd_path, symbols_dispatcher, pack = sys.argv[1:7]
baseline_p = pathlib.Path(baseline_path)

r = subprocess.run([symbols_dispatcher, pack, "-dir", target], capture_output=True, text=True, timeout=60)
if r.returncode != 0:
    print(f"FAIL: symbols enumerator exit {r.returncode}: {r.stderr.strip()}")
    sys.exit(2)
data = json.loads(r.stdout) if r.stdout else {}

stable_re = re.compile(r'\[stable-since:\s*v\d+\.\d+\.\d+\]')

# Walk all symbols; pick those whose godoc carries a [stable-since:] marker.
# Key by "<file>::<name>" so renames register as "removal + addition" rather
# than "change" (consistent with the original semantics).
current = {}
for rel, fs in data.items():
    for s in fs.get("symbols", []):
        godoc = "\n".join(s.get("godoc") or [])
        if not stable_re.search(godoc):
            continue
        key = f"{rel}::{s['name']}"
        current[key] = s.get("signature_text", "")

if not baseline_p.is_file():
    baseline_p.parent.mkdir(parents=True, exist_ok=True)
    baseline_p.write_text(json.dumps(current, indent=2, sort_keys=True) + "\n")
    print(f"baseline created ({len(current)} stable signatures) — first run, skipped")
    sys.exit(0)

baseline = json.loads(baseline_p.read_text())
changed = [k for k, v in current.items() if k in baseline and baseline[k] != v]

if not changed:
    for k, v in current.items():
        baseline.setdefault(k, v)
    baseline_p.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n")
    sys.exit(0)

tprd_text = open(tprd_path).read() if pathlib.Path(tprd_path).is_file() else ""
sec12 = re.search(r'(?i)#+\s*(?:\d+\.\s*)?(?:§\s*)?12[^\n]*\n(.*?)(?=\n#+\s|\Z)', tprd_text, re.DOTALL)
sec12_text = sec12.group(1) if sec12 else ""
has_major = bool(re.search(r'\b(MAJOR|breaking)\b', sec12_text, re.IGNORECASE))

if not has_major:
    print(f"FAIL: {len(changed)} stable signature(s) changed without TPRD §12 MAJOR declaration")
    for k in changed:
        print(f"  {k}")
        print(f"    was:  {baseline[k]}")
        print(f"    now:  {current[k]}")
    sys.exit(1)
print(f"OK: {len(changed)} stable signature change(s) covered by TPRD §12 MAJOR declaration")
sys.exit(0)
PY
