"""Wire types for the graph export and investigation APIs.

Field names match models.jac exactly. The real server endpoints
(graph_export.jac, investigation_api.jac) return these shapes so the client
never needs to change.
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

"""One traversal step, with the real graph edge jid resolved server-side."""
obj InvestEvidence {
    has depth: int = 0,
        node_id: str = "",
        node_name: str = "",
        node_path: str = "",
        node_kind: str = "",
        node_line: int = 0,
        from_id: str = "",
        from_name: str = "",
        edge_id: str = "",
        edge_type: str = "",
        edge_line: int = 0,
        explanation: str = "";
}

"""Client-ready result of one natural-language investigation."""
obj InvestResponse {
    has status: str = "ok",
        message: str = "",
        question: str = "",
        direction: str = "forward",
        seed_name: str = "",
        seed_path: str = "",
        seed_id: str = "",
        ambiguous: bool = False,
        candidates: list[str] = [],
        max_depth: int = 0,
        depth_reached: int = 0,
        depth_capped: bool = False,
        budget_exhausted: bool = False,
        duplicates_skipped: int = 0,
        node_count: int = 0,
        evidence: list[InvestEvidence] = [];
}
