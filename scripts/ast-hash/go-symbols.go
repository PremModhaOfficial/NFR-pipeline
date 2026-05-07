// go-symbols — Go AST symbol enumerator for the marker protocol.
//
// Emits structured JSON describing every top-level declaration in a Go file
// (or recursively in a directory tree), including the godoc comment block,
// canonical signature text, and per-symbol AST hash. Consumed by the marker
// guardrails (G99 traces-to, G101 stable-since, G103 forged-MANUAL) and by
// compute-shape-hash to replace their existing regex/grep-based scanners.
//
// Design principle (same as go-backend): emit pack-neutral data so the
// guardrails themselves stay language-agnostic — they consume JSON, not
// Go-shaped text.
//
// Usage:
//   go-symbols -file <path.go>     → emits JSON for one file
//   go-symbols -dir <root>         → emits JSON map { "rel/path.go": {...}, ... }
//   go-symbols -dir <root> -include-tests  → also include _test.go files
//
// Output schema (per file):
//   {
//     "file":    "rel/cache.go",
//     "package": "dragonfly",
//     "symbols": [
//       {
//         "kind":           "func"|"method"|"type"|"var"|"const",
//         "name":           "New",
//         "receiver":       "*Cache",   // empty for non-methods
//         "exported":       true,
//         "line":           78,         // for human-readable error messages only
//         "signature_text": "func New(opts ...Option) (*Cache, error)",
//         "ast_hash":       "fcbf...bd5d",
//         "godoc":          ["// New creates...", "// [traces-to: TPRD-7-1]"]
//       },
//       ...
//     ]
//   }
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"go/ast"
	"go/parser"
	"go/printer"
	"go/token"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"unicode"
)

type Symbol struct {
	Kind          string   `json:"kind"`
	Name          string   `json:"name"`
	Receiver      string   `json:"receiver,omitempty"`
	Exported      bool     `json:"exported"`
	Line          int      `json:"line"`
	SignatureText string   `json:"signature_text"`
	ASTHash       string   `json:"ast_hash"`
	Godoc         []string `json:"godoc"`
}

type FileSymbols struct {
	File    string   `json:"file"`
	Package string   `json:"package"`
	Symbols []Symbol `json:"symbols"`
}

func main() {
	file := flag.String("file", "", "single source file to enumerate")
	dir := flag.String("dir", "", "directory root to walk recursively")
	includeTests := flag.Bool("include-tests", false, "include _test.go files (default: skip)")
	flag.Parse()
	if (*file == "") == (*dir == "") {
		fmt.Fprintln(os.Stderr, "usage: go-symbols -file <path> | -dir <root> [-include-tests]")
		os.Exit(2)
	}

	if *file != "" {
		fs, err := enumerateFile(*file, *file)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(3)
		}
		emit(fs)
		return
	}

	// -dir mode: emit map[file] -> FileSymbols
	results := map[string]FileSymbols{}
	root := *dir
	if err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			// skip hidden dirs and vendor
			base := filepath.Base(path)
			if strings.HasPrefix(base, ".") || base == "vendor" {
				return filepath.SkipDir
			}
			return nil
		}
		if filepath.Ext(path) != ".go" {
			return nil
		}
		if !*includeTests && strings.HasSuffix(path, "_test.go") {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		fs, err := enumerateFile(path, rel)
		if err != nil {
			fmt.Fprintf(os.Stderr, "warn: %s: %v\n", rel, err)
			return nil // skip the bad file, continue
		}
		results[rel] = fs
		return nil
	}); err != nil {
		fmt.Fprintln(os.Stderr, "walk error:", err)
		os.Exit(4)
	}
	emit(results)
}

func emit(v any) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil {
		fmt.Fprintln(os.Stderr, "json encode:", err)
		os.Exit(5)
	}
}

func enumerateFile(absPath, relPath string) (FileSymbols, error) {
	fset := token.NewFileSet()
	// ParseComments needed: we want to associate godoc with each symbol.
	f, err := parser.ParseFile(fset, absPath, nil, parser.ParseComments)
	if err != nil {
		return FileSymbols{}, fmt.Errorf("parse: %w", err)
	}
	cmap := ast.NewCommentMap(fset, f, f.Comments)

	out := FileSymbols{File: relPath, Package: f.Name.Name}
	for _, d := range f.Decls {
		switch d := d.(type) {
		case *ast.FuncDecl:
			out.Symbols = append(out.Symbols, symbolFromFunc(fset, d, cmap))
		case *ast.GenDecl:
			for _, spec := range d.Specs {
				switch spec := spec.(type) {
				case *ast.TypeSpec:
					out.Symbols = append(out.Symbols, symbolFromType(fset, d, spec, cmap))
				case *ast.ValueSpec:
					for _, id := range spec.Names {
						out.Symbols = append(out.Symbols, symbolFromValue(fset, d, spec, id, cmap))
					}
				}
			}
		}
	}
	return out, nil
}

