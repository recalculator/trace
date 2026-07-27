"""Trace - tests for the Anthropic-backed planner.

No test here makes a network call or needs an API key. `AnthropicPlanner`
isolates its single request behind `request_plan`, so a subclass can hand
back whatever a real model might return - valid JSON, prose, a code fence,
truncation, a hallucinated tool, nothing at all - and every downstream
guarantee is then observable.

The property under test throughout: a model can influence WHICH
investigation runs, and nothing else. It cannot widen the allowlist, invent a
symbol, exceed the bounds, or cost the user functionality by failing.
"""

import os;

import from ingestion { ingest_repo }
import from plan_types {
    InvestigationPlan,
    InvestigationStep,
    MAX_DEPTH,
    PlanResult,
    tool_names
}
import from planner { DeterministicPlanner, Planner, PlannerContext, build_context }
import from planner_anthropic {
    ANTHROPIC_MODEL,
    AnthropicPlanner,
    explain_with_claude,
    has_api_key,
    plan_schema,
    planner_system_prompt,
    planner_user_message
}
import from planner_registry { PLANNER_NAMES, llm_planning_available, select_planner }
import from planner_api { ask, plan_only, run_plan }

glob PY_REPO: str = os.path.join(os.path.dirname(__file__), "..", "sample_repo");

"""Ingest the Python fixture."""
def _ingest_py -> None {
    _s = ingest_repo(PY_REPO, name="sample_repo");
}

"""A planner whose 'model' returns a fixed payload. No network, no key."""
obj StubPlanner(AnthropicPlanner) {
    has name: str = "anthropic",
        fallback: Planner = DeterministicPlanner(),
        payloads: list[str] = [],
        calls: int = 0;

    override def request_plan(context: PlannerContext) -> str {
        idx = self.calls;
        self.calls += 1;
        if idx < len(self.payloads) {
            return self.payloads[idx];
        }
        return "";
    }
}

"""A planner primed with the responses a model would return, in order."""
def _stub(payloads: list[str]) -> StubPlanner {
    return StubPlanner(payloads=payloads);
}

"""Install a placeholder key and return the previous value.

`AnthropicPlanner` refuses to plan without a key, which is the behaviour a
separate test covers. Here the request is stubbed and never leaves the
process, so a placeholder is what lets the rest of the pipeline be observed.
"""
def _fake_key() -> str {
    saved = os.environ.get("ANTHROPIC_API_KEY", "");
    os.environ["ANTHROPIC_API_KEY"] = "sk-test-not-a-real-key";
    return saved;
}

"""Restore whatever key the environment had before."""
def _restore_key(saved: str) -> None {
    os.environ.pop("ANTHROPIC_API_KEY", None);
    if saved {
        os.environ["ANTHROPIC_API_KEY"] = saved;
    }
}

"""Plan with a given stub, with the environment left exactly as found."""
def _stub_plan(
    stub: StubPlanner, question: str = "What calls create_user?"
) -> InvestigationPlan {
    saved = _fake_key();
    ctx = build_context(question, "sample_repo");
    out = stub.plan(question, "sample_repo", ctx);
    _restore_key(saved);
    return out;
}

"""Plan a question with a stubbed model response."""
def _plan(
    payloads: list[str], question: str = "What calls create_user?"
) -> InvestigationPlan {
    return _stub_plan(_stub(payloads), question);
}

glob GOOD_PLAN: str = "{\"intent\": \"find_callers\", \"explanation_focus\": \"callers\", \"confidence\": 0.9, \"clarification_needed\": false, \"clarification_question\": \"\", \"steps\": [{\"tool\": \"find_callers\", \"target\": \"create_user\", \"max_depth\": 1, \"reason\": \"asked who calls it\"}]}";

# --- Configuration ---

test "the key is read from ANTHROPIC_API_KEY and nowhere else" {
    saved = os.environ.get("ANTHROPIC_API_KEY", "");
    os.environ.pop("ANTHROPIC_API_KEY", None);
    assert not has_api_key();

    os.environ["ANTHROPIC_API_KEY"] = "   ";
    assert not has_api_key() , "whitespace was accepted as a key";

    os.environ["ANTHROPIC_API_KEY"] = "sk-test-not-a-real-key";
    assert has_api_key();

    os.environ.pop("ANTHROPIC_API_KEY", None);
    if saved {
        os.environ["ANTHROPIC_API_KEY"] = saved;
    }
}

