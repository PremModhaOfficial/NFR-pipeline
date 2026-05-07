#!/usr/bin/env bash
# phases: design
# severity: BLOCKER
# Every proposed Python runtime / dev dependency in pyproject.toml is documented in dependencies.md.
# Python pack equivalent of dependency-list documentation enforcement.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
F="$RUN_DIR/design/dependencies.md"
[ -f "$F" ] || { echo "design/dependencies.md missing"; exit 1; }
[ -s "$F" ] || { echo "design/dependencies.md empty"; exit 1; }
# Sanity: every dep in pyproject.toml [project] dependencies must appear in the doc
if [ -n "$TARGET" ] && [ -f "$TARGET/pyproject.toml" ]; then
  python3 - "$TARGET/pyproject.toml" "$F" <<'PY' || exit 1
import sys, re, tomllib
pyproject_path, doc_path = sys.argv[1:3]
with open(pyproject_path, "rb") as fh:
    cfg = tomllib.load(fh)
deps = []
for d in cfg.get("project", {}).get("dependencies", []) or []:
    name = re.split(r"[<>=!~\[\s]", d, maxsplit=1)[0].strip().lower()
    if name:
        deps.append(name)
for group, items in (cfg.get("project", {}).get("optional-dependencies", {}) or {}).items():
    for d in items or []:
        name = re.split(r"[<>=!~\[\s]", d, maxsplit=1)[0].strip().lower()
        if name:
            deps.append(name)
doc = open(doc_path).read().lower()
missing = [d for d in deps if d not in doc]
if missing:
    print(f"deps in pyproject.toml not documented in design/dependencies.md: {sorted(set(missing))}")
    sys.exit(1)
PY
fi
