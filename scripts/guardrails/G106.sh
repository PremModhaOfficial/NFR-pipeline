#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER
# Soak-drift detection gate.
# Backs CLAUDE.md rule 32 axis 6.
#
# For each soak-enabled symbol in design/perf-budget.md, fits a linear regression
# over each declared drift_signal column in runs/<id>/testing/soak/state*.jsonl
# (skipping the first 2 min as warmup). FAILs if any signal shows a statistically
# significant positive trend (slope > 0 AND p < 0.05 AND R² > 0.5) — the signature
# of a memory leak / goroutine leak / fd leak / GC pressure growth that unit tests
# miss. Pure-stdlib statistics (no scipy / numpy dep); normal approximation for
# t-distribution p-value is sound at n≥30 (typical soak gives 60+ samples after warmup).
#
# Verdicts (per CLAUDE.md rule 33):
#   PASS         — every declared signal flat, descending, or noisy (R² ≤ 0.5)
#   FAIL         — at least one signal trends up significantly
#   INCOMPLETE   — fewer than 10 post-warmup samples, OR declared signal not in JSONL
#   skipped      — no soak symbols, no perf-budget, or no state files
#
# Language-neutral: drift signal NAMES differ per language but they're declared in
# perf-budget.md and emitted to JSONL with matching column names.
#
# Exit codes:
#   0 — PASS or skipped
#   1 — FAIL
#   2 — INCOMPLETE / INFRA missing
#
# Usage: bash scripts/guardrails/G106.sh <run-dir> [<target-dir>]
set -uo pipefail
RUN_DIR="${1:?usage: G106.sh <run-dir> [<target-dir>]}"
TARGET="${2:-}"
PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "INFRA: python3 is required" >&2
  exit 2
fi

PERF_BUDGET="$RUN_DIR/design/perf-budget.md"
SOAK_DIR="$RUN_DIR/testing/soak"

if [ ! -f "$PERF_BUDGET" ]; then
  echo "no perf-budget.md (skipped — design phase didn't author one)"
  exit 0
fi

python3 - "$PERF_BUDGET" "$SOAK_DIR" <<'PY'
import json
import math
import pathlib
import re
import sys

perf_budget_path, soak_dir = sys.argv[1:3]
soak_dir = pathlib.Path(soak_dir)

WARMUP_SECONDS = 120.0
SLOPE_P_VALUE = 0.05
R_SQUARED_MIN = 0.5
MIN_SAMPLES = 10


def linear_regression(xs: list[float], ys: list[float]) -> tuple[float, float, float, float] | None:
    """Pure-stdlib OLS regression.

    Returns (slope, intercept, r_squared, p_value_one_tail) or None if undefined.
    p_value_one_tail tests H0: slope <= 0 vs H1: slope > 0, using normal
    approximation to the t-distribution. Sound for n >= 30; soak runs deliver
    that with 30 s sampling over 15+ min.
    """
    n = len(xs)
    if n < 3:
        return None
    mean_x = sum(xs) / n
    mean_y = sum(ys) / n
    sum_xy = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    sum_xx = sum((x - mean_x) ** 2 for x in xs)
    sum_yy = sum((y - mean_y) ** 2 for y in ys)
    if sum_xx == 0 or sum_yy == 0:
        return None
    slope = sum_xy / sum_xx
    intercept = mean_y - slope * mean_x
    # SS residual via SS_total - SS_explained
    ss_res = sum_yy - (sum_xy ** 2 / sum_xx)
    ss_tot = sum_yy
    r_squared = max(0.0, 1.0 - ss_res / ss_tot)
    # Slope standard error and t-stat (assume residuals normal — robust enough at n>=30)
    if ss_res < 0:
        ss_res = 0.0
    if n - 2 <= 0:
        return None
    residual_variance = ss_res / (n - 2)
    if sum_xx <= 0:
        return None  # x has no variance — cannot fit slope at all
    if residual_variance <= 0:
        # Perfect linear fit (R²=1.0). Deterministic relationship: positive slope is
        # the strongest possible drift signal, not a non-result. p_one_tail collapses
        # to 0 (slope > 0) or 1 (slope <= 0).
        return slope, intercept, r_squared, 0.0 if slope > 0 else 1.0
    se_slope = math.sqrt(residual_variance / sum_xx)
    if se_slope == 0:
        return slope, intercept, r_squared, 0.0 if slope > 0 else 1.0
    t_stat = slope / se_slope
    # One-tailed p-value via normal CDF approximation
    # p = P(Z > t) = 0.5 * erfc(t / sqrt(2))
    p_value = 0.5 * math.erfc(t_stat / math.sqrt(2.0))
    return slope, intercept, r_squared, p_value


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

soak_specs: list[tuple[str, list[str]]] = []

if parsed and isinstance(parsed, dict):
    for sym in parsed.get("symbols", []) or []:
        soak = sym.get("soak") or {}
        if soak.get("enabled") is True:
            signals = soak.get("drift_signals") or []
            if signals:
                soak_specs.append((sym["name"], list(signals)))
