#!/usr/bin/env bash
# phases: meta
# severity: LOW
# CLAUDE.md rule numbers contiguous
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$(dirname "$0")/../../CLAUDE.md"
python3 - "$F" <<PY
import re, sys
t=open(sys.argv[1]).read()
nums=[int(m.group(1)) for m in re.finditer(r"^### (\d+)\.", t, re.M)]
if not nums: sys.exit(0)
missing=[i for i in range(min(nums), max(nums)+1) if i not in nums and i!=15]  # 15 is explicitly dropped
if missing: print("missing rules:", missing); sys.exit(1)
PY
