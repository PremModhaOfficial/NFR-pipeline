#!/usr/bin/env bash
# phases: testing
# severity: BLOCKER (INCOMPLETE-gated)
# Soak-MMD (Minimum Meaningful Duration) verdict gate.
# Backs CLAUDE.md rule 32 axis 6 + rule 33 (Verdict Taxonomy).
#
# Reads runs/<id>/testing/soak/state*.jsonl files written by sdk-soak-runner-{go,python}
# (background harness writes one line every ~30 s, marks `final: true` on the last entry).
# For each soak run, asserts the final `elapsed_s` is >= the symbol's declared
# `soak.mmd_seconds` in design/perf-budget.md.
#
# Verdicts (per CLAUDE.md rule 33 — never silently promote):
#   PASS         — elapsed_s >= mmd_seconds for every declared symbol
#   FAIL         — at least one symbol has elapsed_s < mmd_seconds
#   INCOMPLETE   — state.jsonl exists but harness crashed (no `final: true`),
#                  OR perf-budget.md declares soak but state file is missing
#   skipped      — no symbol in perf-budget.md has soak.enabled: true
#
# Language-neutral: same script handles Go and Python soak state files.
# Python soak emits {elapsed_s, asyncio_pending_tasks, rss_bytes, ...};
# Go soak emits {elapsed_s, goroutines, heap_bytes, ...}. The MMD check
# only reads `elapsed_s` and `final` — drift signal columns are ignored
# here (G106 reads them).
#
# Exit codes:
#   0 — PASS or skipped
#   1 — FAIL
#   2 — INCOMPLETE / INFRA missing
#
# Usage: bash scripts/guardrails/G105.sh <run-dir> [<target-dir>]
set -uo pipefail
RUN_DIR="${1:?usage: G105.sh <run-dir> [<target-dir>]}"
TARGET="${2:-}"
PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "INFRA: jq is required" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "INFRA: python3 is required (for YAML parsing of perf-budget.md)" >&2
  exit 2
fi

PERF_BUDGET="$RUN_DIR/design/perf-budget.md"
SOAK_DIR="$RUN_DIR/testing/soak"

# If no perf-budget.md, this run didn't go through the perf-architect; skip.
if [ ! -f "$PERF_BUDGET" ]; then
  echo "no perf-budget.md (skipped — design phase didn't author one)"
  exit 0
fi

# Extract soak-enabled symbols and their mmd_seconds from perf-budget.md.
# perf-budget.md contains a YAML block; we parse it via python3 + PyYAML if available,
# else fall back to grep/awk for the simple per-symbol soak.mmd_seconds field.
python3 - "$PERF_BUDGET" "$SOAK_DIR" <<'PY'
import json
import pathlib
import re
import sys

perf_budget_path, soak_dir = sys.argv[1:3]
soak_dir = pathlib.Path(soak_dir)

# Parse the YAML block inside the markdown wrapper.
text = pathlib.Path(perf_budget_path).read_text()
yaml_blocks = re.findall(r"```yaml\n(.*?)```", text, re.DOTALL)
if not yaml_blocks:
    print("INCOMPLETE: perf-budget.md has no YAML code block")
    sys.exit(2)

try:
    import yaml  # type: ignore
    parsed = yaml.safe_load(yaml_blocks[0])
except ImportError:
    # Fallback: regex-extract per-symbol soak blocks. Less robust but no PyYAML dep.
    parsed = None

soak_required: list[tuple[str, int]] = []  # [(symbol_name, mmd_seconds), ...]

if parsed and isinstance(parsed, dict) and "symbols" in parsed:
    for sym in parsed.get("symbols", []) or []:
        soak = sym.get("soak") or {}
        if soak.get("enabled") is True and "mmd_seconds" in soak:
            soak_required.append((sym["name"], int(soak["mmd_seconds"])))
else:
    # Best-effort regex fallback.
    sym_pattern = re.compile(
        r"-\s+name:\s*(\S+)\s*\n(.*?)(?=\n  - name:|\Z)",
        re.DOTALL,
    )
    for m in sym_pattern.finditer(yaml_blocks[0]):
        name, body = m.group(1).strip(), m.group(2)
        if re.search(r"soak:\s*\n[^\n]*\n?\s*enabled:\s*true", body):
            mmd_m = re.search(r"mmd_seconds:\s*(\d+)", body)
            if mmd_m:
                soak_required.append((name, int(mmd_m.group(1))))

