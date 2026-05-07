#!/usr/bin/env bash
# preflight-check.sh — verify every required tool is on $PATH before pipeline kickoff.
#
# Reads `.claude/package-manifests/<lang>.json` to resolve per-language tools so
# the script never drifts from the manifests' authoritative `toolchain` block.
# Always checks the infra-tier; checks Go pack, Python pack, or both based on
# --lang flag (default: both, since either pilot may run).
#
# Categories:
#   - HARD BLOCKER — pipeline cannot run without it; missing → exit 1
#   - SOFT DEGRADE — guardrails downgrade or skip; missing → WARN (exit 2 only with --strict)
#   - OPTIONAL    — MCP enhancements; missing → INFO (never failing)
#
# Usage:
#   bash scripts/preflight-check.sh                  # checks infra + go + python
#   bash scripts/preflight-check.sh --infra-only     # H0 gate: infra-tier alone (target_language not yet known)
#   bash scripts/preflight-check.sh --lang=go        # infra + go only
#   bash scripts/preflight-check.sh --lang=python    # infra + python only
#   bash scripts/preflight-check.sh --strict         # fail on soft-degrade misses too
#   bash scripts/preflight-check.sh --with-docker    # also require Docker (testcontainers)
#   bash scripts/preflight-check.sh --json           # machine-readable output
#
# Exit codes: 0 ok, 1 hard blocker missing, 2 soft miss in --strict, 3 config error.
# When invoked from H0 (commands/run-sdk-addition.md step 4), exit 1 maps to
# pipeline exit code 7 (preflight HARD blocker). Wave I5.5 in sdk-intake-agent
# re-runs with --lang=<resolved> after active-packages.json is written.

set -o pipefail

PIPELINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST_DIR="$PIPELINE_ROOT/.claude/package-manifests"

LANG_FILTER="both"
STRICT=0
WITH_DOCKER=0
JSON_OUT=0
INFRA_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --lang=go) LANG_FILTER="go" ;;
    --lang=python) LANG_FILTER="python" ;;
    --lang=both) LANG_FILTER="both" ;;
    --strict) STRICT=1 ;;
    --with-docker) WITH_DOCKER=1 ;;
    --json) JSON_OUT=1 ;;
    --infra-only) INFRA_ONLY=1 ;;
    -h|--help)
      sed -n '2,25p' "$0"
      exit 0
      ;;
    *) echo "unknown flag: $arg" >&2; exit 3 ;;
  esac
done

# --infra-only short-circuits language-pack + conditional + MCP sections.
# Used at H0 (target_language not yet resolved by intake Wave I5.5).
if [ "$INFRA_ONLY" -eq 1 ]; then
  LANG_FILTER="none"
  WITH_DOCKER=0
fi

# -- color helpers (skip if not a TTY or --json)
if [ -t 1 ] && [ "$JSON_OUT" -eq 0 ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_RST=""
fi

HARD_MISSING=0
SOFT_MISSING=0
JSON_ROWS=()

# tool name | severity (HARD/SOFT/OPT) | description
check() {
  local tool="$1" severity="$2" desc="$3" version_cmd="${4:-}"
  local status_label color path version=""

  if command -v "$tool" >/dev/null 2>&1; then
    path=$(command -v "$tool")
    if [ -n "$version_cmd" ]; then
      version=$(eval "$version_cmd" 2>/dev/null | head -1 || true)
    fi
    status_label="OK"
    color="$C_OK"
  else
    path="(not found)"
    case "$severity" in
      HARD) status_label="MISSING"; color="$C_ERR"; HARD_MISSING=$((HARD_MISSING+1)) ;;
      SOFT) status_label="MISSING"; color="$C_WARN"; SOFT_MISSING=$((SOFT_MISSING+1)) ;;
      OPT)  status_label="absent"; color="$C_DIM" ;;
    esac
  fi

  if [ "$JSON_OUT" -eq 1 ]; then
    JSON_ROWS+=("$(printf '{"tool":"%s","severity":"%s","status":"%s","path":"%s","version":"%s","desc":"%s"}' \
      "$tool" "$severity" "$status_label" "$path" "$version" "$desc")")
  else
    printf "  %s%-22s%s [%s%-7s%s] %s%s%s\n" \
      "$color" "$tool" "$C_RST" "$color" "$status_label" "$C_RST" "$C_DIM" "$desc" "$C_RST"
    if [ -n "$version" ]; then
      printf "  %s%-22s   %s└─ %s%s\n" "" "" "$C_DIM" "$version" "$C_RST"
    fi
  fi
}

