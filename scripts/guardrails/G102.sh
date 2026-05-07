#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# Marker syntax validity — every [<key>: <value>] marker in target .go files
# must conform to the key-specific value grammar (see CLAUDE.md rule 29).
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || { echo "no target dir"; exit 0; }

python3 - "$TARGET" "$RUN_DIR" <<'PY'
import pathlib, re, sys
target, run_dir = sys.argv[1:3]
target_p = pathlib.Path(target)

known_keys = {"traces-to", "constraint", "stable-since", "deprecated-in",
              "owned-by", "do-not-regenerate"}
val_re = {
    "traces-to":    re.compile(r'^(TPRD-\d+(\.\d+)*-[A-Z0-9-]+|MANUAL-[A-Za-z0-9_\-]+)$'),
    "stable-since": re.compile(r'^v\d+\.\d+\.\d+$'),
    "deprecated-in":re.compile(r'^v\d+\.\d+\.\d+$'),
    "owned-by":     re.compile(r'^(MANUAL|pipeline(:[A-Za-z0-9_\-]+)?)$'),
}
# Match either [key: value] or bare [key]
marker_any_re = re.compile(r'\[([a-z-]+)(?::\s*([^\]]*))?\]')

bad = []
for p in target_p.rglob("*.go"):
    text = p.read_text(errors="ignore")
    for lineno, line in enumerate(text.splitlines(), start=1):
        for m in marker_any_re.finditer(line):
            key = m.group(1)
            val = m.group(2)
            if key not in known_keys:
                continue  # unknown keys ignored (not our taxonomy)
            raw = m.group(0)
            if key == "do-not-regenerate":
                if val is not None and val.strip() != "":
                    bad.append(f"{p.relative_to(target_p)}:{lineno} {raw} (must be bare)")
                continue
            if val is None or val.strip() == "":
                bad.append(f"{p.relative_to(target_p)}:{lineno} {raw} (missing value)")
                continue
            v = val.strip()
            if key == "constraint":
                # require colon-separated measurement + verification
                # e.g., p99<=1ms:bench/BenchmarkGet
                if ":" not in v or "/" not in v.split(":", 1)[1]:
                    bad.append(f"{p.relative_to(target_p)}:{lineno} {raw} (constraint needs measurement:verification form)")
                continue
            rx = val_re.get(key)
            if rx and not rx.match(v):
                bad.append(f"{p.relative_to(target_p)}:{lineno} {raw}")

out = pathlib.Path(run_dir) / "impl" / "marker-syntax-check.md"
out.parent.mkdir(parents=True, exist_ok=True)
if bad:
    out.write_text("# Marker syntax: FAIL\n\n" + "\n".join(f"- {b}" for b in bad) + "\n")
    print(f"FAIL: {len(bad)} malformed marker(s)")
    for b in bad[:20]:
        print(f"  {b}")
    sys.exit(1)
out.write_text("# Marker syntax: PASS\n")
sys.exit(0)
PY
