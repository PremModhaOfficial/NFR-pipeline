#!/usr/bin/env bash
# phases: intake feedback meta
# severity: WARN
# MCP health-check: neo4j-memory reachability (bolt://localhost:7687). Non-blocking.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"

# Decide report location based on existing run-dir layout. Prefer intake dir at
# run start; fall back to feedback dir when feedback phase has begun; else meta.
if [ -d "$RUN_DIR/feedback" ]; then
  REPORT_DIR="$RUN_DIR/feedback"
elif [ -d "$RUN_DIR/intake" ]; then
  REPORT_DIR="$RUN_DIR/intake"
else
  REPORT_DIR="$RUN_DIR"
fi
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/mcp-health.md"

neo4j_up=0

# Preferred probe: docker container named claude-neo4j is Up.
if command -v docker >/dev/null 2>&1; then
  status="$(docker ps --filter name=claude-neo4j --format '{{.Status}}' 2>/dev/null || true)"
  case "$status" in
    *Up*) neo4j_up=1 ;;
  esac
fi

# Fallback probe: raw TCP reach on bolt port.
if [ "$neo4j_up" -eq 0 ] && command -v nc >/dev/null 2>&1; then
  if nc -z localhost 7687 >/dev/null 2>&1; then
    neo4j_up=1
  fi
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ "$neo4j_up" -eq 1 ]; then
  {
    echo "# MCP health: OK"
    echo ""
    echo "- timestamp: $TS"
    echo "- neo4j-memory: reachable (bolt://localhost:7687)"
    echo "- cross-run knowledge-graph features: ENABLED"
  } > "$REPORT"
  exit 0
fi

{
  echo "# MCP health: WARN"
  echo ""
  echo "- timestamp: $TS"
  echo "- neo4j-memory: UNREACHABLE (bolt://localhost:7687)"
  echo "- cross-run knowledge-graph features: DISABLED this run"
  echo "- fallback: JSONL source of truth remains authoritative"
  echo ""
  echo "To restore: \`docker start claude-neo4j\` (see CLAUDE.md global §Neo4j Local Instance)."
} > "$REPORT"

echo "WARN: neo4j unreachable; cross-run knowledge-graph features disabled this run — JSONL fallback active"
exit 0
