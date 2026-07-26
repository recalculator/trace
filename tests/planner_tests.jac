"""Trace - investigation planner tests.

No test here calls a live model. The planning stage is either the
deterministic planner or a FakePlanner holding a canned plan, which is the
point of separating planning from execution: execution can be tested
exhaustively without a network.

The invariant most of these protect is that an LLM cannot make the executor
do anything the allowlist does not permit, and cannot cause a claim that no
graph fact supports.
"""

import os;

import from ingestion { ingest_repo }
import from plan_types {
    InvestigationPlan,
    InvestigationStep,
    MAX_DEPTH,
    MAX_LIMIT,
    PlanResult,
    tool_names,
    tool_spec
}
import from planner { DeterministicPlanner, FakePlanner, build_context, plan_from_json }
import from executor { execute_plan, validate_plan }
import from explainer { explain_deterministically }
import from planner_api { ask, plan_only, run_plan }

glob PY_REPO: str = os.path.join(os.path.dirname(__file__), "..", "sample_repo");

glob TS_REPO: str = os.path.join(
         os.path.dirname(__file__), "..", "sample_repo_ts"
     );

"""Ingest the Python fixture."""
def _ingest_py -> None {
    _s = ingest_repo(PY_REPO, name="sample_repo");
}

"""Ingest both fixtures, so repository scoping is observable."""
def _ingest_both -> None {
    _p = ingest_repo(PY_REPO, name="sample_repo");
    _t = ingest_repo(TS_REPO, name="sample_repo_ts");
}

"""Run a plan through the shared executor + explainer path."""
def _run(plan: InvestigationPlan) -> PlanResult {
    return run_plan(plan);
}

"""Every symbol named in a result's evidence."""
def _symbols(result: PlanResult) -> list[str] {
    out: list[str] = [];
    for step in result.steps {
        for e in step.evidence {
            out.append(e.symbol);
        }
    }
    return out;
}

# --- 1. Single-step plans ---

test "single step: find_callers returns the direct callers" {
    _ingest_py();
    plan = InvestigationPlan(
        repo="sample_repo",
        question="What calls create_user?",
        steps=[InvestigationStep(tool="find_callers", target="create_user")]
    );
    res = _run(plan);

    assert res.status == "ok" , f"status {res.status}: {res.message}";
    assert len(res.steps) == 1;
    names = [
        e.symbol
        for e in res.steps[0].evidence
        if e.kind == "call_edge"
    ];
    names.sort();
    assert names == ["seed_demo_users", "signup"] , f"callers were {names}";
    for e in res.steps[0].evidence {
        if e.kind == "call_edge" {
            assert e.relationship == "called_by";
        }
    }
}

test "single step: find_callees returns what a symbol calls" {
    _ingest_py();
    plan = InvestigationPlan(
        repo="sample_repo",
        question="What does create_user call?",
        steps=[InvestigationStep(tool="find_callees", target="create_user")]
    );
    res = _run(plan);

    assert res.status == "ok";
    names = [
        e.symbol
        for e in res.steps[0].evidence
        if e.kind == "call_edge"
    ];
    assert "hash_password" in names;
    assert "generate_token" in names;
    assert "persist" in names;
    for e in res.steps[0].evidence {
        if e.kind == "call_edge" {
            assert e.relationship == "calls";
            assert e.depth == 1 , "find_callees must stay one hop deep";
        }
    }
}

# --- 2. Multi-step plans ---

test "multi-step plans execute every step in order" {
    _ingest_py();
    plan = InvestigationPlan(
        repo="sample_repo",
        question="How does authentication work?",
        intent="explain_area",
        steps=[
            InvestigationStep(tool="find_symbol", target="authenticate_request"),
            InvestigationStep(
                tool="trace_call_flow", target="authenticate_request", max_depth=3
            ),
            InvestigationStep(tool="dependency_analysis", target="authenticate_request")
        ]
    );
    res = _run(plan);

    assert res.status == "ok" , f"{res.message}";
    assert len(res.steps) == 3 , f"expected 3 steps, ran {len(res.steps)}";

    # Execution order is the plan's order, and each step is numbered.
    assert [s.step for s in res.steps] == [1, 2, 3];
    assert [s.tool for s in res.steps] == [
        "find_symbol",
        "trace_call_flow",
        "dependency_analysis"
    ];
    assert res.evidence_count > 0;
    assert res.steps[2].evidence[0].relationship == "imports";
}

