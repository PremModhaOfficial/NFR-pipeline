#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# Go profile-no-surprise hot-path coverage gate (CLAUDE.md rule 32 axis 2).
#
# Reads runs/<id>/impl/profile-cpu.txt (text dump from `go tool pprof -top`)
# produced by sdk-profile-auditor-go at M3.5. Extracts the top-10 CPU samples
# by `flat%`, intersects with the symbols flagged `hot_path: true` in
# design/perf-budget.md. Coverage = sum of declared-hot flat% / sum of top-10
# user-code flat%. Asserts coverage >= 0.80. BLOCKER on surprise hotspots
# (top-10 functions that aren't declared hot_path AND aren't Go runtime).
#
# Verdicts (per CLAUDE.md rule 33):
#   PASS         — coverage ratio >= 0.80
#   FAIL         — coverage ratio < 0.80 (declared hot paths don't dominate)
#   INCOMPLETE   — profile output missing OR < 5 user-code samples (insufficient signal)
#   skipped      — no perf-budget, or no symbols flagged hot_path: true
#
# Go runtime symbols (`runtime.*`, `syscall.*`) are EXCLUDED from coverage
# denominator — they're expected overhead, not user logic.
#
# Exit codes:
#   0 — PASS or skipped
#   1 — FAIL
#   2 — INCOMPLETE / INFRA missing
#
# Usage: bash scripts/guardrails/G109.sh <run-dir> [<target-dir>]
set -uo pipefail
RUN_DIR="${1:?usage: G109.sh <run-dir> [<target-dir>]}"
TARGET="${2:-}"
PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "INFRA: python3 is required" >&2
  exit 2
fi

PERF_BUDGET="$RUN_DIR/design/perf-budget.md"
PROFILE="$RUN_DIR/impl/profile-cpu.txt"

APJ="$RUN_DIR/context/active-packages.json"
if [ -f "$APJ" ] && command -v jq >/dev/null 2>&1; then
  PACK="$(jq -r '.target_language // "go"' "$APJ")"
else
  PACK="go"
fi
if [ "$PACK" != "go" ]; then
  echo "skipped — G109.sh is the Go variant; active language is $PACK"
  exit 0
fi

if [ ! -f "$PERF_BUDGET" ]; then
  echo "no perf-budget.md (skipped)"
  exit 0
fi

if [ ! -f "$PROFILE" ]; then
  echo "INCOMPLETE: $PROFILE missing — sdk-profile-auditor-go (M3.5) didn't capture CPU profile"
  exit 2
fi

python3 - "$PERF_BUDGET" "$PROFILE" <<'PY'
import pathlib
import re
import sys

perf_budget_path, profile_path = sys.argv[1:3]

# Coverage threshold (CLAUDE.md rule 32 axis 2)
COVERAGE_MIN = 0.80
TOP_N = 10
MIN_USER_SAMPLES = 5  # below this, profile is too sparse for verdict

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

# Collect declared-hot symbol names. Match against pprof's qualified-name format
# (`github.com/foo/bar.Type.Method`). We use the leaf identifier as the matcher
# token since perf-budget declares short names like "dragonfly.Client.Get".
hot_tokens: list[str] = []  # match if any of these substrings appear in profile fn name
if parsed and isinstance(parsed, dict):
    for sym in parsed.get("symbols", []) or []:
        if not sym.get("hot_path"):
            continue
        name = sym.get("name") or ""
        # Take the leaf-2 components of the qualified name. e.g. "dragonfly.Client.Get"
        # → matcher tokens "Client.Get" and "Get". Adding the parent type narrows
        # against accidental matches on e.g. "fmt.Get".
        parts = name.split(".")
        if len(parts) >= 2:
            hot_tokens.append(".".join(parts[-2:]))
        if parts:
            hot_tokens.append(parts[-1])
