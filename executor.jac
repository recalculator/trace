"""Trace - plan validation and deterministic execution.

The planner decides WHICH investigation to run. This module decides HOW, and
it is the only place that touches the graph. Nothing here consults an LLM.

Two guarantees this file exists to provide:

  A plan can only invoke allowlisted tools. `tool` is matched against the
  registry in `plan_types.jac`; anything else is rejected, so an LLM cannot
  name a walker, a function or a Jac expression and have it run.

  Evidence is never invented. Every `PlanEvidence` is built from a node or
  edge returned by an existing primitive, and any step naming a symbol that
  is not in the graph fails validation before execution rather than
  producing plausible-looking output.
"""

import from investigation { find_symbol, forward_trace, reverse_trace }
import from graph_export { get_repo_graph }
import from plan_types {
    DEFAULT_LIMIT,
    InvestigationPlan,
    InvestigationStep,
    MAX_DEPTH,
    MAX_LIMIT,
    MAX_STEPS,
    PlanEvidence,
    PlanResult,
    StepResult,
    ToolSpec,
    tool_names,
    tool_spec
}

"""A plan after validation, plus whatever had to be corrected."""
obj ValidatedPlan {
    has plan: InvestigationPlan = InvestigationPlan(),
        ok: bool = True,
        errors: list[str] = [],
        warnings: list[str] = [];
}

# --- Validation ---

"""Check a plan against the allowlist and the graph. Repairs what is safely
repairable (depth, limit) and rejects what is not (unknown tool, unknown
symbol)."""
def validate_plan(plan: InvestigationPlan) -> ValidatedPlan {
    out = ValidatedPlan(plan=plan);

    if not plan.steps and not plan.clarification_needed {
        out.ok = False;
        out.errors.append("The plan contains no steps.");
        return out;
    }

    if len(plan.steps) > MAX_STEPS {
        out.warnings.append(
            "Plan had " + str(len(plan.steps)) + " steps; kept the first " + str(
                MAX_STEPS
            ) + "."
        );
        plan.steps = plan.steps[:MAX_STEPS];
    }

    kept: list[InvestigationStep] = [];
    for (i, step) in enumerate(plan.steps) {
        label = "step " + str(i + 1);
        spec = tool_spec(step.tool);

        if spec is None {
            # The anti-arbitrary-operation guarantee.
            out.errors.append(
                label + ": '" + step.tool + "' is not an available operation. " + "Available: " + ", ".join(
                    tool_names()
                ) + "."
            );
            continue;
        }

        if spec.needs_symbol and not step.target.strip() {
            out.errors.append(label + ": '" + step.tool + "' requires a symbol.");
            continue;
        }

        # Depth and limit are clamped rather than rejected: an over-eager
        # number is a bad request, not a dangerous one.
        depth = step.max_depth if step.max_depth > 0 else spec.default_depth;
        if depth > spec.max_depth {
            out.warnings.append(
                label + ": depth " + str(depth) + " exceeds the maximum for " + step.tool + "; used " + str(
                    spec.max_depth
                ) + "."
            );
            depth = spec.max_depth;
        }
        if depth < 0 {
            depth = spec.default_depth;
        }
        step.max_depth = depth;

        if step.limit <= 0 {
            step.limit = DEFAULT_LIMIT;
        }
        if step.limit > MAX_LIMIT {
            out.warnings.append(
                label + ": limit " + str(step.limit) + " exceeds " + str(MAX_LIMIT) + "."
            );
            step.limit = MAX_LIMIT;
        }

        # The anti-hallucination guarantee: a named symbol must exist in the
        # scoped repository before anything is executed against it.
        if spec.needs_symbol {
            matches = find_symbol(step.target, plan.repo);
            if not matches {
                out.errors.append(
                    label + ": no symbol named '" + step.target + "' exists in " + (
                        plan.repo if plan.repo else "this graph"
                    ) + "."
                );
                continue;
            }
            if len(matches) > 1 {
                out.warnings.append(
                    label + ": '" + step.target + "' matches " + str(len(matches)) + " symbols; used " + matches[
                        0
                    ].path + ":" + str(matches[0].line) + "."
                );
            }
        }

        kept.append(step);
    }

    plan.steps = kept;
    if out.errors {
        out.ok = False;
    }
    return out;
}

# --- Tool implementations. Each one calls an EXISTING primitive. ---

