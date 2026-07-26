"""Wire types for the graph export and investigation APIs.

Field names match models.jac exactly. Both the mock (client/mock_api.jac)
and the real server endpoints (graph_export.jac, investigation walkers) are
expected to return these shapes so the client never needs to change.
"""

"""Flat representation of any graph node for the UI layer.

Discriminate on node_type: "Repository" | "File" | "Symbol" | "Route".
Type-specific fields default to "" / 0 for node types that don't carry them.
"""
obj GraphNode {
    has id: str = "",
        node_type: str = "",
        name: str = "",
        path: str = "",
        ingested_at: str = "",
        file_count: int = 0,
        language: str = "",
        kind: str = "",
        line: int = 0,
        source: str = "",
        method: str = "",
        pattern: str = "";
}

"""Flat representation of any graph edge for the UI layer.

Discriminate on edge_type: "RepositoryContainsFile" | "FileContainsSymbol" |
"FileImportsFile" | "SymbolCallsSymbol" | "RouteHandledBySymbol" |
"RepositoryContainsRoute".
"""
obj GraphEdge {
    has id: str = "",
        edge_type: str = "",
        source: str = "",
        target: str = "",
        line: int = 0;
}

"""Full graph snapshot for a repository — returned by get_repo_graph."""
obj RepoGraph {
    has nodes: list[GraphNode] = [],
        edges: list[GraphEdge] = [];
}

# --- Investigation types (speculative — pending Ayaan's real signatures) ---

"""One step in an investigation trace.

node_ids and edge_ids reference GraphNode.id / GraphEdge.id values in the
RepoGraph returned by get_repo_graph — the client highlights them in-place.
"""
obj TraceStep {
    has step: int = 0,
        node_ids: list[str] = [],
        edge_ids: list[str] = [],
        label: str = "";
}

"""Result of a forward_trace or reverse_trace investigation."""
obj TraceResult {
    has symbol_id: str = "",
        direction: str = "",
        steps: list[TraceStep] = [],
        total_steps: int = 0;
}

"""A symbol match returned by find_symbol."""
obj SymbolMatch {
    has node_id: str = "",
        name: str = "",
        kind: str = "",
        path: str = "",
        line: int = 0;
}
