# Prerequisites

Tools required to run the `motadata-sdk-pipeline` end-to-end.

> **TL;DR** — Run `/sdk-bootstrap` (or `bash scripts/bootstrap.sh`) once after plugin install. It detects what's missing, prompts per category, and installs only what you approve. Then `bash scripts/preflight-check.sh` verifies the result. The runtime pipeline re-runs preflight at H0 and Wave I5.5, so drift is caught before phase 0 burns tokens.

The toolchain splits three ways: **infra-tier** (always needed), **language pack** (Go OR Python depending on TPRD `§Target-Language`), and **conditional** (Docker for integration tests, MCP servers for graceful-degrade enhancements).

The authoritative per-language toolchain lives in `.claude/package-manifests/<lang>.json` under the `toolchain` block. This document mirrors it for human onboarding; manifests win on conflict.

---

## A. Infra-tier (always required)

| Tool | Min version | Install (Linux apt) | Install (macOS brew) | Used by |
|------|-------------|---------------------|----------------------|---------|
| `bash` | 4.0+ | system default | `brew install bash` | every script |
| `git` | 2.40+ | `apt install git` | `brew install git` | Rule 21 (target-dir = git repo); pipeline branch isolation |
| `jq` | latest | `apt install jq` | `brew install jq` | `run-toolchain.sh`, `run-guardrails.sh`, G05/G06/G85/G86/G87, baseline-manager |
| `python3` | 3.10+ | `apt install python3 python3-venv` | bundled | guardrail `*.sh` heredocs (PyYAML imports), `scripts/migrate-jsonl-to-neo4j.py`, AST-hash backend |
| coreutils | any | `apt install coreutils` | bundled | `grep`, `sed`, `awk`, `sort`, `find`, `sha256sum`, `mktemp` across all guardrails |
| Claude Code CLI | matches `pipeline_version` in `.claude/settings.json` (currently `0.7.0`) | https://docs.claude.com/en/docs/claude-code | same | harness — auto-discovers agents/skills/guardrails |

`gcc` / `build-essential` is required only when running Go race detector or testcontainers (Linux: `apt install build-essential`; macOS: ships with Xcode CLT).

---

## B. Go pack — required when `target_language: go`

Source of truth: `.claude/package-manifests/go.json` → `toolchain`.

| Tool | Min version | Install | Severity | Used by |
|------|-------------|---------|----------|---------|
| `go` | 1.26+ | https://go.dev/dl | HARD BLOCK | every Go guardrail; `toolchain.{build,test,vet,fmt,coverage,bench}` |
| `gofmt` | bundled with `go` | — | HARD BLOCK | `toolchain.fmt` |
| `go vet` | bundled with `go` | — | HARD BLOCK | `toolchain.vet` |
| `pprof` | bundled (`go tool pprof`) | — | HARD BLOCK | profile-auditor-go (G109), benchmark-devil-go |
| `golangci-lint` | latest | `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest` | soft (downgrades to MEDIUM) | `toolchain.lint` |
| `staticcheck` | latest | `go install honnef.co/go/tools/cmd/staticcheck@latest` | soft | G44 |
| `govulncheck` | latest | `go install golang.org/x/vuln/cmd/govulncheck@latest` | soft (G32 fails) | `toolchain.supply_chain[0]`, dep-vet-devil-go |
| `osv-scanner` | latest | `go install github.com/google/osv-scanner/cmd/osv-scanner@latest` | soft (G33 fails) | `toolchain.supply_chain[1]` |
| `benchstat` | latest | `go install golang.org/x/perf/cmd/benchstat@latest` | soft (raw-diff fallback) | benchmark-devil-go, perf delta analysis |
| `goleak` | lib (imported in tests) | `go get go.uber.org/goleak` | soft | `toolchain.leak_check` (`goleak.VerifyTestMain`) |

After `go install`, ensure `$(go env GOPATH)/bin` is on `$PATH`.

---

## C. Python pack — required when `target_language: python`

Source of truth: `.claude/package-manifests/python.json` → `toolchain`.

| Tool | Min version | Install | Severity | Used by |
|------|-------------|---------|----------|---------|
| `python` | 3.12+ | https://www.python.org/downloads | HARD BLOCK | every Python guardrail |
| `pip` | latest | bundled with Python | HARD BLOCK | dependency installs |
| `pytest` | 8+ | `pip install pytest` | HARD BLOCK | `toolchain.test` |
| `pytest-asyncio` | latest | `pip install pytest-asyncio` | soft | async test discovery |
| `pytest-benchmark` | latest | `pip install pytest-benchmark` | soft | `toolchain.bench` |
| `pytest-cov` | latest | `pip install pytest-cov` | soft (coverage gate fails) | `toolchain.coverage` |
| `pytest-repeat` | latest | `pip install pytest-repeat` | HARD BLOCK (G63-py) | flake-hunter-python |
| `ruff` | latest | `pip install ruff` | soft (G43-py / G44-py fail) | `toolchain.lint`, `toolchain.fmt` |
| `mypy` | 1.0+ | `pip install mypy` | soft (G42-py fails) | `toolchain.vet` (`--strict`) |
| `pip-audit` | latest | `pip install pip-audit` | soft (G32-py fails) | `toolchain.supply_chain[0]` |
| `safety` | latest | `pip install safety` | soft (G33-py fails) | `toolchain.supply_chain[1]` |
| `build` | latest | `pip install build` | soft | `toolchain.build` (`python -m build`) |
| `pyyaml` | latest | `pip install pyyaml` | soft (JSON fallback) | guardrails reading `perf-config.yaml` |
| `py-spy` | latest | `pip install py-spy` | soft (profiling skipped) | profile-auditor-python (G109-py) |

