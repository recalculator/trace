"""Trace - repository-scoping regression tests.

Before this refactor `investigate(question, repo_name)` accepted a repository
and then ignored it: symbol resolution walked every ingested repository, so
asking the TypeScript repo about `signup` returned Python evidence with
status "ok". These tests exist so that cannot come back.

Both fixtures declare a symbol called `signup`, which is what makes the
scoping observable at all.
"""

import os;

import from models { Repository }
import from ingestion { ingest_repo }
import from investigation { find_symbol, forward_trace }
import from investigation_api { investigate }

glob PY_REPO: str = os.path.join(os.path.dirname(__file__), "..", "sample_repo");

glob TS_REPO: str = os.path.join(
         os.path.dirname(__file__), "..", "sample_repo_ts"
     );

"""Ingest both fixtures so a colliding symbol name exists."""
def _ingest_both -> None {
    _p = ingest_repo(PY_REPO, name="sample_repo");
    _t = ingest_repo(TS_REPO, name="sample_repo_ts");
}

test "the fixtures really do collide on a symbol name" {
    _ingest_both();
    paths = [m.path for m in find_symbol("signup")];
    paths.sort();
    assert paths == ["app/main.py", "src/api/routes.ts"] , f"expected a colliding name across both repos, got {paths}";
}

test "identical symbol names resolve to the requested repository" {
    _ingest_both();

    py = investigate("What happens when signup runs?", "sample_repo");
    assert py.status == "ok" , f"python status {py.status}";
    assert py.seed_path == "app/main.py" , f"python resolved to {py.seed_path}";

    ts = investigate("What happens when signup runs?", "sample_repo_ts");
    assert ts.status == "ok" , f"typescript status {ts.status}";
    assert ts.seed_path == "src/api/routes.ts" , f"typescript resolved to {ts.seed_path}";

    # The regression this file exists for: two different repositories must
    # not produce the same evidence.
    assert py.seed_id != ts.seed_id , "both repositories resolved to one symbol";
}

test "scoped evidence never leaks across repositories" {
    _ingest_both();

    ts = investigate("What happens when signup runs?", "sample_repo_ts");
    for e in ts.evidence {
        assert e.node_path.endswith(".ts") or e.node_path.endswith(".tsx") , f"python evidence leaked into a typescript investigation: {e.node_path}";
    }

    py = investigate("What happens when signup runs?", "sample_repo");
    for e in py.evidence {
        assert e.node_path.endswith(".py") , f"typescript evidence leaked into a python investigation: {e.node_path}";
    }
}

test "an unscoped request still searches globally" {
    _ingest_both();

    # Backwards compatibility: no repository named means the historical
    # whole-graph search, not an error and not an empty result.
    everywhere = investigate("What happens when signup runs?", "");
    assert everywhere.seed_name == "signup";
    assert len(everywhere.evidence) > 0 , "global search returned nothing";
}

test "ambiguity reaches the caller instead of being silently resolved" {
    _ingest_both();

    res = investigate("What happens when signup runs?", "");
    assert res.ambiguous == True , "colliding names were not reported as ambiguous";
    assert res.status == "ambiguous" , f"status was {res.status}, not 'ambiguous'";
    assert res.message != "" , "ambiguity carried no message for the caller";
    assert "ambiguous" in res.message;
    assert "signup" in res.message;

    # The message must name the alternative, not just admit one exists.
    assert "src/api/routes.ts" in res.message or "app/main.py" in res.message , f"message names no candidate: {res.message}";

    cands = list(res.candidates);
    cands.sort();
    assert cands == ["app/main.py:13", "src/api/routes.ts:5"] , f"candidates were {cands}";
}

test "a scoped request is unambiguous" {
    _ingest_both();

    scoped = investigate("What happens when signup runs?", "sample_repo_ts");
    assert scoped.ambiguous == False , "scoping did not remove the ambiguity";
    assert scoped.status == "ok";
    assert scoped.message == "" , f"unexpected message: {scoped.message}";
}

test "find_symbol honours the repository scope" {
    _ingest_both();

    everywhere = [m.path for m in find_symbol("signup")];
    assert len(everywhere) == 2 , f"global find_symbol returned {everywhere}";

    ts_only = find_symbol("signup", "sample_repo_ts");
    assert len(ts_only) == 1 , f"scoped find_symbol returned {len(ts_only)} matches";
    assert ts_only[0].path == "src/api/routes.ts";

    py_only = find_symbol("signup", "sample_repo");
    assert len(py_only) == 1;
    assert py_only[0].path == "app/main.py";

    # An unknown repository yields nothing rather than falling back to global.
    assert find_symbol("signup", "no_such_repo") == [];
}

test "the walker accepts a repository scope directly" {
    _ingest_both();

    w = root spawn forward_trace(target_name="signup", repo_name="sample_repo_ts");
    res = w.reports[0];
    assert res.status == "ok";
    assert res.seed_path == "src/api/routes.ts" , f"walker resolved to {res.seed_path}";
    assert res.ambiguous == False;

    # Default (no scope) preserves the historical global behaviour.
    w2 = root spawn forward_trace(target_name="signup");
    assert w2.reports[0].ambiguous == True , "unscoped walker lost its ambiguity flag";
}

test "a symbol missing from the scoped repository is not found elsewhere" {
    _ingest_both();

    # `createUser` exists only in the TypeScript fixture. Asking the Python
    # repository for it must fail rather than silently crossing over.
    res = investigate("What happens when createUser runs?", "sample_repo");
    assert res.status == "not_found" , f"status was {res.status}, seed {res.seed_path}";
    assert "sample_repo" in res.message , f"message lacks the scope: {res.message}";
}