else:
    sym_pattern = re.compile(
        r"-\s+name:\s*(\S+)\s*\n(.*?)(?=\n  - name:|\Z)",
        re.DOTALL,
    )
    for m in sym_pattern.finditer(yaml_blocks[0]):
        name, body = m.group(1).strip(), m.group(2)
        if not re.search(r"hot_path:\s*true", body):
            continue
        parts = name.split(".")
        if len(parts) >= 2:
            hot_tokens.append(".".join(parts[-2:]))
        if parts:
            hot_tokens.append(parts[-1])

if not hot_tokens:
    print("no hot_path symbols in perf-budget.md (skipped)")
    sys.exit(0)

# Parse pprof -top output. Format:
#       flat  flat%   sum%        cum   cum%
#       30s 30.00% 30.00%        35s 35.00%  github.com/foo/bar.Cache.Get
# Extract (flat%, fn_name) pairs. Coverage uses flat%, not cum%, because cum
# inflates per-call overhead in callers.
profile_text = pathlib.Path(profile_path).read_text()
sample_re = re.compile(
    r"^\s*\S+\s+(\d+\.\d+)%\s+\d+\.\d+%\s+\S+\s+\d+\.\d+%\s+(\S.*)$",
    re.MULTILINE,
)


def is_runtime(fn: str) -> bool:
    """Go runtime / syscall / GC symbols — excluded from coverage denominator."""
    runtime_prefixes = (
        "runtime.", "syscall.", "internal/syscall",
        "internal/runtime", "internal/poll.",
    )
    return any(fn.startswith(p) for p in runtime_prefixes)


samples = []  # [(flat_pct, fn_name), ...]
for m in sample_re.finditer(profile_text):
    flat = float(m.group(1))
    fn = m.group(2).strip()
    samples.append((flat, fn))

# Take top-10 by flat% (samples should already be sorted descending; sort to be safe)
samples.sort(reverse=True)
top = samples[:TOP_N]

if not top:
    print("INCOMPLETE: profile-cpu.txt has no parseable samples — re-run sdk-profile-auditor-go")
    sys.exit(2)

user_samples = [(p, fn) for p, fn in top if not is_runtime(fn)]
runtime_samples = [(p, fn) for p, fn in top if is_runtime(fn)]

if len(user_samples) < MIN_USER_SAMPLES:
    print(
        f"INCOMPLETE: only {len(user_samples)} user-code samples in top-{TOP_N} "
        f"(need >={MIN_USER_SAMPLES}). Profile may be I/O-bound or workload-too-small."
    )
    if runtime_samples:
        print(f"  Runtime samples seen: {[fn for _, fn in runtime_samples]}")
    sys.exit(2)


def matches_any_hot(fn: str) -> bool:
    return any(token and token in fn for token in hot_tokens)


user_total = sum(p for p, _ in user_samples)
hot_pct = sum(p for p, fn in user_samples if matches_any_hot(fn))
surprise_pct = user_total - hot_pct

coverage = hot_pct / user_total if user_total > 0 else 0.0

print(f"  Top-{TOP_N} CPU samples (flat%):")
for p, fn in top:
    tag = ""
    if is_runtime(fn):
        tag = " [runtime]"
    elif matches_any_hot(fn):
        tag = " [declared-hot]"
    else:
        tag = " [SURPRISE]"
    print(f"    {p:5.2f}%  {fn}{tag}")
print(f"  Declared-hot coverage of user-code top-{TOP_N}: {hot_pct:.1f}% / {user_total:.1f}% = {coverage:.3f}")
print(f"  Surprise hotspots (user code not declared hot): {surprise_pct:.1f}%")

if coverage < COVERAGE_MIN:
    print(
        f"FAIL: coverage {coverage:.3f} < {COVERAGE_MIN:.2f} — declared hot paths don't dominate "
        f"the profile. Either (a) declare the surprise functions as hot_path: true in perf-budget.md, "
        f"or (b) refactor so the declared hot paths actually dominate."
    )
    sys.exit(1)

print(f"PASS: coverage {coverage:.3f} >= {COVERAGE_MIN:.2f}")
sys.exit(0)
PY
