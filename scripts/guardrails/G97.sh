#!/usr/bin/env bash
# phases: impl testing
# severity: BLOCKER
# [constraint: ... bench/BenchmarkX] markers → automatic bench proof.
# Every symbol annotated with a constraint that references a benchmark must
# have a matching passing bench result in runs/<id>/testing/bench-raw.txt.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
BENCH="$RUN_DIR/testing/bench-raw.txt"
[ -n "$TARGET" ] || exit 0

python3 - "$TARGET" "$BENCH" <<'PY'
import re, pathlib, sys
target, bench_path = sys.argv[1:3]
bench_text = open(bench_path).read() if pathlib.Path(bench_path).is_file() else ""

constraints = []
for p in pathlib.Path(target).rglob("*.go"):
    for m in re.finditer(r'\[constraint:\s*([^\]]*?bench/(\w+))\s*\]', p.read_text(errors="ignore")):
        constraints.append((p, m.group(1), m.group(2)))

fail = []
for p, spec, bench_name in constraints:
    # Bench results look like: BenchmarkGet-8   100000  12345 ns/op
    if not re.search(rf'^\s*{re.escape(bench_name)}\b', bench_text, re.MULTILINE):
        fail.append(f"{p}: constraint references {bench_name} but no result found in bench-raw.txt")

for f in fail:
    print(f"FAIL: {f}")
sys.exit(1 if fail else 0)
PY