func symbolFromFunc(fset *token.FileSet, fd *ast.FuncDecl, cmap ast.CommentMap) Symbol {
	s := Symbol{
		Kind:     "func",
		Name:     fd.Name.Name,
		Exported: isExported(fd.Name.Name),
		Line:     fset.Position(fd.Pos()).Line,
		Godoc:    extractGodoc(fd.Doc, cmap[fd]),
		ASTHash:  astHash(fd),
	}
	if fd.Recv != nil && len(fd.Recv.List) > 0 {
		s.Kind = "method"
		s.Receiver = exprText(fset, fd.Recv.List[0].Type)
	}
	// Signature text: print the FuncDecl with body stripped
	clone := *fd
	clone.Body = nil
	s.SignatureText = canonicalText(fset, &clone)
	return s
}

func symbolFromType(fset *token.FileSet, gd *ast.GenDecl, ts *ast.TypeSpec, cmap ast.CommentMap) Symbol {
	doc := ts.Doc
	if doc == nil {
		doc = gd.Doc // single-spec `type X struct{}` puts the doc on the GenDecl
	}
	s := Symbol{
		Kind:          "type",
		Name:          ts.Name.Name,
		Exported:      isExported(ts.Name.Name),
		Line:          fset.Position(ts.Pos()).Line,
		Godoc:         extractGodoc(doc, cmap[gd]),
		ASTHash:       astHash(ts),
		SignatureText: "type " + ts.Name.Name + " " + exprText(fset, ts.Type),
	}
	return s
}

func symbolFromValue(fset *token.FileSet, gd *ast.GenDecl, vs *ast.ValueSpec, id *ast.Ident, cmap ast.CommentMap) Symbol {
	doc := vs.Doc
	if doc == nil {
		doc = gd.Doc
	}
	kind := "var"
	if gd.Tok == token.CONST {
		kind = "const"
	}
	return Symbol{
		Kind:          kind,
		Name:          id.Name,
		Exported:      isExported(id.Name),
		Line:          fset.Position(id.Pos()).Line,
		Godoc:         extractGodoc(doc, cmap[gd]),
		ASTHash:       astHashIdent(vs, id),
		SignatureText: kind + " " + id.Name + valueTypeText(fset, vs),
	}
}

func extractGodoc(doc *ast.CommentGroup, leading []*ast.CommentGroup) []string {
	// Prefer the AST-attached doc; fall back to leading comments from the comment map.
	if doc == nil && len(leading) > 0 {
		doc = leading[0]
	}
	if doc == nil {
		return nil
	}
	out := make([]string, 0, len(doc.List))
	for _, c := range doc.List {
		out = append(out, c.Text)
	}
	return out
}

func isExported(name string) bool {
	if name == "" {
		return false
	}
	r := []rune(name)[0]
	return unicode.IsUpper(r)
}

func exprText(fset *token.FileSet, e ast.Expr) string {
	var b bytes.Buffer
	cfg := printer.Config{Mode: printer.TabIndent | printer.UseSpaces, Tabwidth: 8}
	_ = cfg.Fprint(&b, fset, e)
	return strings.TrimSpace(b.String())
}

func canonicalText(fset *token.FileSet, n ast.Node) string {
	var b bytes.Buffer
	cfg := printer.Config{Mode: printer.TabIndent | printer.UseSpaces, Tabwidth: 8}
	_ = cfg.Fprint(&b, fset, n)
	// collapse runs of whitespace for stable signature comparison
	s := strings.TrimSpace(b.String())
	var out strings.Builder
	prevSpace := false
	for _, r := range s {
		if unicode.IsSpace(r) {
			if !prevSpace {
				out.WriteByte(' ')
				prevSpace = true
			}
			continue
		}
		out.WriteRune(r)
		prevSpace = false
	}
	return out.String()
}

func valueTypeText(fset *token.FileSet, vs *ast.ValueSpec) string {
	if vs.Type == nil {
		return ""
	}
	return " " + exprText(fset, vs.Type)
}

// astHash computes a position-stripped AST dump SHA256.
// Identical mechanism to go-backend.go for hash-equivalence with G95.
func astHash(node ast.Node) string {
	var buf bytes.Buffer
	_ = ast.Fprint(&buf, token.NewFileSet(), node, positionStrippingFilter)
	h := sha256.Sum256(buf.Bytes())
	return hex.EncodeToString(h[:])
}

// astHashIdent hashes a single identifier's spec — used for var/const where
// one ValueSpec may declare multiple names sharing a value.
func astHashIdent(vs *ast.ValueSpec, id *ast.Ident) string {
	// Build a synthetic spec containing only the target identifier
	clone := *vs
	clone.Names = []*ast.Ident{id}
	return astHash(&clone)
}

func positionStrippingFilter(name string, value reflect.Value) bool {
	if value.IsValid() && value.Type().Kind() == reflect.Int && value.Type().String() == "token.Pos" {
		return false
	}
	return ast.NotNilFilter(name, value)
}
