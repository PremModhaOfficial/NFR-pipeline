#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# Go complexity-mismatch gate (CLAUDE.md rule 32 axis 4).
#
# For every symbol in design/perf-budget.md with a declared `complexity.time`
# big-O, parses runs/<id>/testing/bench-scaling.txt for that bench's per-N
# measurements (`BenchmarkX/N=10-8`, `BenchmarkX/N=100-8`, ...). Log-log
# curve-fits the slope; compares to the declared big-O exponent. BLOCKER on
# mismatch (e.g. declared O(n) measured O(n²)). Catches accidental quadratic
# paths that pass wallclock gates at microbench sizes.
#
# Big-O → expected log-log slope mapping:
#   O(1), O(log n)            → slope ≈ 0   (≤ 0.5 tolerance — log-fit slope is small)
#   O(n)                      → slope ≈ 1   (0.5–1.4 tolerance)
#   O(n log n)                → slope ≈ 1   (~1.0–1.4 — log term curves it slightly above 1)
#   O(n²)                     → slope ≈ 2   (1.5–2.5 tolerance)
#   O(n³)                     → slope ≈ 3   (2.5–3.5 tolerance)
#
# Verdicts (per CLAUDE.md rule 33):
#   PASS         — every symbol's measured slope within tolerance of declared
#   FAIL         — declared O(n) but measured O(n²) (or any worse-than-declared)
#   INCOMPLETE   — fewer than 3 N-points, OR scaling output missing for budgeted symbol
#   skipped      — no perf-budget, no symbols with complexity.time declared
#
# Exit codes:
#   0 — PASS or skipped
#   1 — FAIL
#   2 — INCOMPLETE / INFRA missing
#
# Usage: bash scripts/guardrails/G107.sh <run-dir> [<target-dir>]
set -uo pipefail
RUN_DIR="${1:?usage: G107.sh <run-dir> [<target-dir>]}"
TARGET="${2:-}"
PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "INFRA: python3 is required" >&2
  exit 2
fi

PERF_BUDGET="$RUN_DIR/design/perf-budget.md"
SCALING="$RUN_DIR/testing/bench-scaling.txt"

APJ="$RUN_DIR/context/active-packages.json"
if [ -f "$APJ" ] && command -v jq >/dev/null 2>&1; then
  PACK="$(jq -r '.target_language // "go"' "$APJ")"
else
  PACK="go"
fi
if [ "$PACK" != "go" ]; then
  echo "skipped — G107.sh is the Go variant; active language is $PACK"
  exit 0
fi

if [ ! -f "$PERF_BUDGET" ]; then
  echo "no perf-budget.md (skipped)"
  exit 0
fi

if [ ! -f "$SCALING" ]; then
  echo "INCOMPLETE: $SCALING missing — sdk-complexity-devil-go didn't produce scaling sweep"
  exit 2
fi

python3 - "$PERF_BUDGET" "$SCALING" <<'PY'
import math
import pathlib
import re
import sys

perf_budget_path, scaling_path = sys.argv[1:3]

# Big-O → (lo_slope, hi_slope) tolerance windows.
# Designed to catch declared-vs-measured drift at the order-of-magnitude level
# without false-positives from constant overhead at small N.
BIG_O_TOLERANCE: dict[str, tuple[float, float]] = {
    "O(1)":         (-0.3, 0.5),
    "O(log n)":     (-0.3, 0.6),
    "O(n)":         (0.6, 1.4),
    "O(n log n)":   (0.7, 1.5),  # n*log(n) is between n^1 and n^1.x in log-log space
    "O(n^2)":       (1.5, 2.5),
    "O(n²)":        (1.5, 2.5),  # alternative spelling
    "O(n^3)":       (2.5, 3.5),
    "O(n³)":        (2.5, 3.5),
}


def declared_to_window(declared: str) -> tuple[float, float] | None:
    norm = declared.strip().replace(" ", "").lower()
    # Normalize a few common variants
    norm = norm.replace("n^2", "n²").replace("n^3", "n³").replace("nlogn", "nlog(n)")
    aliases = {
        "o(1)": "O(1)",
        "o(logn)": "O(log n)",
        "o(log(n))": "O(log n)",
        "o(n)": "O(n)",
        "o(nlog(n))": "O(n log n)",
        "o(nlogn)": "O(n log n)",
        "o(n²)": "O(n²)",
        "o(n³)": "O(n³)",
    }
    canonical = aliases.get(norm)
    if canonical is None:
        # Try one more pass: the aliases-key strips spaces, original may have them
        canonical = aliases.get(norm.replace(" ", ""))
    if canonical is None:
        return None
    return BIG_O_TOLERANCE.get(canonical)


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

