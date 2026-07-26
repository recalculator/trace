"""Trace - investigation planners.

A planner turns a question into an `InvestigationPlan`. It never touches the
graph, never produces evidence and never answers anything - it only chooses
which allowlisted operations should run. Everything it emits is validated
before execution.

Three implementations share one contract:

  DeterministicPlanner  keyword routing over graph-derived context. No LLM,
                        no network, always available. This is the fallback
                        AND the default when no model is configured.
  LlmPlanner            asks a model for structured output, then falls back
                        to the deterministic planner on any failure -
                        missing key, timeout, malformed JSON, bad schema.
  FakePlanner           returns a plan handed to it. For tests.

The context builder is deterministic and bounded: it reads names and counts
from the graph, never source text, and never the whole repository.
"""

import json;

import from investigation { find_symbol }
import from graph_export { get_repo_graph }
import from plan_types {
    InvestigationPlan,
    InvestigationStep,
    MAX_DEPTH,
    MAX_STEPS,
    TOOLS,
    tool_names,
    tool_spec
}

glob MAX_CONTEXT_SYMBOLS: int = 400;

glob MAX_CANDIDATES: int = 8;

"""Words that never identify a symbol."""
glob STOPWORDS: list[str] = [
         "what",
         "which",
         "who",
         "how",
         "does",
         "do",
         "did",
         "is",
         "are",
         "was",
         "the",
         "a",
         "an",
         "of",
         "to",
         "in",
         "on",
         "for",
         "from",
         "by",
         "with",
         "when",
         "where",
         "why",
         "happens",
         "happen",
         "runs",
         "run",
         "call",
         "calls",
         "called",
         "calling",
         "breaks",
         "break",
         "modify",
         "modifies",
         "change",
         "changed",
         "changes",
         "affect",
         "affects",
         "use",
         "uses",
         "used",
         "work",
         "works",
         "begin",
         "begins",
         "start",
         "starts",
         "i",
         "if",
         "my",
         "our",
         "this",
         "that",
         "it",
         "and",
         "or",
         "me",
         "show",
         "tell",
         "explain",
         "trace",
         "find",
         "path",
         "flow",
         "would",
         "will",
         "can",
         "could",
         "should",
         "there",
         "here",
         "code",
         "function",
         "method",
         "class",
         "route",
         "routes",
         "api",
         "endpoint",
         "endpoints",
         "user"
     ];

"""Phrases that mean "who depends on this" rather than "what does this do"."""
glob REVERSE_PHRASES: list[str] = [
         "what breaks",
         "what would break",
         "who calls",
         "what calls",
         "called by",
         "callers of",
         "impact of",
         "affected by",
         "depends on",
         "dependents",
         "blast radius",
         "if i modify",
         "if i change",
         "if we modify",
         "if we change",
         "consumers of",
         "used by"
     ];

"""Bounded, deterministic context for a planner. Names and counts only."""
obj PlannerContext {
    has repo: str = "",
        question: str = "",
        tools: list[str] = [],
        symbol_names: list[str] = [],
        symbol_count: int = 0,
        file_count: int = 0,
        route_count: int = 0,
        routes: list[str] = [],
        likely_symbols: list[str] = [];
}

"""Lowercased word tokens of a question."""
def _tokens(question: str) -> list[str] {
    cleaned = "";
    for ch in question.lower() {
        cleaned += ch if (ch.isalnum() or ch == "_") else " ";
    }
    return [
        w
        for w in cleaned.split()
        if w and w not in STOPWORDS
    ];
}

