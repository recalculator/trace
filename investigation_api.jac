"""Trace - investigation API glue for the client.

`investigation.jac` is frozen: it owns the real BFS traversal (`forward_trace`
/ `reverse_trace`) and the exact seed-matching rules. This module adds no
traversal of its own. It only:

  1. Plans a trace from a free-text question - direction (forward/reverse)
     and seed symbol name - with a deterministic phrase/token matcher (no
     LLM, no `by llm`).
  2. Spawns the real walker (`root spawn forward_trace(...)` /
     `root spawn reverse_trace(...)`), exactly the way `main.jac` and
     `tests/investigation_tests.jac` already do.
  3. Resolves each evidence step's real `SymbolCallsSymbol` edge jid, using
     the flat graph `get_repo_graph` already exports - `Evidence` carries
     node/from jids but no edge jid, and only the server can look one up.

The wire types (`InvestEvidence`, `InvestResponse`) are imported from
`client/types.jac` rather than redeclared here, matching the precedent set
by `graph_export.jac` importing `GraphNode` / `GraphEdge` / `RepoGraph` from
the same module.
"""

import from investigation { find_symbol, forward_trace, reverse_trace }
import from graph_export { get_repo_graph }
import from client.types { InvestEvidence, InvestResponse }
import from plan_types { InvestigationPlan, tool_spec }
import from planner_api { plan_only, run_plan }

# --- Planner vocabulary ------------------------------------------------

"""A question phrase that maps onto one or more candidate symbol names."""
obj AliasRule {
    has phrase: str = "",
        names: list[str] = [];
}

glob REVERSE_PHRASES: list[str] = [
         "what breaks",
         "breaks if",
         "break if",
         "if i modify",
         "if i change",
         "if i delete",
         "if i remove",
         "impact of",
         "impact on",
         "blast radius",
         "depends on",
         "depend on",
         "dependents of",
         "who calls",
         "what calls",
         "callers of",
         "called by",
         "affected by",
         "affects"
     ];

glob STOPWORDS: list[str] = [
         "what",
         "whats",
         "when",
         "where",
         "which",
         "who",
         "whom",
         "why",
         "how",
         "does",
         "do",
         "did",
         "is",
         "are",
         "was",
         "were",
         "be",
         "been",
         "being",
         "a",
         "an",
         "the",
         "if",
         "i",
         "we",
         "you",
         "it",
         "its",
         "this",
         "that",
         "these",
         "those",
         "to",
         "of",
         "in",
         "on",
         "at",
         "by",
         "for",
         "from",
         "with",
         "and",
         "or",
         "but",
         "not",
         "my",
         "our",
         "their",
         "there",
         "here",
         "happens",
         "happen",
         "happening",
         "breaks",
         "break",
         "modify",
         "modifying",
         "change",
         "changing",
         "changed",
         "delete",
         "deleting",
         "remove",
         "removing",
         "impact",
         "depends",
         "depend",
         "dependency",
         "dependencies",
         "calls",
         "call",
         "called",
         "caller",
         "callers",
         "begin",
         "begins",
         "beginning",
         "start",
         "starts",
         "started",
         "run",
         "runs",
         "running",
         "code",
         "function",
         "method",
         "symbol",
         "please",
         "show",
         "me",
         "tell",
         "about",
         "would",
         "will",
         "can",
         "could",
         "should",
         "up",
         "down",
         "out",
         "get",
         "all",
         "any",
         "some",
         "flow",
         "path",
         "then",
         "after",
         "before"
     ];

glob QUESTION_ALIASES: list[AliasRule] = [
         AliasRule(phrase="signs up", names=["signup"]),
         AliasRule(phrase="sign up", names=["signup"]),
         AliasRule(phrase="signing up", names=["signup"]),
         AliasRule(phrase="signup", names=["signup"]),
         AliasRule(phrase="registration", names=["signup"]),
         AliasRule(phrase="registers", names=["signup"]),
         AliasRule(phrase="register", names=["signup"]),
         AliasRule(phrase="new user", names=["signup", "create_user"]),
         AliasRule(
             phrase="authentication", names=["require_auth", "authenticate_request"]
         ),
         AliasRule(
             phrase="authenticating", names=["require_auth", "authenticate_request"]
         ),
         AliasRule(
             phrase="authenticate", names=["require_auth", "authenticate_request"]
         ),
         AliasRule(
             phrase="authenticated", names=["require_auth", "authenticate_request"]
         ),
         AliasRule(phrase="auth", names=["require_auth", "authenticate_request"]),
         AliasRule(phrase="logging in", names=["require_auth", "authenticate_request"]),
         AliasRule(phrase="log in", names=["require_auth", "authenticate_request"]),
         AliasRule(phrase="login", names=["require_auth", "authenticate_request"]),
         AliasRule(phrase="logged in", names=["require_auth", "authenticate_request"]),
         AliasRule(phrase="validation", names=["validate_signup_input"]),
         AliasRule(phrase="validating", names=["validate_signup_input"]),
         AliasRule(phrase="validate", names=["validate_signup_input"]),
         AliasRule(phrase="password", names=["hash_password"]),
         AliasRule(phrase="hashing", names=["hash_password"]),
         AliasRule(phrase="token", names=["generate_token"]),
         AliasRule(phrase="jwt", names=["generate_token"]),
         AliasRule(phrase="database", names=["persist"]),
         AliasRule(phrase="persistence", names=["persist"]),
         AliasRule(phrase="saving", names=["persist"]),
         AliasRule(phrase="seeding", names=["seed_demo_users"]),
         AliasRule(phrase="seed", names=["seed_demo_users"])
     ];