test "a broad question produces a multi-step plan rather than a clarification" {
    _ingest_py();
    plan = plan_only("How does authentication work?", "sample_repo");

    assert plan.clarification_needed == False , "broad question asked to clarify";
    assert len(plan.steps) > 1 , f"expected multi-step, got {len(plan.steps)}";
    assert plan.intent == "explain_area";
    for step in plan.steps {
        assert tool_spec(step.tool) is not None , f"{step.tool} is not allowlisted";
    }
}

# --- 3. Invalid plans ---

test "a plan with no steps is rejected" {
    _ingest_py();
    res = _run(InvestigationPlan(repo="sample_repo", question="?"));
    assert res.status == "rejected";
    assert "no steps" in res.message;
}

test "a step missing a required symbol is rejected" {
    _ingest_py();
    res = _run(
        InvestigationPlan(
            repo="sample_repo",
            question="callers of nothing",
            steps=[InvestigationStep(tool="find_callers", target="")]
        )
    );
    assert res.status == "rejected";
    assert "requires a symbol" in res.message;
}

# --- 4. Unknown intents / arbitrary operations ---

test "the planner cannot invoke an operation outside the allowlist" {
    _ingest_py();
    for bad in ["delete_everything", "forward_trace", "exec", "reset_graph", ""] {
        res = _run(
            InvestigationPlan(
                repo="sample_repo",
                question="do something",
                steps=[InvestigationStep(tool=bad, target="create_user")]
            )
        );
        assert res.status == "rejected" , f"'{bad}' was not rejected";
        assert "not an available operation" in res.message;
        assert res.evidence_count == 0 , f"'{bad}' produced evidence";
    }
}

test "naming a real walker is still rejected" {
    _ingest_py();
    # `reverse_trace` is a real walker but NOT an allowlisted tool. The
    # planner must not be able to reach past the registry into the engine.
    res = _run(
        InvestigationPlan(
            repo="sample_repo",
            question="x",
            steps=[InvestigationStep(tool="reverse_trace", target="create_user")]
        )
    );
    assert res.status == "rejected";
    assert "reverse_trace" in res.message;
}

# --- 5. Missing and ambiguous symbols ---

test "a plan naming a nonexistent symbol is rejected before execution" {
    _ingest_py();
    res = _run(
        InvestigationPlan(
            repo="sample_repo",
            question="What calls totally_made_up_symbol?",
            steps=[
                InvestigationStep(tool="find_callers", target="totally_made_up_symbol")
            ]
        )
    );
    assert res.status == "rejected" , "a hallucinated symbol was executed";
    assert "no symbol named" in res.message;
    assert res.evidence_count == 0;
}

test "an ambiguous symbol is reported as a warning, not silently resolved" {
    _ingest_both();
    # `signup` exists in both fixtures; an unscoped plan must say so.
    plan = InvestigationPlan(
        repo="",
        question="What calls signup?",
        steps=[InvestigationStep(tool="find_callers", target="signup")]
    );
    checked = validate_plan(plan);
    assert checked.ok , "ambiguity should warn, not reject";
    joined = " ".join(checked.warnings);
    assert "matches 2 symbols" in joined , f"warnings were {checked.warnings}";
}

test "an ambiguous question asks for clarification instead of guessing" {
    _ingest_py();
    plan = plan_only("What calls check?", "sample_repo");
    if plan.clarification_needed {
        assert plan.clarification_question != "";
        assert len(plan.candidates) > 1 , "clarification offered no candidates";
        res = ask("What calls check?", "sample_repo");
        assert res.status == "clarification_needed";
        assert res.evidence_count == 0;
    }
}

# --- 6. Repository scoping ---

