#!/usr/bin/env python3
"""python-symbols — Python AST symbol enumerator for the marker protocol.

Sibling of go-symbols.go; emits the same JSON schema. Consumers (G99/G101/G103,
compute-shape-hash) read both Go and Python output identically.

Usage:
    python-symbols.py -file <path>
    python-symbols.py -dir <root> [-include-tests]

Output schema (per file):
    {
      "file":    "rel/client.py",
      "package": "motadatapysdk.client",   # module dotted path, derived from file path
      "symbols": [
        {
          "kind":           "func"|"method"|"class"|"var"|"const",
          "name":           "Client",
          "receiver":       "Client",        # empty for non-methods; class name for methods
          "exported":       true,            # `True` if name does NOT start with `_`
          "line":           42,              # for human-readable messages only
          "signature_text": "def get(self, key: str) -> str | None",
          "ast_hash":       "fcbf...bd5d",
          "godoc":          ["First line of docstring", "Second line"]
        },
        ...
      ]
    }

Kind decisions:
    - func    — top-level FunctionDef / AsyncFunctionDef
    - method  — FunctionDef / AsyncFunctionDef inside a ClassDef
    - class   — ClassDef
    - const   — top-level Assign / AnnAssign whose target name is ALL_CAPS
                (Python convention for module-level constants)
    - var     — every other top-level Assign / AnnAssign

`exported` follows the PEP 8 convention: leading underscore = private,
otherwise public. (No equivalent of Go's UpperCase rule — Python uses the
underscore prefix.)

`receiver` for a method is the class name (no `*` / `[T]` decoration like Go,
because Python method receivers are always `self` / `cls` — the class itself
is the receiver type). The format keeps consistency with go-symbols' field
shape so downstream guardrails can treat the field uniformly.

[traces-to: pipeline-multi-lang-Item-2A-2]
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import sys
from typing import Any, Optional

# Reuse canonicalization from python-backend.py — must stay byte-identical to
# preserve the invariant "ast_hash from python-symbols == ast_hash from
# python-backend on the same symbol". Inlined here rather than imported to
# avoid path-juggling for stdlib-only operation.
_CANON_VERSION = 1


def main() -> int:
    parser = argparse.ArgumentParser(prog="python-symbols", add_help=False)
    parser.add_argument("-file", dest="file")
    parser.add_argument("-dir", dest="dir")
    parser.add_argument("-include-tests", dest="include_tests", action="store_true")
    parser.add_argument("-h", "--help", action="store_true")
    args = parser.parse_args()

    if args.help or (bool(args.file) == bool(args.dir)):
        print("usage: python-symbols.py -file <path> | -dir <root> [-include-tests]",
              file=sys.stderr)
        return 2

    if args.file:
        try:
            result = enumerate_file(args.file, args.file)
        except OSError as err:
            print(f"file read error: {err}", file=sys.stderr)
            return 3
        except SyntaxError as err:
            print(f"parse error: {err}", file=sys.stderr)
            return 3
        json.dump(result, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0

    # -dir mode
    results: dict[str, dict] = {}
    root = args.dir
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            d for d in dirnames
            if not d.startswith(".") and d not in ("__pycache__", "venv", ".venv")
        ]
        for fn in filenames:
            if not fn.endswith(".py"):
                continue
            if not args.include_tests and (fn.startswith("test_") or fn.endswith("_test.py")):
                continue
            abs_path = os.path.join(dirpath, fn)
            rel_path = os.path.relpath(abs_path, root)
            try:
                results[rel_path] = enumerate_file(abs_path, rel_path)
            except (OSError, SyntaxError) as err:
                print(f"warn: {rel_path}: {err}", file=sys.stderr)
                continue

    json.dump(results, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


def enumerate_file(abs_path: str, rel_path: str) -> dict[str, Any]:
    with open(abs_path, "rb") as fh:
        src = fh.read()
    tree = ast.parse(src, filename=abs_path)
    package = _module_path(rel_path)

    symbols: list[dict[str, Any]] = []
    for stmt in tree.body:
        if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
            symbols.append(_symbol_from_func(stmt, receiver=""))
        elif isinstance(stmt, ast.ClassDef):
            # Methods first — _ast_hash on the class would otherwise strip
            # method docstrings through recursive in-place mutation.
            method_syms: list[dict[str, Any]] = []
            for sub in stmt.body:
                if isinstance(sub, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    method_syms.append(_symbol_from_func(sub, receiver=stmt.name))
            symbols.append(_symbol_from_class(stmt))
            symbols.extend(method_syms)
        elif isinstance(stmt, ast.Assign):
            for tgt in stmt.targets:
                if isinstance(tgt, ast.Name):
                    symbols.append(_symbol_from_value(tgt.id, stmt, annotation=None))
        elif isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name):
            symbols.append(_symbol_from_value(stmt.target.id, stmt, annotation=stmt.annotation))

    return {"file": rel_path, "package": package, "symbols": symbols}


def _module_path(rel_path: str) -> str:
    """Convert a relative path like 'pkg/sub/mod.py' to 'pkg.sub.mod'."""
    no_ext = rel_path[:-3] if rel_path.endswith(".py") else rel_path
    parts = no_ext.replace(os.sep, "/").split("/")
    if parts and parts[-1] == "__init__":
        parts = parts[:-1]
    return ".".join(parts)


def _symbol_from_func(node: ast.AST, receiver: str) -> dict[str, Any]:
    name = node.name  # type: ignore[union-attr]
    # Extract godoc BEFORE _ast_hash — _ast_hash strips docstrings via
    # in-place AST mutation, which would also mutate this node's body.
    godoc = _godoc_lines(node)
    sig = _signature_text_func(node)
    return {
        "kind": "method" if receiver else "func",
        "name": name,
        "receiver": receiver,
        "exported": _is_exported(name),
        "line": node.lineno,  # type: ignore[union-attr]
        "signature_text": sig,
        "ast_hash": _ast_hash(node),
        "godoc": godoc,
    }


def _symbol_from_class(node: ast.ClassDef) -> dict[str, Any]:
    godoc = _godoc_lines(node)
    sig = _signature_text_class(node)
    return {
        "kind": "class",
        "name": node.name,
        "receiver": "",
        "exported": _is_exported(node.name),
        "line": node.lineno,
        "signature_text": sig,
        "ast_hash": _ast_hash(node),
        "godoc": godoc,
    }


def _symbol_from_value(name: str, stmt: ast.AST, annotation: Optional[ast.AST]) -> dict[str, Any]:
    # Convention: ALL_CAPS module-level names are constants (PEP 8 §Constants).
    # Single-letter uppercase like `T` (TypeVar) also matches but rarely
    # appears as Assign — usually wrapped in TypeVar() call.
    is_const = name.isupper()
    sig = name
    if annotation is not None:
        try:
            sig = f"{name}: {ast.unparse(annotation)}"
        except (ValueError, AttributeError):
            sig = f"{name}: <annotation>"
    return {
        "kind": "const" if is_const else "var",
        "name": name,
        "receiver": "",
        "exported": _is_exported(name),
        "line": stmt.lineno,  # type: ignore[union-attr]
        "signature_text": sig,
        "ast_hash": _ast_hash_value(name, stmt),
        "godoc": [],  # Python lacks per-assignment docstrings; PEP 224 was rejected
    }


def _is_exported(name: str) -> bool:
    return bool(name) and not name.startswith("_")


def _signature_text_func(node: ast.AST) -> str:
    """Render `def name(args) -> ret:` with body stripped, decorators included."""
    decorators = "".join(f"@{ast.unparse(d)} " for d in getattr(node, "decorator_list", []))
    is_async = isinstance(node, ast.AsyncFunctionDef)
    kw = "async def" if is_async else "def"
    args = ast.unparse(node.args)  # type: ignore[union-attr]
    ret = ""
    if getattr(node, "returns", None) is not None:
        ret = f" -> {ast.unparse(node.returns)}"  # type: ignore[union-attr]
    return f"{decorators}{kw} {node.name}({args}){ret}".strip()  # type: ignore[union-attr]


def _signature_text_class(node: ast.ClassDef) -> str:
    bases = ", ".join(ast.unparse(b) for b in node.bases)
    keywords = ", ".join(f"{kw.arg}={ast.unparse(kw.value)}" for kw in node.keywords if kw.arg)
    if bases and keywords:
        head = f"({bases}, {keywords})"
    elif bases:
        head = f"({bases})"
    elif keywords:
        head = f"({keywords})"
    else:
        head = ""
    return f"class {node.name}{head}"


def _godoc_lines(node: ast.AST) -> list[str]:
    """Return docstring split by lines, or [] if absent. Uses stdlib
    ast.get_docstring (read-only, doesn't mutate the tree)."""
    if not isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        return []
    doc = ast.get_docstring(node, clean=False)
    if doc is None:
        return []
    return doc.splitlines()


def _ast_hash(node: ast.AST) -> str:
    """Compute the same canonical SHA256 as python-backend.py."""
    cleaned = _strip_docstrings(node)
    body = ast.dump(cleaned, annotate_fields=True, include_attributes=False)
    canonical = f"v{_CANON_VERSION}\n{body}\n"
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _ast_hash_value(name: str, stmt: ast.AST) -> str:
    """Hash a single var/const declaration. For multi-target Assigns, narrow
    the synthesized node to the named target only — same approach as Go's
    astHashIdent."""
    if isinstance(stmt, ast.AnnAssign):
        return _ast_hash(stmt)
    if isinstance(stmt, ast.Assign):
        # Build a synthetic single-target Assign for stable per-name hashing
        narrow = ast.Assign(
            targets=[ast.Name(id=name, ctx=ast.Store())],
            value=stmt.value,
            type_comment=getattr(stmt, "type_comment", None),
        )
        ast.copy_location(narrow, stmt)
        return _ast_hash(narrow)
    return _ast_hash(stmt)


def _strip_docstrings(node: ast.AST) -> ast.AST:
    """Mirror of python-backend.py._strip_docstrings — must stay in sync.

    Mutates the input AST in-place. Callers that need to preserve docstrings
    (e.g. _godoc_lines) MUST extract them before invoking _ast_hash.
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
