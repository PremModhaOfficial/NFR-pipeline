#!/usr/bin/env bash
# bootstrap.sh — interactive installer for the motadata-sdk-pipeline toolchain.
#
# Detects what's missing, asks for consent per category, installs only what
# the user approves. Pairs with scripts/preflight-check.sh: bootstrap mutates
# the system, preflight only inspects. Re-runs preflight after install.
#
# Categories:
#   1. Infra-tier         (sudo: jq, git, python3, build-essential, netcat)
#   2. Go pack            (go install only — no sudo. Go compiler itself MUST be pre-installed.)
#   3. Python pack        (pip install in venv — detects active venv or prompts to create .venv/)
#   4. Docker             (sudo: docker.io + daemon start) — opt-in
#
# Trigger points:
#   - /sdk-bootstrap slash command
#   - bash scripts/bootstrap.sh (manual)
#   - Suggested by H0 preflight failure message
#
# Usage:
#   bash scripts/bootstrap.sh              # interactive, all categories
#   bash scripts/bootstrap.sh --skip-go    # skip Go pack
#   bash scripts/bootstrap.sh --skip-python
#   bash scripts/bootstrap.sh --with-docker
#   bash scripts/bootstrap.sh --dry-run    # preview, no mutation
#
# Exit codes: 0 = success, 1 = user aborted, 2 = install failed, 3 = config error.

set -o pipefail

PIPELINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$PIPELINE_ROOT/runs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"

SKIP_GO=0
SKIP_PYTHON=0
WITH_DOCKER=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --skip-go) SKIP_GO=1 ;;
    --skip-python) SKIP_PYTHON=1 ;;
    --with-docker) WITH_DOCKER=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; exit 3 ;;
  esac
done

# ---- color + logging helpers
if [ -t 1 ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_ERR=""; C_BOLD=""; C_DIM=""; C_RST=""
fi

log() { printf "%s %s\n" "$(date -Iseconds)" "$*" >> "$LOG_FILE"; }
say() { printf "%s\n" "$*"; log "[stdout] $*"; }
warn() { printf "${C_WARN}%s${C_RST}\n" "$*"; log "[warn] $*"; }
fail() { printf "${C_ERR}%s${C_RST}\n" "$*"; log "[fail] $*"; }

confirm() {
  # confirm "<prompt>" → returns 0 on y/Y, 1 otherwise. Default no.
  local prompt="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf "  ${C_DIM}[dry-run] would prompt: %s${C_RST}\n" "$prompt"
    return 1
  fi
  read -r -p "  $prompt [y/N]: " ans
  case "$ans" in [yY]|[yY][eE][sS]) log "[confirm-yes] $prompt"; return 0 ;; *) log "[confirm-no] $prompt"; return 1 ;; esac
}

run_cmd() {
  # run_cmd "<description>" "<shell command>"
  local desc="$1" cmd="$2"
  log "[exec] $desc :: $cmd"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf "  ${C_DIM}[dry-run] %s${C_RST}\n" "$cmd"
    return 0
  fi
  printf "  ${C_DIM}\$ %s${C_RST}\n" "$cmd"
  if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
    return 0
  else
    fail "  ✗ $desc failed (see $LOG_FILE)"
    return 1
  fi
}

# ---- OS detection
detect_os() {
  case "$(uname -s)" in
    Linux*)
      if command -v apt-get >/dev/null 2>&1; then echo "linux-apt"
      elif command -v dnf >/dev/null 2>&1; then echo "linux-dnf"
      elif command -v pacman >/dev/null 2>&1; then echo "linux-pacman"
      else echo "linux-unknown"; fi ;;
    Darwin*)
      if command -v brew >/dev/null 2>&1; then echo "macos-brew"
      else echo "macos-no-brew"; fi ;;
    *) echo "unsupported" ;;
  esac
}

OS=$(detect_os)
log "[detect] OS=$OS"

