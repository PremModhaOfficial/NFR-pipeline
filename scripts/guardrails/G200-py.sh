#!/usr/bin/env bash
# phases: design impl
# severity: BLOCKER
# pyproject.toml conforms to PEP 517/518/621/639 + py.typed marker is present.
# Python pack distribution-metadata gate. No counterpart in flat module systems.
#
# Checks:
#   1. pyproject.toml exists and parses as TOML.
#   2. [build-system] has both `requires` and `build-backend`.
#   3. [project] has required fields: name, version (or dynamic), description,
#      requires-python, license, readme, authors|maintainers.
#   4. requires-python floor is >= 3.12 (Python pack default).
#   5. License classifier is in the allowlist (per python-dependency-vetting skill).
#   6. py.typed marker file exists at src/<distribution>/py.typed (PEP 561).
#   7. No legacy setup.py / setup.cfg as primary metadata source.
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0

PYPROJECT="$TARGET/pyproject.toml"
[ -f "$PYPROJECT" ] || { echo "pyproject.toml missing at $TARGET"; exit 1; }

# Forbid legacy setup.py as primary metadata source
if [ -f "$TARGET/setup.py" ]; then
  if ! grep -q "from setuptools import setup; setup()" "$TARGET/setup.py" 2>/dev/null; then
    echo "setup.py present and non-trivial — Python pack requires pyproject.toml as the sole metadata source"
    exit 1
  fi
fi

python3 - "$PYPROJECT" "$TARGET" <<'PY' || exit 1
import sys, tomllib, pathlib

pyproject_path, target = sys.argv[1:3]
target_path = pathlib.Path(target)

ALLOWED_LICENSE_FRAGMENTS = (
    "MIT", "Apache", "BSD", "ISC", "0BSD", "MPL", "Python-2.0",
    "Unlicense", "CC0",
)

errors: list[str] = []

try:
    with open(pyproject_path, "rb") as fh:
        cfg = tomllib.load(fh)
except (OSError, tomllib.TOMLDecodeError) as e:
    print(f"pyproject.toml unparseable: {e}")
    sys.exit(1)

# 1. [build-system]
build_sys = cfg.get("build-system", {})
if not build_sys:
    errors.append("[build-system] table missing (PEP 518)")
else:
    if not build_sys.get("requires"):
        errors.append("[build-system].requires missing")
    if not build_sys.get("build-backend"):
        errors.append("[build-system].build-backend missing")

# 2. [project]
proj = cfg.get("project")
if proj is None:
    errors.append("[project] table missing (PEP 621)")
else:
    required = ["name", "description", "requires-python", "readme"]
    for k in required:
        if not proj.get(k):
            errors.append(f"[project].{k} missing or empty")
    # version OR dynamic = ['version']
    if not proj.get("version"):
        if "version" not in (proj.get("dynamic") or []):
            errors.append("[project].version missing (and not declared dynamic)")
    # authors / maintainers
    if not (proj.get("authors") or proj.get("maintainers")):
        errors.append("[project].authors or [project].maintainers required")
    # license (PEP 639 form OR legacy form)
    license_field = proj.get("license")
    license_text = ""
    if isinstance(license_field, str):
        license_text = license_field
    elif isinstance(license_field, dict):
        license_text = license_field.get("text", "") or license_field.get("file", "")
    classifiers = proj.get("classifiers") or []
    classifier_license = next(
        (c for c in classifiers if c.startswith("License :: ")), ""
    )
    license_repr = license_text or classifier_license
    if not license_repr:
        errors.append("[project].license missing (PEP 621 / PEP 639) and no License classifier")
    else:
        if not any(frag.lower() in license_repr.lower() for frag in ALLOWED_LICENSE_FRAGMENTS):
            errors.append(f"license `{license_repr}` not in Python-pack allowlist")

    # requires-python floor
    rp = proj.get("requires-python", "")
    # Accept >=3.12 or >=3.13 etc. Extract the floor
    import re
    m = re.search(r">=\s*(\d+\.\d+)", rp)
    if m:
        major, minor = m.group(1).split(".")
        if (int(major), int(minor)) < (3, 12):
            errors.append(f"requires-python floor is {rp} — Python pack default is >=3.12")
    else:
        errors.append(f"requires-python `{rp}` does not declare a >= floor")

# 3. py.typed marker (PEP 561)
import_name = (proj or {}).get("name", "").replace("-", "_") if proj else ""
if not import_name:
    errors.append("cannot determine import package name from [project].name")
else:
    py_typed_candidates = [
        target_path / "src" / import_name / "py.typed",
        target_path / import_name / "py.typed",
    ]
    if not any(p.exists() for p in py_typed_candidates):
        errors.append(
            f"py.typed marker missing — expected at one of {[str(p) for p in py_typed_candidates]}"
        )

if errors:
    print("pyproject.toml / packaging issues:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)

print("pyproject.toml + py.typed: OK")
PY
