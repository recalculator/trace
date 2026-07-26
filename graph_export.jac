"""Trace - graph export for the client visualisation.

Serialises an already-ingested repository subgraph into the flat
`RepoGraph` wire shape defined in `docs/graph_export_shape.md`. This module
builds NO graph of its own - it only reads what `ingestion.jac` already
created, so the code graph stays the single source of truth.

The wire types are imported from `client/types.jac` rather than redeclared
here: the client and the server must agree on this shape exactly, and one
definition cannot drift from itself.

The contract fixes this as a FUNCTION endpoint (`POST /function/get_repo_graph`),
so it is a `def:pub`, not a walker. Edges are read with the paired
`[edge src ->:E:-> tgt]` form because an edge object exposes its own fields
and `jid`, but not its endpoints - so both ends must be in hand already.
"""

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

import from client.types { GraphNode, GraphEdge, RepoGraph }

# --- Node projections: one GraphNode per archetype, type-specific fields
#     left at their defaults so the client can discriminate on node_type ---

"""Project a Repository onto the flat wire node."""
def _repo_node(r: Repository) -> GraphNode {
    return GraphNode(
        id=jid(r),
        node_type="Repository",
        name=r.name,
        path=r.path,
        ingested_at=r.ingested_at,
        file_count=r.file_count
    );
}

"""Project a File onto the flat wire node."""
def _file_node(f: File) -> GraphNode {
    return GraphNode(
        id=jid(f), node_type="File", name=f.name, path=f.path, language=f.language
    );
}

"""Project a Symbol onto the flat wire node."""
def _symbol_node(s: Symbol) -> GraphNode {
    return GraphNode(
        id=jid(s),
        node_type="Symbol",
        name=s.name,
        path=s.path,
        kind=s.kind,
        line=s.line,
        source=s.source
    );
}

"""Project a Route onto the flat wire node."""
def _route_node(rt: Route) -> GraphNode {
    return GraphNode(
        id=jid(rt),
        node_type="Route",
        name=rt.name,
        path=rt.path,
        line=rt.line,
        method=rt.method,
        pattern=rt.pattern
    );
}

"""Resolve an ingested repository by name, or None when it is not in the graph."""
def _find_repo(name: str) -> Repository | None {
    for r in [root-->[?:Repository]] {
        if r.name == name {
            return r;
        }
    }
    return None;
}

"""Export a repository's subgraph as a flat node/edge snapshot for the UI."""
def:pub get_repo_graph(name: str) -> RepoGraph {
    repo = _find_repo(name);
    if repo is None {
        # Unknown repository - an empty graph, matching the mock's behaviour.
        return RepoGraph();
    }

    nodes: list[GraphNode] = [_repo_node(repo)];
    edges: list[GraphEdge] = [];

    files = [repo->:RepositoryContainsFile:->];
    routes = [repo->:RepositoryContainsRoute:->];

    # Repository -> File
    for f in files {
        nodes.append(_file_node(f));
        for e in [edge repo->:RepositoryContainsFile:->f] {
            edges.append(
                GraphEdge(
                    id=jid(e),
                    edge_type="RepositoryContainsFile",
                    source=jid(repo),
                    target=jid(f)
                )
            );
        }
    }

    # Repository -> Route
    for rt in routes {
        nodes.append(_route_node(rt));
        for e in [edge repo->:RepositoryContainsRoute:->rt] {
            edges.append(
                GraphEdge(
                    id=jid(e),
                    edge_type="RepositoryContainsRoute",
                    source=jid(repo),
                    target=jid(rt)
                )
            );
        }
    }

    # File -> Symbol, and File -> File imports
    for f in files {
        for s in [f->:FileContainsSymbol:->] {
            nodes.append(_symbol_node(s));
            for e in [edge f->:FileContainsSymbol:->s] {
                edges.append(
                    GraphEdge(
                        id=jid(e),
                        edge_type="FileContainsSymbol",
                        source=jid(f),
                        target=jid(s)
                    )
                );
            }
        }
        for other in [f->:FileImportsFile:->] {
            for e in [edge f->:FileImportsFile:->other] {
                edges.append(
                    GraphEdge(
                        id=jid(e),
                        edge_type="FileImportsFile",
                        source=jid(f),
                        target=jid(other)
                    )
                );
            }
        }
    }

    # Symbol -> Symbol calls. Walked per file so every symbol is reached
    # exactly once - call edges may cross files, but their endpoints are
    # already emitted above.
    for f in files {
        for s in [f->:FileContainsSymbol:->] {
            for callee in [s->:SymbolCallsSymbol:->] {
                for e in [edge s->:SymbolCallsSymbol:->callee] {
                    edges.append(
                        GraphEdge(
                            id=jid(e),
                            edge_type="SymbolCallsSymbol",
                            source=jid(s),
                            target=jid(callee),
                            line=e.line
                        )
                    );
                }
            }
        }
    }

    # Route -> handler Symbol
    for rt in routes {
        for handler in [rt->:RouteHandledBySymbol:->] {
            for e in [edge rt->:RouteHandledBySymbol:->handler] {
                edges.append(
                    GraphEdge(
                        id=jid(e),
                        edge_type="RouteHandledBySymbol",
                        source=jid(rt),
                        target=jid(handler)
                    )
                );
            }
        }
    }

    return RepoGraph(nodes=nodes, edges=edges);
}
