"""Trace - the explanation layer.

Receives the question, the executed plan and the collected evidence. It never
reads the repository, never queries the graph and never runs a walker - if a
fact is not in the evidence it cannot appear in the explanation.

The deterministic explainer is the default and always works. It summarises
what was actually found and states plainly when something was not found,
which is the behaviour that matters most: a failed step must never be
narrated as a confident answer.
"""

import from plan_types { PlanResult, StepResult }

"""Group a step's evidence into a one-line summary of what was observed."""
def _summarise_step(step: StepResult) -> str {
    if step.status == "rejected" {
        return "Step " + str(step.step) + " (" + step.tool + ") was rejected: " + step.message;
    }
    if step.status == "failed" {
        return "Step " + str(step.step) + " (" + step.tool + ") failed: " + step.message;
    }
    if step.status == "empty" or not step.evidence {
        return "Step " + str(step.step) + " (" + step.tool + ") found nothing" + (
            ": " + step.message if step.message else "."
        );
    }

    findings = [
        e
        for e in step.evidence
        if e.kind != "seed"
    ];

    if step.tool == "find_routes" {
        return "Found " + str(len(findings)) + " HTTP route(s): " + ", ".join(
            [e.symbol for e in findings[:8]]
        ) + ("..." if len(findings) > 8 else "") + ".";
    }
    if step.tool == "repo_summary" {
        return "Repository contents: " + ", ".join([e.detail for e in findings]) + ".";
    }
    if step.tool == "dependency_analysis" {
        return step.target + "'s file imports " + str(len(findings)) + " other file(s): " + ", ".join(
            [e.related for e in findings[:8]]
        ) + ".";
    }
    if step.tool == "find_symbol" {
        return "'" + step.target + "' is defined at " + ", ".join(
            [e.path + ":" + str(e.line) for e in findings[:5]]
        ) + ".";
    }

    depths = [e.depth for e in findings];
    deepest = max(depths) if depths else 0;
    direction = "depend on"
        if findings and findings[0].relationship == "called_by"
        else "are reached from";
    return str(len(findings)) + " symbol(s) " + direction + " " + step.target + ", across " + str(
        deepest
    ) + " level(s): " + ", ".join([e.symbol for e in findings[:8]]) + (
        "..." if len(findings) > 8 else ""
    ) + ".";
}

"""Build an explanation from evidence alone. Always available, no model needed."""
def explain_deterministically(result: PlanResult) -> str {
    parts: list[str] = [];

    if result.status == "clarification_needed" {
        return result.clarification_question;
    }
    if result.status == "rejected" {
        return "I could not run that investigation. " + result.message;
    }

    if result.intent {
        parts.append("Intent: " + result.intent + ".");
    }

    for step in result.steps {
        parts.append(_summarise_step(step));
    }

    if result.evidence_count == 0 {
        parts.append(
            "No graph evidence was collected, so there is nothing to conclude."
        );
    }

    # Limitations are stated, never smoothed over.
    if result.warnings {
        parts.append("Caveats: " + " ".join(result.warnings));
    }

    parts.append(
        "Every statement above comes from " + str(result.evidence_count) + " graph fact(s); nothing was inferred beyond them."
    );
    return " ".join(parts);
}

"""The instruction for a model-backed explanation. Reviewable as data."""
def explanation_prompt(result: PlanResult) -> str {
    lines: list[str] = [];
    lines.append(
        "Explain a code investigation to an engineer. Use ONLY the evidence " + "below. Do not infer relationships that are not listed. If the " + "evidence is insufficient, say so plainly."
    );
    lines.append("Question: " + result.question);
    lines.append("Repository: " + result.repo);
    if result.warnings {
        lines.append("Warnings: " + " ".join(result.warnings));
    }
    lines.append("Evidence:");
    for step in result.steps {
        lines.append(
            "  step " + str(step.step) + " (" + step.tool + ", " + step.status + ")"
        );
        for e in step.evidence {
            lines.append("    - " + e.detail);
        }
        if not step.evidence {
            lines.append("    - nothing found: " + step.message);
        }
    }
    lines.append(
        "Distinguish observed facts from interpretation. Never claim a symbol " + "or relationship that is not in the evidence."
    );
    return "\n".join(lines);
}

"""Attach an explanation to a result. Deterministic unless a model is supplied."""
def explain(result: PlanResult) -> PlanResult {
    result.explanation = explain_deterministically(result);
    result.explained_by = "deterministic";
    return result;
}
