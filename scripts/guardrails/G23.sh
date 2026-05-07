#!/usr/bin/env bash
# phases: intake
# severity: WARN
# Skills-Manifest validation — declared skills exist at ≥ declared version.
# WARNING only: missing skills are logged + filed to docs/PROPOSED-SKILLS.md
# but the pipeline proceeds. Skill authorship is a human PR concern, not a
# run-time blocker.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
TPRD="$RUN_DIR/tprd.md"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEX="$REPO/.claude/skills/skill-index.json"
REPORT="$RUN_DIR/intake/skills-manifest-check.md"
PROPOSED="$REPO/docs/PROPOSED-SKILLS.md"

mkdir -p "$(dirname "$REPORT")"
[ -f "$TPRD" ] || { echo "missing $TPRD"; exit 0; }
[ -f "$INDEX" ] || { echo "missing skill-index.json (pipeline mis-configured)"; exit 0; }

python3 - "$TPRD" "$INDEX" "$REPORT" "$PROPOSED" "$(basename "$RUN_DIR")" <<'PY'
import json, re, sys, pathlib, datetime

tprd_path, index_path, report_path, proposed_path, run_id = sys.argv[1:6]
tprd = open(tprd_path).read()
index = json.load(open(index_path))

# Build catalog: name -> version
catalog = {}
for section, entries in index.get("skills", {}).items():
    for e in entries:
        catalog[e["name"]] = e.get("version", "0.0.0")

# Extract §Skills-Manifest table
m = re.search(r'##\s*§?\s*Skills-?Manifest\b.*?$(.*?)(?=^##\s|\Z)',
              tprd, re.IGNORECASE | re.MULTILINE | re.DOTALL)
if not m:
    pathlib.Path(report_path).write_text(
        "# Skills-Manifest check\n\nStatus: WARN — §Skills-Manifest section absent from TPRD.\n"
        "Pipeline proceeds without skill-prescription guidance; design and impl phases\n"
        "may produce generic output. Recommended: author the manifest; see LIFECYCLE.md §3a.\n"
    )
    print("WARN: §Skills-Manifest absent; proceeding without skill guidance")
    sys.exit(0)

body = m.group(1)
declared = []
for line in body.splitlines():
    cells = [c.strip().strip('`') for c in line.split('|') if c.strip()]
    if len(cells) >= 2 and not cells[0].startswith('-') and not cells[0].lower().startswith('skill'):
        name, version = cells[0], cells[1]
        if re.match(r'^\d+\.\d+\.\d+', version.lstrip('≥>=v ')):
            declared.append((name, version.lstrip('≥>=v ')))

missing, underver, ok = [], [], []
def ver_tuple(v): return tuple(int(x) for x in v.split('.')[:3])
for name, need in declared:
    if name not in catalog:
        missing.append((name, need))
    else:
        have = catalog[name]
        if ver_tuple(have) < ver_tuple(need):
            underver.append((name, need, have))
        else:
            ok.append((name, need, have))

lines = ["# Skills-Manifest check", ""]
lines.append(f"Status: {'PASS' if not (missing or underver) else 'WARN'}")
lines.append(f"Declared: {len(declared)} · OK: {len(ok)} · Missing: {len(missing)} · Under-versioned: {len(underver)}")
lines.append("")
if ok:
    lines.append("## OK")
    for n, need, have in ok:
        lines.append(f"- `{n}` declared ≥{need}, found {have} ✓")
    lines.append("")
if missing:
    lines.append("## Missing (WARN — filed to docs/PROPOSED-SKILLS.md)")
    for n, need in missing:
        lines.append(f"- `{n}` declared ≥{need} — not in skill-index.json")
    lines.append("")
if underver:
    lines.append("## Under-versioned (WARN — pipeline uses older version)")
    for n, need, have in underver:
        lines.append(f"- `{n}` declared ≥{need}, found {have}")
    lines.append("")
lines.append("\nNote: missing or under-versioned skills are WARNINGS only. Pipeline proceeds.\n")

pathlib.Path(report_path).write_text("\n".join(lines))

# Append missing to PROPOSED-SKILLS.md
if (missing or underver) and pathlib.Path(proposed_path).exists():
    today = datetime.date.today().isoformat()
    with open(proposed_path, "a") as f:
        f.write(f"\n---\n\n## Auto-filed from run `{run_id}` on {today}\n\n")
        for n, need in missing:
            f.write(f"- **MISSING** `{n}` (≥{need}) — source run `{run_id}`\n")
        for n, need, have in underver:
            f.write(f"- **UNDER-VERSIONED** `{n}` declared ≥{need}, have {have} — source run `{run_id}`\n")

if missing:
    print(f"WARN: {len(missing)} skill(s) missing (non-blocking). See {report_path}")
if underver:
    print(f"WARN: {len(underver)} skill(s) under-versioned (non-blocking)")
sys.exit(0)
PY
