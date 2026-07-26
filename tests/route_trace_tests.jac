"""Trace - tests for the trace_from_route capability.

The capability is a composition, not a new traversal: `get_repo_graph`
resolves the route's handler and the existing `forward_trace` walker follows
execution from there. These tests assert both halves - that the right
handler is picked, and that the downstream trace is the same call flow the
ordinary forward tools produce.
"""

import os;

import from ingestion { ingest_repo }
import from plan_types { InvestigationPlan, InvestigationStep, PlanResult, tool_spec }
import from executor { find_route_matches, validate_plan }
import from explainer { explain_deterministically }
import from planner_api { ask, plan_only, run_plan }

glob PY_REPO: str = os.path.join(os.path.dirname(__file__), "..", "sample_repo");

glob TS_REPO: str = os.path.join(
         os.path.dirname(__file__), "..", "sample_repo_ts"
     );

"""Ingest the Python fixture, which is the one with routes."""
def _ingest_py -> None {
    _s = ingest_repo(PY_REPO, name="sample_repo");
}

"""Ingest both fixtures so repository scoping is observable."""
def _ingest_both -> None {
    _p = ingest_repo(PY_REPO, name="sample_repo");
    _t = ingest_repo(TS_REPO, name="sample_repo_ts");
}

"""Run a single trace_from_route step."""
def _trace(target: str, repo: str, depth: int = 6) -> PlanResult {
    return run_plan(
        InvestigationPlan(
            repo=repo,
            question="trace " + target,
            steps=[
                InvestigationStep(
                    tool="trace_from_route", target=target, max_depth=depth
                )
            ]
        )
    );
}

"""Symbols of a given evidence kind in the first step."""
def _kind(res: PlanResult, kind: str) -> list[str] {
    return [
        e.symbol
        for e in res.steps[0].evidence
        if e.kind == kind
    ];
}

# --- Registration ---

test "trace_from_route is registered as a route-targeted tool" {
    spec = tool_spec("trace_from_route");
    assert spec is not None , "trace_from_route is not in the allowlist";
    assert spec.target_kind == "route" , f"target_kind is {spec.target_kind}";
    assert spec.direction == "forward";
    assert spec.max_depth == 6;
}

# --- Route resolution ---

test "routes resolve from method+pattern, pattern alone, and a bare segment" {
    _ingest_py();
    for target in ["POST /auth/signup", "/auth/signup", "auth/signup"] {
        matches = find_route_matches(target, "sample_repo");
        assert matches , f"'{target}' resolved to nothing";
        assert matches[0].pattern == "/auth/signup" , f"'{target}' -> {matches[
            0
        ].pattern}";
        assert matches[0].handler_name == "signup" , f"handler was {matches[
            0
        ].handler_name}";
    }
}

test "the method narrows the match when several routes share a path" {
    _ingest_py();
    get_me = find_route_matches("GET /auth/me", "sample_repo");
    assert len(get_me) == 1;
    assert get_me[0].method == "GET";

    # A method that no route uses matches nothing rather than falling back.
    assert find_route_matches("DELETE /auth/signup", "sample_repo") == [];
}

test "an unknown route resolves to nothing" {
    _ingest_py();
    assert find_route_matches("/does/not/exist", "sample_repo") == [];
    assert find_route_matches("", "sample_repo") == [];
}

# --- The trace itself ---

test "tracing a route follows execution through to the data layer" {
    _ingest_py();
    res = _trace("POST /auth/signup", "sample_repo");

    assert res.status == "ok" , f"{res.message}";
    assert _kind(res, "route") == ["POST /auth/signup"];
    assert _kind(res, "handler") == ["signup"];

    reached = _kind(res, "call_edge");
    # route -> handler -> controller -> service -> repository -> db
    for expected in [
        "validate_signup_input",
        "create_user",
        "hash_password",
        "persist",
        "execute",
        "connect"
    ] {
        assert expected in reached , f"{expected} missing from {reached}";
    }
}

test "the trace terminates naturally rather than at the cap" {
    _ingest_py();
    res = _trace("POST /auth/signup", "sample_repo", 6);

    depths = [
        e.depth
        for e in res.steps[0].evidence
        if e.kind == "call_edge"
    ];
    assert max(depths) < 6 , "the trace hit the depth cap instead of terminating";
    assert max(depths) >= 3 , f"the trace stopped too shallow: {max(depths)}";
}

test "depth bounds the trace" {
    _ingest_py();
    shallow = _trace("POST /auth/signup", "sample_repo", 1);
    deep = _trace("POST /auth/signup", "sample_repo", 6);

    shallow_depths = [
        e.depth
        for e in shallow.steps[0].evidence
        if e.kind == "call_edge"
    ];
    assert max(shallow_depths) == 1 , f"depth=1 reached {max(shallow_depths)}";
    assert len(_kind(deep, "call_edge")) > len(_kind(shallow, "call_edge")) , "a deeper trace found no more than a shallow one";
}

