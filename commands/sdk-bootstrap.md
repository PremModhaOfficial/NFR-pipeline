---
name: sdk-bootstrap
description: Interactive installer for the motadata-sdk-pipeline toolchain. Detects what's already on the device, asks consent per category, installs only what the user approves. Pairs with /preflight-check (detection-only). Run once after plugin install, and any time the runtime preflight (H0 / Wave I5.5) reports HARD blockers.
user-invocable: true
---

# /sdk-bootstrap

Interactive bootstrap for the pipeline toolchain. Mutates the local environment **only** with user consent — never silently installs.

## What it does

Walks four categories, skipping anything already installed:

1. **Infra-tier** — `jq`, `git`, `python3`, `build-essential`, `sha256sum`. Sudo prompt per OS package manager (apt / dnf / pacman / brew).
2. **Go pack** — `golangci-lint`, `staticcheck`, `govulncheck`, `osv-scanner`, `benchstat`. No sudo (`go install` only). Go compiler itself is NOT auto-installed (tarball install too opinionated) — bootstrap warns and points at https://go.dev/dl if missing or below 1.26.
3. **Python pack** — `pytest`, `pytest-asyncio`, `pytest-benchmark`, `pytest-cov`, `pytest-repeat`, `ruff`, `mypy`, `pip-audit`, `safety`, `build`, `pyyaml`, `py-spy`. Detects `$VIRTUAL_ENV`; if absent, prompts to create `.venv/`. Refuses to pollute the global Python env.
4. **Docker** (opt-in via `--with-docker`) — `docker.io` + `docker-compose-plugin`, daemon start, user-group add. Required only when integration tests use testcontainers.

Re-runs `bash scripts/preflight-check.sh` at the end and reports green / remaining gaps.

## Arguments

| Flag | Default | Description |
|------|---------|-------------|
| `--skip-go` | false | Skip the Go pack section (Python-only environments) |
| `--skip-python` | false | Skip the Python pack section (Go-only environments) |
| `--with-docker` | false | Include Docker install + daemon start |
| `--dry-run` | false | Print what would be installed; make no changes |

## Examples

```
/sdk-bootstrap                           # full interactive bootstrap
/sdk-bootstrap --skip-go                 # Python pilot environment
/sdk-bootstrap --with-docker             # include integration-test runtime
/sdk-bootstrap --dry-run --with-docker   # preview the full plan
```

## Audit log

Every action (prompt, command exec, exit code) appends to `runs/bootstrap-<timestamp>.log` for diagnosis.

## Exit codes

- `0` — bootstrap finished and preflight is green
- `1` — user aborted at a prompt
- `2` — at least one install command failed; see audit log
- `3` — config error (unknown flag, etc.)

## When to run

- **First time after plugin install** — run once before `/run-sdk-addition`
- **After `/run-sdk-addition` exit 7** — preflight at H0 or Wave I5.5 detected a HARD-blocker miss
- **After environment drift** — `apt autoremove` / venv reset / fresh dev container

## Implementation

This command is a thin wrapper around `bash scripts/bootstrap.sh`. The script is the source of truth; this file documents the slash-command interface.
