#!/usr/bin/env bash
# phases: intake
# severity: BLOCKER
# Guardrails-Manifest validation — every declared guardrail has an executable
# script in scripts/guardrails/<id>.sh.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
TPRD="$RUN_DIR/tprd.md"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GRDIR="$REPO/scripts/guardrails"
REPORT="$RUN_DIR/intake/guardrails-manifest-check.md"

mkdir -p "$(dirname "$REPORT")"
[ -f "$TPRD" ] || { echo "missing $TPRD"; exit 1; }

python3 - "$TPRD" "$GRDIR" "$REPORT" <<'PY'
import re, sys, pathlib, os

tprd_path, grdir, report_path = sys.argv[1:4]
tprd = open(tprd_path).read()

m = re.search(r'##\s*§?\s*Guardrails-?Manifest\b.*?$(.*?)(?=^##\s|\Z)',
              tprd, re.IGNORECASE | re.MULTILINE | re.DOTALL)
if not m:
    pathlib.Path(report_path).write_text(
        "# Guardrails-Manifest check\n\nStatus: FAIL — §Guardrails-Manifest section absent from TPRD.\n"
        "This is a BLOCKER. Author the manifest (see LIFECYCLE.md §3a).\n"
    )
    print("FAIL: §Guardrails-Manifest absent")
    sys.exit(1)

body = m.group(1)
declared = []
for line in body.splitlines():
    # Match G-ids: G01, G01-G03, G95–G103, etc.
    for match in re.finditer(r'\bG\d{2,3}(?:\s*[-–]\s*G\d{2,3})?\b', line):
        token = match.group(0).replace(' ', '').replace('–', '-')
        if '-' in token:
            lo, hi = [int(x.lstrip('G')) for x in token.split('-')]
            for n in range(lo, hi + 1):
                declared.append(f"G{n:02d}" if n < 100 else f"G{n}")
        else:
            declared.append(token)
declared = sorted(set(declared))

missing, ok = [], []
for gid in declared:
    script = pathlib.Path(grdir) / f"{gid}.sh"
    if not script.is_file():
        missing.append(gid)
    elif not os.access(script, os.X_OK):
        missing.append(f"{gid} (not executable)")
    else:
        ok.append(gid)

lines = ["# Guardrails-Manifest check", ""]
status = "PASS" if not missing else "FAIL"
lines.append(f"Status: {status}")
lines.append(f"Declared: {len(declared)} · OK: {len(ok)} · Missing/non-exec: {len(missing)}")
lines.append("")
if ok:
    lines.append("## OK")
    for g in ok:
        lines.append(f"- `{g}` ✓")
    lines.append("")
if missing:
    lines.append("## Missing / non-executable (BLOCKER)")
    for g in missing:
        lines.append(f"- `{g}` — author script at scripts/guardrails/{g.split()[0]}.sh and `chmod +x`")
    lines.append("")

pathlib.Path(report_path).write_text("\n".join(lines))

if missing:
    print(f"FAIL: {len(missing)} guardrail script(s) missing")
    for g in missing:
        print(f"  - {g}")
    sys.exit(1)
sys.exit(0)
PY