"""find_symbol / inspect_symbol - locate a symbol and describe it."""
def _run_lookup(step: InvestigationStep, repo: str, index: int) -> StepResult {
    res = StepResult(step=index, tool=step.tool, target=step.target);
    for m in find_symbol(step.target, repo)[:step.limit] {
        res.evidence.append(
            PlanEvidence(
                step=index,
                tool=step.tool,
                kind="definition",
                symbol=m.name,
                path=m.path,
                line=m.line,
                node_id=m.symbol_id,
                relationship="defined_in",
                detail=m.name + " (" + m.kind + ") is defined at " + m.path + ":" + str(
                    m.line
                )
            )
        );
    }
    if not res.evidence {
        res.status = "empty";
        res.message = "No symbol named '" + step.target + "'.";
    }
    return res;
}

"""Any traversal tool - delegates to the existing forward/reverse walkers."""
def _run_trace(
    step: InvestigationStep, repo: str, index: int, spec: ToolSpec
) -> StepResult {
    res = StepResult(step=index, tool=step.tool, target=step.target);

    reports: list[any] = [];
    if spec.direction == "reverse" {
        w_rev = root spawn reverse_trace(
            target_name=step.target, repo_name=repo, max_depth=step.max_depth
        );
        reports = w_rev.reports;
    } else {
        w_fwd = root spawn forward_trace(
            target_name=step.target, repo_name=repo, max_depth=step.max_depth
        );
        reports = w_fwd.reports;
    }

    if not reports {
        res.status = "failed";
        res.message = "The walker produced no report.";
        return res;
    }

    traced = reports[0];
    if (traced.status as str) != "ok" {
        res.status = "empty";
        res.message = "'" + step.target + "' is not in the code graph.";
        return res;
    }

    relationship = "called_by" if spec.direction == "reverse" else "calls";
    found: list[any] = list(traced.evidence);
    for ev in found[:step.limit] {
        if (ev.depth as int) == 0 and step.tool != "inspect_symbol" {
            # The seed is context, not a finding, for traversal tools.
            res.evidence.append(
                PlanEvidence(
                    step=index,
                    tool=step.tool,
                    kind="seed",
                    symbol=ev.node_name as str,
                    path=ev.node_path as str,
                    line=ev.node_line as int,
                    node_id=ev.node_id as str,
                    depth=0,
                    detail=ev.explanation as str
                )
            );
            continue;
        }
        res.evidence.append(
            PlanEvidence(
                step=index,
                tool=step.tool,
                kind="call_edge",
                symbol=ev.node_name as str,
                path=ev.node_path as str,
                line=ev.node_line as int,
                node_id=ev.node_id as str,
                related=ev.from_name as str,
                relationship=relationship,
                depth=ev.depth as int,
                detail=ev.explanation as str
            )
        );
    }

    if len(res.evidence) <= 1 {
        res.status = "empty";
        res.message = "No " + relationship + " relationships found for '" + step.target + "'.";
    }
    return res;
}

"""dependency_analysis - file-level imports, read from the exported graph."""
def _run_dependencies(step: InvestigationStep, repo: str, index: int) -> StepResult {
    res = StepResult(step=index, tool=step.tool, target=step.target);
    matches = find_symbol(step.target, repo);
    if not matches {
        res.status = "empty";
        res.message = "No symbol named '" + step.target + "'.";
        return res;
    }
    owner_path = matches[0].path;

    graph = get_repo_graph(repo);
    by_id: dict[str, any] = {};
    for n in graph.nodes {
        by_id[n.id] = n;
    }

    for e in graph.edges {
        if e.edge_type != "FileImportsFile" {
            continue;
        }
        src = by_id[e.source] if e.source in by_id else None;
        dst = by_id[e.target] if e.target in by_id else None;
        if src is None or dst is None or (src.path as str) != owner_path {
            continue;
        }
        res.evidence.append(
            PlanEvidence(
                step=index,
                tool=step.tool,
                kind="import",
                symbol=step.target,
                path=owner_path,
                node_id=e.id,
                related=dst.path as str,
                relationship="imports",
                detail=owner_path + " imports " + (dst.path as str)
            )
        );
    }
    if not res.evidence {
        res.status = "empty";
        res.message = owner_path + " imports nothing else in this repository.";
    }
    return res;
}

