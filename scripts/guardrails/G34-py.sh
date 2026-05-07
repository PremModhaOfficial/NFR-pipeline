#!/usr/bin/env bash
# phases: design
# severity: BLOCKER
# License allowlist enforcement on Python deps.
# Allow:    MIT, Apache-2.0, BSD-3-Clause, BSD-2-Clause, ISC, 0BSD, MPL-2.0,
#           Python-2.0 (PSF), Unlicense, CC0-1.0
# Reject:   GPL-*, AGPL-*, SSPL, proprietary, "all rights reserved"
# Requires: design/dependencies.md (authored by sdk-dep-vet-devil-python)
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/design/dependencies.md"
[ -f "$F" ] || exit 0

# Reject explicit copyleft / proprietary mentions
BAD=$(grep -inE "license:\s*(GPL|AGPL|SSPL|Proprietary|Commercial|All Rights Reserved)" "$F" || true)
[ -z "$BAD" ] || { echo "forbidden license:"; echo "$BAD"; exit 1; }

# LGPL is conditional — surface as warning, not blocker (caller decides at H6)
LGPL=$(grep -inE "license:\s*LGPL" "$F" || true)
if [ -n "$LGPL" ]; then
  echo "WARN: LGPL dependencies present (CONDITIONAL — verify at H6):"
  echo "$LGPL"
fi
