"""Async handler implementations for App.jac.

`loadGraph` calls the real graph-export endpoint; `on_question_submit` calls
the real investigation endpoint (`investigation_api.investigate`), which
spawns `forward_trace` / `reverse_trace` server-side and resolves each
evidence step's real graph edge jid before handing the response back.
"""

sv import from graph_export { get_repo_graph }
sv import from investigation_api { investigate }

# `InvestStep`, `InvestEvidence` and `InvestResponse` are NOT re-imported
# here: an impl annex already sees its head module's imports (App.jac line
# 1), and re-importing emits a duplicate `import { ... }` into the merged
# App.js, which is a hard JS "already declared" error once the client bundle
# is actually built.

impl app.loadGraph -> None {
    try {
        fetched = await get_repo_graph("sample_repo");
        graph = fetched;
        loading = False;
    } except Exception as e {
        error = str(e);
        loading = False;
    }
}

impl app.on_question_submit(q: str) -> None {
    question = q;
    invest_error = None;
    result = None;
    active_node_ids = [];
    active_edge_ids = [];
    investigating = True;
    invest_steps = [
        InvestStep(
            step_name="Investigating…",
            status="running",
            timestamp="",
            node_ids=[],
            edge_ids=[]
        )
    ];
    try {
        res = await investigate(q, "sample_repo");
        result = res;
        if res.status != "ok" {
            invest_steps = [];
            investigating = False;
            return;
        }

        steps: list[InvestStep] = [];
        nids: list[str] = [];
        eids: list[str] = [];
        d: int = 0;
        while d <= res.depth_reached {
            lvl: list[InvestEvidence] = [
                ev
                for ev in res.evidence
                if ev.depth == d
            ];
            if len(lvl) > 0 {
                lvl_nodes: list[str] = [];
                lvl_edges: list[str] = [];
                for ev in lvl {
                    lvl_nodes = lvl_nodes + [ev.node_id];
                    if ev.edge_id != "" {
                        lvl_edges = lvl_edges + [ev.edge_id];
                    }
                }
                label: str = "";
                if d == 0 {
                    label = "Depth 0 — seed: " + res.seed_name;
                } elif len(lvl) == 1 {
                    label = "Depth " + str(d) + " — 1 symbol";
                } else {
                    label = "Depth " + str(d) + " — " + str(len(lvl)) + " symbols";
                }
                steps = steps + [
                    InvestStep(
                        step_name=label,
                        status="done",
                        timestamp="",
                        node_ids=lvl_nodes,
                        edge_ids=lvl_edges
                    )
                ];
                nids = nids + lvl_nodes;
                eids = eids + lvl_edges;
            }
            d = d + 1;
        }
        invest_steps = steps;
        active_node_ids = nids;
        active_edge_ids = eids;
        investigating = False;
    } except Exception as e {
        invest_error = str(e);
        invest_steps = [];
        investigating = False;
    }
}
