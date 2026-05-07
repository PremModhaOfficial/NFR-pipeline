# AST-Hash Protocol — Phase P1 deliverable

> Part of the C-refactor (shared core + language packs). Replaces the byte-range SHA256 in the marker protocol (G95/G96) and the regex-based Go symbol scanners (G99–G103) with a language-pluggable AST hasher.

## Why

The current marker protocol (CLAUDE.md §29) byte-hashes source regions to lock `[owned-by: MANUAL]` symbols against pipeline modification. This is **fragile**:

- `gofmt` on an adjacent symbol shifts byte offsets → false-positive BLOCKER
- comment edits flip the hash even without semantic change
- every check is Go-specific (Go comment syntax, Go symbol regex)

AST-hashing fixes all three: the hash is computed over a **canonical form** of the symbol's AST subtree, stripped of comments and formatting.

## Interface

```
ast-hash.sh <pack> <file> <symbol>   →   <sha256-hex>
```

- `<pack>`: `go` (P1), `python` (P4)
- `<file>`: absolute or relative path to the source file
- `<symbol>`: name of the symbol:
  - `Foo` — top-level func/type/var/const named Foo
  - `T.Foo` — method Foo on type T (handles pointer + generic receivers)
  - `T` — type T (bare)

Success: prints the hash + exits 0.
Failure exits:
- 2: usage error
- 3: file missing
- 4: backend missing for the pack
- 5: pack not implemented yet
- 6: unknown pack

The Go backend additionally uses:
- 3: Go parse error
- 4: symbol not found

## Canonicalization rules

### Go backend (`go-backend.go`)

1. Parses the file with `go/parser.ParseFile(fset, path, nil, 0)` — **no `ParseComments` flag**, so comments are discarded at parse time.
2. Walks `file.Decls` to locate the named symbol (FuncDecl, TypeSpec, ValueSpec).
3. Prints the node with `go/printer.Config{Mode: TabIndent|UseSpaces, Tabwidth: 8}` — deterministic output for any AST.
4. Trims trailing whitespace, appends a single newline.
5. SHA256 of the canonical bytes.

This gives **the invariances we want**:
- Whitespace change in the symbol → same hash.
- Comment added/edited/removed → same hash.
- Import reordering (outside the symbol) → same hash.
- Formatter change (gofmt version bump) → same hash (printer is version-stable).

And the **sensitivity we want**:
- Any identifier renamed, statement added/removed, expression changed → different hash.

### Per-language canonicalization rules — open contract for new backends

Any new language backend (Python, Rust, TypeScript, etc.) MUST answer the following questions in writing — either inline in this README under a per-language subsection, or in a sibling `<lang>-backend.md`. Without explicit answers, two implementations of the same backend can produce different hashes and silently break the marker protocol.

The **four core questions** every backend author must answer:

1. **Are docstrings part of the hash, or stripped?**
   - *Go answer*: stripped (no `ParseComments`).
   - *Python author must decide*: `ast.parse()` includes docstrings as the first `Expr(Str)` of a function/module body. Strip them by removing `node.body[0]` when it's a string-only expression, OR include them (treating docstrings as semantic). Recommended: **strip**, to match Go's invariance and avoid spurious hash flips from doc rewrites. Document the choice.
   - *Implications*: stripping means a doc-only edit doesn't trigger marker-hygiene-devil; including means it does.

2. **Are type hints / annotations part of the hash?**
   - *Go answer*: yes — Go types are part of the AST, can't be stripped without changing semantics.
   - *Python author must decide*: type hints are syntactically optional but semantically meaningful. `def f(x: int) -> str` vs `def f(x)` are different APIs. Recommended: **include**, since changing a type annotation IS a behavioral change worth catching.
   - Same question applies to TS/Rust generics, return-type annotations, etc.

3. **Are decorators part of the hash?**
   - *Go answer*: N/A (Go has no decorators).
   - *Python author must decide*: `@retry(3)` and `@property` change behavior; should be **included**. This means decorator order matters for the hash (which is correct — `@retry @cache` ≠ `@cache @retry`).
   - Same applies to Java/Kotlin annotations, TS/Rust attributes/derives.

4. **Are async-vs-sync forms equivalent for hashing purposes?**
   - *Go answer*: N/A (Go uses goroutines, not async syntax).
   - *Python author must decide*: `def foo()` and `async def foo()` produce different ASTs. They MUST hash differently — they have different call contracts. Don't normalize them.
   - Same for Rust `fn` vs `async fn`, JS `function` vs `async function`.

### Backend-specific extras to document

- **Sort-stability**: if your AST traversal isn't deterministic (e.g., dict-iteration in older Python), you MUST sort children by source position before printing. Pin the version of any printer/serializer you depend on.
- **Whitespace in string literals**: indentation INSIDE a multi-line string literal is part of the literal's value — don't normalize it. Distinguish from indentation OUTSIDE (which is whitespace).
- **Identifier qualification**: `T.method` resolution should handle method receivers, class methods, static methods, classmethod/staticmethod decorators, instance vs unbound, etc. Document the resolution rules per language.
- **Encoding**: emit canonical bytes as UTF-8 NFC; strip BOM if present; reject non-UTF-8 source files.

### Python backend (`python-backend.py`, `python-symbols.py`)

**Status**: shipped 2026-04-28 in v0.5.0 Phase B (Item 2A foundations). Stdlib-only (`ast` + `hashlib`). Files at `scripts/ast-hash/python-backend.py` (single-symbol hash) and `scripts/ast-hash/python-symbols.py` (file/dir enumeration). The dispatchers (`ast-hash.sh`, `symbols.sh`) auto-route on `<pack>=python` with a fallback chain identical in shape to the Go branch.