section() {
  if [ "$JSON_OUT" -eq 0 ]; then
    printf "\n${C_DIM}==[ %s ]==${C_RST}\n" "$1"
  fi
}

# version_lt <a> <b> → exit 0 if a < b (semver-ish via sort -V).
version_lt() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}

# check_version <tool> <observed> <minimum> <description>
# Emits WARN (SOFT) if observed < minimum. Never HARD.
check_version() {
  local tool="$1" obs="$2" min="$3" desc="$4" label color
  if [ -z "$obs" ]; then return; fi  # version unknown — skip silently
  if version_lt "$obs" "$min"; then
    label="OLD"; color="$C_WARN"
    SOFT_MISSING=$((SOFT_MISSING+1))
    if [ "$JSON_OUT" -eq 1 ]; then
      JSON_ROWS+=("$(printf '{"tool":"%s","severity":"SOFT","status":"OLD","observed":"%s","minimum":"%s","desc":"%s"}' \
        "$tool" "$obs" "$min" "$desc")")
    else
      printf "  %s%-22s%s [%s%-7s%s] %s%s observed=%s min=%s%s\n" \
        "$color" "$tool" "$C_RST" "$color" "$label" "$C_RST" "$C_DIM" "$desc" "$obs" "$min" "$C_RST"
    fi
  fi
}

# -- A. Infra-tier (always)
section "Infra-tier (always required)"
check bash    HARD "shell ≥4.0"           "bash --version"
check git     HARD "Rule 21 — target-dir = git repo" "git --version"
check jq      HARD "manifest + baseline parsing"     "jq --version"
check python3 HARD "guardrail heredocs / AST-hash backend" "python3 --version"
check grep    HARD "coreutils"
check sed     HARD "coreutils"
check awk     HARD "coreutils"
check sort    HARD "coreutils"
check find    HARD "coreutils"
check sha256sum HARD "coreutils — marker byte-hash" "sha256sum --version"
check claude  HARD "Claude Code CLI — harness" "claude --version 2>/dev/null || echo unknown"