test "the model is a current one, not a pinned legacy id" {
    assert ANTHROPIC_MODEL == "claude-opus-5" , ANTHROPIC_MODEL;
}

test "no key is ever embedded in the source" {
    src = open(
        os.path.join(os.path.dirname(__file__), "..", "planner_anthropic.jac")
    ).read();
    assert "sk-ant" not in src , "an API key literal is present in the source";
}

# --- Missing API key ---

test "a missing API key falls back instead of crashing" {
    _ingest_py();
    saved = os.environ.get("ANTHROPIC_API_KEY", "");
    os.environ.pop("ANTHROPIC_API_KEY", None);

    ctx = build_context("What calls create_user?", "sample_repo");
    # The real planner, not the stub - this must not touch the network.
    plan = AnthropicPlanner().plan("What calls create_user?", "sample_repo", ctx);

    assert plan.planner == "anthropic+fallback:no_api_key" , plan.planner;
    assert plan.steps , "the fallback produced no plan at all";
    assert plan.steps[0].tool in tool_names();

    if saved {
        os.environ["ANTHROPIC_API_KEY"] = saved;
    }
}

test "a missing API key still answers the question end to end" {
    _ingest_py();
    saved = os.environ.get("ANTHROPIC_API_KEY", "");
    os.environ.pop("ANTHROPIC_API_KEY", None);

    res = ask("What calls create_user?", "sample_repo", planner="anthropic");
    assert res.status == "ok" , res.message;
    assert res.evidence_count > 0 , "functionality was lost when the key was absent";
    assert res.explained_by == "deterministic" , res.explained_by;

    if saved {
        os.environ["ANTHROPIC_API_KEY"] = saved;
    }
}

# --- Successful planning ---

test "a well-formed model plan is used verbatim" {
    _ingest_py();
    plan = _plan([GOOD_PLAN]);

    assert plan.planner == "anthropic" , plan.planner;
    assert plan.intent == "find_callers";
    assert len(plan.steps) == 1;
    assert plan.steps[0].tool == "find_callers";
    assert plan.steps[0].target == "create_user";
    assert plan.repo == "sample_repo";
}

test "a model plan executes through the ordinary deterministic path" {
    _ingest_py();
    res = run_plan(_plan([GOOD_PLAN]));

    assert res.status == "ok" , res.message;
    assert res.planner == "anthropic";
    assert res.evidence_count > 0;
    assert "signup" in [e.symbol for step in res.steps for e in step.evidence];
}

test "the model can request clarification instead of guessing" {
    _ingest_py();
    payload = "{\"intent\": \"clarify\", \"explanation_focus\": \"\", \"confidence\": 0.2, \"clarification_needed\": true, \"clarification_question\": \"Which 'update' did you mean?\", \"steps\": []}";
    res = run_plan(_plan([payload], "how does update work?"));

    assert res.status == "clarification_needed" , res.status;
    assert "update" in res.clarification_question;
    assert res.evidence_count == 0 , "a clarification still executed steps";
}

# --- Malformed output ---

test "malformed JSON is retried once, then falls back" {
    _ingest_py();
    stub = _stub(["not json at all", "still not json"]);
    plan = _stub_plan(stub);

    assert stub.calls == 2 , f"expected one retry, saw {stub.calls} call(s)";
    assert plan.planner == "anthropic+fallback:unusable_response" , plan.planner;
    assert plan.steps , "the fallback produced no plan";
}

test "a retry that succeeds is used" {
    _ingest_py();
    stub = _stub(["```json\n{oops", GOOD_PLAN]);
    plan = _stub_plan(stub);

    assert stub.calls == 2;
    assert plan.planner == "anthropic" , plan.planner;
    assert plan.steps[0].tool == "find_callers";
}

test "markdown fences and prose are rejected rather than half-parsed" {
    _ingest_py();
    for bad in [
        "Here is the plan:\n```json\n" + GOOD_PLAN + "\n```",
        "[]",
        "{\"steps\": \"find_callers\"}",
        "{\"intent\": \"x\"",
        "null",
        ""
    ] {
        plan = _plan([bad, bad]);
        assert plan.planner.startswith("anthropic+fallback:") , f"{bad!r} was accepted as a plan";
    }
}

# --- API failure, timeout, rate limit ---

