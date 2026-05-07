#!/usr/bin/env bash
# phases: design
# severity: BLOCKER
# api.go.stub compiles (toolchain.build via run-toolchain.sh)
#
# NOTE: this guardrail is Go-pack today (api.go.stub naming, `go mod init`
# scaffolding are Go-specific). Step 13 (Go-leakage refactor) may split it
# into G30-go and G30-python with language-native stub harnesses.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/design/api.go.stub"
[ -f "$F" ] || { echo "api.go.stub missing"; exit 1; }
PIPELINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export ACTIVE_PACKAGES_JSON="$RUN_DIR/context/active-packages.json"
TMP=$(mktemp -d)
cp "$F" "$TMP/api.go"
cd "$TMP" && go mod init stubcheck >/dev/null 2>&1 || true
bash "$PIPELINE_ROOT/scripts/run-toolchain.sh" build 2>&1 || { echo "compile fail"; exit 1; }
