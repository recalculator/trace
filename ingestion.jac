"""Trace - Python repository ingestion.

Turns a directory of `.py` files into the code graph declared in
`models.jac`. Ingestion builds the graph; it does not traverse one, so it
is a `def:pub` function rather than a walker (Jac's shape rule: no
`visit`, no walker). The walkers arrive in the next phase, once there is a
graph for them to move through.

Two passes, both deterministic:

  Pass 1  parse every file with Python's `ast`, materialise `File`,
          `Symbol` and `Route` nodes, and record unresolved references.
  Pass 2  resolve those references against an index built from pass 1 and
          draw `FileImportsFile`, `SymbolCallsSymbol` and
          `RouteHandledBySymbol` edges.

Re-ingesting the same path purges the previous `Repository` subgraph
first, so ingestion is idempotent.
"""

import os;
import ast;
import from datetime { datetime }

import from models {
    Repository,
    File,
    Symbol,
    Route,
    RepositoryContainsFile,
    FileContainsSymbol,
    FileImportsFile,
    SymbolCallsSymbol,
    RouteHandledBySymbol,
    RepositoryContainsRoute
}

glob IGNORED_DIRS: list[str] = [
         ".git",
         ".venv",
         "venv",
         "__pycache__",
         "node_modules",
         "build",
         "dist",
         ".tox",
         ".mypy_cache",
         ".pytest_cache",
         ".eggs",
         "site-packages",
         ".jac"
     ];

glob HTTP_DECORATORS: list[str] = [
         "get",
         "post",
         "put",
         "patch",
         "delete",
         "head",
         "options"
     ];

glob MAX_SOURCE_CHARS: int = 1200;

# --- Intermediate parse results (plain objs - they never touch the graph) ---

"""A call site found inside a function body."""
obj RawCall {
    has name: str = "",
        line: int = 0;
}

"""A function, async function, class or method extracted from a file."""
obj RawSymbol {
    has name: str = "",
        kind: str = "",
        line: int = 0,
        source: str = "",
        calls: list[RawCall] = [];
}

"""A route decorator found on a function."""
obj RawRoute {
    has method: str = "",
        pattern: str = "",
        line: int = 0,
        handler: str = "";
}

"""Everything pass 1 learned about one source file."""
obj RawModule {
    has rel_path: str = "",
        name: str = "",
        symbols: list[RawSymbol] = [],
        imports: list[str] = [],
        routes: list[RawRoute] = [],
        error: str = "";
}

"""A route node awaiting resolution to its handler symbol in pass 2."""
obj PendingRoute {
    has route: Route,
        handler: str,
        rel_path: str;
}

"""What an ingestion run produced."""
obj IngestSummary {
    has repo_name: str = "",
        repo_path: str = "",
        files: int = 0,
        symbols: int = 0,
        routes: int = 0,
        contains_file_edges: int = 0,
        contains_symbol_edges: int = 0,
        import_edges: int = 0,
        call_edges: int = 0,
        route_edges: int = 0,
        unresolved_calls: int = 0,
        parse_errors: list[str] = [];
}

"""Counts read back off the graph by traversal, not by the ingester."""
obj GraphStats {
    has repositories: int = 0,
        files: int = 0,
        symbols: int = 0,
        routes: int = 0;
}

# --- File discovery ---

"""Recursively collect .py files, pruning ignored directories."""
def _find_py_files(root_path: str) -> list[str] {
    found: list[str] = [];
    for (dirpath, dirnames, filenames) in os.walk(root_path) {
        keep = [
            d
            for d in dirnames
            if d not in IGNORED_DIRS and not d.startswith(".")
        ];
        dirnames[:] = keep;
        for fn in filenames {
            if fn.endswith(".py") {
                found.append(os.path.join(dirpath, fn));
            }
        }
    }
    found.sort();
    return found;
}

# --- AST extraction ---

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
    text = seg as str;
    if len(text) > MAX_SOURCE_CHARS {
        return text[:MAX_SOURCE_CHARS];
    }
    return text;
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