"""find_routes - routes and their handlers, read from the exported graph."""
def _run_routes(step: InvestigationStep, repo: str, index: int) -> StepResult {
    res = StepResult(step=index, tool=step.tool, target=step.target);
    graph = get_repo_graph(repo);

    by_id: dict[str, any] = {};
    for n in graph.nodes {
        by_id[n.id] = n;
    }
    handler_of: dict[str, str] = {};
    for e in graph.edges {
        if e.edge_type == "RouteHandledBySymbol" {
            handler_of[e.source] = e.target;
        }
    }

    for n in graph.nodes {
        if (n.node_type as str) != "Route" {
            continue;
        }
        handler_name = "";
        handler_path = "";
        if n.id in handler_of {
            h = by_id[handler_of[n.id]] if handler_of[n.id] in by_id else None;
            if h is not None {
                handler_name = h.name as str;
                handler_path = h.path as str;
            }
        }
        res.evidence.append(
            PlanEvidence(
                step=index,
                tool=step.tool,
                kind="route",
                symbol=(n.method as str) + " " + (n.pattern as str),
                path=n.path as str,
                line=n.line as int,
                node_id=n.id as str,
                related=handler_name,
                relationship="handled_by",
                detail=(n.method as str) + " " + (n.pattern as str) + (
                    " is handled by " + handler_name + " (" + handler_path + ")"
                        if handler_name
                        else " has no resolved handler"
                )
            )
        );
        if len(res.evidence) >= step.limit {
            break;
        }
    }
    if not res.evidence {
        res.status = "empty";
        res.message = "No HTTP routes were detected in this repository.";
    }
    return res;
}

"""repo_summary - counts, read from the exported graph."""
def _run_summary(step: InvestigationStep, repo: str, index: int) -> StepResult {
    res = StepResult(step=index, tool=step.tool, target=step.target);
    graph = get_repo_graph(repo);
    counts: dict[str, int] = {};
    for n in graph.nodes {
        key = n.node_type as str;
        counts[key] = counts.get(key, 0) + 1;
    }
    if not graph.nodes {
        res.status = "empty";
        res.message = "Repository '" + repo + "' is not in the graph.";
        return res;
    }
    for key in ["File", "Symbol", "Route"] {
        res.evidence.append(
            PlanEvidence(
                step=index,
                tool=step.tool,
                kind="count",
                symbol=key,
                relationship="count",
                detail=str(counts.get(key, 0)) + " " + key + " nodes"
            )
        );
    }
    return res;
}

"""Execute one validated step against the graph."""
def execute_step(step: InvestigationStep, repo: str, index: int) -> StepResult {
    spec = tool_spec(step.tool);
    if spec is None {
        return StepResult(
            step=index,
            tool=step.tool,
            target=step.target,
            status="rejected",
            message="'" + step.tool + "' is not an available operation."
        );
    }

    if step.tool == "find_routes" {
        return _run_routes(step, repo, index);
    }
    if step.tool == "repo_summary" {
        return _run_summary(step, repo, index);
    }
    if step.tool == "dependency_analysis" {
        return _run_dependencies(step, repo, index);
    }
    if step.tool == "find_symbol" {
        return _run_lookup(step, repo, index);
    }
    return _run_trace(step, repo, index, spec);
}

"""Validate a plan and execute it in order. The only entry point that runs a plan."""
def execute_plan(plan: InvestigationPlan) -> PlanResult {
    result = PlanResult(
        question=plan.question,
        repo=plan.repo,
        intent=plan.intent,
        planner=plan.planner,
        clarification_needed=plan.clarification_needed,
        clarification_question=plan.clarification_question,
        candidates=plan.candidates
    );

    if plan.clarification_needed {
        result.status = "clarification_needed";
        result.message = plan.clarification_question;
        return result;
    }

    checked = validate_plan(plan);
    result.warnings = checked.warnings;
    if not checked.ok {
        result.status = "rejected";
        result.message = " ".join(checked.errors);
        return result;
    }

    total = 0;
    for (i, step) in enumerate(checked.plan.steps) {
        outcome = execute_step(step, plan.repo, i + 1);
        result.steps.append(outcome);
        total += len(outcome.evidence);
    }
    result.evidence_count = total;

    if total == 0 {
        result.status = "empty";
        result.message = "The plan executed but produced no graph evidence.";
    }
    return result;
}
