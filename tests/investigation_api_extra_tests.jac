"""Trace - additional coverage for investigation_api.jac beyond
tests/integration_tests.jac.

Run with:  jac test -d tests/

Covers spec-named edge cases not exercised elsewhere: an unknown repo_name
(spec section 3c "Edge cases this must survive"), alias-table phrasings
reviewers were told to hand-check ("who is affected if get_repository
changes", "flow for logging in"), and a punctuation-heavy unresolvable
question (failure case).

NOTE: this file is deliberately NOT named `test_*.jac` - that prefix
collides with Python's test-module import machinery.
"""

import os;

import from ingestion { ingest_repo }
import from investigation_api { investigate }

glob SAMPLE: str = os.path.join(os.path.dirname(__file__), "..", "sample_repo");

"""Ingest the sample repo before each test."""
def _ingest {
    _summary = ingest_repo(SAMPLE, name="sample_repo");
}

test "an unknown repo_name finds nothing rather than tracing another repo" {
    _ingest();
    res = investigate("What happens when a user signs up?", "no_such_repo_xyz");

    # BEHAVIOUR CHANGE (repository-scoping refactor). This test previously
    # asserted status == "ok": an unknown repo_name still traced, because
    # `repo_name` was ignored for symbol resolution and only used to look up
    # edge ids. That was the bug - asking for repository A could return
    # repository B's evidence with full confidence. Scoping now applies to
    # resolution, so a repository that does not exist contains no symbols.
    assert res.status == "not_found" , f"unknown repo returned {res.status}";
    assert res.node_count == 0;
    assert res.evidence == [];
    assert "no_such_repo_xyz" in res.message , f"message lacks the scope: {res.message}";
}

test "a known repo_name still traces with edge ids resolved" {
    _ingest();
    res = investigate("What happens when a user signs up?", "sample_repo");

    assert res.status == "ok";
    assert res.seed_name == "signup";
    assert res.node_count == 19;
    resolved = [
        ev
        for ev in res.evidence
        if ev.edge_id != ""
    ];
    assert len(resolved) == 18 , f"expected 18 resolved edge ids, got {len(resolved)}";
}

test "who calls get_repository routes reverse from get_repository" {
    _ingest();
    res = investigate("who calls get_repository?");

    assert res.direction == "reverse";
    assert res.status == "ok";
    assert res.seed_name == "get_repository";
}

test "PLANNER GAP (documented, not a bug): 'who is affected if X changes' does not match REVERSE_PHRASES" {
    _ingest();
    # The exact REVERSE_PHRASES list has "affected by" and "if i change", but
    # NOT "affected if" or "if <subject> changes" - so this reasonable-sounding
    # question falls through to the forward default per spec section 3a's
    # literal phrase table. This asserts the actual (spec-compliant) behavior
    # so a future change to the phrase table doesn't silently regress this
    # test's intent; see .pipeline/test-results.md for the full note.
    res = investigate("who is affected if get_repository changes");

    assert res.status == "ok";
    assert res.direction == "forward" , "if this starts failing, REVERSE_PHRASES grew a new match - update the note in test-results.md";
    assert res.seed_name == "get_repository";
}

test "alias table: flow for logging in resolves to the auth entry point" {
    _ingest();
    res = investigate("flow for logging in");

    assert res.status == "ok";
    assert res.direction == "forward";
    assert res.seed_name in ["require_auth", "authenticate_request"];
}

test "punctuation-heavy unresolvable question fails cleanly" {
    _ingest();
    res = investigate("!!! ??? ...what/is/the-meaning_of***life??? !!!");

    assert res.status == "not_found";
    assert res.message != "";
    assert len(res.evidence) == 0;
}

test "whitespace-only question reports not_found without raising" {
    _ingest();
    res = investigate("     ");

    assert res.status == "not_found";
    assert len(res.evidence) == 0;
}
