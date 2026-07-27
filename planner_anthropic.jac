"""Trace - the Anthropic-backed planner and explanation layer.

Claude decides WHICH investigations to run; it never traverses the graph,
never sees source code, and never produces evidence. Its entire output is an
`InvestigationPlan`, which the existing validator and executor then police -
so a bad or adversarial plan fails validation rather than doing anything.

Everything here degrades to the deterministic path. No API key, a timeout, a
rate limit, malformed JSON, a schema mismatch, a refusal - all of it falls
back to `DeterministicPlanner`, which needs no network. The user never loses
functionality because the model was unavailable.

Two design points worth knowing:

  The plan is requested as a STRUCTURED OUTPUT (`output_config.format` with a
  JSON schema), not as prose we hope parses. The API constrains generation to
  the schema, which removes an entire class of parse failures. The retry and
  the fallback still exist beneath it.

  The key is read from ANTHROPIC_API_KEY and nowhere else. It is never a
  parameter, never logged, and never written to a plan or a result.
"""

import os;
import json;

import from plan_types {
    InvestigationPlan,
    MAX_DEPTH,
    MAX_STEPS,
    PlanResult,
    TOOLS,
    tool_names
}
import from planner { DeterministicPlanner, Planner, PlannerContext, plan_from_json }
import from explainer { explain_deterministically, explanation_prompt }

"""The model. Claude Opus 5 - the current, most capable Opus."""
glob ANTHROPIC_MODEL: str = "claude-opus-5";

"""A plan is small, but thinking shares this budget on Opus 5 - leave room.

If the budget is exhausted before the plan is emitted the response comes
back truncated, which is treated as a failure rather than parsed.
"""
glob PLAN_MAX_TOKENS: int = 8000;

"""Explanations are prose over a bounded evidence set."""
glob EXPLAIN_MAX_TOKENS: int = 2000;

"""Seconds before a call is abandoned and the deterministic path takes over."""
glob REQUEST_TIMEOUT: float = 60.0;

"""One reattempt on a malformed response, then fall back."""
glob PARSE_RETRIES: int = 1;

"""True when a key is present in the environment."""
def has_api_key() -> bool {
    return bool(os.environ.get("ANTHROPIC_API_KEY", "").strip());
}

"""The JSON schema the model's plan must satisfy.

Passed as a structured-output format so the API constrains generation rather
than the parser rejecting it afterwards. `tool` is an enum of the allowlist,
so the model cannot even emit an operation name that does not exist.
"""
def plan_schema() -> dict {
    return {
        "type": "object",
        "properties": {
            "intent": {
                "type": "string",
                "description": "Short label for what the user wants to learn."
            },
            "explanation_focus": {
                "type": "string",
                "description": "What the final explanation should concentrate on."
            },
            "confidence": {"type": "number"},
            "clarification_needed": {"type": "boolean"},
            "clarification_question": {
                "type": "string",
                "description": "Ask this when the question is genuinely ambiguous. Empty otherwise."
            },
            "steps": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "tool": {"type": "string", "enum": tool_names()},
                        "target": {
                            "type": "string",
                            "description": "Symbol name, or route as 'METHOD /path'. Empty when the tool needs none."
                        },
                        "max_depth": {"type": "integer"},
                        "reason": {"type": "string"}
                    },
                    "required": ["tool", "target", "max_depth", "reason"],
                    "additionalProperties": False
                }
            }
        },
        "required": [
            "intent",
            "explanation_focus",
            "confidence",
            "clarification_needed",
            "clarification_question",
            "steps"
        ],
        "additionalProperties": False
    };
}