printf "${C_BOLD}== motadata-sdk-pipeline bootstrap ==${C_RST}\n"
printf "OS detected: ${C_BOLD}%s${C_RST}    log: %s\n\n" "$OS" "$LOG_FILE"

if [ "$DRY_RUN" -eq 1 ]; then
  warn "DRY-RUN mode — no changes will be made."
fi

# ---- 1. Infra-tier
section_infra() {
  printf "${C_BOLD}[1/4] Infra-tier${C_RST} (sudo apt/brew packages)\n"

  local missing=()
  for tool in jq git python3 sha256sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then missing+=("$tool"); fi
  done
  if ! command -v gcc >/dev/null 2>&1; then missing+=("build-essential"); fi
  if [ "$WITH_DOCKER" -eq 1 ] && ! command -v nc >/dev/null 2>&1; then missing+=("netcat-openbsd"); fi

  if [ "${#missing[@]}" -eq 0 ]; then
    printf "  ${C_OK}✓ All infra tools present.${C_RST}\n\n"; return 0
  fi

  printf "  Missing: ${C_WARN}%s${C_RST}\n" "${missing[*]}"

  case "$OS" in
    linux-apt)
      local pkgs="${missing[*]}"
      pkgs="${pkgs//build-essential/build-essential}"
      pkgs="${pkgs//python3/python3 python3-venv python3-pip}"
      if confirm "Install via 'sudo apt install ${pkgs}'?"; then
        run_cmd "apt update" "sudo apt update" || return 2
        run_cmd "apt install $pkgs" "sudo apt install -y $pkgs" || return 2
      else say "  Skipped infra install."; fi ;;
    linux-dnf)
      if confirm "Install via 'sudo dnf install ${missing[*]}'?"; then
        run_cmd "dnf install" "sudo dnf install -y ${missing[*]}" || return 2
      else say "  Skipped infra install."; fi ;;
    linux-pacman)
      if confirm "Install via 'sudo pacman -S ${missing[*]}'?"; then
        run_cmd "pacman -S" "sudo pacman -S --noconfirm ${missing[*]}" || return 2
      else say "  Skipped infra install."; fi ;;
    macos-brew)
      local brew_pkgs="${missing[*]}"
      brew_pkgs="${brew_pkgs//build-essential/}"  # macOS uses Xcode CLT for compilers
      brew_pkgs="${brew_pkgs//netcat-openbsd/netcat}"
      if confirm "Install via 'brew install ${brew_pkgs}'?"; then
        run_cmd "brew install" "brew install $brew_pkgs" || return 2
      else say "  Skipped infra install."; fi ;;
    *)
      warn "  Unsupported OS for auto-install. Install manually:"
      printf "    %s\n" "${missing[*]}" ;;
  esac
  echo
}

# ---- 2. Go pack
section_go() {
  if [ "$SKIP_GO" -eq 1 ]; then return 0; fi
  printf "${C_BOLD}[2/4] Go pack${C_RST} (go install — no sudo)\n"

  if ! command -v go >/dev/null 2>&1; then
    warn "  Go compiler not found. Install Go 1.26+ from https://go.dev/dl before re-running."
    warn "  (Bootstrap does not auto-install Go itself — tarball install is opinionated.)"
    echo; return 0
  fi

  # Verify Go version meets manifest minimum.
  local go_ver
  go_ver=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//')
  if [ -n "$go_ver" ]; then
    local major minor
    major=$(echo "$go_ver" | cut -d. -f1)
    minor=$(echo "$go_ver" | cut -d. -f2)
    if [ "$major" -lt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -lt 26 ]; }; then
      warn "  Installed Go is $go_ver — manifest requires 1.26+. Upgrade before running pipeline."
    fi
  fi

  declare -A go_tools=(
    ["golangci-lint"]="github.com/golangci/golangci-lint/cmd/golangci-lint@latest"
    ["staticcheck"]="honnef.co/go/tools/cmd/staticcheck@latest"
    ["govulncheck"]="golang.org/x/vuln/cmd/govulncheck@latest"
    ["osv-scanner"]="github.com/google/osv-scanner/cmd/osv-scanner@latest"
    ["benchstat"]="golang.org/x/perf/cmd/benchstat@latest"
  )

  local missing=()
  for tool in "${!go_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then missing+=("$tool"); fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    printf "  ${C_OK}✓ All Go tools present.${C_RST}\n\n"; return 0
  fi

  printf "  Missing: ${C_WARN}%s${C_RST}\n" "${missing[*]}"
  if confirm "Install all ${#missing[@]} via 'go install ...@latest'?"; then
    for tool in "${missing[@]}"; do
      run_cmd "go install $tool" "go install ${go_tools[$tool]}" || true
    done
    say "  Ensure \$(go env GOPATH)/bin is on your PATH."
    local gopath_bin
    gopath_bin=$(go env GOPATH 2>/dev/null)/bin
    if [ -n "$gopath_bin" ] && ! echo ":$PATH:" | grep -q ":$gopath_bin:"; then
      warn "  PATH does not contain $gopath_bin — add to your shell rc:"
      printf "    ${C_DIM}export PATH=\"\$PATH:%s\"${C_RST}\n" "$gopath_bin"
    fi
  else say "  Skipped Go pack."; fi
  echo
}

