"""Trace - investigation engine tests.

Run with:  jac test -d tests/

Each test re-ingests the sample repository (ingestion purges any previous
`Repository` at the same path first), so tests are independent of each
other and of whatever the persisted root happens to be holding. The one
exception, T3, hangs synthetic `Symbol` nodes directly off `root` (never
under a `Repository`) and deletes them again before returning, so it too
leaves no residue for later runs.

NOTE: this file is deliberately NOT named `test_*.jac` - that prefix
collides with Python's test-module import machinery.
"""

import os;

import from models { Repository, Symbol, SymbolCallsSymbol }
import from ingestion { ingest_repo }
import from investigation { find_symbol, forward_trace, reverse_trace }

glob SAMPLE: str = os.path.join(os.path.dirname(__file__), "..", "sample_repo");

"""Ingest the sample repo and return the fresh Repository node."""
def _ingest -> Repository {
    _summary = ingest_repo(SAMPLE, name="sample_repo");
    repos = [root-->[?:Repository]];
    assert len(repos) == 1 , f"expected exactly 1 repository, got {len(repos)}";
    return repos[0];
}

test "forward trace from signup follows the whole signup chain" {
    _ingest();
    w = root spawn forward_trace(target_name="signup");
    res = w.reports[0];

    assert res.status == "ok";
    assert res.direction == "forward";
    assert res.seed_name == "signup" and res.seed_path == "app/main.py";
    assert res.evidence[0].node_name == "signup" and res.evidence[0].depth == 0;

    names = [e.node_name for e in res.evidence];
    for expected in [
        "validate_signup_input",
        "create_user",
        "hash_password",
        "persist",
        "execute",
        "generate_token"
    ] {
        assert expected in names , f"{expected} missing from forward trace of signup: {names}";
    }

    d1 = [
        e.node_name
        for e in res.evidence
        if e.depth == 1
    ];
    d1.sort();
    assert d1 == ["create_user", "validate_signup_input"];

    assert "require_auth" not in names , "forward trace from signup swept in an unrelated route handler";
    assert "me" not in names , "forward trace from signup is not a whole-graph sweep";

    assert res.depth_reached == 4 , f"expected depth_reached 4 (signup>create_user>persist>execute>connect), got {res.depth_reached}";
    assert not res.depth_capped;
    assert res.node_count == len(res.evidence);
}

test "reverse trace from create_user is the exact blast radius" {
    _ingest();
    w = root spawn reverse_trace(target_name="create_user");
    res = w.reports[0];

    assert res.direction == "reverse";
    assert res.evidence[0].node_name == "create_user" and res.evidence[0].depth == 0;

    d1 = [
        e.node_name
        for e in res.evidence
        if e.depth == 1
    ];
    d1.sort();
    assert d1 == ["seed_demo_users", "signup"];

    d2 = [
        e.node_name
        for e in res.evidence
        if e.depth == 2
    ];
    d2.sort();
    assert d2 == ["main"] , "admin/seed.py main() calls seed_demo_users, so it is the only depth-2 caller";

    assert len(res.evidence) == 4;
    assert res.depth_reached == 2;
}

test "cycle protection stops a cyclic call chain" {
    _ingest();

    # The fixture repo's call graph is acyclic, so we build a synthetic
    # 3-cycle hanging directly off root - it is invisible to
    # _find_symbol_nodes / seed resolution because it is never linked under
    # a Repository/File, exactly as the spec calls out.
    a = root ++> Symbol(name="cyc_a", path="synthetic.py", kind="function", line=1);
    b = root ++> Symbol(name="cyc_b", path="synthetic.py", kind="function", line=2);
    c = root ++> Symbol(name="cyc_c", path="synthetic.py", kind="function", line=3);
    a +>:SymbolCallsSymbol(line=1):+> b;
    b +>:SymbolCallsSymbol(line=2):+> c;
    c +>:SymbolCallsSymbol(line=3):+> a;

    w = a spawn forward_trace();  # direct spawn on a Symbol: no Root entry, read ctx not reports

    assert [e.node_name for e in w.ctx.evidence] == ["cyc_a", "cyc_b", "cyc_c"];
    assert w.ctx.duplicates_skipped >= 1 , "the c -> a edge back into the cycle should have been refused";
    assert len(w.reports) == 0 , "Root exit never fires on a direct (non-root) spawn";

    del a;
    del b;
    del c;
}

test "evidence is ordered and every step names its predecessor" {
    _ingest();
    res = (root spawn forward_trace(target_name="signup")).reports[0];

    depths = [e.depth for e in res.evidence];
    assert depths[0] == 0;
    for i in range(1, len(depths)) {
        assert depths[i] >= depths[i - 1] , "evidence depths are not non-decreasing (BFS order violated)";
    }

    emitted: list[str] = [];
    for e in res.evidence {
        if e.depth > 0 {
            assert e.from_id in emitted , f"{e.node_name} cites a predecessor that was not emitted earlier";
            assert e.from_name != "";
            assert e.edge_type == "SymbolCallsSymbol";
            assert e.explanation != "";
        } else {
            assert e.from_id == "";
        }
        emitted.append(e.node_id);
    }
}

test "converging paths record each symbol exactly once" {
    _ingest();
    # check_email and check_password both raise ValidationError, so it is
    # reachable by two distinct call edges - it must still be recorded once.
    res = (root spawn forward_trace(target_name="validate_signup_input")).reports[0];

    names = [e.node_name for e in res.evidence];
    assert len(
        [
            n
            for n in names
            if n == "ValidationError"
        ]
    ) == 1;
    assert res.duplicates_skipped >= 1;

    ids = [e.node_id for e in res.evidence];
    assert len(ids) == len(set(ids)) , "every node_id in evidence must be unique";
}

test "depth cap keeps the frontier but stops expanding" {
    _ingest();
    res = (root spawn forward_trace(target_name="signup", max_depth=1)).reports[0];

    assert res.depth_capped;
    frontier = [e.node_name for e in res.evidence];
    frontier.sort();
    assert frontier == ["create_user", "signup", "validate_signup_input"];
    assert res.depth_reached == 1;
}

test "find_symbol returns structured matches" {
    _ingest();
    hits = find_symbol("create_user");

    assert len(hits) == 1;
    assert hits[0].path == "services/user_service.py";
    assert hits[0].kind == "function";
    assert hits[0].symbol_id != "";

    assert len(find_symbol("no_such_symbol_anywhere")) == 0;
}

test "an unknown seed reports not_found once" {
    _ingest();
    w = root spawn forward_trace(target_name="no_such_symbol_anywhere");

    assert len(w.reports) == 1;
    assert w.reports[0].status == "not_found";
    assert len(w.reports[0].evidence) == 0;
}