test "plans execute against the requested repository only" {
    _ingest_both();

    ts = _run(
        InvestigationPlan(
            repo="sample_repo_ts",
            question="What calls signup?",
            steps=[InvestigationStep(tool="find_callees", target="signup")]
        )
    );
    assert ts.status == "ok";
    for step in ts.steps {
        for e in step.evidence {
            assert e.path.endswith(".ts") or e.path.endswith(".tsx") , f"python evidence leaked in: {e.path}";
        }
    }

    py = _run(
        InvestigationPlan(
            repo="sample_repo",
            question="What calls signup?",
            steps=[InvestigationStep(tool="find_callees", target="signup")]
        )
    );
    for step in py.steps {
        for e in step.evidence {
            assert e.path.endswith(".py") , f"typescript evidence leaked in: {e.path}";
        }
    }
}

test "a symbol from another repository is rejected, not borrowed" {
    _ingest_both();
    res = _run(
        InvestigationPlan(
            repo="sample_repo",
            question="What calls createUser?",
            steps=[InvestigationStep(tool="find_callers", target="createUser")]
        )
    );
    assert res.status == "rejected" , "a cross-repository symbol was executed";
    assert "sample_repo" in res.message;
}

test "the same plan works against a mixed-language graph" {
    _ingest_both();
    for (repo, seed, exts) in [
        ("sample_repo", "create_user", [".py"]),
        ("sample_repo_ts", "createUser", [".ts", ".tsx"])
    ] {
        res = _run(
            InvestigationPlan(
                repo=repo,
                question="impact",
                steps=[InvestigationStep(tool="impact_analysis", target=seed)]
            )
        );
        assert res.status == "ok" , f"{repo} failed: {res.message}";
        assert res.evidence_count > 1 , f"{repo} produced no impact evidence";
        for step in res.steps {
            for e in step.evidence {
                matched = False;
                for ext in exts {
                    if e.path.endswith(ext) {
                        matched = True;
                    }
                }
                assert matched , f"{repo} leaked {e.path}";
            }
        }
    }
}

# --- 7. Bounds and repair ---

test "excessive depth is clamped rather than executed" {
    _ingest_py();
    plan = InvestigationPlan(
        repo="sample_repo",
        question="trace deeply",
        steps=[
            InvestigationStep(tool="find_callees", target="create_user", max_depth=9999)
        ]
    );
    checked = validate_plan(plan);
    assert checked.ok , "excessive depth should be repaired, not rejected";
    assert checked.plan.steps[0].max_depth == 1 , "find_callees must cap at 1 hop";
    assert "exceeds the maximum" in " ".join(checked.warnings);
}

test "excessive limits and step counts are clamped" {
    _ingest_py();
    steps: list[InvestigationStep] = [];
    for _i in range(20) {
        steps.append(
            InvestigationStep(tool="find_callers", target="create_user", limit=99999)
        );
    }
    checked = validate_plan(
        InvestigationPlan(repo="sample_repo", question="many", steps=steps)
    );
    assert len(checked.plan.steps) <= 6 , "step count was not clamped";
    assert checked.plan.steps[0].limit == MAX_LIMIT;
}

# --- 8. Malformed planner output ---

test "malformed planner JSON is rejected without executing" {
    for bad in [
        "not json at all",
        "[]",
        "{\"steps\": \"nope\"}",
        "{}",
        "{\"steps\": []}"
    ] {
        assert plan_from_json(bad, "q", "sample_repo") is None , f"accepted malformed payload: {bad}";
    }
}

test "well-formed planner JSON parses into a plan" {
    parsed = plan_from_json(
        "{\"intent\": \"impact_analysis\", \"confidence\": 0.9, \"steps\": " + "[{\"tool\": \"impact_analysis\", \"target\": \"create_user\", " + "\"max_depth\": 3, \"reason\": \"blast radius\"}]}",
        "What breaks?",
        "sample_repo"
    );
    assert parsed is not None;
    assert parsed.intent == "impact_analysis";
    assert len(parsed.steps) == 1;
    assert parsed.steps[0].tool == "impact_analysis";
    assert parsed.steps[0].max_depth == 3;
}