# ---- 3. Python pack
section_python() {
  if [ "$SKIP_PYTHON" -eq 1 ]; then return 0; fi
  printf "${C_BOLD}[3/4] Python pack${C_RST} (pip install in venv)\n"

  local PY=""
  if command -v python3 >/dev/null 2>&1; then PY=python3
  elif command -v python >/dev/null 2>&1; then PY=python
  else
    warn "  Neither python nor python3 on PATH. Re-run after infra-tier installs python3."
    echo; return 0
  fi

  # Verify Python ≥3.12.
  local py_ver
  py_ver=$("$PY" -c 'import sys;print(f"{sys.version_info[0]}.{sys.version_info[1]}")' 2>/dev/null)
  if [ -n "$py_ver" ]; then
    local pmaj pmin
    pmaj=$(echo "$py_ver" | cut -d. -f1)
    pmin=$(echo "$py_ver" | cut -d. -f2)
    if [ "$pmaj" -lt 3 ] || { [ "$pmaj" -eq 3 ] && [ "$pmin" -lt 12 ]; }; then
      warn "  Python $py_ver — manifest requires 3.12+. Upgrade before running Python pipeline."
    fi
  fi

  # Detect venv: $VIRTUAL_ENV is the canonical signal.
  local venv_path=""
  if [ -n "${VIRTUAL_ENV:-}" ]; then
    venv_path="$VIRTUAL_ENV"
    say "  Active venv detected: $venv_path"
  elif [ -d "$PIPELINE_ROOT/.venv" ]; then
    say "  .venv/ exists at $PIPELINE_ROOT/.venv but is not active."
    if confirm "Activate it for this install?"; then
      # shellcheck disable=SC1091
      source "$PIPELINE_ROOT/.venv/bin/activate"
      venv_path="$PIPELINE_ROOT/.venv"
    fi
  else
    if confirm "No venv active. Create $PIPELINE_ROOT/.venv/?"; then
      run_cmd "create venv" "$PY -m venv $PIPELINE_ROOT/.venv" || return 2
      # shellcheck disable=SC1091
      source "$PIPELINE_ROOT/.venv/bin/activate"
      venv_path="$PIPELINE_ROOT/.venv"
    fi
  fi

  if [ -z "$venv_path" ]; then
    warn "  No venv chosen — skipping Python pack to avoid global pollution."
    say  "  Re-run after activating a venv: 'source <path>/bin/activate'"
    echo; return 0
  fi

  local pip_pkgs=(pytest pytest-asyncio pytest-benchmark pytest-cov pytest-repeat \
                  ruff mypy pip-audit safety build pyyaml py-spy)

  # Filter out already-present.
  local to_install=()
  for pkg in "${pip_pkgs[@]}"; do
    local mod="${pkg//-/_}"
    if ! python -c "import $mod" 2>/dev/null && ! command -v "$pkg" >/dev/null 2>&1; then
      to_install+=("$pkg")
    fi
  done

  if [ "${#to_install[@]}" -eq 0 ]; then
    printf "  ${C_OK}✓ All Python deps present in venv.${C_RST}\n\n"; return 0
  fi

  printf "  Missing: ${C_WARN}%s${C_RST}\n" "${to_install[*]}"
  if confirm "pip install ${#to_install[@]} package(s) into $venv_path?"; then
    run_cmd "pip install" "pip install --upgrade pip" || true
    run_cmd "pip install pkgs" "pip install ${to_install[*]}" || return 2
  else say "  Skipped Python pack."; fi
  echo
}

