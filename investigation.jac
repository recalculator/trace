"""Trace - the investigation engine.

Ingestion builds the code graph; this module walks it. Given a symbol name,
`forward_trace` answers "what happens when this runs?" by following
`SymbolCallsSymbol` edges outward, and `reverse_trace` answers "what breaks
if I change this?" by following the same edges backward. Both are BFS
traversals, so they are walkers (Jac's shape rule: a `visit` makes it a
walker), and both share one base walker, `investigation_base`, that owns
every piece of bookkeeping - seed resolution, cycle protection, depth
capping, evidence construction and reporting - exactly once. The two public
walkers differ only in which neighbours they expand and which edge carries
the call line; a future "impact radius" walker subclasses the same base
rather than re-deriving the traversal.
"""

import from models {
    Repository,
    Symbol,
    RepositoryContainsFile,
    FileContainsSymbol,
    SymbolCallsSymbol
}

glob DEFAULT_MAX_DEPTH: int = 6;
glob DEFAULT_MAX_NODES: int = 500;

"""Which way a trace follows `SymbolCallsSymbol` edges."""
enum Direction {
    FORWARD,
    REVERSE
}

"""One traversal step: a node reached, and the edge that reached it."""
obj Evidence {
    has depth: int = 0,
        node_id: str = "",
        node_name: str = "",
        node_path: str = "",
        node_kind: str = "",
        node_line: int = 0,
        from_id: str = "",
        from_name: str = "",
        edge_type: str = "",
        edge_line: int = 0,
        explanation: str = "";
}

"""All mutable state for one traversal - reusable by any future walker."""
obj InvestigationContext {
    has seed_id: str = "",
        seed_name: str = "",
        seed_path: str = "",
        direction: str = "forward",
        question: str = "",
        status: str = "ok",
        max_depth: int = DEFAULT_MAX_DEPTH,
        max_nodes: int = DEFAULT_MAX_NODES,
        seen: dict[str, bool] = {},
        depth_of: dict[str, int] = {},
        evidence: list[Evidence] = [],
        depth_reached: int = 0,
        depth_capped: bool = False,
        budget_exhausted: bool = False,
        duplicates_skipped: int = 0,
        ambiguous: bool = False,
        candidates: list[str] = [],
        meta: dict[str, str] = {};
}

"""One symbol match returned by name lookup."""
obj SymbolMatch {
    has name: str = "",
        path: str = "",
        kind: str = "",
        line: int = 0,
        symbol_id: str = "";
}

"""The reported outcome of a trace, built from an `InvestigationContext`."""
obj InvestigationResult {
    has status: str = "ok",
        question: str = "",
        direction: str = "forward",
        seed_name: str = "",
        seed_path: str = "",
        seed_id: str = "",
        ambiguous: bool = False,
        candidates: list[str] = [],
        max_depth: int = 0,
        depth_reached: int = 0,
        depth_capped: bool = False,
        budget_exhausted: bool = False,
        duplicates_skipped: int = 0,
        node_count: int = 0,
        evidence: list[Evidence] = [];
}

"""Every Symbol node in the graph, reached Repository -> File -> Symbol."""
def _all_symbols -> list[Symbol] {
    out: list[Symbol] = [];
    for repo in [root-->[?:Repository]] {
        for f in [repo->:RepositoryContainsFile:->] {
            for s in [f->:FileContainsSymbol:->] {
                out.append(s);
            }
        }
    }
    return out;
}

"""Symbols whose name matches exactly, ordered by (path, line) for determinism."""
def _find_symbol_nodes(name: str) -> list[Symbol] {
    matches = [
        s
        for s in _all_symbols()
        if s.name == name
    ];
    matches.sort(key=lambda (s: Symbol) { (s.path, s.line); });
    return matches;
}

