// go-backend — Go AST hasher for the motadata-sdk-pipeline marker protocol.
//
// Computes a canonical SHA256 over a named symbol's AST subtree. Invariant to:
//   - whitespace / gofmt differences
//   - comments (including godoc)
//   - import reordering (scope is per-symbol, not per-file)
//
// Sensitive to: any structural change — added/removed/renamed identifiers,
// altered expression trees, changed operators, new statements.
//
// Usage:
//   go run go-backend.go -file <path.go> -symbol <name>
//   go run go-backend.go -file cache.go -symbol Client.Get
//
// Symbol name syntax:
//   Foo         — top-level func, type, var, or const named Foo
//   T.Foo       — method Foo on receiver type T (pointer or value)
//   T           — type T (when also matches a func, prefer explicit disambiguation)
//
// Output: <sha256 hex> on success to stdout; exits 0.
// On error: message on stderr; non-zero exit.
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"reflect"
	"strings"
)

func main() {
	file := flag.String("file", "", "source file path")
	symbol := flag.String("symbol", "", "symbol name (e.g., Foo or T.Foo)")
	verbose := flag.Bool("v", false, "also print the canonical form to stderr")
	flag.Parse()
	if *file == "" || *symbol == "" {
		fmt.Fprintln(os.Stderr, "usage: go-backend -file <path> -symbol <name>")
		os.Exit(2)
	}

	fset := token.NewFileSet()
	// ParseFile without parser.ParseComments → comments are discarded from the AST,
	// so the printer cannot emit them. This is exactly the insensitivity we want.
	f, err := parser.ParseFile(fset, *file, nil, 0)
	if err != nil {
		fmt.Fprintln(os.Stderr, "parse error:", err)
		os.Exit(3)
	}

	node := findSymbol(f, *symbol)
	if node == nil {
		fmt.Fprintln(os.Stderr, "symbol not found:", *symbol)
		os.Exit(4)
	}

	// Canonical form: dump the AST structure using ast.Fprint with a filter
	// that strips all position information (token.Pos fields) and nil fields.
	// This produces a textual representation of the pure AST structure,
	// insensitive to any whitespace, blank lines, or comment placement in the
	// source — because none of those are part of the AST proper.
	var buf bytes.Buffer
	if err := ast.Fprint(&buf, token.NewFileSet(), node, positionStrippingFilter); err != nil {
		fmt.Fprintln(os.Stderr, "ast.Fprint error:", err)
		os.Exit(5)
	}
	canonical := buf.String()
	if *verbose {
		fmt.Fprintln(os.Stderr, "--- canonical form ---")
		fmt.Fprint(os.Stderr, canonical)
		fmt.Fprintln(os.Stderr, "--- end ---")
	}
	h := sha256.Sum256([]byte(canonical))
	fmt.Println(hex.EncodeToString(h[:]))
}

// findSymbol locates the top-level decl matching name.
//
// Accepts: "Foo" (any top-level), "T.Foo" (method on T, handles pointer receivers),
// "T" (type alone). Returns nil if no match.
func findSymbol(f *ast.File, name string) ast.Node {
	var recv string
	if i := strings.IndexByte(name, '.'); i >= 0 {
		recv = name[:i]
		name = name[i+1:]
	}
	for _, d := range f.Decls {
		switch d := d.(type) {
		case *ast.FuncDecl:
			if d.Name.Name != name {
				continue
			}
			if recv == "" {
				if d.Recv == nil {
					return d
				}
				continue
			}
			if d.Recv == nil || len(d.Recv.List) == 0 {
				continue
			}
			if receiverTypeName(d.Recv.List[0].Type) == recv {
				return d
			}
		case *ast.GenDecl:
			if recv != "" {
				// "T.X" only makes sense for func decls
				continue
			}
			for _, spec := range d.Specs {
				switch spec := spec.(type) {
				case *ast.TypeSpec:
					if spec.Name.Name == name {
						return spec
					}
				case *ast.ValueSpec:
					for _, id := range spec.Names {
						if id.Name == name {
							return spec
						}
					}
				}
			}
		}
	}
	return nil
}

// positionStrippingFilter skips fields of type token.Pos and nil fields.
// ast.Fprint uses this filter to produce a position-independent dump of the
// AST — essential for the "whitespace/blank-line invariance" property of
// canonical AST hashing.
func positionStrippingFilter(name string, value reflect.Value) bool {
	// Skip any field whose type is token.Pos (these carry source line/col info)
	if value.IsValid() && value.Type().Kind() == reflect.Int && value.Type().String() == "token.Pos" {
		return false
	}
	// Delegate nil-skipping to stdlib
	return ast.NotNilFilter(name, value)
}

// receiverTypeName extracts the receiver type name from a FuncDecl receiver expr.
// Handles: T, *T, T[K], T[K, V].
func receiverTypeName(e ast.Expr) string {
	switch t := e.(type) {
	case *ast.Ident:
		return t.Name
	case *ast.StarExpr:
		return receiverTypeName(t.X)
	case *ast.IndexExpr:
		return receiverTypeName(t.X)
	case *ast.IndexListExpr:
		return receiverTypeName(t.X)
	}
	return ""
}