# Claude CLI vs pipeline_version (warn-only).
if command -v claude >/dev/null 2>&1 && [ -f "$PIPELINE_ROOT/.claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
  CLAUDE_VER=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  PIPELINE_VER=$(jq -r '.pipeline_version // empty' "$PIPELINE_ROOT/.claude/settings.json")
  # Note: claude CLI version and pipeline_version are independent semvers; we only
  # warn if claude CLI is suspiciously old (<2.0). pipeline_version drift is G06's job.
  check_version "claude (CLI)" "$CLAUDE_VER" "2.0.0" "Claude Code CLI minimum"
fi

# -- B. Go pack
if [ "$LANG_FILTER" = "go" ] || [ "$LANG_FILTER" = "both" ]; then
  section "Go pack (target_language=go)"
  check go            HARD "Go 1.26+ compiler"                     "go version"
  if command -v go >/dev/null 2>&1; then
    GO_VER=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//')
    check_version "go (version)" "$GO_VER" "1.26.0" "Go ≥1.26 (manifest min)"
  fi
  check gofmt         HARD "toolchain.fmt"
  # `pprof` is bundled as `go tool pprof`, not a standalone binary on $PATH.
  if command -v go >/dev/null 2>&1 && go tool pprof -h >/dev/null 2>&1; then
    printf "  %s%-22s%s [%s%-7s%s] %sgo tool pprof — profile-auditor-go%s\n" \
      "$C_OK" "go tool pprof" "$C_RST" "$C_OK" "OK" "$C_RST" "$C_DIM" "$C_RST"
  else
    printf "  %s%-22s%s [%s%-7s%s] %sgo tool pprof — profile-auditor-go%s\n" \
      "$C_WARN" "go tool pprof" "$C_RST" "$C_WARN" "MISSING" "$C_RST" "$C_DIM" "$C_RST"
    SOFT_MISSING=$((SOFT_MISSING+1))
  fi
  check golangci-lint SOFT "toolchain.lint"                        "golangci-lint --version"
  check staticcheck   SOFT "G44"                                   "staticcheck -version"
  check govulncheck   SOFT "supply_chain[0] / G32"                 "govulncheck -version 2>&1 | head -1"
  check osv-scanner   SOFT "supply_chain[1] / G33"                 "osv-scanner --version 2>&1 | head -1"
  check benchstat     SOFT "benchmark-devil-go delta analysis"
  check gcc           SOFT "race detector / cgo (build-essential)" "gcc --version"
fi

# -- C. Python pack
if [ "$LANG_FILTER" = "python" ] || [ "$LANG_FILTER" = "both" ]; then
  section "Python pack (target_language=python)"

  # `python` and `pip` may only exist as `python3` / `pip3` on some distros.
  # Resolve once: prefer the bare name, fall back to the suffixed one.
  PY_BIN=$(command -v python 2>/dev/null || command -v python3 2>/dev/null || echo "")
  PIP_BIN=$(command -v pip 2>/dev/null || command -v pip3 2>/dev/null || echo "")

  if [ -n "$PY_BIN" ]; then
    PY_VER=$("$PY_BIN" --version 2>&1 | head -1)
    PY_NUM=$("$PY_BIN" -c 'import sys;print(f"{sys.version_info[0]}.{sys.version_info[1]}.{sys.version_info[2]}")' 2>/dev/null)
    printf "  %s%-22s%s [%s%-7s%s] %sPython 3.12+ (resolved: %s)%s\n" \
      "$C_OK" "python" "$C_RST" "$C_OK" "OK" "$C_RST" "$C_DIM" "$PY_BIN" "$C_RST"
    printf "  %-22s   %s└─ %s%s\n" "" "$C_DIM" "$PY_VER" "$C_RST"
    check_version "python (version)" "$PY_NUM" "3.12.0" "Python ≥3.12 (manifest min)"
  else
    printf "  %s%-22s%s [%s%-7s%s] %sPython 3.12+ (neither python nor python3 on PATH)%s\n" \
      "$C_ERR" "python" "$C_RST" "$C_ERR" "MISSING" "$C_RST" "$C_DIM" "$C_RST"
    HARD_MISSING=$((HARD_MISSING+1))
  fi

  if [ -n "$PIP_BIN" ]; then
    printf "  %s%-22s%s [%s%-7s%s] %spackage installer (resolved: %s)%s\n" \
      "$C_OK" "pip" "$C_RST" "$C_OK" "OK" "$C_RST" "$C_DIM" "$PIP_BIN" "$C_RST"
  else
    printf "  %s%-22s%s [%s%-7s%s] %spackage installer (install: apt install python3-pip)%s\n" \
      "$C_ERR" "pip" "$C_RST" "$C_ERR" "MISSING" "$C_RST" "$C_DIM" "$C_RST"
    HARD_MISSING=$((HARD_MISSING+1))
  fi

  check pytest   HARD "toolchain.test"              "pytest --version 2>&1 | head -1"
  check ruff     SOFT "toolchain.lint + fmt"        "ruff --version"
  check mypy     SOFT "toolchain.vet (G42-py)"      "mypy --version"
  if command -v mypy >/dev/null 2>&1; then
    MYPY_VER=$(mypy --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    check_version "mypy (version)" "$MYPY_VER" "1.0.0" "mypy ≥1.0 (strict-mode flags)"
  fi
  check pip-audit SOFT "supply_chain[0] / G32-py"   "pip-audit --version"
  check safety   SOFT "supply_chain[1] / G33-py"    "safety --version 2>&1 | head -1"
  check py-spy   SOFT "profile-auditor-python"      "py-spy --version"

  # Python module-level deps (not on $PATH; check via import)
  check_pymodule() {
    local mod="$1" severity="$2" desc="$3"
    local label color
    if python3 -c "import $mod" 2>/dev/null; then
      label="OK"; color="$C_OK"
    else
      case "$severity" in
        HARD) label="MISSING"; color="$C_ERR"; HARD_MISSING=$((HARD_MISSING+1)) ;;
        SOFT) label="MISSING"; color="$C_WARN"; SOFT_MISSING=$((SOFT_MISSING+1)) ;;
      esac
    fi
    if [ "$JSON_OUT" -eq 1 ]; then
      JSON_ROWS+=("$(printf '{"tool":"py:%s","severity":"%s","status":"%s","desc":"%s"}' \
        "$mod" "$severity" "$label" "$desc")")
    else
      printf "  %s%-22s%s [%s%-7s%s] %s%s%s\n" \
        "$color" "py:$mod" "$C_RST" "$color" "$label" "$C_RST" "$C_DIM" "$desc" "$C_RST"
    fi
  }
  check_pymodule pytest_asyncio   SOFT "async test discovery"
  check_pymodule pytest_benchmark SOFT "toolchain.bench"
  check_pymodule pytest_cov       SOFT "toolchain.coverage"
  check_pymodule pytest_repeat    HARD "G63-py flake-hunter"
  check_pymodule build            SOFT "toolchain.build (python -m build)"
  check_pymodule yaml             SOFT "guardrails reading perf-config.yaml"
