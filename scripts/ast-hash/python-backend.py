#!/usr/bin/env python3
"""python-backend — Python AST hasher for the motadata-sdk-pipeline marker protocol.

Computes a canonical SHA256 over a named symbol's AST subtree. Sibling of
go-backend.go; same contract, same exit codes, same hash semantics for the
properties that map across languages.

Usage:
    python-backend.py <file> <symbol>
    python-backend.py path/to/client.py 'Client.get'

Symbol name syntax (mirrors go-backend):
    foo         — top-level function or class named foo
    T.foo       — method foo on class T (instance / class / static — uniform)
    T           — class T (bare)

Output: <sha256 hex> on success to stdout; exits 0.
On error: message on stderr; non-zero exit.

Exit codes (deliberate alignment with go-backend):
    0  success
    2  usage error
    3  parse error
    4  symbol not found
    5  internal error (canonicalization failure)

Canonicalization decisions (the four cross-language questions answered):

  1. Docstrings — STRIPPED. The first statement of a function/class/module
     body that is a bare string Expr is removed before hashing. This matches
     Go's invariance under godoc edits: doc-only changes don't trip the
     marker hash. Guardrail-marker-hygiene-devil is the right place to catch
     missing-doc regressions, not the AST hasher.

  2. Type hints / annotations — INCLUDED. `def f(x: int) -> str` and
     `def f(x)` produce different ASTs because the annotation is part of
     `arg.annotation`. Changing a type annotation is a behavioral change
     worth flagging.

  3. Decorators — INCLUDED. `@retry(3)` is part of `FunctionDef.decorator_list`.
     Decorator order is preserved in the AST and is part of the hash —
     `@retry @cache` and `@cache @retry` correctly hash differently.

  4. async vs sync — KEPT DISTINCT. `def foo()` is `FunctionDef` while
     `async def foo()` is `AsyncFunctionDef`; their node types differ so
     their hashes differ. Don't normalize them — they have different call
     contracts (returns coroutine vs. result).

Python edge cases this backend explicitly handles:

  - lambda forms: hashed via their AST subtree if assigned to a name
    (`X = lambda ...` → ValueSpec analog).
  - generator expressions / comprehensions: structural — same AST, same hash.
  - walrus operator (`:=` / NamedExpr): part of expression AST.
  - match-case (3.10+): Match / match_case nodes are part of the body.
  - ParamSpec / TypeVar / TypeAlias (3.12 PEP 695): TypeAlias nodes carry
    their RHS; type-parameter changes affect the hash, which is correct.
  - *args / **kwargs / positional-only / keyword-only: all encoded in
    arguments node fields (vararg, kwarg, posonlyargs, kwonlyargs).

Determinism caveats:
  - ast.dump uses sorted child order via __match_args__ in 3.9+; output is
    stable across runs of the same Python version.
  - We pin the canonical-form version with `_CANON_VERSION = 1` in the
    output stream. If we ever change canonicalization rules, bump this to
    invalidate stale hashes deliberately.
  - Python version drift: ast nodes can grow new fields in new Python
    minors (e.g., `type_params` added in 3.12). The canonical form
    includes ALL non-position fields, so a Python-version bump that adds
    a field will rehash. Document the pinned interpreter version in the
    pack manifest's toolchain block.

[traces-to: pipeline-multi-lang-Item-2A-1]
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import sys
from typing import Optional

_CANON_VERSION = 1
"""Canonical-form schema version. Bump to deliberately invalidate stale hashes
when a canonicalization rule changes. Stamped into the dump prefix so two
hashes with different schema versions are never confused for equivalent."""


def main() -> int:
    parser = argparse.ArgumentParser(prog="python-backend", add_help=False)
    parser.add_argument("file", nargs="?")
    parser.add_argument("symbol", nargs="?")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="also print the canonical form to stderr")
    parser.add_argument("-h", "--help", action="store_true")
    args = parser.parse_args()

    if args.help or not args.file or not args.symbol:
        print("usage: python-backend.py <file> <symbol>", file=sys.stderr)
        print("  symbol: 'Foo' or 'T.Foo'", file=sys.stderr)
        return 2

    try:
        with open(args.file, "rb") as fh:
            src = fh.read()
    except OSError as err:
        print(f"file read error: {err}", file=sys.stderr)
        return 2

    try:
        tree = ast.parse(src, filename=args.file)
    except SyntaxError as err:
        print(f"parse error: {err}", file=sys.stderr)
        return 3

    node = find_symbol(tree, args.symbol)
    if node is None:
        print(f"symbol not found: {args.symbol}", file=sys.stderr)
        return 4

    try:
        canonical = canonicalize(node)
    except Exception as err:  # pragma: no cover - canonicalize is total
        print(f"canonicalize error: {err}", file=sys.stderr)
        return 5

    if args.verbose:
        print("--- canonical form ---", file=sys.stderr)
        print(canonical, file=sys.stderr)
        print("--- end ---", file=sys.stderr)

    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    print(digest)
    return 0


def find_symbol(tree: ast.Module, qualified_name: str) -> Optional[ast.AST]:
    """Resolve `Foo` (top-level) or `T.Foo` (method on class T) to its AST node.

    Resolution rules:
        - Top-level: scans tree.body for FunctionDef / AsyncFunctionDef /
          ClassDef / Assign / AnnAssign whose name matches.
        - Method: scans the named ClassDef's body for FunctionDef /
          AsyncFunctionDef matching the method name. classmethod /
          staticmethod / property all resolve uniformly — the decorator is
          part of the method's AST and contributes to the hash.
        - Returns None if no match.
    """
    if "." in qualified_name:
        cls_name, _, method = qualified_name.partition(".")
        cls = _find_class(tree, cls_name)
        if cls is None:
            return None
        return _find_method(cls, method)

    return _find_top_level(tree, qualified_name)


def _find_top_level(tree: ast.Module, name: str) -> Optional[ast.AST]:
    for stmt in tree.body:
        if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            if stmt.name == name:
                return stmt
        elif isinstance(stmt, ast.Assign):
            for target in stmt.targets:
                if isinstance(target, ast.Name) and target.id == name:
                    return stmt
        elif isinstance(stmt, ast.AnnAssign):
            if isinstance(stmt.target, ast.Name) and stmt.target.id == name:
                return stmt
        elif hasattr(ast, "TypeAlias") and isinstance(stmt, ast.TypeAlias):  # 3.12+
            if isinstance(stmt.name, ast.Name) and stmt.name.id == name:
                return stmt
    return None


def _find_class(tree: ast.Module, name: str) -> Optional[ast.ClassDef]:
    for stmt in tree.body:
        if isinstance(stmt, ast.ClassDef) and stmt.name == name:
            return stmt
    return None


def _find_method(cls: ast.ClassDef, name: str) -> Optional[ast.AST]:
    for stmt in cls.body:
        if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if stmt.name == name:
                return stmt
    return None


def canonicalize(node: ast.AST) -> str:
    """Render `node` to a deterministic, position-independent string.

    Strategy:
        1. Strip docstrings from any function/class/module body whose first
           statement is a bare string Expr (decision #1 above).
        2. Use ast.dump with annotate_fields=True, include_attributes=False
           to emit a textual structural form. include_attributes=False drops
           lineno / col_offset / end_lineno / end_col_offset — the fields
           that change with whitespace edits but carry no semantics.
        3. Prefix with `_CANON_VERSION` so a schema bump invalidates old
           hashes intentionally.
    """
    cleaned = _strip_docstrings(node)
    body = ast.dump(cleaned, annotate_fields=True, include_attributes=False)
    return f"v{_CANON_VERSION}\n{body}\n"


def _strip_docstrings(node: ast.AST) -> ast.AST:
    """Return a copy of `node` with docstrings removed from every body.

    A docstring is the first statement of a body that is `Expr(Constant(str))`
    (PY3.8+) or `Expr(Str)` (legacy AST shape). Module / FunctionDef /
    AsyncFunctionDef / ClassDef bodies are scrubbed.

    Implementation: deep-copy via ast.parse(ast.unparse(node)) is too lossy
    (re-formats), so we rebuild via a NodeTransformer that drops the leading
    docstring stmt without touching anything else.
    """

    class DocstringStripper(ast.NodeTransformer):
        def visit_Module(self, n: ast.Module) -> ast.Module:
            self.generic_visit(n)
            return _drop_doc(n)

        def visit_FunctionDef(self, n: ast.FunctionDef) -> ast.AST:
            self.generic_visit(n)
            return _drop_doc(n)

        def visit_AsyncFunctionDef(self, n: ast.AsyncFunctionDef) -> ast.AST:
            self.generic_visit(n)
            return _drop_doc(n)

        def visit_ClassDef(self, n: ast.ClassDef) -> ast.AST:
            self.generic_visit(n)
            return _drop_doc(n)

    def _drop_doc(n: ast.AST) -> ast.AST:
        body = getattr(n, "body", None)
        if not body:
            return n
        first = body[0]
        if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant):
            if isinstance(first.value.value, str):
                n.body = body[1:]
        return n

    return DocstringStripper().visit(node)


if __name__ == "__main__":
    sys.exit(main())