"""Shared BFS traversal mechanics for symbol-call tracing walkers."""
walker investigation_base {
    has target_name: str = "",
        question: str = "",
        max_depth: int = DEFAULT_MAX_DEPTH,
        max_nodes: int = DEFAULT_MAX_NODES,
        direction: Direction = Direction.FORWARD,
        ctx: InvestigationContext = InvestigationContext(),
        ctx_ready: bool = False,
        reports: list[InvestigationResult] = [];

    """Give this spawn its own context exactly once, whatever the entry path was."""
    def _ensure_ctx {
        if not self.ctx_ready {
            self.ctx = InvestigationContext();
            self.ctx_ready = True;
            self.ctx.max_depth = self.max_depth;
            self.ctx.max_nodes = self.max_nodes;
            direction_label = "forward"
                if self.direction == Direction.FORWARD
                else "reverse";
            self.ctx.direction = direction_label;
            if self.question {
                self.ctx.question = self.question;
            } elif self.direction == Direction.FORWARD {
                self.ctx.question = f"What happens when {self.target_name} runs?";
            } else {
                self.ctx.question = f"What breaks if I modify {self.target_name}?";
            }
            self.ctx.meta["direction"] = direction_label;
            self.ctx.meta["seed"] = self.target_name;
        }
    }

    """Neighbours to expand from `current`. Overridden per direction."""
    def _next_hops(_current: Symbol) -> list[Symbol] {
        return [];
    }

    """Call-site line of the edge between the two symbols. Overridden per direction."""
    def _edge_line(_current: Symbol, _other: Symbol) -> int {
        return 0;
    }

    """Record one node as evidence and register its depth. Caller has already deduped."""
    def _record(`node: Symbol, from_node: Symbol | None, edge_line: int, depth: int) {
        self.ctx.seen[jid(`node)] = True;
        self.ctx.depth_of[jid(`node)] = depth;
        if depth > self.ctx.depth_reached {
            self.ctx.depth_reached = depth;
        }
        if from_node is None {
            self.ctx.evidence.append(
                Evidence(
                    depth=depth,
                    node_id=jid(`node),
                    node_name=`node.name,
                    node_path=`node.path,
                    node_kind=`node.kind,
                    node_line=`node.line,
                    from_id="",
                    from_name="",
                    edge_type="",
                    edge_line=0,
                    explanation=f"seed: {`node.name} at {`node.path}:{`node.line}"
                )
            );
        } elif self.direction == Direction.FORWARD {
            self.ctx.evidence.append(
                Evidence(
                    depth=depth,
                    node_id=jid(`node),
                    node_name=`node.name,
                    node_path=`node.path,
                    node_kind=`node.kind,
                    node_line=`node.line,
                    from_id=jid(from_node),
                    from_name=from_node.name,
                    edge_type="SymbolCallsSymbol",
                    edge_line=edge_line,
                    explanation=f"{from_node.name} calls {`node.name} at {from_node.path}:{edge_line} (depth {depth})"
                )
            );
        } else {
            self.ctx.evidence.append(
                Evidence(
                    depth=depth,
                    node_id=jid(`node),
                    node_name=`node.name,
                    node_path=`node.path,
                    node_kind=`node.kind,
                    node_line=`node.line,
                    from_id=jid(from_node),
                    from_name=from_node.name,
                    edge_type="SymbolCallsSymbol",
                    edge_line=edge_line,
                    explanation=f"{`node.name} calls {from_node.name} at {`node.path}:{edge_line} (depth {depth})"
                )
            );
        }
    }

    can seed with Root entry {
        self._ensure_ctx();
        matches = _find_symbol_nodes(self.target_name);
        if not matches {
            self.ctx.status = "not_found";
            skip;
        }
        if len(matches) > 1 {
            self.ctx.ambiguous = True;
            self.ctx.candidates = [f"{m.path}:{m.line}" for m in matches];
        }
        seed = matches[0];
        self.ctx.seed_id = jid(seed);
        self.ctx.seed_name = seed.name;
        self.ctx.seed_path = seed.path;
        self._record(seed, None, 0, 0);
        frontier: list[Symbol] = [seed];
        visit frontier;
    }

    can step with Symbol entry {
        self._ensure_ctx();
        if self.ctx.budget_exhausted {
            skip;
        }

        # Direct spawn on a Symbol (no Root entry ran): `here` is the seed.
        if jid(here) not in self.ctx.seen {
            self.ctx.seed_id = jid(here);
            self.ctx.seed_name = here.name;
            self.ctx.seed_path = here.path;
            self._record(here, None, 0, 0);
        }

        depth = self.ctx.depth_of[jid(here)];
        if depth >= self.ctx.max_depth {
            self.ctx.depth_capped = True;
            skip;
        }

        next_hops: list[Symbol] = [];
        for other in self._next_hops(here) {
            if len(self.ctx.evidence) >= self.ctx.max_nodes {
                self.ctx.budget_exhausted = True;
                skip;
            }
            if jid(other) in self.ctx.seen {
                self.ctx.duplicates_skipped += 1;
                continue;
            }
            self._record(other, here, self._edge_line(here, other), depth + 1);
            next_hops.append(other);
        }
        visit next_hops;
    }

    can deliver with Root exit {
        self._ensure_ctx();
        report InvestigationResult(
            status=self.ctx.status,
            question=self.ctx.question,
            direction=self.ctx.direction,
            seed_name=self.ctx.seed_name,
            seed_path=self.ctx.seed_path,
            seed_id=self.ctx.seed_id,
            ambiguous=self.ctx.ambiguous,
            candidates=self.ctx.candidates,
            max_depth=self.ctx.max_depth,
            depth_reached=self.ctx.depth_reached,
            depth_capped=self.ctx.depth_capped,
            budget_exhausted=self.ctx.budget_exhausted,
            duplicates_skipped=self.ctx.duplicates_skipped,
            node_count=len(self.ctx.evidence),
            evidence=self.ctx.evidence
        );
    }
}

"""What happens when this symbol runs? Follows SymbolCallsSymbol outgoing."""
walker:pub forward_trace(investigation_base) {
    has direction: Direction = Direction.FORWARD;

    def _next_hops(current: Symbol) -> list[Symbol] {
        return [current->:SymbolCallsSymbol:->];
    }

    def _edge_line(current: Symbol, other: Symbol) -> int {
        links = [edge current->:SymbolCallsSymbol:->other];
        if links {
            return links[0].line;
        }
        return 0;
    }
}

"""What breaks if I modify this symbol? Follows SymbolCallsSymbol incoming."""
walker:pub reverse_trace(investigation_base) {
    has direction: Direction = Direction.REVERSE;

    def _next_hops(current: Symbol) -> list[Symbol] {
        return [current<-:SymbolCallsSymbol:<-];
    }

    def _edge_line(current: Symbol, other: Symbol) -> int {
        links = [edge other->:SymbolCallsSymbol:->current];
        if links {
            return links[0].line;
        }
        return 0;
    }
}

"""Look a symbol up by exact name and return every match with its graph id."""
def:pub find_symbol(name: str) -> list[SymbolMatch] {
    return [
        SymbolMatch(
            name=s.name, path=s.path, kind=s.kind, line=s.line, symbol_id=jid(s)
        ) for s in _find_symbol_nodes(name)
    ];
}
