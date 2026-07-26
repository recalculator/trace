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

test "unknown repo_name still traces but every edge_id is empty" {
    _ingest();
    res = investigate("What happens when a user signs up?", "no_such_repo_xyz");

    assert res.status == "ok" , "spec 3c: an unknown repo_name must not break the trace itself";
    assert res.seed_name == "signup";
    assert res.node_count == 19;
    for ev in res.evidence {
        assert ev.edge_id == "" , f"{ev.node_name} got a non-empty edge_id from a repo with no exported graph";
    }
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