# --- Private helpers -----------------------------------------------------

"""Lowercase, strip punctuation to spaces, collapse runs - token list preserving nothing else."""
def _norm_tokens(q: str) -> list[str] {
    buf: str = "";
    for ch in q {
        if ch.isalnum() or ch == "_" {
            buf = buf + ch;
        } else {
            buf = buf + " ";
        }
    }
    toks = [
        t
        for t in buf.split(" ")
        if t != ""
    ];
    return toks;
}

"""Space-padded lowercase question, for word-boundary-safe phrase matching."""
def _norm_phrase(q: str) -> str {
    toks = _norm_tokens(q);
    lowered = [t.lower() for t in toks];
    return " " + " ".join(lowered) + " ";
}

"""Reverse when any reverse phrase is present, otherwise forward."""
def _plan_direction(q: str) -> str {
    phrase = _norm_phrase(q);
    for p in REVERSE_PHRASES {
        if (" " + p + " ") in phrase {
            return "reverse";
        }
    }
    return "forward";
}

"""First symbol name in `names` that exists in the graph, or "" if none do."""
def _first_real(names: list[str]) -> str {
    for n in names {
        if find_symbol(n) {
            return n;
        }
    }
    return "";
}

"""Resolve a question to a real symbol name, or "" when nothing matches."""
def _plan_seed(q: str) -> str {
    toks = _norm_tokens(q);

    cands: list[str] = [];
    i: int = 0;
    while i <= len(toks) - 2 {
        cands.append(toks[i] + "_" + toks[i + 1]);
        i = i + 1;
    }
    for t in toks {
        if t.lower() not in STOPWORDS and len(t) >= 3 {
            cands.append(t);
        }
    }

    best: str = "";
    best_len: int = -1;
    for c in cands {
        resolved: str = "";
        if find_symbol(c) {
            resolved = c;
        } elif find_symbol(c.lower()) {
            resolved = c.lower();
        }
        if resolved != "" and len(c) > best_len {
            best = resolved;
            best_len = len(c);
        }
    }
    if best != "" {
        return best;
    }

    phrase = _norm_phrase(q);
    for rule in QUESTION_ALIASES {
        if (" " + rule.phrase + " ") in phrase {
            hit = _first_real(rule.names);
            if hit != "" {
                return hit;
            }
        }
    }

    return "";
}

"""Map "<src_jid>-><tgt_jid>" -> SymbolCallsSymbol edge jid, from the exported graph."""
def _call_edge_index(repo_name: str) -> dict[str, str] {
    g = get_repo_graph(repo_name);
    idx: dict[str, str] = {};
    for e in g.edges {
        if e.edge_type == "SymbolCallsSymbol" {
            key = e.source + "->" + e.target;
            if key not in idx {
                idx[key] = e.id;
            }
        }
    }
    return idx;
}

# --- Repository-wide questions --------------------------------------------

"""What the timeline calls a repository-wide investigation - it has no seed."""
glob REPO_WIDE_LABELS: dict[str, str] = {
         "find_routes": "all routes",
         "repo_summary": "repository summary"
     };

"""Route jid -> the RouteHandledBySymbol edge jid and the handler's jid.

Routes are linked to their handler by an edge the client can highlight, the
same way call edges are resolved for symbol traces. Read from the exported
graph; no traversal is added here.
"""
def _route_links(repo_name: str) -> dict[str, list[str]] {
    g = get_repo_graph(repo_name);
    idx: dict[str, list[str]] = {};
    for e in g.edges {
        if e.edge_type == "RouteHandledBySymbol" and e.source not in idx {
            idx[e.source] = [e.id, e.target];
        }
    }
    return idx;
}

"""Execute a plan whose tool needs no target, and shape it for the client.

This is the path a question like "where are the routes?" takes. It never
resolves a symbol, because the tool it runs does not have one.
"""
def _repo_wide(
    question: str, repo_name: str, plan: InvestigationPlan
) -> InvestResponse {
    result = run_plan(plan);
    tool = plan.steps[0].tool;
    label = REPO_WIDE_LABELS[tool] if tool in REPO_WIDE_LABELS else tool;

    if result.status != "ok" {
        note = result.message;
        if not note {
            note = "Nothing matching that question was found in this repository.";
        }
        return InvestResponse(
            status="not_found", message=note, question=question, direction="forward"
        );
    }

    links = _route_links(repo_name);
    out: list[InvestEvidence] = [];
    for step in result.steps {
        for e in step.evidence {
            nid: str = e.node_id;
            link: list[str] = links[nid] if nid in links else [];
            out.append(
                InvestEvidence(
                    depth=e.depth,
                    node_id=nid,
                    node_name=e.symbol,
                    node_path=e.path,
                    node_kind=e.kind,
                    node_line=e.line,
                    from_id=link[1] if link else "",
                    from_name=e.related,
                    edge_id=link[0] if link else "",
                    edge_type="RouteHandledBySymbol" if link else "",
                    edge_line=0,
                    explanation=e.detail
                )
            );
        }
    }

    depths = [e.depth for e in out];
    return InvestResponse(
        status="ok",
        message="",
        question=question,
        direction="forward",
        seed_name=label,
        max_depth=0,
        depth_reached=max(depths) if depths else 0,
        node_count=len(out),
        evidence=out
    );
}

