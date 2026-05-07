#!/usr/bin/env bash
# phases: impl
# severity: BLOCKER
# Implementation completeness on Python source.
# Reject: TODO, FIXME, XXX, NotImplementedError, lone `...` placeholders, `pass  # impl`.
# Scan src/ only (tests + examples + docs may legitimately contain these markers).
set -uo pipefail
RUN_DIR="${1:?}"; TARGET="${2:-}"
[ -n "$TARGET" ] || exit 0
SRC="$TARGET/src"
[ -d "$SRC" ] || SRC="$TARGET"

BAD_FILES=""
# String markers
WORD_HITS=$(grep -rlE "TODO|FIXME|XXX|NotImplementedError|HACK" "$SRC" --include="*.py" 2>/dev/null || true)
[ -z "$WORD_HITS" ] || BAD_FILES="$BAD_FILES$WORD_HITS"$'\n'

# `...` lone placeholder body — match a Python function/class with body of exactly `...`
# pattern: `def name(...) -> ...:\n    ...` — flag any function body that is JUST ellipsis
# (Protocol / abstract method bodies are legitimate; production impl bodies are not.)
# Heuristic: a `...` body in a non-Protocol, non-abstract context is a stub.
# This is best-effort; mypy + tests catch the rest.
ELLIPSIS_HITS=$(python3 - "$SRC" <<'PY' || true
import ast, pathlib, sys
root = pathlib.Path(sys.argv[1])
problems = []
for py in root.rglob("*.py"):
    try:
        tree = ast.parse(py.read_text())
    except SyntaxError:
        continue
    # Find functions whose body is exactly `[Expr(Constant(Ellipsis))]`,
    # excluding Protocol methods (parent class includes "Protocol") and
    # @abstractmethod-decorated methods.
    class V(ast.NodeVisitor):
        def __init__(self):
            self.in_protocol = False
            self.in_abstract = False
        def visit_ClassDef(self, node):
            is_protocol = any(
                (isinstance(b, ast.Name) and b.id == "Protocol")
                or (isinstance(b, ast.Subscript) and isinstance(b.value, ast.Name) and b.value.id == "Protocol")
                for b in node.bases
            )
            saved = self.in_protocol
            if is_protocol:
                self.in_protocol = True
            self.generic_visit(node)
            self.in_protocol = saved
        def _check_func(self, node):
            decorators = {d.id if isinstance(d, ast.Name) else getattr(d, "attr", "") for d in node.decorator_list}
            if "abstractmethod" in decorators or "overload" in decorators:
                return
            if self.in_protocol:
                return
            body = node.body
            # Skip docstring; check the rest
            if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) and isinstance(body[0].value.value, str):
                body = body[1:]
            if len(body) == 1 and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) and body[0].value.value is Ellipsis:
                problems.append(f"{py}:{node.lineno}: stub function `{node.name}` (body is `...`)")
        def visit_FunctionDef(self, node):
            self._check_func(node)
            self.generic_visit(node)
        def visit_AsyncFunctionDef(self, node):
            self._check_func(node)
            self.generic_visit(node)
    V().visit(tree)
for p in problems:
    print(p)
sys.exit(1 if problems else 0)
PY
)
[ -z "$ELLIPSIS_HITS" ] || BAD_FILES="$BAD_FILES$ELLIPSIS_HITS"$'\n'

if [ -n "$BAD_FILES" ]; then
  echo "incomplete implementation found:"
  echo "$BAD_FILES"
  exit 1
fi
