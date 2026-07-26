"""Trace - the TypeScript / TSX language parser, built on Tree-sitter.

Tree-sitter is used rather than a hand-written parser: it already has a
maintained TypeScript grammar, and the same approach extends to Java, Go,
Rust and C# by swapping the grammar and the node-type names below.

The whole job of this file is translating Tree-sitter's concrete node types
into Trace's normalised vocabulary:

  function_declaration                 -> "function"  / "async_function"
  class_declaration, interface_declaration -> "class"
  method_definition                    -> "method"
  arrow / function-expression bound to a const -> "function"
  call_expression                      -> RawCall
  import_statement, require(...)       -> import specifier

After that translation a TypeScript file is indistinguishable from a Python
file to everything upstream.
"""

import os;
import tree_sitter_typescript as tsts;

import from tree_sitter { Language, Parser }
import from parser_types { LanguageParser, RawCall, RawModule, RawSymbol, clip_source }

"""Grammar handles, built once - constructing a Language per file is slow."""
glob TS_LANGUAGES: dict[str, any] = {};

"""Return a cached Tree-sitter parser for a `.ts` or `.tsx` file."""
def _parser_for(rel_path: str) -> any {
    key = "tsx" if rel_path.endswith(".tsx") else "typescript";
    if key not in TS_LANGUAGES {
        raw = tsts.language_tsx() if key == "tsx" else tsts.language_typescript();
        TS_LANGUAGES[key] = Parser(Language(raw));
    }
    return TS_LANGUAGES[key];
}

"""Decoded text of a node."""
def _text(nd: any) -> str {
    return nd.text.decode("utf-8", "replace") as str;
}

"""1-based line number of a node."""
def _line(nd: any) -> int {
    return (nd.start_point[0] as int) + 1;
}

"""Name of a declaration, via its `name` field."""
def _name_of(nd: any) -> str {
    field = nd.child_by_field_name("name");
    if field is None {
        return "";
    }
    return _text(field);
}

"""Bare callee name for a call expression.

`helper()` -> "helper"; `service.createUser()` -> "createUser". This mirrors
the Python parser's attribute handling exactly, so cross-language call
resolution behaves identically.
"""
def _callee_name(call_node: any) -> str {
    fn = call_node.child_by_field_name("function");
    if fn is None {
        return "";
    }
    kind = fn.type as str;
    if kind == "identifier" {
        return _text(fn);
    }
    if kind == "member_expression" {
        prop = fn.child_by_field_name("property");
        if prop is not None {
            return _text(prop);
        }
    }
    return "";
}

"""Collect calls inside a callable, without descending into nested callables."""
def _calls_in(scope_node: any) -> list[RawCall] {
    out: list[RawCall] = [];
    body = scope_node.child_by_field_name("body");
    if body is None {
        return out;
    }
    stack: list[any] = [body];
    while stack {
        nd = stack.pop();
        if (nd.type as str) == "call_expression" {
            callee = _callee_name(nd);
            if callee {
                out.append(RawCall(name=callee, line=_line(nd)));
            }
        }
        for child in nd.children {
            # Descend into nested callables too. Anonymous arrows and
            # closures are NOT separate symbols, so a call inside
            # `xs.map((r) => createUser(r))` belongs to the enclosing named
            # function - which is exactly how Python's `ast.walk` attributes
            # it. Parity here is what keeps the graph language-neutral.
            stack.append(child);
        }
    }
    return out;
}

"""True when a declaration node carries the `async` keyword."""
def _is_async(nd: any) -> bool {
    for child in nd.children {
        if (child.type as str) == "async" {
            return True;
        }
    }
    return False;
}

"""Unwrap `export ...` / `export default ...` to the declaration underneath."""
def _unwrap_export(nd: any) -> any {
    if (nd.type as str) != "export_statement" {
        return nd;
    }
    inner = nd.child_by_field_name("declaration");
    if inner is not None {
        return inner;
    }
    return nd;
}

"""Import specifiers declared by a file, plus CommonJS `require(...)` targets."""
def _imports_of(tree_root: any) -> list[str] {
    out: list[str] = [];
    stack: list[any] = [tree_root];
    while stack {
        nd = stack.pop();
        kind = nd.type as str;
        if kind == "import_statement" or kind == "export_statement" {
            src = nd.child_by_field_name("source");
            if src is not None {
                out.append(_text(src).strip("\"'`"));
            }
        } elif kind == "call_expression" {
            fn = nd.child_by_field_name("function");
            if fn is not None and _text(fn) == "require" {
                args = nd.child_by_field_name("arguments");
                if args is not None {
                    for arg in args.children {
                        if (arg.type as str) == "string" {
                            out.append(_text(arg).strip("\"'`"));
                        }
                    }
                }
            }
        }
        for child in nd.children {
            stack.append(child);
        }
    }
    return out;
}

