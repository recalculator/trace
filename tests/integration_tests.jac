"""Trace - end-to-end investigation API tests.

Run with:  jac test -d tests/

Each test re-ingests the sample repository (ingestion purges any previous
`Repository` at the same path first), so tests are independent of each
other and of whatever the persisted root happens to be holding.

NOTE: this file is deliberately NOT named `test_*.jac` - that prefix
collides with Python's test-module import machinery.
"""

import os;

import from ingestion { ingest_repo }
import from graph_export { get_repo_graph }
import from investigation_api { investigate }

glob SAMPLE: str = os.path.join(os.path.dirname(__file__), "..", "sample_repo");

"""Ingest the sample repo before each test."""
def _ingest {
    _summary = ingest_repo(SAMPLE, name="sample_repo");
}

test "forward trace: what happens when a user signs up" {
    _ingest();
    res = investigate("What happens when a user signs up?");

    assert res.status == "ok";
    assert res.direction == "forward";
    assert res.seed_name == "signup";
    assert res.seed_path == "app/main.py";
    assert res.node_count == 19;
    assert res.depth_reached == 4;
}

test "reverse trace: what breaks if I modify create_user" {
    _ingest();
    res = investigate("What breaks if I modify create_user?");

    assert res.status == "ok";
    assert res.direction == "reverse";
    assert res.seed_name == "create_user";
    assert res.node_count == 4;

    names = [ev.node_name for ev in res.evidence];
    names.sort();
    assert names == ["create_user", "main", "seed_demo_users", "signup"];
}

test "forward trace: where does authentication begin" {
    _ingest();
    res = investigate("Where does authentication begin?");

    assert res.status == "ok";
    assert res.direction == "forward";
    assert res.seed_name == "require_auth";
    assert res.node_count == 13;
    assert res.depth_reached == 5;
}

test "edge jids resolve to real SymbolCallsSymbol edges in the exported graph" {
    _ingest();
    res = investigate("What happens when a user signs up?");
    graph = get_repo_graph("sample_repo");
    edge_ids = [e.id for e in graph.edges];

    for ev in res.evidence {
        if ev.from_id != "" {
            assert ev.edge_id != "" , f"{ev.node_name} has no resolved edge_id";
            assert ev.edge_id in edge_ids , f"{ev.node_name}'s edge_id is not a real graph edge";
        }
    }
}

test "seed evidence carries no predecessor and no edge" {
    _ingest();
    res = investigate("What happens when a user signs up?");

    assert res.evidence[0].depth == 0;
    assert res.evidence[0].from_id == "";
    assert res.evidence[0].edge_id == "";
}

test "unresolvable question reports not_found without raising" {
    _ingest();
    res = investigate("What happens when a quokka sneezes?");

    assert res.status == "not_found";
    assert res.message != "";
    assert len(res.evidence) == 0;
}

test "empty question reports not_found without raising" {
    _ingest();
    res = investigate("");

    assert res.status == "not_found";
}

test "direction routing" {
    _ingest();
    reverse_res = investigate("who calls persist?");
    assert reverse_res.direction == "reverse";

    forward_res = investigate("how does create_user work?");
    assert forward_res.direction == "forward";
}