"""Build bounded planner context by reading the graph - never source text."""
def build_context(question: str, repo: str) -> PlannerContext {
    ctx = PlannerContext(repo=repo, question=question, tools=tool_names());
    graph = get_repo_graph(repo);

    names: list[str] = [];
    for n in graph.nodes {
        ntype = n.node_type as str;
        if ntype == "Symbol" {
            ctx.symbol_count += 1;
            if len(names) < MAX_CONTEXT_SYMBOLS {
                names.append(n.name as str);
            }
        } elif ntype == "File" {
            ctx.file_count += 1;
        } elif ntype == "Route" {
            ctx.route_count += 1;
            if len(ctx.routes) < 25 {
                ctx.routes.append((n.method as str) + " " + (n.pattern as str));
            }
        }
    }
    ctx.symbol_names = names;

    # Likely matches: exact token hits first, then case-insensitive, so a
    # planner is offered real symbol names rather than guessing them.
    known: dict[str, bool] = {};
    for nm in names {
        known[nm] = True;
    }
    lowered: dict[str, str] = {};
    for nm in names {
        lowered[nm.lower()] = nm;
    }

    hits: list[str] = [];
    for tok in _tokens(question) {
        if tok in known and tok not in hits {
            hits.append(tok);
        } elif tok in lowered and lowered[tok] not in hits {
            hits.append(lowered[tok]);
        }
    }
    # Fuzzy fallback: a question word rarely matches a symbol name exactly.
    # "authentication" must reach `authenticate_request`, so match on a
    # shared prefix in either direction as well as containment.
    if not hits {
        for tok in _tokens(question) {
            if len(tok) < 4 {
                continue;
            }
            stem = tok[:6];
            for nm in names {
                low = nm.lower();
                related = tok in low or low in tok or low.startswith(stem);
                if related and nm not in hits and len(hits) < MAX_CANDIDATES {
                    hits.append(nm);
                }
            }
        }
    }
    ctx.likely_symbols = hits[:MAX_CANDIDATES];
    return ctx;
}

"""Phrases that ask for an overview rather than one symbol's behaviour."""
glob BROAD_PHRASES: list[str] = [
         "how does",
         "how do",
         "how is",
         "walk me through",
         "give me an overview",
         "explain how",
         "architecture",
         "overview of",
         "how are"
     ];

"""True when the question asks for an overview rather than one symbol."""
def _is_broad(question: str) -> bool {
    lowered = " " + question.lower() + " ";
    for phrase in BROAD_PHRASES {
        if phrase in lowered {
            return True;
        }
    }
    return False;
}

"""True when the question asks who depends on something."""
def _is_reverse(question: str) -> bool {
    lowered = " " + question.lower() + " ";
    for phrase in REVERSE_PHRASES {
        if phrase in lowered {
            return True;
        }
    }
    return False;
}

"""The base contract. Subclasses override `plan`."""
obj Planner {
    has name: str = "base";

    def plan(question: str, repo: str, context: PlannerContext) -> InvestigationPlan {
        return InvestigationPlan(repo=repo, question=question, planner=self.name);
    }
}

"""Keyword routing over graph context. Always available, never calls out."""
obj DeterministicPlanner(Planner) {
    has name: str = "deterministic";

    override def plan(
        question: str, repo: str, context: PlannerContext
    ) -> InvestigationPlan {
        out = InvestigationPlan(
            repo=repo, question=question, planner=self.name, confidence=0.5
        );
        lowered = question.lower();

        # Route questions need no symbol at all.
        if "route" in lowered or "endpoint" in lowered or "api" in lowered {
            out.intent = "find_routes";
            out.explanation_focus = "the HTTP surface of this repository";
            out.steps = [
                InvestigationStep(
                    tool="find_routes", reason="The question asks about HTTP routes."
                )
            ];
            out.confidence = 0.8;
            return out;
        }

        if not context.likely_symbols {
            out.intent = "unknown";
            out.clarification_needed = True;
            out.clarification_question = "Which symbol should I investigate? " + "Name a function, method or class from this repository.";
            out.confidence = 0.0;
            return out;
        }

        target = context.likely_symbols[0];

        # A broad question is answered with a multi-step investigation rather
        # than a clarification: locate the entry point, follow execution from
        # it, then report what its file depends on.
        if _is_broad(question) {
            out.intent = "explain_area";
            out.explanation_focus = "how " + target + " and its callees fit together";
            out.candidates = context.likely_symbols;
            out.steps = [
                InvestigationStep(
                    tool="find_symbol",
                    target=target,
                    reason="Establish where " + target + " is defined."
                ),
                InvestigationStep(
                    tool="trace_call_flow",
                    target=target,
                    max_depth=MAX_DEPTH,
                    reason="Follow execution outward from " + target + "."
                ),
                InvestigationStep(
                    tool="dependency_analysis",
                    target=target,
                    reason="Show what that area depends on."
                )
            ];
            out.confidence = 0.6;
            return out;
        }

        # A narrow question naming several plausible symbols is genuinely
        # ambiguous - ask rather than guess.
        if len(context.likely_symbols) > 1 {
            out.clarification_needed = True;
            out.candidates = context.likely_symbols;
            out.clarification_question = "Did you mean " + ", ".join(
                context.likely_symbols[:MAX_CANDIDATES]
            ) + "?";
            out.intent = "ambiguous";
            return out;
        }

        if _is_reverse(question) {
            out.intent = "impact_analysis";
            out.explanation_focus = "what depends on " + target;
            out.steps = [
                InvestigationStep(
                    tool="impact_analysis",
                    target=target,
                    max_depth=MAX_DEPTH,
                    reason="The question asks what depends on " + target + "."
                )
            ];
            out.confidence = 0.8;
            return out;
        }

        out.intent = "trace_call_flow";
        out.explanation_focus = "what happens when " + target + " runs";
        out.steps = [
            InvestigationStep(
                tool="trace_call_flow",
                target=target,
                max_depth=MAX_DEPTH,
                reason="The question asks what " + target + " does."
            )
        ];
        out.confidence = 0.8;
        return out;
    }
}

