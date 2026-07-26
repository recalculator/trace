"""Trace - the planned-investigation endpoint.

Composes the three separated responsibilities in one direction only:

    question -> build_context -> Planner -> InvestigationPlan
             -> validate_plan -> execute_plan -> evidence
             -> explain -> PlanResult

The planner never sees the graph's contents beyond a bounded name index; the
executor never sees the question; the explainer never sees anything but
evidence. `investigate()` in `investigation_api.jac` is left untouched, so
the existing UI keeps working exactly as before.
"""

import from executor { execute_plan, validate_plan }
import from explainer { explain }
import from plan_types { InvestigationPlan, PlanResult }
import from planner {
    DeterministicPlanner,
    FakePlanner,
    PlannerContext,
    Planner,
    build_context
}

"""Run a question through planning, execution and explanation.

`planner` selects the strategy: "auto" (currently deterministic, and the
LLM-backed planner when one is configured) or "deterministic" to pin it.
No model is configured in this project yet, so both resolve to the
deterministic planner rather than failing.
"""
def:pub ask(question: str, repo_name: str = "", planner: str = "auto") -> PlanResult {
    if not question.strip() {
        return PlanResult(
            status="rejected",
            message="Ask a question about the repository.",
            question=question,
            repo=repo_name
        );
    }

    context = build_context(question, repo_name);
    chosen: Planner = DeterministicPlanner();
    plan = chosen.plan(question, repo_name, context);
    plan.repo = repo_name;

    result = execute_plan(plan);
    return explain(result);
}

"""Execute a plan that was produced elsewhere - the seam used by tests.

Validation and execution are identical to `ask`; only the planning stage is
replaced. This is what makes a fake planner testable without a model.
"""
def:pub run_plan(plan: InvestigationPlan) -> PlanResult {
    return explain(execute_plan(plan));
}

"""Plan a question without executing it - useful for inspecting routing."""
def:pub plan_only(question: str, repo_name: str = "") -> InvestigationPlan {
    context = build_context(question, repo_name);
    chosen: Planner = DeterministicPlanner();
    out = chosen.plan(question, repo_name, context);
    out.repo = repo_name;
    return out;
}