Install all in one shot:

```bash
pip install pytest pytest-asyncio pytest-benchmark pytest-cov pytest-repeat ruff mypy pip-audit safety build pyyaml py-spy
```

---

## D. Conditional — install when condition holds

| Tool | Condition | Install | Used by |
|------|-----------|---------|---------|
| `docker` ≥20.10 | SDK client uses testcontainers (touches Postgres / NATS / Redis / Kafka / MinIO / LocalStack / Dragonfly / RabbitMQ) | `apt install docker.io` / `brew install --cask docker` | testcontainers-go, testcontainers-python, integration tests in Phase 3 |
| `docker compose` | multi-container integration tests | `apt install docker-compose-plugin` | same |
| `nc` (netcat) | Neo4j MCP TCP probe fallback | `apt install netcat-openbsd` | G04 |
| Node.js ≥18 + `npx` | `mcp__context7` enabled | `apt install nodejs npm` | design-phase library docs |
| `uv` / `uvx` | `mcp__neo4j-memory` enabled | `pip install uv` | feedback knowledge graph |
| Neo4j daemon | `mcp__neo4j-memory` or `mcp__code-graph` enabled | `docker run -d --name claude-neo4j -e NEO4J_AUTH=none -p 7687:7687 neo4j:latest` | knowledge graph storage |

Pure in-memory clients (no I/O — e.g. resource-pool, circuit-breaker, ring-buffer) skip the Docker dependency entirely.

---

## E. Optional MCP servers (graceful-degrade per Rule 31)

These are enhancements, **not** correctness dependencies. `G04.sh` writes a verdict to `runs/<id>/<phase>/mcp-health.md`; pipeline never halts on MCP failure.

| MCP | Activation | Fallback when missing |
|-----|------------|-----------------------|
| `mcp__context7` | `npx -y @upstash/context7-mcp` | in-repo docs + agent training cutoff |
| `mcp__neo4j-memory` | `uvx mcp-neo4j-memory@0.4.5` (needs Neo4j daemon) | JSONL writes under `evolution/knowledge-base/` |
| `mcp__code-graph` | `cgc mcp start` (needs Neo4j) | static `grep` + AST call-graph |
| `mcp__serena` | `serena start-mcp-server` | `grep` symbol extraction |

---

## Install snapshots — one-shot per environment

### Linux (Debian/Ubuntu) — Go pilot, no integration tests

```bash
sudo apt update && sudo apt install -y bash git jq python3 python3-venv coreutils build-essential netcat-openbsd
# Go 1.26 from https://go.dev/dl (apt repos lag); then:
export PATH=$PATH:$(go env GOPATH)/bin
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
go install honnef.co/go/tools/cmd/staticcheck@latest
go install golang.org/x/vuln/cmd/govulncheck@latest
go install github.com/google/osv-scanner/cmd/osv-scanner@latest
go install golang.org/x/perf/cmd/benchstat@latest
```

### Linux — Python pilot, no integration tests

```bash
sudo apt update && sudo apt install -y bash git jq python3.12 python3.12-venv coreutils
python3.12 -m venv .venv && source .venv/bin/activate
pip install pytest pytest-asyncio pytest-benchmark pytest-cov pytest-repeat ruff mypy pip-audit safety build pyyaml py-spy
```

### Add Docker (when integration tests use testcontainers)

```bash
sudo apt install -y docker.io docker-compose-plugin
sudo usermod -aG docker $USER && newgrp docker
docker run hello-world  # verify
```

---

## Verification

```bash
bash scripts/preflight-check.sh          # auto-detects active language; reports pass/fail
bash scripts/preflight-check.sh --lang=go
bash scripts/preflight-check.sh --lang=python
bash scripts/preflight-check.sh --strict # fail on soft-degrade misses too
```

Exit codes: `0` = green, `1` = hard blocker missing, `2` = soft degrade missing (only with `--strict`), `3` = config error.

## Where preflight runs in the pipeline

Two checkpoints, both BLOCKER on HARD miss:

1. **H0** (`commands/run-sdk-addition.md` step 4) — runs `preflight-check.sh --infra-only` before phase 0 starts. `target_language` not yet resolved, so only the infra-tier is checked. HARD miss → pipeline exit 7.
2. **Wave I5.5** (`agents/sdk-intake-agent.md`) — after `active-packages.json` lands, re-runs `preflight-check.sh --lang=<resolved> --json` and writes the report to `runs/<run-id>/intake/preflight-language.json`. HARD miss → exit 7.

Both checkpoints share the same script + exit-code semantics — install once, re-run pipeline, both checkpoints pass.