fi

# -- D. Conditional — Docker (only with --with-docker)
if [ "$WITH_DOCKER" -eq 1 ]; then
  section "Conditional — Docker (testcontainers)"
  check docker HARD "testcontainers Postgres/NATS/Redis/Kafka/MinIO" "docker --version"
  check nc     SOFT "Neo4j MCP TCP probe (G04)"
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      printf "  %s%-22s%s [%s%-7s%s] %sdaemon reachable%s\n" "$C_OK" "docker daemon" "$C_RST" "$C_OK" "OK" "$C_RST" "$C_DIM" "$C_RST"
    else
      printf "  %s%-22s%s [%s%-7s%s] %sbinary present but daemon unreachable — start Docker Desktop / systemctl start docker%s\n" \
        "$C_ERR" "docker daemon" "$C_RST" "$C_ERR" "DOWN" "$C_RST" "$C_DIM" "$C_RST"
      HARD_MISSING=$((HARD_MISSING+1))
    fi
  fi
fi

# -- E. Optional MCP (informational only) — skipped in --infra-only
if [ "$INFRA_ONLY" -eq 0 ]; then
  section "Optional — MCP enhancements (graceful degrade per Rule 31)"
  check npx  OPT "context7 MCP (npx -y @upstash/context7-mcp)" "npx --version"
  check uvx  OPT "neo4j-memory MCP (uvx mcp-neo4j-memory)"     "uvx --version"
  check cgc  OPT "code-graph MCP"
  check serena OPT "serena LSP MCP"
fi

# -- Manifest cross-check (informational)
if [ -f "$MANIFEST_DIR/go.json" ] && [ -f "$MANIFEST_DIR/python.json" ] && [ "$JSON_OUT" -eq 0 ]; then
  section "Manifest cross-check"
  for lang in go python; do
    if [ "$LANG_FILTER" = "$lang" ] || [ "$LANG_FILTER" = "both" ]; then
      cmds=$(jq -r '.toolchain | keys | join(", ")' "$MANIFEST_DIR/$lang.json" 2>/dev/null || echo "")
      printf "  %s%s.toolchain%s: %s\n" "$C_DIM" "$lang" "$C_RST" "$cmds"
    fi
  done
fi

# -- Summary
if [ "$JSON_OUT" -eq 1 ]; then
  printf '{"hard_missing":%d,"soft_missing":%d,"strict":%s,"rows":[%s]}\n' \
    "$HARD_MISSING" "$SOFT_MISSING" \
    "$([ "$STRICT" -eq 1 ] && echo true || echo false)" \
    "$(IFS=,; echo "${JSON_ROWS[*]}")"
else
  printf "\n${C_DIM}-----------------------------------------------------------${C_RST}\n"
  if [ "$HARD_MISSING" -gt 0 ]; then
    printf "${C_ERR}✗ %d hard blocker(s) missing — pipeline will not run.${C_RST}\n" "$HARD_MISSING"
  elif [ "$SOFT_MISSING" -gt 0 ]; then
    if [ "$STRICT" -eq 1 ]; then
      printf "${C_ERR}✗ %d soft-degrade tool(s) missing (--strict).${C_RST}\n" "$SOFT_MISSING"
    else
      printf "${C_WARN}⚠ %d soft-degrade tool(s) missing — pipeline will run with reduced gates.${C_RST}\n" "$SOFT_MISSING"
    fi
  else
    printf "${C_OK}✓ All checks passed.${C_RST}\n"
  fi
fi

if [ "$HARD_MISSING" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$SOFT_MISSING" -gt 0 ]; then exit 2; fi
exit 0