# --- The endpoint ---------------------------------------------------------

"""Answer a natural-language question by planning an investigation and running it.

The tool is chosen BEFORE any target is resolved. Which target a question
needs - a symbol, a route, or nothing at all - is a property of the tool the
planner selects, recorded as `target_kind` in the registry. That is why a
repository-wide question is no longer rejected for naming no symbol: the
tool it needs, `find_routes`, does not take one.

Symbol-targeted questions still take the original path - `_plan_seed` plus
the real `forward_trace` / `reverse_trace` walkers - so seed matching, edge
resolution and ambiguity reporting are unchanged.
"""
def:pub investigate(
    question: str, repo_name: str = "sample_repo", planner: str = "deterministic"
) -> InvestResponse {
    plan = plan_only(question, repo_name, planner=planner);
    spec = tool_spec(plan.steps[0].tool) if plan.steps else None;

    # Divert ONLY when a no-target tool was actually selected. Anything else -
    # a symbol tool, a route tool, or no plan at all - falls through to the
    # original path, whose alias table resolves phrasings ("signs up",
    # "logging in") that the planner's symbol extraction does not.
    if spec is not None and spec.target_kind == "none" {
        return _repo_wide(question, repo_name, plan);
    }

    direction = _plan_direction(question);
    seed = _plan_seed(question);

    if seed == "" {
        return InvestResponse(
            status="not_found",
            message="No symbol in this repository matches that question. Try naming a function, for example create_user.",
            question=question,
            direction=direction
        );
    }

    reports: list[any] = [];
    if direction == "reverse" {
        w_rev = root spawn reverse_trace(
            target_name=seed, question=question, repo_name=repo_name
        );
        reports = w_rev.reports;
    } else {
        w_fwd = root spawn forward_trace(
            target_name=seed, question=question, repo_name=repo_name
        );
        reports = w_fwd.reports;
    }

    if not reports {
        return InvestResponse(
            status="not_found",
            message="The investigation walker produced no report.",
            question=question,
            direction=direction
        );
    }

    res = reports[0];
    if res.status != "ok" {
        scope = " in " + repo_name if repo_name else "";
        return InvestResponse(
            status="not_found",
            message="Symbol '" + seed + "' is not in the code graph" + scope + ".",
            question=question,
            direction=direction
        );
    }

    idx = _call_edge_index(repo_name);
    out: list[InvestEvidence] = [];
    for ev in res.evidence {
        key: str = "";
        if ev.from_id != "" {
            if res.direction == "forward" {
                key = (ev.from_id as str) + "->" + (ev.node_id as str);
            } else {
                key = (ev.node_id as str) + "->" + (ev.from_id as str);
            }
        }
        edge_id = idx[key] if key in idx else "";
        out.append(
            InvestEvidence(
                depth=ev.depth,
                node_id=ev.node_id,
                node_name=ev.node_name,
                node_path=ev.node_path,
                node_kind=ev.node_kind,
                node_line=ev.node_line,
                from_id=ev.from_id,
                from_name=ev.from_name,
                edge_id=edge_id,
                edge_type=ev.edge_type,
                edge_line=ev.edge_line,
                explanation=ev.explanation
            )
        );
    }

    # Ambiguity is reported, not resolved away. The walker picks the first
    # candidate deterministically so a result still comes back, but the
    # caller is told another symbol shares the name and which ones.
    notice = "";
    if res.ambiguous {
        traced: str = (res.seed_path as str) + ":" + str(res.evidence[0].node_line);
        others: list[str] = [
            c
            for c in res.candidates
            if c != traced
        ];
        notice = "'" + (res.seed_name as str) + "' is ambiguous - traced " + traced + ". Other matches: " + ", ".join(
            others
        ) + ".";
    }

    return InvestResponse(
        status="ambiguous" if res.ambiguous else "ok",
        message=notice,
        question=res.question,
        direction=res.direction,
        seed_name=res.seed_name,
        seed_path=res.seed_path,
        seed_id=res.seed_id,
        ambiguous=res.ambiguous,
        candidates=res.candidates,
        max_depth=res.max_depth,
        depth_reached=res.depth_reached,
        depth_capped=res.depth_capped,
        budget_exhausted=res.budget_exhausted,
        duplicates_skipped=res.duplicates_skipped,
        node_count=res.node_count,
        evidence=out
    );
}