**Answers to the four canonicalization questions:**

1. **Docstrings — STRIPPED.** First statement of any function / class / module body that is `Expr(Constant(str))` is removed before hashing. Doc-only edits do NOT change the hash. This matches Go's `parser.ParseFile` without `ParseComments`. Use `marker-hygiene-devil` (not the AST hasher) to enforce missing-doc regressions.

2. **Type hints / annotations — INCLUDED.** `def f(x: int) -> str` and `def f(x)` produce different ASTs (`arg.annotation`, `FunctionDef.returns` differ). Changing an annotation IS a behavioral change worth catching.

3. **Decorators — INCLUDED.** `FunctionDef.decorator_list` is preserved verbatim; order matters. `@retry @cache` and `@cache @retry` correctly hash differently.

4. **async vs sync — KEPT DISTINCT.** `def foo()` is `FunctionDef`; `async def foo()` is `AsyncFunctionDef`. Different node types → different hashes. They have different call contracts (returns coroutine vs result).

**Python edge cases the backend explicitly handles:**

| Construct | Treatment |
|---|---|
| `lambda` assigned to a name | Hashed via the `Assign(value=Lambda(...))` subtree. |
| Comprehensions / generator expressions | Structural — distinct nodes (`ListComp`, `SetComp`, `DictComp`, `GeneratorExp`). |
| Walrus operator `:=` (`NamedExpr`) | Part of expression AST. |
| `match` / `case` (3.10+) | `Match` / `match_case` nodes are part of the body. |
| `TypeAlias` (3.12+ PEP 695) | Resolved as a top-level symbol; RHS contributes to hash. |
| `*args` / `**kwargs` | Encoded in `arguments.vararg` / `arguments.kwarg`. |
| Positional-only (`/`) / keyword-only (`*`) | `arguments.posonlyargs` / `arguments.kwonlyargs`. |
| `classmethod` / `staticmethod` / `property` | Resolved uniformly as `method`; the decorator is in `decorator_list` and hashes accordingly. |
| `from __future__ import annotations` | No special handling — annotations are still part of the AST regardless of stringification at runtime. |

**Versioning:** the canonical form is prefixed with `v<N>` where `N` is `_CANON_VERSION` (currently `1`). Bump only when the canonicalization rules change deliberately — that invalidates all prior hashes by design.

**Pinned interpreter:** `ast` node fields can grow across Python minors (e.g., 3.12 added `type_params`). The canonical form includes ALL non-position fields, so a Python upgrade may rehash the same source. Pin the interpreter version in the pack manifest's `toolchain` block (`python.json` declares `python3.12+`).

**Symbol-resolution rules** (`T.foo` resolution):
- Top-level: scans module `body` for `FunctionDef` / `AsyncFunctionDef` / `ClassDef` / `Assign` / `AnnAssign` / `TypeAlias`.
- Method: scans the named `ClassDef` body. `classmethod`, `staticmethod`, `property` resolve uniformly (the decorator is part of the method node, not the lookup).
- `exported`: PEP 8 underscore convention. `name.startswith("_")` → not exported.

**Worked examples:**

```bash
./ast-hash.sh python motadatapysdk/cache/redis_cache.py 'Cache.get'
# → 3f5a...b091

./symbols.sh python -file motadatapysdk/cache/redis_cache.py
# → JSON with one entry per top-level + per method
```

## Worked examples (Go)

```bash
# Hash the Client.Get method of an SDK client
./ast-hash.sh go core/l2cache/dragonfly/cache.go 'Client.Get'
# → 3f5a...b091

# Hash a top-level type
./ast-hash.sh go core/l2cache/dragonfly/config.go 'Config'
# → 8e2c...a4df

# Hash a constant (top-level ValueSpec)
./ast-hash.sh go core/l2cache/dragonfly/const.go 'DefaultPoolSize'
# → 7b1d...9e00
```

## Integration with `ownership-map.json`

The marker protocol's ownership map gains two new fields:

```json
{
  "symbol": "Client.Get",
  "file": "core/l2cache/dragonfly/cache.go",
  "language": "go",              // NEW — drives pack dispatch
  "ast_hash": "3f5a...b091",     // NEW — preferred

  "byte_start": 1234,            // DEPRECATED (kept one release)
  "byte_end": 1580,              // DEPRECATED
  "sha256": "..."                // DEPRECATED (byte-range hash)
}
```

`G95.sh` / `G96.sh` check `ast_hash` first; fall back to `sha256`+`byte_start`/`byte_end` for older ownership maps. After one pipeline-version release (0.3.0 → 0.4.0) the byte fields are removed.

## Testing

`tests/ast-hash/` (P1 week 2) will contain:

1. **gofmt invariance**: same symbol, pre-gofmt vs. post-gofmt source → identical hashes.
2. **comment invariance**: same symbol, comment added → identical hash.
3. **semantic sensitivity**: single identifier renamed inside the symbol → different hash.
4. **receiver resolution**: `T.X`, `*T.X`, `T[K].X`, `T[K,V].X` all resolve correctly.
5. **unknown symbol**: exits 4.
6. **parse error** (malformed Go): exits 3.

## What's next (P3 migration)

When Phase P3 creates `packs/go/`:

1. `scripts/ast-hash/go-backend.go` → `packs/go/ast-hash-backend.go`
2. `packs/go/pack-manifest.yaml` declares `ast_hash_backend: ast-hash-backend.go`
3. The dispatcher's `go` branch prefers `$ROOT/packs/go/ast-hash-backend.go` (it already does — P1 dispatcher was written pack-aware).
4. Add `packs/python/ast-hash-backend.py` (uses Python's `ast` stdlib module) when P4 kicks off.
