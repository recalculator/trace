"""Trace - the Python language parser.

Every `ast` reference in Trace lives in this file. The logic is unchanged
from the original inline implementation in `ingestion.jac`; it has only been
moved behind the `LanguageParser` contract so a second language can sit
beside it. Behaviour is intentionally identical - the Python test suite is
the regression check.
"""

import os;
import ast;

import from parser_types {
    LanguageParser,
    RawCall,
    RawModule,
    RawRoute,
    RawSymbol,
    clip_source
}

glob HTTP_DECORATORS: list[str] = [
         "get",
         "post",
         "put",
         "patch",
         "delete",
         "head",
         "options"
     ];

"""Resolve a call node to a bare callee name, or "" when it is not a simple call."""
def _callee_name(call_node: any) -> str {
    fn = call_node.func;
    if isinstance(fn, ast.Name) {
        return fn.id as str;
    }
    if isinstance(fn, ast.Attribute) {
        # `service.create_user()` -> "create_user"
        return fn.attr as str;
    }
    return "";
}

"""Collect every direct call made inside a function body."""
def _calls_in(fn_node: any) -> list[RawCall] {
    out: list[RawCall] = [];
    for sub in ast.walk(fn_node) {
        if isinstance(sub, ast.Call) {
            callee = _callee_name(sub);
            if callee {
                out.append(RawCall(name=callee, line=sub.lineno as int));
            }
        }
    }
    return out;
}

"""Read a node's source text, truncated to keep the graph light."""
def _source_of(src: str, ast_node: any) -> str {
    seg = ast.get_source_segment(src, ast_node);
    if seg is None {
        return "";
    }
    return clip_source(seg as str);
}

"""Extract a route from one decorator, or None when it is not a route."""
def _route_from_decorator(dec: any, handler: str) -> RawRoute | None {
    if not isinstance(dec, ast.Call) {
        return None;
    }
    fn = dec.func;
    if not isinstance(fn, ast.Attribute) {
        return None;
    }
    verb = fn.attr as str;
    args = dec.args;
    if len(args) == 0 or not isinstance(args[0], ast.Constant) {
        return None;
    }
    pattern = args[0].value;
    if not isinstance(pattern, str) {
        return None;
    }

    if verb in HTTP_DECORATORS {
        # FastAPI: @app.post("/path")
        return RawRoute(
            method=verb.upper(),
            pattern=pattern as str,
            line=dec.lineno as int,
            handler=handler
        );
    }
    if verb == "route" {
        # Flask: @app.route("/path", methods=["POST"])
        method = "GET";
        for kw in dec.keywords {
            if (kw.arg as str) == "methods" and isinstance(kw.value, ast.List) {
                for elt in kw.value.elts {
                    if isinstance(elt, ast.Constant) and isinstance(elt.value, str) {
                        method = (elt.value as str).upper();
                    }
                }
            }
        }
        return RawRoute(
            method=method,
            pattern=pattern as str,
            line=dec.lineno as int,
            handler=handler
        );
    }
    return None;
}

"""Collect the routes declared by a function's decorator list."""
def _routes_of(fn_node: any, handler: str) -> list[RawRoute] {
    out: list[RawRoute] = [];
    for dec in fn_node.decorator_list {
        found = _route_from_decorator(dec, handler);
        if found is not None {
            out.append(found);
        }
    }
    return out;
}

"""Collect the dotted module names a file imports."""
def _imports_of(tree: any) -> list[str] {
    out: list[str] = [];
    for node in ast.walk(tree) {
        if isinstance(node, ast.Import) {
            for alias in node.names {
                out.append(alias.name as str);
            }
        } elif isinstance(node, ast.ImportFrom) {
            if node.level and (node.level as int) > 0 {
                # Relative imports are resolved against the importer's package
                # in pass 2; mark them with leading dots.
                prefix = "." * (node.level as int);
                base = node.module as str if node.module else "";
                out.append(prefix + base);
                for alias in node.names {
                    joined = base + "." + (alias.name as str)
                        if base
                        else (alias.name as str);
                    out.append(prefix + joined);
                }
            } elif node.module {
                base = node.module as str;
                out.append(base);
                for alias in node.names {
                    # `from repository import db` -> also try "repository.db"
                    out.append(base + "." + (alias.name as str));
                }
            }
        }
    }
    return out;
}

"""Python source, parsed with the standard library `ast` module."""
obj PythonParser(LanguageParser) {
    has name: str = "python",
        extensions: list[str] = [".py"];

    override def parse_file(abs_path: str, rel_path: str) -> RawModule {
        mod = RawModule(
            rel_path=rel_path, name=os.path.basename(abs_path), language=self.name
        );
        try {
            handle = open(abs_path, "r", encoding="utf-8");
            src = handle.read();
            handle.close();
            tree = ast.parse(src);
        } except Exception as e {
            mod.error = f"{rel_path}: {str(e)}";
            return mod;
        }

        mod.imports = _imports_of(tree);

        for node in tree.body {
            if isinstance(node, ast.FunctionDef)
            or isinstance(node, ast.AsyncFunctionDef) {
                kind = "async_function"
                    if isinstance(node, ast.AsyncFunctionDef)
                    else "function";
                fn_name = node.name as str;
                mod.symbols.append(
                    RawSymbol(
                        name=fn_name,
                        kind=kind,
                        line=node.lineno as int,
                        source=_source_of(src, node),
                        calls=_calls_in(node)
                    )
                );
                for r in _routes_of(node, fn_name) {
                    mod.routes.append(r);
                }
            } elif isinstance(node, ast.ClassDef) {
                # A class carries no calls of its own - its methods do, and
                # they become their own symbols. Walking the class body for
                # calls here would double-count every method's call sites.
                mod.symbols.append(
                    RawSymbol(
                        name=node.name as str,
                        kind="class",
                        line=node.lineno as int,
                        source=_source_of(src, node)
                    )
                );
                for item in node.body {
                    if isinstance(item, ast.FunctionDef)
                    or isinstance(item, ast.AsyncFunctionDef) {
                        m_name = item.name as str;
                        mod.symbols.append(
                            RawSymbol(
                                name=m_name,
                                kind="method",
                                line=item.lineno as int,
                                source=_source_of(src, item),
                                calls=_calls_in(item)
                            )
                        );
                        for r in _routes_of(item, m_name) {
                            mod.routes.append(r);
                        }
                    }
                }
            }
        }
        return mod;
    }

    override def module_candidates(spec: str, importer_rel: str) -> list[str] {
        if not spec {
            return [];
        }
        if spec.startswith(".") {
            depth = len(spec) - len(spec.lstrip("."));
            tail = spec[depth:];
            pkg = os.path.dirname(importer_rel);
            for _i in range(depth - 1) {
                pkg = os.path.dirname(pkg);
            }
            stem = os.path.join(pkg, tail.replace(".", "/")) if tail else pkg;
        } else {
            stem = spec.replace(".", "/");
        }
        stem = stem.strip("/");
        if not stem {
            return [];
        }
        return [stem + ".py", stem + "/__init__.py"];
    }
}