"""The system prompt. Kept here as data so it is reviewable in diffs."""
def planner_system_prompt() -> str {
    lines: list[str] = [];
    lines.append(
        "You plan code investigations for Trace, a tool that answers questions " + "about a repository by traversing a code graph."
    );
    lines.append("");
    lines.append("You are NOT answering the user's question. You are only");
    lines.append("choosing which deterministic investigations should run.");
    lines.append("");
    lines.append("Absolute rules:");
    lines.append("- Never answer the question. Never explain code. Never summarise.");
    lines.append("- Never describe what the code does. A separate stage does that.");
    lines.append("- Never invent a relationship, a call, a route, or a file.");
    lines.append(
        "- Never invent a symbol name. Use ONLY names given to you in the context."
    );
    lines.append("- Never invent a tool name. Use ONLY the listed tools.");
    lines.append("- Never guess. If you are unsure, request clarification.");
    lines.append("- Never emit prose, markdown, or commentary. Emit only the plan.");
    lines.append("");
    lines.append("Judgement:");
    lines.append(
        "- Plans should be as SHORT as possible while still answering the " + "question. One step is usually right; use more only when the question " + "genuinely needs them."
    );
    lines.append(
        "- If several symbols in the context are plausible and the question does " + "not distinguish them, set clarification_needed instead of picking one."
    );
    lines.append(
        "- If the repository context contains nothing relevant to the question, " + "set clarification_needed and say what is missing."
    );
    lines.append("- Correctness matters far more than creativity. Be conservative.");
    lines.append("");
    lines.append("Available tools:");
    for t in TOOLS {
        target = "route"
            if t.target_kind == "route"
            else ("symbol" if t.target_kind == "symbol" else "no target");
        lines.append("  " + t.name + " (" + target + ") - " + t.summary);
    }
    lines.append("");
    lines.append("Examples:");
    lines.append("");
    lines.append("Q: \"What calls processPayment?\"  (context lists processPayment)");
    lines.append(
        "{\"intent\": \"find_callers\", \"explanation_focus\": \"what depends on " + "processPayment\", \"confidence\": 0.9, \"clarification_needed\": false, " + "\"clarification_question\": \"\", \"steps\": [{\"tool\": \"find_callers\", " + "\"target\": \"processPayment\", \"max_depth\": 1, \"reason\": \"The " + "question asks who calls it.\"}]}"
    );
    lines.append("");
    lines.append("Q: \"What does processPayment call?\"");
    lines.append(
        "{\"intent\": \"find_callees\", \"explanation_focus\": \"what " + "processPayment invokes\", \"confidence\": 0.9, \"clarification_needed\": " + "false, \"clarification_question\": \"\", \"steps\": [{\"tool\": " + "\"find_callees\", \"target\": \"processPayment\", \"max_depth\": 1, " + "\"reason\": \"The question asks what it calls.\"}]}"
    );
    lines.append("");
    lines.append(
        "Q: \"How does authentication work?\"  (context lists authenticate_request)"
    );
    lines.append(
        "{\"intent\": \"explain_area\", \"explanation_focus\": \"the authentication " + "path\", \"confidence\": 0.6, \"clarification_needed\": false, " + "\"clarification_question\": \"\", \"steps\": [{\"tool\": \"find_symbol\", " + "\"target\": \"authenticate_request\", \"max_depth\": 0, \"reason\": " + "\"Locate the entry point.\"}, {\"tool\": \"trace_call_flow\", \"target\": " + "\"authenticate_request\", \"max_depth\": 6, \"reason\": \"Follow execution " + "outward.\"}, {\"tool\": \"dependency_analysis\", \"target\": " + "\"authenticate_request\", \"max_depth\": 0, \"reason\": \"Show what that " + "area depends on.\"}]}"
    );
    lines.append("");
    lines.append("Q: \"What breaks if I modify UserRepository?\"");
    lines.append(
        "{\"intent\": \"impact_analysis\", \"explanation_focus\": \"the blast " + "radius of UserRepository\", \"confidence\": 0.9, \"clarification_needed\": " + "false, \"clarification_question\": \"\", \"steps\": [{\"tool\": " + "\"impact_analysis\", \"target\": \"UserRepository\", \"max_depth\": 6, " + "\"reason\": \"The question asks what depends on it.\"}]}"
    );
    lines.append("");
    lines.append("Q: \"Where are the API routes?\"");
    lines.append(
        "{\"intent\": \"find_routes\", \"explanation_focus\": \"the HTTP surface\", " + "\"confidence\": 0.95, \"clarification_needed\": false, " + "\"clarification_question\": \"\", \"steps\": [{\"tool\": \"find_routes\", " + "\"target\": \"\", \"max_depth\": 0, \"reason\": \"The question asks for " + "the route list.\"}]}"
    );
    lines.append("");
    lines.append("Q: \"Trace /auth/signup to the database\"");
    lines.append(
        "{\"intent\": \"trace_from_route\", \"explanation_focus\": \"the execution " + "path behind the signup route\", \"confidence\": 0.85, " + "\"clarification_needed\": false, \"clarification_question\": \"\", " + "\"steps\": [{\"tool\": \"trace_from_route\", \"target\": \"POST " + "/auth/signup\", \"max_depth\": 6, \"reason\": \"Follow execution from the " + "route through its handler.\"}]}"
    );
    lines.append("");
    lines.append("Q: \"What about update?\"  (context lists several update* symbols)");
    lines.append(
        "{\"intent\": \"ambiguous\", \"explanation_focus\": \"\", \"confidence\": " + "0.2, \"clarification_needed\": true, \"clarification_question\": \"Which " + "'update' do you mean?\", \"steps\": []}"
    );
    lines.append("");
    lines.append(
        "At most " + str(MAX_STEPS) + " steps. Maximum depth " + str(MAX_DEPTH) + "."
    );
    return "\n".join(lines);
}

"""The per-question message. Bounded context only - never source code."""
def planner_user_message(ctx: PlannerContext) -> str {
    lines: list[str] = [];
    lines.append("Repository: " + (ctx.repo if ctx.repo else "(unscoped)"));
    lines.append(
        "Contains " + str(ctx.file_count) + " files, " + str(ctx.symbol_count) + " symbols, " + str(
            ctx.route_count
        ) + " routes."
    );
    if ctx.likely_symbols {
        lines.append(
            "Symbols matching this question: " + ", ".join(ctx.likely_symbols)
        );
    }
    if ctx.likely_routes {
        lines.append("Routes matching this question: " + ", ".join(ctx.likely_routes));
    }
    if ctx.routes {
        lines.append("Routes in this repository: " + ", ".join(ctx.routes[:15]));
    }
    # A bounded name index, never file contents.
    if ctx.symbol_names {
        lines.append("Symbol names available: " + ", ".join(ctx.symbol_names[:150]));
    }
    lines.append("");
    lines.append("Question: " + ctx.question);
    return "\n".join(lines);
}