# (symbol_name, bench_id, declared_big_o)
specs: list[tuple[str, str, str]] = []
if parsed and isinstance(parsed, dict):
    for sym in parsed.get("symbols", []) or []:
        complexity = sym.get("complexity") or {}
        big_o = complexity.get("time") or ""
        bench = (sym.get("bench") or "").split("/")[-1]
        if big_o and bench:
            specs.append((sym["name"], bench, big_o))
else:
    sym_pattern = re.compile(
        r"-\s+name:\s*(\S+)\s*\n(.*?)(?=\n  - name:|\Z)",
        re.DOTALL,
    )
    for m in sym_pattern.finditer(yaml_blocks[0]):
        name, body = m.group(1).strip(), m.group(2)
        bench_m = re.search(r"bench:\s*(\S+)", body)
        big_o_m = re.search(r"complexity:\s*\n\s*time:\s*\"?([^\"\n]+)\"?", body)
        if bench_m and big_o_m:
            specs.append((name, bench_m.group(1).split("/")[-1], big_o_m.group(1).strip()))

if not specs:
    print("no symbols with complexity.time declared in perf-budget.md (skipped)")
    sys.exit(0)

# Parse bench-scaling.txt for `BenchmarkX/N=K-cores  iters  ns/op` lines.
scaling_text = pathlib.Path(scaling_path).read_text()
scaling_re = re.compile(
    r"^(Benchmark\S+?)/N=(\d+)(?:-\d+)?\s+\d+\s+([\d.]+)\s*ns/op",
    re.MULTILINE,
)

# Map: bench_id → list of (n, ns_per_op)
points: dict[str, list[tuple[int, float]]] = {}
for m in scaling_re.finditer(scaling_text):
    bench, n, ns = m.group(1), int(m.group(2)), float(m.group(3))
    points.setdefault(bench, []).append((n, ns))


def log_log_slope(pts: list[tuple[int, float]]) -> float | None:
    """Pure-stdlib OLS on (log N, log ns) points. Returns slope or None."""
    if len(pts) < 3:
        return None
    xs = [math.log(n) for n, _ in pts]
    ys = [math.log(ns) for _, ns in pts]
    mean_x = sum(xs) / len(xs)
    mean_y = sum(ys) / len(ys)
    sum_xy = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    sum_xx = sum((x - mean_x) ** 2 for x in xs)
    if sum_xx == 0:
        return None
    return sum_xy / sum_xx


fails: list[str] = []
incompletes: list[str] = []
passes: list[str] = []

for symbol, bench, declared in specs:
    window = declared_to_window(declared)
    if window is None:
        incompletes.append(
            f"{symbol}: declared complexity '{declared}' not recognized "
            f"(supported: O(1), O(log n), O(n), O(n log n), O(n²), O(n³))"
        )
        continue
    pts = sorted(points.get(bench, []))
    if len(pts) < 3:
        incompletes.append(
            f"{symbol}: bench {bench} has {len(pts)} N-points in {scaling_path} "
            f"(need >=3 for log-log fit). Add more parametrize values."
        )
        continue
    slope = log_log_slope(pts)
    if slope is None:
        incompletes.append(f"{symbol}: bench {bench} log-log fit failed (degenerate data)")
        continue
    lo, hi = window
    sample_str = ", ".join(f"N={n}:{ns:.0f}ns" for n, ns in pts)
    if slope > hi:
        fails.append(
            f"{symbol}: declared {declared} but measured slope {slope:+.2f} > expected upper {hi:.2f} "
            f"(samples: {sample_str})"
        )
    elif slope < lo:
        # Measured FASTER than declared — surface as note, not FAIL.
        # (Caller may want to tighten the declaration.)
        passes.append(
            f"{symbol}: declared {declared}, measured slope {slope:+.2f} ≤ expected lower {lo:.2f} "
            f"(faster than declared — consider tightening)"
        )
    else:
        passes.append(
            f"{symbol}: declared {declared} ✓ measured slope {slope:+.2f} ∈ [{lo:.2f}, {hi:.2f}]"
        )

if fails:
    print(f"FAIL: {len(fails)} symbol(s) exceed declared big-O")
    for line in fails:
        print(f"  {line}")
    if incompletes:
        print(f"  + {len(incompletes)} INCOMPLETE")
        for line in incompletes:
            print(f"  ! {line}")
    sys.exit(1)
if incompletes:
    print(f"INCOMPLETE: {len(incompletes)} symbol(s)")
    for line in incompletes:
        print(f"  {line}")
    sys.exit(2)
print(f"PASS: {len(passes)} symbol(s) within declared big-O")
for line in passes:
    print(f"  {line}")
sys.exit(0)
PY