"""Symbols declared by a `const x = () => {}` / `const x = function () {}` statement."""
def _symbols_from_lexical(nd: any) -> list[RawSymbol] {
    out: list[RawSymbol] = [];
    for declarator in nd.children {
        if (declarator.type as str) != "variable_declarator" {
            continue;
        }
        value = declarator.child_by_field_name("value");
        if value is None {
            continue;
        }
        vkind = value.type as str;
        if vkind != "arrow_function" and vkind != "function_expression" {
            continue;
        }
        sym_name = _name_of(declarator);
        if not sym_name {
            continue;
        }
        out.append(
            RawSymbol(
                name=sym_name,
                kind="async_function" if _is_async(value) else "function",
                line=_line(declarator),
                source=clip_source(_text(declarator)),
                calls=_calls_in(value)
            )
        );
    }
    return out;
}

"""Methods declared inside a class or interface body."""
def _methods_of(decl: any) -> list[RawSymbol] {
    out: list[RawSymbol] = [];
    body = decl.child_by_field_name("body");
    if body is None {
        return out;
    }
    for member in body.children {
        if (member.type as str) != "method_definition" {
            continue;
        }
        m_name = _name_of(member);
        if not m_name {
            continue;
        }
        out.append(
            RawSymbol(
                name=m_name,
                kind="method",
                line=_line(member),
                source=clip_source(_text(member)),
                calls=_calls_in(member)
            )
        );
    }
    return out;
}

"""TypeScript and TSX source, parsed with Tree-sitter."""
obj TypeScriptParser(LanguageParser) {
    has name: str = "typescript",
        extensions: list[str] = [".ts", ".tsx"];

    override def parse_file(abs_path: str, rel_path: str) -> RawModule {
        mod = RawModule(
            rel_path=rel_path, name=os.path.basename(abs_path), language=self.name
        );
        try {
            handle = open(abs_path, "rb");
            raw = handle.read();
            handle.close();
            tree = _parser_for(rel_path).parse(raw);
        } except Exception as e {
            mod.error = f"{rel_path}: {str(e)}";
            return mod;
        }

        ts_root = tree.root_node;
        mod.imports = _imports_of(ts_root);

        # Only top-level declarations become symbols, matching the Python
        # parser's `tree.body` scan rather than a full-tree walk.
        for raw_node in ts_root.children {
            nd = _unwrap_export(raw_node);
            kind = nd.type as str;

            if kind == "function_declaration"
            or kind == "generator_function_declaration" {
                fn_name = _name_of(nd);
                if fn_name {
                    mod.symbols.append(
                        RawSymbol(
                            name=fn_name,
                            kind="async_function" if _is_async(nd) else "function",
                            line=_line(nd),
                            source=clip_source(_text(nd)),
                            calls=_calls_in(nd)
                        )
                    );
                }
            } elif kind == "class_declaration" or kind == "interface_declaration" {
                cls_name = _name_of(nd);
                if cls_name {
                    # Like Python, a class carries no calls of its own; its
                    # methods become separate symbols and own their calls.
                    mod.symbols.append(
                        RawSymbol(
                            name=cls_name,
                            kind="class",
                            line=_line(nd),
                            source=clip_source(_text(nd))
                        )
                    );
                    for m in _methods_of(nd) {
                        mod.symbols.append(m);
                    }
                }
            } elif kind == "lexical_declaration" or kind == "variable_declaration" {
                for sym in _symbols_from_lexical(nd) {
                    mod.symbols.append(sym);
                }
            }
        }
        return mod;
    }

    override def module_candidates(spec: str, importer_rel: str) -> list[str] {
        if not spec {
            return [];
        }
        # Only relative specifiers can resolve inside the repository; bare
        # specifiers ("react", "@scope/pkg") are third-party by definition.
        if not spec.startswith(".") {
            return [];
        }
        base = os.path.normpath(os.path.join(os.path.dirname(importer_rel), spec));
        base = base.strip("/");
        if not base or base.startswith("..") {
            return [];
        }

        out: list[str] = [];
        for ext in [".ts", ".tsx"] {
            if base.endswith(ext) {
                out.append(base);
            }
        }
        if not out {
            for ext in [".ts", ".tsx"] {
                out.append(base + ext);
            }
            for ext in [".ts", ".tsx"] {
                out.append(base + "/index" + ext);
            }
        }
        return out;
    }
}