"""Ask Claude for a plan. Returns raw JSON text, or "" on any failure."""
def _request_plan(ctx: PlannerContext) -> str {
    response: any = None;
    try {
        import anthropic;
        client = anthropic.Anthropic(timeout=REQUEST_TIMEOUT);
        response = client.messages.create(
            model=ANTHROPIC_MODEL,
            max_tokens=PLAN_MAX_TOKENS,
            system=planner_system_prompt(),
            output_config={"format": {"type": "json_schema", "schema": plan_schema()}},
            messages=[{"role": "user", "content": planner_user_message(ctx)}]
        );
    } except Exception {
        # Missing key, auth failure, timeout, rate limit, connection error,
        # bad request - every one of them means "use the deterministic path".
        return "";
    }

    # A refusal, or a response truncated before the plan was finished, is a
    # successful HTTP call with nothing usable in it.
    if (response.stop_reason as str) in ["refusal", "max_tokens"] {
        return "";
    }

    for block in response.content {
        if (block.type as str) == "text" {
            return block.text as str;
        }
    }
    return "";
}

"""Claude-backed planner. Falls back to the deterministic planner on anything."""
obj AnthropicPlanner(Planner) {
    has name: str = "anthropic",
        fallback: Planner = DeterministicPlanner();

    override def plan(
        question: str, repo: str, context: PlannerContext
    ) -> InvestigationPlan {
        if not has_api_key() {
            # Logged rather than raised: the product still works without a key.
            print(
                "[trace] ANTHROPIC_API_KEY is not set - using the deterministic " + "planner. Export the key to enable Claude-backed planning."
            );
            return self._fall_back(question, repo, context, "no_api_key");
        }

        attempt = 0;
        while attempt <= PARSE_RETRIES {
            attempt += 1;
            payload = self.request_plan(context);
            if not payload {
                # An API-level failure. Retrying only repeats the same wait,
                # so hand over to the deterministic path immediately.
                break;
            }
            parsed = plan_from_json(payload, question, repo);
            if parsed is not None {
                parsed.planner = self.name;
                parsed.repo = repo;
                return parsed;
            }
            print(
                "[trace] the planner returned unparseable output (attempt " + str(
                    attempt
                ) + ")."
            );
        }

        print("[trace] falling back to the deterministic planner.");
        return self._fall_back(question, repo, context, "unusable_response");
    }

    """The single network call, isolated so tests can substitute it.

    Overriding this - rather than patching a module global - is what lets the
    test suite exercise success, malformed JSON, timeouts and refusals with
    no API key and no network.
    """
    def request_plan(context: PlannerContext) -> str {
        return _request_plan(context);
    }

    """Produce a deterministic plan, tagged so the caller can see what happened."""
    def _fall_back(
        question: str, repo: str, context: PlannerContext, reason: str
    ) -> InvestigationPlan {
        out = self.fallback.plan(question, repo, context);
        out.planner = self.name + "+fallback:" + reason;
        out.repo = repo;
        return out;
    }
}

# --- Explanation layer ---

"""Explain an executed plan with Claude, from evidence alone.

Receives the question, the validated plan and the collected evidence - never
the repository, never the graph. Falls back to the deterministic summary on
any failure, so an explanation always exists.
"""
def explain_with_claude(result: PlanResult) -> PlanResult {
    if not has_api_key() {
        result.explanation = explain_deterministically(result);
        result.explained_by = "deterministic";
        return result;
    }

    system = "You explain the results of a code investigation to an engineer. " + "You did not run the investigation and you cannot see the repository. " + "Use ONLY the evidence supplied. Never claim a symbol, call, route or " + "file that is not in the evidence. Distinguish what was directly " + "observed from what you are inferring, and say plainly when the " + "evidence is insufficient or a step found nothing - never present a " + "failed step as a confident answer. Be concise.";

    response: any = None;
    try {
        import anthropic;
        client = anthropic.Anthropic(timeout=REQUEST_TIMEOUT);
        response = client.messages.create(
            model=ANTHROPIC_MODEL,
            max_tokens=EXPLAIN_MAX_TOKENS,
            system=system,
            messages=[{"role": "user", "content": explanation_prompt(result)}]
        );
    } except Exception {
        result.explanation = explain_deterministically(result);
        result.explained_by = "deterministic+fallback";
        return result;
    }

    if (response.stop_reason as str) == "refusal" {
        result.explanation = explain_deterministically(result);
        result.explained_by = "deterministic+refused";
        return result;
    }

    text = "";
    for block in response.content {
        if (block.type as str) == "text" {
            text = block.text as str;
        }
    }
    if not text.strip() {
        result.explanation = explain_deterministically(result);
        result.explained_by = "deterministic+empty";
        return result;
    }

    result.explanation = text;
    result.explained_by = "anthropic";
    return result;
}
