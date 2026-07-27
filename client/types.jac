"""Wire types for the graph export, investigation, and planner APIs.

Field names match models.jac / plan_types.jac exactly. The real server
endpoints return these shapes so the client never needs to change.
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

"""Outcome of cloning and ingesting a GitHub repository.

`status` is one of "ok" | "invalid_url" | "clone_failed" | "unsupported" |
"error"; `message` is always safe to show the user directly.
"""
obj CloneResult {
    has status: str = "",
        message: str = "",
        repo_name: str = "",
        repo_id: str = "",
        url: str = "",
        files: int = 0,
        symbols: int = 0,
        routes: int = 0,
        call_edges: int = 0,
        cleaned_up: bool = False;
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

"""Client-ready result of one natural-language investigation (investigate endpoint)."""
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

"""One piece of evidence from a planner step (ask / run_plan endpoint)."""
obj PlanEvidence {
    has step: int = 0,
        tool: str = "",
        kind: str = "",
        symbol: str = "",
        path: str = "",
        line: int = 0,
        node_id: str = "",
        related: str = "",
        relationship: str = "",
        depth: int = 0,
        detail: str = "";
}

"""The outcome of executing one planner step."""
obj StepResult {
    has step: int = 0,
        tool: str = "",
        target: str = "",
        status: str = "ok",
        message: str = "",
        evidence: list[PlanEvidence] = [];
}

"""The full result of ask() — planning + execution + Anthropic explanation."""
obj PlanResult {
    has status: str = "ok",
        message: str = "",
        question: str = "",
        repo: str = "",
        intent: str = "",
        planner: str = "",
        clarification_needed: bool = False,
        clarification_question: str = "",
        candidates: list[str] = [],
        warnings: list[str] = [],
        steps: list[StepResult] = [],
        evidence_count: int = 0,
        explanation: str = "",
        explained_by: str = "";
}
