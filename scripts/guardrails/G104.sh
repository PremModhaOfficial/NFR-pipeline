#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# Go alloc-budget gate (CLAUDE.md rule 32 axis 3).
#
# For every benchmark in runs/<id>/testing/bench-raw.txt (produced by
# `go test -bench=. -benchmem` at wave T4), parses `allocs/op` and compares
# against the per-symbol `allocs_per_op` declared in design/perf-budget.md.
# BLOCKER if measured > budget. Owner: sdk-profile-auditor-go (M3.5).
#
# Verdicts (per CLAUDE.md rule 33):
#   PASS         — every benched symbol's measured allocs/op <= declared budget
#   FAIL         — at least one symbol over budget
#   INCOMPLETE   — bench output exists but a budgeted symbol's bench is missing,
#                  OR perf-budget exists but bench output missing entirely
#   skipped      — no perf-budget.md (no symbol budgets to enforce)
#
# Exit codes:
#   0 — PASS or skipped
#   1 — FAIL
#   2 — INCOMPLETE / INFRA missing
#
# Usage: bash scripts/guardrails/G104.sh <run-dir> [<target-dir>]
set -uo pipefail
RUN_DIR="${1:?usage: G104.sh <run-dir> [<target-dir>]}"
TARGET="${2:-}"
PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "INFRA: python3 is required" >&2
  exit 2
fi

PERF_BUDGET="$RUN_DIR/design/perf-budget.md"
BENCH_RAW="$RUN_DIR/testing/bench-raw.txt"

# Resolve target language from active-packages; G104 is the Go variant.
APJ="$RUN_DIR/context/active-packages.json"
if [ -f "$APJ" ] && command -v jq >/dev/null 2>&1; then
  PACK="$(jq -r '.target_language // "go"' "$APJ")"
else
  PACK="go"
fi
if [ "$PACK" != "go" ]; then
  echo "skipped — G104.sh is the Go variant; active language is $PACK (use G104-py for Python)"
  exit 0
fi

if [ ! -f "$PERF_BUDGET" ]; then
  echo "no perf-budget.md (skipped — design phase didn't author one)"
  exit 0
fi

if [ ! -f "$BENCH_RAW" ]; then
  echo "INCOMPLETE: perf-budget.md exists but $BENCH_RAW missing — bench wave (T4) didn't run"
  exit 2
fi

python3 - "$PERF_BUDGET" "$BENCH_RAW" <<'PY'
import pathlib
import re
import sys

perf_budget_path, bench_raw_path = sys.argv[1:3]

# Parse perf-budget.md YAML block for per-symbol allocs_per_op + bench identifier.
text = pathlib.Path(perf_budget_path).read_text()
yaml_blocks = re.findall(r"```yaml\n(.*?)```", text, re.DOTALL)
if not yaml_blocks:
    print("INCOMPLETE: perf-budget.md has no YAML code block")
    sys.exit(2)

try:
    import yaml  # type: ignore
    parsed = yaml.safe_load(yaml_blocks[0])
except ImportError:
    parsed = None

# Each entry: (symbol_name, bench_id, alloc_budget, hot_path)
budgets: list[tuple[str, str, int, bool]] = []

if parsed and isinstance(parsed, dict):
    for sym in parsed.get("symbols", []) or []:
        if "allocs_per_op" not in sym:
            continue
        bench = sym.get("bench") or ""
        # Strip "bench/" prefix if present (e.g. "bench/BenchmarkGet" -> "BenchmarkGet")
        bench_id = bench.split("/")[-1] if bench else ""
        if not bench_id:
            continue
        try:
            budget = int(sym["allocs_per_op"])
        except (TypeError, ValueError):
            continue
        budgets.append((sym["name"], bench_id, budget, bool(sym.get("hot_path"))))
else:
    # Regex fallback (less robust)
    sym_pattern = re.compile(
        r"-\s+name:\s*(\S+)\s*\n(.*?)(?=\n  - name:|\Z)",
        re.DOTALL,
    )
    for m in sym_pattern.finditer(yaml_blocks[0]):
        name, body = m.group(1).strip(), m.group(2)
        bench_m = re.search(r"bench:\s*(\S+)", body)
        budget_m = re.search(r"allocs_per_op:\s*(\d+)", body)
        hot_m = re.search(r"hot_path:\s*true", body)
        if bench_m and budget_m:
            bench_id = bench_m.group(1).split("/")[-1]
            budgets.append((name, bench_id, int(budget_m.group(1)), bool(hot_m)))

if not budgets:
    print("no symbols with allocs_per_op declared in perf-budget.md (skipped)")
    sys.exit(0)

# Parse bench-raw.txt for `BenchmarkX-N  iters  ns/op  B/op  allocs/op` lines.
# Two variants: simple `BenchmarkGet-8` and parametrized `BenchmarkGet/N=10-8`.
# We match against bench_id as a prefix; if multiple variants exist, take the
# unparametrized form (the canonical bench).
bench_text = pathlib.Path(bench_raw_path).read_text()
bench_re = re.compile(
    r"^(Benchmark\S+?)(?:-\d+)?\s+\d+\s+[\d.]+\s*ns/op(?:\s+\d+\s*B/op)?\s+(\d+)\s+allocs/op",
    re.MULTILINE,
)

# Build a map: bench_id (canonical, no /N=… suffix) → measured allocs/op
measured: dict[str, int] = {}
for m in bench_re.finditer(bench_text):
    full_name = m.group(1)
    # Strip "/N=…" suffix to canonical bench id
    canonical = full_name.split("/")[0]
    allocs = int(m.group(2))
    # Prefer the canonical (non-parametrized) measurement if both exist;
    # otherwise take the LAST one seen for parametrized benches.
    if canonical not in measured or full_name == canonical:
        measured[canonical] = allocs

fails: list[str] = []
incompletes: list[str] = []
passes: list[str] = []

for symbol, bench_id, budget, hot in budgets:
    if bench_id not in measured:
        incompletes.append(
            f"{symbol}: bench {bench_id} declared but not in bench-raw.txt — "
            f"add to bench harness or remove from perf-budget.md"
        )
        continue
    actual = measured[bench_id]
    if actual > budget:
        delta = actual - budget
        marker = "[hot-path]" if hot else "[shared]"
        fails.append(
            f"{symbol} {marker}: {bench_id} measured {actual} allocs/op > budget {budget} "
            f"(over by {delta})"
        )
    else:
        passes.append(f"{symbol}: {bench_id} {actual}/{budget} allocs/op ✓")

# Report. Precedence FAIL > INCOMPLETE > PASS.
if fails:
    print(f"FAIL: {len(fails)} symbol(s) exceed allocs_per_op budget")
    for line in fails:
        print(f"  {line}")
    if incompletes:
        print(f"  + {len(incompletes)} INCOMPLETE")
        for line in incompletes:
            print(f"  ! {line}")
    sys.exit(1)
if incompletes:
    print(f"INCOMPLETE: {len(incompletes)} symbol(s) — bench output missing")
    for line in incompletes:
        print(f"  {line}")
    sys.exit(2)
print(f"PASS: {len(passes)} symbol(s) within allocs_per_op budget")
for line in passes:
    print(f"  {line}")
sys.exit(0)
PY