test "an API failure falls back without a second call" {
    _ingest_py();
    # An empty payload is what _request_plan returns for a timeout, a rate
    # limit, an auth error or a connection failure - they are indistinguishable
    # here on purpose, because the response to all of them is identical.
    stub = _stub([]);
    plan = _stub_plan(stub);

    assert stub.calls == 1 , f"an API failure was retried {stub.calls} times";
    assert plan.planner == "anthropic+fallback:unusable_response";
    assert plan.steps;
}

test "a failing model never costs the user an answer" {
    _ingest_py();
    plan = _plan([], "What breaks if I change create_user?");
    res = run_plan(plan);

    assert res.status == "ok" , res.message;
    assert res.evidence_count > 0;
    assert res.explanation , "no explanation survived the failure";
}

# --- Invalid plans and validator rejection ---

test "a hallucinated tool name is rejected before execution" {
    _ingest_py();
    payload = "{\"intent\": \"x\", \"explanation_focus\": \"\", \"confidence\": 1.0, \"clarification_needed\": false, \"clarification_question\": \"\", \"steps\": [{\"tool\": \"run_shell\", \"target\": \"create_user\", \"max_depth\": 1, \"reason\": \"\"}]}";
    res = run_plan(_plan([payload, payload]));

    # Either the parser drops the step or the validator rejects it; what must
    # never happen is `run_shell` reaching the executor.
    for step in res.steps {
        assert step.tool in tool_names() , f"{step.tool} escaped the allowlist";
    }
    assert res.evidence_count == 0 or res.steps[0].tool in tool_names();
}

test "a hallucinated symbol is rejected before execution" {
    _ingest_py();
    payload = "{\"intent\": \"find_callers\", \"explanation_focus\": \"\", \"confidence\": 1.0, \"clarification_needed\": false, \"clarification_question\": \"\", \"steps\": [{\"tool\": \"find_callers\", \"target\": \"totally_invented_symbol\", \"max_depth\": 1, \"reason\": \"\"}]}";
    res = run_plan(_plan([payload, payload]));

    assert res.status == "rejected" , f"a hallucinated symbol executed: {res.status}";
    assert res.evidence_count == 0;
}

test "an over-deep model plan is clamped, not honoured" {
    _ingest_py();
    payload = "{\"intent\": \"impact\", \"explanation_focus\": \"\", \"confidence\": 1.0, \"clarification_needed\": false, \"clarification_question\": \"\", \"steps\": [{\"tool\": \"impact_analysis\", \"target\": \"create_user\", \"max_depth\": 9999, \"reason\": \"\"}]}";
    res = run_plan(_plan([payload]));

    assert res.status == "ok" , res.message;
    depths = [e.depth for step in res.steps for e in step.evidence];
    assert max(depths) <= MAX_DEPTH , f"depth {max(depths)} exceeded the cap";
    assert res.warnings , "the clamp was applied silently";
}

# --- Planner swapping ---

test "select_planner honours an explicit strategy" {
    saved = os.environ.get("ANTHROPIC_API_KEY", "");
    os.environ.pop("ANTHROPIC_API_KEY", None);

    assert select_planner("deterministic").name == "deterministic";
    assert select_planner("anthropic").name == "anthropic";
    # Without a key, "auto" must not choose a planner that needs one.
    assert select_planner("auto").name == "deterministic";
    assert not llm_planning_available();

    os.environ["ANTHROPIC_API_KEY"] = "sk-test-not-a-real-key";
    assert select_planner("auto").name == "anthropic" , "a key did not enable Claude";
    assert llm_planning_available();

    os.environ.pop("ANTHROPIC_API_KEY", None);
    if saved {
        os.environ["ANTHROPIC_API_KEY"] = saved;
    }
}

test "an unknown strategy degrades instead of raising" {
    for name in ["", "gpt-9", "  DETERMINISTIC  ", "openai"] {
        chosen = select_planner(name);
        assert chosen.name in ["deterministic", "anthropic"] , chosen.name;
    }
    assert "anthropic" in PLANNER_NAMES;
}