"""Returns a plan supplied by the caller. Test seam - never used in production."""
obj FakePlanner(Planner) {
    has name: str = "fake",
        canned: InvestigationPlan = InvestigationPlan(),
        raw_json: str = "";

    override def plan(
        question: str, repo: str, context: PlannerContext
    ) -> InvestigationPlan {
        if self.raw_json {
            parsed = plan_from_json(self.raw_json, question, repo);
            if parsed is not None {
                parsed.planner = self.name;
                return parsed;
            }
            fallback = DeterministicPlanner().plan(question, repo, context);
            fallback.planner = self.name + "+fallback";
            return fallback;
        }
        out = self.canned;
        out.repo = repo if not out.repo else out.repo;
        out.question = question;
        out.planner = self.name;
        return out;
    }
}

"""Parse a model's JSON into a plan. Returns None on anything malformed.

Unknown tools are NOT filtered here on purpose - the validator rejects them
with a message, which is more useful than silently dropping a step.
"""
def plan_from_json(payload: str, question: str, repo: str) -> InvestigationPlan | None {
    try {
        raw = json.loads(payload);
    } except Exception {
        return None;
    }
    if not isinstance(raw, dict) {
        return None;
    }

    out = InvestigationPlan(repo=repo, question=question);
    out.intent = str(raw.get("intent", ""));
    out.explanation_focus = str(raw.get("explanation_focus", ""));
    out.clarification_needed = bool(raw.get("clarification_needed", False));
    out.clarification_question = str(raw.get("clarification_question", ""));
    try {
        out.confidence = float(raw.get("confidence", 0.0));
    } except Exception {
        out.confidence = 0.0;
    }

    steps_raw = raw.get("steps", []);
    if not isinstance(steps_raw, list) {
        return None;
    }
    steps: list[InvestigationStep] = [];
    for item in steps_raw {
        if not isinstance(item, dict) {
            continue;
        }
        depth_val = 0;
        try {
            depth_val = int(item.get("max_depth", 0));
        } except Exception {
            depth_val = 0;
        }
        steps.append(
            InvestigationStep(
                tool=str(item.get("tool", "")),
                target=str(item.get("target", "")),
                max_depth=depth_val,
                reason=str(item.get("reason", ""))
            )
        );
    }
    out.steps = steps;
    if not steps and not out.clarification_needed {
        return None;
    }
    return out;
}

"""The instruction given to a model. Kept here so it is reviewable as data."""
def planner_prompt(ctx: PlannerContext) -> str {
    lines: list[str] = [];
    lines.append(
        "You plan code investigations. You do NOT answer the question and you " + "do NOT traverse any graph. Emit ONLY a JSON object."
    );
    lines.append("Available tools (use no others):");
    for t in TOOLS {
        lines.append("  " + t.name + " - " + t.summary);
    }
    lines.append("Repository: " + ctx.repo);
    lines.append(
        "It contains " + str(ctx.file_count) + " files, " + str(ctx.symbol_count) + " symbols, " + str(
            ctx.route_count
        ) + " routes."
    );
    if ctx.likely_symbols {
        lines.append("Symbols matching the question: " + ", ".join(ctx.likely_symbols));
    }
    lines.append(
        "Only use symbol names that exist in this repository. If the question " + "names no symbol you can identify, set clarification_needed."
    );
    lines.append(
        "JSON shape: {\"intent\": str, \"explanation_focus\": str, " + "\"confidence\": number, \"clarification_needed\": bool, " + "\"clarification_question\": str, \"steps\": [{\"tool\": str, " + "\"target\": str, \"max_depth\": int, \"reason\": str}]}"
    );
    lines.append("At most " + str(MAX_STEPS) + " steps. Question: " + ctx.question);
    return "\n".join(lines);
}