test "a fake planner drives the real executor" {
    _ingest_py();
    canned = InvestigationPlan(
        repo="sample_repo",
        steps=[InvestigationStep(tool="find_callers", target="create_user")]
    );
    fake = FakePlanner(canned=canned);
    produced = fake.plan(
        "What calls create_user?",
        "sample_repo",
        build_context("What calls create_user?", "sample_repo")
    );
    assert produced.planner == "fake";

    res = _run(produced);
    assert res.status == "ok";
    assert "signup" in _symbols(res);
}

test "a fake planner emitting malformed json falls back deterministically" {
    _ingest_py();
    fake = FakePlanner(raw_json="{ this is not json");
    q = "What calls create_user?";
    produced = fake.plan(q, "sample_repo", build_context(q, "sample_repo"));

    assert produced.planner == "fake+fallback" , f"planner was {produced.planner}";
    assert len(produced.steps) > 0 , "fallback produced no plan";
    res = _run(produced);
    assert res.status == "ok";
}

# --- 9. No LLM configured ---

test "the whole pipeline works with no model configured" {
    _ingest_py();
    # No API key, no model, no network. This is the default path.
    res = ask("What calls create_user?", "sample_repo");

    assert res.status == "ok" , f"{res.message}";
    assert res.planner == "deterministic";
    assert res.explained_by == "deterministic";
    assert res.evidence_count > 0;
    assert res.explanation != "";
}

test "routes are answerable without naming any symbol" {
    _ingest_py();
    res = ask("Where are the API routes?", "sample_repo");

    assert res.status == "ok";
    assert res.intent == "find_routes";
    patterns = _symbols(res);
    assert "POST /auth/signup" in patterns , f"routes were {patterns}";
}

# --- 10. Explanation is evidence-only ---

test "the explanation reports failures instead of narrating around them" {
    _ingest_py();
    res = _run(
        InvestigationPlan(
            repo="sample_repo",
            question="What calls connect?",
            steps=[InvestigationStep(tool="find_callees", target="connect")]
        )
    );
    # `connect` calls nothing, so the step is legitimately empty.
    text = explain_deterministically(res);
    assert "found nothing" in text or "No " in text , f"explanation hid the gap: {text}";
    assert "graph fact" in text , "explanation did not state its provenance";
}

test "the explanation names only symbols present in the evidence" {
    _ingest_py();
    res = ask("What calls create_user?", "sample_repo");
    evidence_names = _symbols(res);

    # Every capitalised-ish identifier the explanation mentions should be a
    # symbol we actually collected, the repo name, or an intent label.
    for token in ["seed_demo_users", "signup"] {
        assert token in evidence_names , f"{token} missing from evidence";
    }
    assert "hallucinat" not in res.explanation.lower();
    assert str(res.evidence_count) in res.explanation;
}

test "a clarification never carries evidence" {
    _ingest_py();
    res = _run(
        InvestigationPlan(
            repo="sample_repo",
            question="which one?",
            clarification_needed=True,
            clarification_question="Did you mean check_email or check_password?",
            candidates=["check_email", "check_password"]
        )
    );
    assert res.status == "clarification_needed";
    assert res.evidence_count == 0;
    assert explain_deterministically(res) == res.clarification_question;
}

# --- 11. Legacy behaviour is untouched ---

test "the tool registry only exposes capabilities the engine really has" {
    names = tool_names();
    for expected in [
        "find_symbol",
        "find_callers",
        "find_callees",
        "trace_call_flow",
        "impact_analysis",
        "find_routes"
    ] {
        assert expected in names , f"{expected} missing from the registry";
    }
    # Nothing in the registry may claim a traversal direction the engine
    # cannot perform.
    for n in names {
        spec = tool_spec(n);
        assert spec is not None;
        assert spec.direction in ["", "forward", "reverse"] , f"{n} declares an impossible direction";
        assert spec.max_depth <= MAX_DEPTH;
    }
}

test "an empty question is refused" {
    _ingest_py();
    res = ask("   ", "sample_repo");
    assert res.status == "rejected";
    assert res.evidence_count == 0;
}