"""Parse one file into a RawModule. Never raises - errors ride on `.error`."""
def _parse_file(abs_path: str, rel_path: str) -> RawModule {
    mod = RawModule(rel_path=rel_path, name=os.path.basename(abs_path));
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
            # A class carries no calls of its own - its methods do, and they
            # become their own symbols. Walking the class body for calls here
            # would double-count every method's call sites.
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

# --- Reference resolution helpers ---

"""Map a dotted module name onto the repo-relative file it would live in."""
def _module_candidates(dotted: str, importer_rel: str) -> list[str] {
    if not dotted {
        return [];
    }
    if dotted.startswith(".") {
        depth = len(dotted) - len(dotted.lstrip("."));
        tail = dotted[depth:];
        pkg = os.path.dirname(importer_rel);
        for _i in range(depth - 1) {
            pkg = os.path.dirname(pkg);
        }
        stem = os.path.join(pkg, tail.replace(".", "/")) if tail else pkg;
    } else {
        stem = dotted.replace(".", "/");
    }
    stem = stem.strip("/");
    if not stem {
        return [];
    }
    return [stem + ".py", stem + "/__init__.py"];
}

# --- Ingestion ---

"""Delete a previously ingested repository subgraph so re-ingest is idempotent."""
def _purge_repository(repo: Repository) -> None {
    for f in [repo->:RepositoryContainsFile:->] {
        for s in [f->:FileContainsSymbol:->] {
            del s;
        }
        del f;
    }
    for r in [repo->:RepositoryContainsRoute:->] {
        del r;
    }
    del repo;
}

"""Ingest a local Python repository into the code graph."""
def:pub ingest_repo(path: str, name: str = "") -> IngestSummary {
    abs_root = os.path.abspath(os.path.expanduser(path));
    repo_name = name if name else os.path.basename(abs_root.rstrip("/"));
    summary = IngestSummary(repo_name=repo_name, repo_path=abs_root);

    if not os.path.isdir(abs_root) {
        summary.parse_errors = [f"not a directory: {abs_root}"];
        return summary;
    }

    # Idempotency: drop any previous ingest of this same path.
    for existing in [root-->[?:Repository]] {
        if existing.path == abs_root {
            _purge_repository(existing);
        }
    }

    repo = root ++> Repository(
        name=repo_name, path=abs_root, ingested_at=datetime.now().isoformat()
    );

    # --- Pass 1: parse and materialise nodes ---
    modules: list[RawModule] = [];
    files_by_rel: dict[str, File] = {};
    symbols_by_name: dict[str, list[Symbol]] = {};
    symbols_by_file: dict[str, dict[str, Symbol]] = {};
    routes_pending: list[PendingRoute] = [];

    for abs_path in _find_py_files(abs_root) {
        rel = os.path.relpath(abs_path, abs_root);
        mod = _parse_file(abs_path, rel);
        if mod.error {
            summary.parse_errors.append(mod.error);
            continue;
        }
        modules.append(mod);

        file_node = (
            repo +>:RepositoryContainsFile():+> File(
                name=mod.name, path=rel, language="python"
            )
        ) as File;
        files_by_rel[rel] = file_node;
        symbols_by_file[rel] = {};
        summary.files += 1;
        summary.contains_file_edges += 1;

        for raw in mod.symbols {
            sym = (
                file_node +>:FileContainsSymbol():+> Symbol(
                    name=raw.name,
                    path=rel,
                    kind=raw.kind,
                    line=raw.line,
                    source=raw.source
                )
            ) as Symbol;
            summary.symbols += 1;
            summary.contains_symbol_edges += 1;

            if raw.name not in symbols_by_name {
                symbols_by_name[raw.name] = [];
            }
            symbols_by_name[raw.name].append(sym);
            if raw.name not in symbols_by_file[rel] {
                symbols_by_file[rel][raw.name] = sym;
            }
        }

        for raw_route in mod.routes {
            route_node = (
                repo +>:RepositoryContainsRoute():+> Route(
                    name=f"{raw_route.method} {raw_route.pattern}",
                    path=rel,
                    method=raw_route.method,
                    pattern=raw_route.pattern,
                    line=raw_route.line
                )
            ) as Route;
            summary.routes += 1;
            routes_pending.append(
                PendingRoute(route=route_node, handler=raw_route.handler, rel_path=rel)
            );
        }
    }

    repo.file_count = summary.files;

    # --- Pass 2: resolve references into edges ---

    # Imports: only when the imported module resolves to a file in this repo.
    seen_imports: dict[str, bool] = {};
    for mod in modules {
        src_file = files_by_rel[mod.rel_path];
        for dotted in mod.imports {
            for cand in _module_candidates(dotted, mod.rel_path) {
                if cand in files_by_rel and cand != mod.rel_path {
                    key = mod.rel_path + "->" + cand;
                    if key not in seen_imports {
                        seen_imports[key] = True;
                        src_file +>:FileImportsFile():+> files_by_rel[cand];
                        summary.import_edges += 1;
                    }
                }
            }
        }
    }

    # Calls: same-file match wins; otherwise a globally unique name wins;
    # anything ambiguous or external is left unresolved on purpose.
    seen_calls: dict[str, bool] = {};
    for mod in modules {
        local = symbols_by_file[mod.rel_path];
        for raw in mod.symbols {
            caller = local[raw.name];
            for call in raw.calls {
                target: Symbol | None = None;
                if call.name in local {
                    target = local[call.name];
                } elif call.name in symbols_by_name
                and len(symbols_by_name[call.name]) == 1 {
                    target = symbols_by_name[call.name][0];
                }
                if target is None {
                    summary.unresolved_calls += 1;
                    continue;
                }
                if jid(target) == jid(caller) {
                    continue;
                }
                key = jid(caller) + "->" + jid(target);
                if key not in seen_calls {
                    seen_calls[key] = True;
                    caller +>:SymbolCallsSymbol(line=call.line):+> target;
                    summary.call_edges += 1;
                }
            }
        }
    }

    # Routes: bind each route to the handler function that carried the decorator.
    for pending in routes_pending {
        handler_sym: Symbol | None = None;
        local_syms = symbols_by_file[pending.rel_path];
        if pending.handler in local_syms {
            handler_sym = local_syms[pending.handler];
        } elif pending.handler in symbols_by_name
        and len(symbols_by_name[pending.handler]) == 1 {
            handler_sym = symbols_by_name[pending.handler][0];
        }
        if handler_sym is not None {
            pending.route +>:RouteHandledBySymbol():+> handler_sym;
            summary.route_edges += 1;
        }
    }

    return summary;
}

"""List the repositories currently in the graph."""
def:pub list_repositories() -> list[Repository] {
    return [root-->[?:Repository]];
}

"""Drop every ingested repository from the graph."""
def:pub reset_graph() -> int {
    repos = [root-->[?:Repository]];
    count = len(repos);
    for r in repos {
        _purge_repository(r);
    }
    return count;
}

"""Count the graph by walking it - verification independent of the ingester."""
walker:pub graph_summary {
    has repositories: int = 0,
        files: int = 0,
        symbols: int = 0,
        routes: int = 0,
        reports: list[GraphStats] = [];

    can start with Root entry {
        visit [-->[?:Repository]];
    }

    can on_repo with Repository entry {
        self.repositories += 1;
        visit [here->:RepositoryContainsFile:->];
        visit [here->:RepositoryContainsRoute:->];
    }

    can on_file with File entry {
        self.files += 1;
        visit [here->:FileContainsSymbol:->];
    }

    can on_symbol with Symbol entry {
        self.symbols += 1;
    }

    can on_route with Route entry {
        self.routes += 1;
    }

    can deliver with Root exit {
        report GraphStats(
            repositories=self.repositories,
            files=self.files,
            symbols=self.symbols,
            routes=self.routes
        );
    }
}