else:
    sym_pattern = re.compile(
        r"-\s+name:\s*(\S+)\s*\n(.*?)(?=\n  - name:|\Z)",
        re.DOTALL,
    )
    for m in sym_pattern.finditer(yaml_blocks[0]):
        name, body = m.group(1).strip(), m.group(2)
        if not re.search(r"soak:\s*\n[^\n]*\n?\s*enabled:\s*true", body):
            continue
        sig_block_m = re.search(r"drift_signals:\s*\n((?:\s*-\s*\S+\s*\n)+)", body)
        if sig_block_m:
            signals = re.findall(r"-\s*(\S+)", sig_block_m.group(1))
            if signals:
                soak_specs.append((name, signals))

if not soak_specs:
    print("no soak-enabled symbols with drift_signals in perf-budget.md (skipped)")
    sys.exit(0)

if not soak_dir.is_dir():
    names = ", ".join(s for s, _ in soak_specs)
    print(f"INCOMPLETE: perf-budget declares drift_signals for [{names}] but {soak_dir} missing")
    sys.exit(2)

state_files = sorted(soak_dir.glob("state*.jsonl"))
if not state_files:
    names = ", ".join(s for s, _ in soak_specs)
    print(f"INCOMPLETE: perf-budget declares drift_signals for [{names}] but no state*.jsonl in {soak_dir}")
    sys.exit(2)


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def find_state_for_symbol(symbol: str) -> pathlib.Path | None:
    if len(state_files) == 1:
        return state_files[0]
    sym_slug = slug(symbol)
    for f in state_files:
        if sym_slug in f.stem.lower():
            return f
    runs = [f for f in state_files if ".run" in f.name]
    if runs:
        return sorted(runs)[-1]
    return state_files[0]


def read_entries(path: pathlib.Path) -> list[dict]:
    entries: list[dict] = []
    try:
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    entries.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    except OSError:
        pass
    return entries


fails: list[str] = []
incompletes: list[str] = []
passes: list[str] = []

for symbol, signals in soak_specs:
    state_file = find_state_for_symbol(symbol)
    if state_file is None:
        incompletes.append(f"{symbol}: no state file matched")
        continue
    entries = [e for e in read_entries(state_file) if "elapsed_s" in e]
    post = [e for e in entries if float(e.get("elapsed_s", 0)) >= WARMUP_SECONDS]
    if len(post) < MIN_SAMPLES:
        incompletes.append(
            f"{symbol}: only {len(post)} post-warmup samples in {state_file.name} "
            f"(need {MIN_SAMPLES}); soak duration too short for regression fit"
        )
        continue

    sym_failures: list[str] = []
    sym_warnings: list[str] = []
    sym_passes: list[str] = []

    for sig in signals:
        xs: list[float] = []
        ys: list[float] = []
        for e in post:
            if sig not in e:
                continue
            try:
                xs.append(float(e["elapsed_s"]))
                ys.append(float(e[sig]))
            except (TypeError, ValueError):
                continue
        if len(xs) < MIN_SAMPLES:
            sym_warnings.append(
                f"signal {sig}: only {len(xs)} usable samples (column missing or non-numeric)"
            )
            continue
        if len(set(ys)) == 1:
            sym_passes.append(f"{sig}: constant value {ys[0]} (no drift)")
            continue
        result = linear_regression(xs, ys)
        if result is None:
            sym_warnings.append(f"signal {sig}: regression undefined (zero variance)")
            continue
        slope, _intercept, r_sq, p = result
        if math.isnan(slope) or math.isnan(p) or math.isnan(r_sq):
            sym_warnings.append(f"signal {sig}: regression NaN (insufficient variance)")
            continue
        if slope > 0 and p < SLOPE_P_VALUE and r_sq > R_SQUARED_MIN:
            sym_failures.append(
                f"{sig}: slope={slope:+.3g}/s, p={p:.4f}, R²={r_sq:.3f} → DRIFT (rising trend, statistically significant)"
            )
        else:
            sym_passes.append(
                f"{sig}: slope={slope:+.3g}/s, p={p:.4f}, R²={r_sq:.3f} → flat / noisy / descending"
            )

    if sym_failures:
        fails.append(f"{symbol}:")
        for line in sym_failures:
            fails.append(f"  - {line}")
        if sym_warnings:
            for line in sym_warnings:
                fails.append(f"  ! {line}")
    elif sym_warnings:
        if not sym_passes:
            incompletes.append(f"{symbol}: no usable drift signals")
            for line in sym_warnings:
                incompletes.append(f"  ! {line}")
        else:
            passes.append(f"{symbol}: {len(sym_passes)} signal(s) flat ({len(sym_warnings)} unreadable)")
    else:
        passes.append(f"{symbol}: {len(sym_passes)} signal(s) flat or descending")

report_lines: list[str] = []
if fails:
    fail_count = sum(1 for line in fails if not line.startswith(" "))
    report_lines.append(f"FAIL: drift detected in {fail_count} symbol(s)")
    report_lines.extend(fails)
if incompletes:
    if not fails:
        report_lines.append(f"INCOMPLETE: {sum(1 for line in incompletes if not line.startswith(' '))} symbol(s) unrenderable")
    report_lines.extend(incompletes)
if passes and not fails and not incompletes:
    report_lines.append(f"PASS: {len(passes)} symbol(s) show no drift")
    for line in passes:
        report_lines.append(f"  {line}")

print("\n".join(report_lines))

if fails:
    sys.exit(1)
if incompletes:
    sys.exit(2)
sys.exit(0)
PY
