"""Trace - regression tests for repository-wide question routing.

The bug these pin down: `investigate()` resolved a seed SYMBOL from the
question before any tool had been chosen, so a repository-wide question
("where are the routes?") was rejected for naming no symbol - even though
the tool it needs, `find_routes`, takes no target at all.

The rule being protected is the one the tool registry already encodes:
a question may only be rejected for lacking a symbol when the selected
tool's `target_kind` is actually "symbol". Nothing else may require one.
"""

import os;

import from ingestion { ingest_repo }
import from plan_types { TOOLS, tool_spec }
import from investigation_api { investigate }
import from planner_api { ask, plan_only }

glob PY_REPO: str = os.path.join(os.path.dirname(__file__), "..", "sample_repo");

"""The two questions from the bug report, plus the phrasings around them."""
glob ROUTE_QUESTIONS: list[str] = [
         "Where are API routes?",
         "LIST ALL ROUTES",
         "Where are the API routes?",
         "list all routes",
         "What endpoints does this service expose?"
     ];

"""Ingest the Python fixture, which is the one with routes."""
def _ingest_py -> None {
    _s = ingest_repo(PY_REPO, name="sample_repo");
}

# --- The reported bug ---

test "repository-wide route questions are not rejected for naming no symbol" {
    _ingest_py();
    for q in ROUTE_QUESTIONS {
        res = investigate(q, "sample_repo");
        assert "No symbol in this repository matches" not in res.message , f"'{q}' was rejected by the symbol guard: {res.message}";
        assert res.status != "not_found" , f"'{q}' returned {res.status}: {res.message}";
    }
}

test "route questions actually return the repository's routes" {
    _ingest_py();
    for q in ["Where are API routes?", "LIST ALL ROUTES"] {
        res = investigate(q, "sample_repo");
        assert res.status == "ok" , f"'{q}' -> {res.status}: {res.message}";
        assert res.evidence , f"'{q}' produced no evidence";

        named = [e.node_name for e in res.evidence];
        for expected in ["POST /auth/signup", "GET /auth/me", "GET /healthz"] {
            assert expected in named , f"{expected} missing from {named}";
        }
        # Highlighting depends on real jids, never fabricated ones.
        for e in res.evidence {
            assert e.node_id != "" , f"{e.node_name} carries no node id";
        }
    }
}

# --- The underlying rule ---

test "only symbol-targeted tools may demand a symbol" {
    # The registry is the single source of truth for what needs a target.
    none_tools = [
        t.name
        for t in TOOLS
        if t.target_kind == "none"
    ];
    assert "find_routes" in none_tools , "find_routes should need no target";
    assert "repo_summary" in none_tools;
    routes_spec = tool_spec("find_routes");
    assert routes_spec is not None;
    assert routes_spec.target_kind == "none";
}

test "the planner picks a no-target tool for repository-wide questions" {
    _ingest_py();
    for q in ROUTE_QUESTIONS {
        plan = plan_only(q, "sample_repo", planner="deterministic");
        spec = tool_spec(plan.steps[0].tool);
        assert spec is not None , f"'{q}' planned an unknown tool";
        assert spec.target_kind == "none" , f"'{q}' planned {plan.steps[
            0
        ].tool} which needs a {spec.target_kind}";
    }
}

test "a repository-wide question does not require a symbol to exist" {
    _ingest_py();
    # `ask()` already routes correctly - this guards against the planner
    # pipeline regressing to the legacy symbol-first behaviour.
    for q in ["Where are API routes?", "LIST ALL ROUTES"] {
        res = ask(q, "sample_repo", planner="deterministic");
        assert res.status == "ok" , f"'{q}' -> {res.status}: {res.message}";
        assert res.evidence_count > 0;
    }
}

# --- What must NOT change ---

test "symbol questions that name nothing real are still rejected" {
    _ingest_py();
    # The guard is correct when the chosen tool genuinely needs a symbol.
    for q in ["What happens when a quokka sneezes?", "     ", ""] {
        res = investigate(q, "sample_repo");
        assert res.status == "not_found" , f"'{q}' unexpectedly returned {res.status}";
    }
}

test "symbol-targeted investigations are unchanged" {
    _ingest_py();
    res = investigate("What breaks if I modify create_user?", "sample_repo");
    assert res.status == "ok" , res.message;
    assert res.direction == "reverse";
    assert res.seed_name == "create_user";
    named = [e.node_name for e in res.evidence];
    assert "signup" in named and "seed_demo_users" in named;
    # Edge highlighting must survive the change.
    edges = [
        e.edge_id
        for e in res.evidence
        if e.from_id != ""
    ];
    assert edges and all([x != "" for x in edges]) , f"edge ids were lost: {edges}";
}