# ---- 4. Docker (opt-in)
section_docker() {
  if [ "$WITH_DOCKER" -eq 0 ]; then return 0; fi
  printf "${C_BOLD}[4/4] Docker${C_RST} (sudo apt + daemon start)\n"

  if ! command -v docker >/dev/null 2>&1; then
    case "$OS" in
      linux-apt)
        if confirm "Install Docker via 'sudo apt install docker.io docker-compose-plugin'?"; then
          run_cmd "apt install docker" "sudo apt install -y docker.io docker-compose-plugin" || return 2
        else say "  Skipped Docker install."; fi ;;
      macos-brew)
        if confirm "Install Docker Desktop via 'brew install --cask docker'?"; then
          run_cmd "brew install docker" "brew install --cask docker" || return 2
        else say "  Skipped Docker install."; fi ;;
      *) warn "  Auto-install not supported for OS=$OS. Install Docker manually." ;;
    esac
  else
    printf "  ${C_OK}✓ docker present.${C_RST}\n"
  fi

  # Daemon status
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      printf "  ${C_OK}✓ docker daemon reachable.${C_RST}\n"
    else
      warn "  docker daemon not reachable."
      if [ "$OS" = "linux-apt" ] || [ "$OS" = "linux-dnf" ] || [ "$OS" = "linux-pacman" ]; then
        if confirm "Start daemon via 'sudo systemctl start docker' + add user to docker group?"; then
          run_cmd "start docker" "sudo systemctl start docker" || return 2
          run_cmd "enable docker" "sudo systemctl enable docker" || true
          run_cmd "usermod" "sudo usermod -aG docker $USER" || true
          warn "  Group change requires re-login (or 'newgrp docker') to take effect."
        fi
      else
        warn "  Start Docker Desktop manually."
      fi
    fi
  fi
  echo
}

# ---- Run sections
section_infra
section_go
section_python
section_docker

# ---- Re-run preflight to verify
printf "${C_BOLD}== Re-running preflight ==${C_RST}\n\n"
LANG_ARG="--lang=both"
[ "$SKIP_GO" -eq 1 ] && LANG_ARG="--lang=python"
[ "$SKIP_PYTHON" -eq 1 ] && LANG_ARG="--lang=go"
DOCKER_ARG=""
[ "$WITH_DOCKER" -eq 1 ] && DOCKER_ARG="--with-docker"

if [ "$DRY_RUN" -eq 1 ]; then
  printf "${C_DIM}[dry-run] would run: bash scripts/preflight-check.sh %s %s${C_RST}\n" "$LANG_ARG" "$DOCKER_ARG"
  exit 0
fi

if bash "$PIPELINE_ROOT/scripts/preflight-check.sh" "$LANG_ARG" "$DOCKER_ARG"; then
  printf "\n${C_OK}${C_BOLD}✓ Bootstrap complete — preflight green.${C_RST}\n"
  log "[done] preflight green"
  exit 0
else
  rc=$?
  printf "\n${C_WARN}⚠ Bootstrap finished but preflight reports remaining issues (exit %d).${C_RST}\n" "$rc"
  printf "  Audit log: %s\n" "$LOG_FILE"
  log "[done] preflight rc=$rc"
  exit 2
fi
