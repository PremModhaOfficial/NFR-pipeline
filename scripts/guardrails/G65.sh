#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# Benchmark regression gate: >5% on new-package hot paths, >10% on shared paths.
# Reads benchstat output from runs/<id>/testing/bench-compare.txt (produced by
# sdk-testing-lead wave T4). Missing file = skip (no benches run).
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
COMPARE="$RUN_DIR/testing/bench-compare.txt"
[ -f "$COMPARE" ] || { echo "no bench-compare (skipped — no benchmarks recorded)"; exit 0; }

python3 - "$COMPARE" "$RUN_DIR" <<'PY'
import re, sys, pathlib
compare, run_dir = sys.argv[1:3]
text = open(compare).read()

# benchstat output format: "name   old time/op   new time/op   delta"
# e.g.  "Get-8   195µs ± 2%   205µs ± 3%   +5.13% (p=0.000 n=10+10)"
fail = []
for line in text.splitlines():
    m = re.match(r'^\s*(\S+)\s+.*?([+-]?\d+\.\d+)%', line)
    if not m:
        continue
    name, delta = m.group(1), float(m.group(2))
    # Heuristic: hot paths contain "Get", "Set", "Publish", "Fetch", "Send", "Recv"
    is_hot = bool(re.search(r'Get|Set|Publish|Fetch|Send|Recv|Write|Read', name, re.IGNORECASE))
    threshold = 5.0 if is_hot else 10.0
    if delta > threshold:
        fail.append((name, delta, threshold))

report = pathlib.Path(run_dir) / "testing" / "bench-regression-verdict.md"
report.parent.mkdir(parents=True, exist_ok=True)
if fail:
    lines = ["# Bench regression verdict: FAIL", ""]
    for n, d, t in fail:
        lines.append(f"- `{n}`: +{d:.2f}% regression (threshold {t:.0f}%) — BLOCKER")
    lines.append("")
    lines.append("Override with --accept-perf-regression <pct> if intentional.")
    report.write_text("\n".join(lines))
    print(f"FAIL: {len(fail)} benchmark regression(s)")
    sys.exit(1)
report.write_text("# Bench regression verdict: PASS\n")
sys.exit(0)
PY