if not soak_required:
    print("no soak-enabled symbols in perf-budget.md (skipped)")
    sys.exit(0)

# For each soak-enabled symbol, look for a matching state file.
# Convention: state.jsonl OR state.run<N>.jsonl OR state-<symbol-slug>.jsonl
if not soak_dir.is_dir():
    names = ", ".join(s for s, _ in soak_required)
    print(f"INCOMPLETE: perf-budget declares soak for [{names}] but {soak_dir} missing — soak harness did not run")
    sys.exit(2)

state_files = sorted(soak_dir.glob("state*.jsonl"))
if not state_files:
    names = ", ".join(s for s, _ in soak_required)
    print(f"INCOMPLETE: perf-budget declares soak for [{names}] but no state*.jsonl files in {soak_dir}")
    sys.exit(2)


def read_last_entry(path: pathlib.Path) -> dict | None:
    try:
        with open(path) as fh:
            lines = [line for line in fh.read().splitlines() if line.strip()]
        if not lines:
            return None
        return json.loads(lines[-1])
    except (OSError, json.JSONDecodeError):
        return None


# Build a map from symbol → state file. If exactly one state file exists, use it
# for all symbols (single-symbol soak); else match by symbol slug in filename.
def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def find_state_for_symbol(symbol: str) -> pathlib.Path | None:
    if len(state_files) == 1:
        return state_files[0]
    sym_slug = slug(symbol)
    for f in state_files:
        if sym_slug in f.stem.lower():
            return f
    # Heuristic: if filenames carry .runN. suffix, the last (latest) run wins.
    runs = [f for f in state_files if ".run" in f.name]
    if runs:
        return sorted(runs)[-1]
    return state_files[0]


fails: list[str] = []
incompletes: list[str] = []
passes: list[str] = []

for symbol, mmd in soak_required:
    state_file = find_state_for_symbol(symbol)
    if state_file is None:
        incompletes.append(f"{symbol}: no state file matched (mmd={mmd}s required)")
        continue
    last = read_last_entry(state_file)
    if last is None:
        incompletes.append(f"{symbol}: {state_file.name} empty or unreadable")
        continue
    elapsed = float(last.get("elapsed_s") or 0.0)
    is_final = bool(last.get("final"))
    if elapsed < float(mmd):
        if is_final:
            # Harness completed but ran less than MMD = FAIL (someone shortened the run)
            fails.append(
                f"{symbol}: elapsed_s={elapsed:.1f} < mmd_seconds={mmd} "
                f"(final entry recorded; run was cut short)"
            )
        else:
            # Harness still running / crashed = INCOMPLETE
            incompletes.append(
                f"{symbol}: elapsed_s={elapsed:.1f} < mmd_seconds={mmd} "
                f"(no `final: true` — harness crashed or wallclock cap hit)"
            )
    else:
        passes.append(f"{symbol}: elapsed_s={elapsed:.1f} >= mmd_seconds={mmd} ✓")

# Report. Precedence: FAIL > INCOMPLETE > PASS (per rule 33).
report_lines: list[str] = []
if fails:
    report_lines.append(f"FAIL: {len(fails)} soak symbol(s) ran less than declared MMD")
    for line in fails:
        report_lines.append(f"  {line}")
if incompletes:
    if not fails:
        report_lines.append(f"INCOMPLETE: {len(incompletes)} soak verdict(s) unrenderable")
    else:
        report_lines.append(f"  + {len(incompletes)} additional INCOMPLETE")
    for line in incompletes:
        report_lines.append(f"  {line}")
if passes and not fails and not incompletes:
    report_lines.append(f"PASS: {len(passes)} soak symbol(s) met MMD")
    for line in passes:
        report_lines.append(f"  {line}")
elif passes:
    report_lines.append(f"  ({len(passes)} passing symbol(s) not detailed above)")

print("\n".join(report_lines))

if fails:
    sys.exit(1)
if incompletes:
    sys.exit(2)
sys.exit(0)
PY