test "every downstream fact carries provenance" {
    _ingest_py();
    res = _trace("GET /auth/me", "sample_repo");

    for e in res.steps[0].evidence {
        assert e.node_id != "" , f"{e.symbol} has no node id";
        assert e.path != "" , f"{e.symbol} has no file";
        assert e.detail != "" , f"{e.symbol} has no description";
        if e.kind == "call_edge" {
            assert e.related != "" , f"{e.symbol} does not name its caller";
            assert e.relationship == "calls";
            assert e.line > 0;
        }
    }
}

test "the auth route reaches the authentication chain" {
    _ingest_py();
    res = _trace("GET /auth/me", "sample_repo");

    assert _kind(res, "handler") == ["me"];
    reached = _kind(res, "call_edge");
    for expected in ["require_auth", "authenticate_request", "verify_token"] {
        assert expected in reached , f"{expected} missing from {reached}";
    }
}

# --- Termination and partial results ---

test "a route whose handler calls nothing reports a terminated trace" {
    _ingest_py();
    res = _trace("GET /healthz", "sample_repo");

    # `healthz` returns a literal - the trace legitimately stops at it.
    assert _kind(res, "handler") == ["healthz"];
    assert res.steps[0].status == "partial" , f"status was {res.steps[0].status}";
    assert "terminates" in res.steps[0].message , res.steps[0].message;
    text = explain_deterministically(res);
    assert "healthz" in text;
}

# --- Validation ---

test "a plan naming a nonexistent route is rejected before execution" {
    _ingest_py();
    res = _trace("/no/such/route", "sample_repo");
    assert res.status == "rejected" , "a hallucinated route was executed";
    assert "no route matching" in res.message;
    assert res.evidence_count == 0;
}

test "trace_from_route requires a target" {
    _ingest_py();
    res = run_plan(
        InvestigationPlan(
            repo="sample_repo",
            question="trace",
            steps=[InvestigationStep(tool="trace_from_route", target="")]
        )
    );
    assert res.status == "rejected";
    assert "requires a route" in res.message , res.message;
}

test "excessive depth is clamped for route traces too" {
    _ingest_py();
    checked = validate_plan(
        InvestigationPlan(
            repo="sample_repo",
            question="trace deep",
            steps=[
                InvestigationStep(
                    tool="trace_from_route", target="POST /auth/signup", max_depth=9999
                )
            ]
        )
    );
    assert checked.ok;
    assert checked.plan.steps[0].max_depth == 6;
    assert "exceeds the maximum" in " ".join(checked.warnings);
}

# --- Repository scoping ---

test "route traces stay inside the requested repository" {
    _ingest_both();
    res = _trace("POST /auth/signup", "sample_repo");
    assert res.status == "ok";
    for e in res.steps[0].evidence {
        assert e.path.endswith(".py") , f"non-python evidence leaked in: {e.path}";
    }

    # The TypeScript fixture has no routes, so the same target must not be
    # borrowed from the Python repository.
    ts = _trace("POST /auth/signup", "sample_repo_ts");
    assert ts.status == "rejected" , "a route was borrowed across repositories";
}

# --- Planner routing ---

test "a trace-shaped route question plans trace_from_route" {
    _ingest_py();
    for q in [
        "Trace the path from the /auth/signup route to the database.",
        "Trace execution from POST /auth/signup",
        "What happens end to end for the /auth/me endpoint?"
    ] {
        plan = plan_only(q, "sample_repo");
        assert plan.intent == "trace_from_route" , f"'{q}' planned {plan.intent}";
        assert len(plan.steps) == 1;
        assert plan.steps[0].tool == "trace_from_route";
        assert plan.steps[0].target.startswith("POST ")
        or plan.steps[0].target.startswith("GET ") , f"target was {plan.steps[
            0
        ].target}";
    }
}

test "listing routes is still preferred when no route is named" {
    _ingest_py();
    plan = plan_only("Where are the API routes?", "sample_repo");
    assert plan.intent == "find_routes" , f"planned {plan.intent} instead";
}

test "the full pipeline answers the route-to-database question" {
    _ingest_py();
    res = ask(
        "Trace the path from the /auth/signup route to the database.", "sample_repo"
    );

    assert res.status == "ok" , f"{res.message}";
    assert res.intent == "trace_from_route";
    assert res.evidence_count > 5;
    assert "signup" in res.explanation;
    assert "handled by" in res.explanation;
    assert str(res.evidence_count) in res.explanation;
}