test "who authored a plan does not change what executes" {
    _ingest_py();
    q = "What calls create_user?";
    from_model = run_plan(_plan([GOOD_PLAN], q));
    hand_built = run_plan(
        InvestigationPlan(
            repo="sample_repo",
            question=q,
            intent="find_callers",
            steps=[
                InvestigationStep(
                    tool="find_callers", target="create_user", max_depth=1
                )
            ],
            planner="deterministic"
        )
    );

    assert from_model.planner == "anthropic";
    assert hand_built.planner == "deterministic";
    assert from_model.status == "ok" and hand_built.status == "ok";
    model_syms = sorted([e.symbol for step in from_model.steps for e in step.evidence]);
    built_syms = sorted([e.symbol for step in hand_built.steps for e in step.evidence]);
    assert model_syms == built_syms , "identical plans produced different evidence";
    assert "signup" in model_syms;
}

test "the deterministic planner is still reachable and still routes" {
    _ingest_py();
    plan = plan_only(
        "What breaks if I modify create_user?", "sample_repo", planner="deterministic"
    );
    assert plan.planner == "deterministic" , plan.planner;
    assert plan.steps[0].tool == "impact_analysis" , plan.steps[0].tool;
}

test "plan_only stays deterministic so inspection never hits the network" {
    _ingest_py();
    saved = _fake_key();
    plan = plan_only("What calls create_user?", "sample_repo");
    assert plan.planner == "deterministic" , plan.planner;
    _restore_key(saved);
}

# --- What the model is allowed to see ---

test "the prompt context contains names and counts, never source code" {
    _ingest_py();
    ctx = build_context("What calls create_user?", "sample_repo");
    msg = planner_user_message(ctx);

    assert "create_user" in msg , "candidate symbols were not offered";
    assert "sample_repo" in msg;
    # Nothing that only appears in a file's body may reach the model.
    for leaked in ["def ", "import ", "return ", "class ", "```"] {
        assert leaked not in msg , f"source-shaped text leaked into the prompt: {leaked!r}";
    }
    assert len(msg) < 20000 , f"the prompt is unbounded at {len(msg)} chars";
}

test "the schema constrains tools to the allowlist" {
    schema = plan_schema();
    step = schema["properties"]["steps"]["items"];
    assert step["properties"]["tool"]["enum"] == tool_names();
    assert step["additionalProperties"] == False;
    assert "clarification_needed" in schema["required"];
}

test "the system prompt forbids answering and lists every tool" {
    prompt = planner_system_prompt();
    for rule in [
        "Never answer the question",
        "Never invent",
        "Never guess",
        "clarification",
        "SHORT"
    ] {
        assert rule in prompt , f"the prompt does not enforce: {rule}";
    }
    for name in tool_names() {
        assert name in prompt , f"{name} is not offered to the model";
    }
}

# --- Explanation layer ---

test "the explanation falls back to evidence-only prose without a key" {
    _ingest_py();
    saved = os.environ.get("ANTHROPIC_API_KEY", "");
    os.environ.pop("ANTHROPIC_API_KEY", None);

    res = explain_with_claude(run_plan(_plan([GOOD_PLAN])));
    assert res.explained_by == "deterministic" , res.explained_by;
    assert "create_user" in res.explanation;
    assert str(res.evidence_count) in res.explanation;

    if saved {
        os.environ["ANTHROPIC_API_KEY"] = saved;
    }
}

test "an API failure in the explainer still yields an explanation" {
    _ingest_py();
    # A syntactically valid but unusable key: the SDK call raises, and the
    # deterministic summary must take over rather than the result arriving
    # with an empty explanation.
    saved = os.environ.get("ANTHROPIC_API_KEY", "");
    os.environ["ANTHROPIC_API_KEY"] = "sk-ant-invalid-key-for-testing";

    res = explain_with_claude(run_plan(_plan([GOOD_PLAN])));
    assert res.explanation , "an API failure left the result unexplained";
    assert res.explained_by.startswith("deterministic") , res.explained_by;

    os.environ.pop("ANTHROPIC_API_KEY", None);
    if saved {
        os.environ["ANTHROPIC_API_KEY"] = saved;
    }
}

test "the explainer is given evidence only, never the repository" {
    _ingest_py();
    src = open(
        os.path.join(os.path.dirname(__file__), "..", "planner_anthropic.jac")
    ).read();
    tail = src.split("def explain_with_claude")[1];
    for forbidden in [
        "ingest_repo",
        "find_symbol",
        "get_repo_graph",
        "spawn",
        "open("
    ] {
        assert forbidden not in tail , f"the explainer reaches for {forbidden}";
    }
}
