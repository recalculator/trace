"""Trace - the investigation plan schema and tool allowlist.

A plan is data. It names tools from a fixed registry and the arguments they
take; it can never name a walker, a Jac expression or anything executable.
That is the property that makes an LLM-authored plan safe to run: the worst
a bad plan can do is fail validation.

Every tool here maps onto a capability that ALREADY exists
(`forward_trace`, `reverse_trace`, `find_symbol`, `get_repo_graph`). No new
graph operation was invented to satisfy the planner - the vocabulary was
derived from the engine, not the other way round.
"""

glob MAX_STEPS: int = 6;

glob MAX_DEPTH: int = 6;

glob MAX_LIMIT: int = 200;

glob DEFAULT_LIMIT: int = 50;

"""One deterministic capability the planner is allowed to request.

`needs_symbol` tools are validated against the graph before execution, so a
plan naming a symbol that does not exist is rejected rather than run.
`direction` and `depth` are the fixed traversal semantics of the tool; the
planner may narrow depth but never change direction.
"""
obj ToolSpec {
    has name: str = "",
        summary: str = "",
        needs_symbol: bool = True,
        direction: str = "",
        default_depth: int = 1,
        max_depth: int = MAX_DEPTH;
}

"""The allowlist. A tool absent from this registry cannot be executed."""
glob TOOLS: list[ToolSpec] = [
         ToolSpec(
             name="find_symbol",
             summary="Locate a symbol by exact name and report where it is defined.",
             needs_symbol=True,
             direction="",
             default_depth=0,
             max_depth=0
         ),
         ToolSpec(
             name="inspect_symbol",
             summary="Report a symbol's kind, file, line and immediate neighbours.",
             needs_symbol=True,
             direction="",
             default_depth=1,
             max_depth=1
         ),
         ToolSpec(
             name="find_callees",
             summary="What a symbol calls directly (one hop forward).",
             needs_symbol=True,
             direction="forward",
             default_depth=1,
             max_depth=1
         ),
         ToolSpec(
             name="find_callers",
             summary="What calls a symbol directly (one hop backward).",
             needs_symbol=True,
             direction="reverse",
             default_depth=1,
             max_depth=1
         ),
         ToolSpec(
             name="trace_call_flow",
             summary="Follow execution forward from a symbol through the call graph.",
             needs_symbol=True,
             direction="forward",
             default_depth=MAX_DEPTH,
             max_depth=MAX_DEPTH
         ),
         ToolSpec(
             name="impact_analysis",
             summary="Everything that transitively depends on a symbol - its blast radius.",
             needs_symbol=True,
             direction="reverse",
             default_depth=MAX_DEPTH,
             max_depth=MAX_DEPTH
         ),
         ToolSpec(
             name="dependency_analysis",
             summary="Which files the symbol's file imports, within this repository.",
             needs_symbol=True,
             direction="",
             default_depth=0,
             max_depth=0
         ),
         ToolSpec(
             name="find_routes",
             summary="Every HTTP route in the repository and the symbol that handles it.",
             needs_symbol=False,
             direction="",
             default_depth=0,
             max_depth=0
         ),
         ToolSpec(
             name="repo_summary",
             summary="Counts of files, symbols and routes in the repository.",
             needs_symbol=False,
             direction="",
             default_depth=0,
             max_depth=0
         )
     ];

"""One requested operation. `tool` must name a ToolSpec."""
obj InvestigationStep {
    has tool: str = "",
        target: str = "",
        max_depth: int = 0,
        limit: int = DEFAULT_LIMIT,
        reason: str = "";
}

"""What the planner produces. Never an answer - only what to execute."""
obj InvestigationPlan {
    has repo: str = "",
        question: str = "",
        intent: str = "",
        steps: list[InvestigationStep] = [],
        explanation_focus: str = "",
        confidence: float = 0.0,
        clarification_needed: bool = False,
        clarification_question: str = "",
        candidates: list[str] = [],
        planner: str = "";
}

"""One graph fact, traceable to the node or edge it came from."""
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

"""The outcome of executing one step."""
obj StepResult {
    has step: int = 0,
        tool: str = "",
        target: str = "",
        status: str = "ok",
        message: str = "",
        evidence: list[PlanEvidence] = [];
}

"""The outcome of executing a whole plan."""
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

"""The ToolSpec for a name, or None when the name is not allowlisted."""
def tool_spec(name: str) -> ToolSpec | None {
    for t in TOOLS {
        if t.name == name {
            return t;
        }
    }
    return None;
}

"""Every allowlisted tool name."""
def tool_names() -> list[str] {
    return [t.name for t in TOOLS];
}
