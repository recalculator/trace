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
import from planner_anthropic { explain_with_claude }
import from planner_registry { select_planner }

"""Run a question through planning, execution and explanation.

`planner` selects the strategy - "auto", "anthropic" or "deterministic";
see `planner_registry`. "auto" uses Claude when ANTHROPIC_API_KEY is set and
the local planner otherwise, so the endpoint behaves identically either way.

Only the planning and explanation stages differ between strategies.
Validation and execution are deterministic in every case: whatever produced
the plan, the same allowlist and the same walkers run it.
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
    chosen: Planner = select_planner(planner);
    plan = chosen.plan(question, repo_name, context);
    plan.repo = repo_name;

    return run_plan(plan, explain_with=planner);
}

"""Execute a plan that was produced elsewhere - the seam used by tests.

Validation and execution are identical to `ask`; only the planning stage is
replaced. This is what makes a fake planner testable without a model.

`explain_with` defaults to the deterministic summary so that executing a
plan directly never makes a network call unless it was asked to.
"""
def:pub run_plan(
    plan: InvestigationPlan, explain_with: str = "deterministic"
) -> PlanResult {
    result = execute_plan(plan);
    if (explain_with or "").strip().lower() == "deterministic" {
        return explain(result);
    }
    # Evidence-only, and itself falling back to `explain` on any failure.
    return explain_with_claude(result);
}

"""Plan a question without executing it - useful for inspecting routing."""
def:pub plan_only(
    question: str, repo_name: str = "", planner: str = "deterministic"
) -> InvestigationPlan {
    context = build_context(question, repo_name);
    chosen: Planner = select_planner(planner);
    out = chosen.plan(question, repo_name, context);
    out.repo = repo_name;
    return out;
}
