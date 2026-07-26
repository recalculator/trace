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

# --- The endpoint ---------------------------------------------------------

"""Answer a natural-language question by planning a trace and spawning the real walker."""
def:pub investigate(question: str, repo_name: str = "sample_repo") -> InvestResponse {
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
        w_rev = root spawn reverse_trace(target_name=seed, question=question);
        reports = w_rev.reports;
    } else {
        w_fwd = root spawn forward_trace(target_name=seed, question=question);
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
        return InvestResponse(
            status="not_found",
            message="Symbol '" + seed + "' is not in the code graph.",
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

    return InvestResponse(
        status="ok",
        message="",
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
