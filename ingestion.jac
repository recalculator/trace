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
import from datetime { datetime }

import from langs {
    SourceFile,
    find_source_files,
    module_candidates,
    parse_source_file,
    supported_languages
}
import from parser_types { RawModule }

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

    for src in find_source_files(abs_root) {
        rel = src.rel_path;
        mod = parse_source_file(src);
        if mod.error {
            summary.parse_errors.append(mod.error);
            continue;
        }
        modules.append(mod);

        file_node = (
            repo +>:RepositoryContainsFile():+> File(
                name=mod.name, path=rel, language=mod.language
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
            for cand in module_candidates(dotted, mod.rel_path, mod.language) {
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
