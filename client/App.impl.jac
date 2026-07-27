"""Async handler implementations for App.jac.

`loadGraph` calls the real graph-export endpoint; `on_question_submit` calls
the real investigation endpoint (`investigation_api.investigate`), which
spawns `forward_trace` / `reverse_trace` server-side and resolves each
evidence step's real graph edge jid before handing the response back.
"""

sv import from graph_export { get_repo_graph }
sv import from investigation_api { investigate }
sv import from github_ingest { analyze_github_repo }

# `InvestStep`, `InvestEvidence` and `InvestResponse` are NOT re-imported
# here: an impl annex already sees its head module's imports (App.jac line
# 1), and re-importing emits a duplicate `import { ... }` into the merged
# App.js, which is a hard JS "already declared" error once the client bundle
# is actually built.

impl AppDashboard.loadGraph -> None {
    try {
        fetched = await get_repo_graph(repo);
        graph = fetched;
        loading = False;
    } except Exception as e {
        error = str(e);
        loading = False;
    }
}

impl AppDashboard.on_analyze_repo(url: str) -> None {
    analyzing = True;
    repo_error = None;
    repo_notice = None;
    try {
        res = await analyze_github_repo(url, True);
        if res.status != "ok" {
            repo_error = res.message;
            analyzing = False;
            return;
        }

        # Switch the whole dashboard onto the new repository: clear the
        # previous investigation, point at the new graph, reload.
        repo = res.repo_name;
        repo_notice = res.message;
        invest_steps = [];
        active_node_ids = [];
        active_edge_ids = [];
        result = None;
        invest_error = None;
        question = "";
        loading = True;

        fetched = await get_repo_graph(res.repo_name);
        graph = fetched;
        loading = False;
        analyzing = False;
    } except Exception as e {
        repo_error = "Analyze failed: " + str(e);
        loading = False;
        analyzing = False;
    }
}

impl AppDashboard.on_question_submit(q: str) -> None {
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
        res = await investigate(q, repo);
        result = res;
        if res.status != "ok" {
            invest_steps = [];
            investigating = False;
            return;
        }

        # Bucket evidence into 4 fixed narrative stages regardless of how
        # many depth levels the traversal actually produced.
        # Bucketing rule:
        #   depth 0                 → Planner
        #   depth 1 (if not last)   → Call Graph
        #   depths 2..last-1        → Dependency Analysis
        #   last depth              → Risk Analysis
        # When depth_reached < 3 some stages will have empty node/edge sets;
        # all 4 steps are always emitted so the Timeline label list is stable.
        planner_nids: list[str] = [];
        planner_eids: list[str] = [];
        callgraph_nids: list[str] = [];
        callgraph_eids: list[str] = [];
        depanalysis_nids: list[str] = [];
        depanalysis_eids: list[str] = [];
        risk_nids: list[str] = [];
        risk_eids: list[str] = [];

        for ev in res.evidence {
            d: int = ev.depth;
            if d == 0 {
                planner_nids = planner_nids + [ev.node_id];
                if ev.edge_id != "" {
                    planner_eids = planner_eids + [ev.edge_id];
                }
            } elif d == res.depth_reached {
                risk_nids = risk_nids + [ev.node_id];
                if ev.edge_id != "" {
                    risk_eids = risk_eids + [ev.edge_id];
                }
            } elif d == 1 {
                callgraph_nids = callgraph_nids + [ev.node_id];
                if ev.edge_id != "" {
                    callgraph_eids = callgraph_eids + [ev.edge_id];
                }
            } else {
                depanalysis_nids = depanalysis_nids + [ev.node_id];
                if ev.edge_id != "" {
                    depanalysis_eids = depanalysis_eids + [ev.edge_id];
                }
            }
        }

        steps: list[InvestStep] = [
            InvestStep(
                step_name="Planner — Started investigation",
                status="done",
                timestamp="",
                node_ids=planner_nids,
                edge_ids=planner_eids
            ),
            InvestStep(
                step_name="Call Graph — Following execution path",
                status="done",
                timestamp="",
                node_ids=callgraph_nids,
                edge_ids=callgraph_eids
            ),
            InvestStep(
                step_name="Dependency Analysis — Following imports",
                status="done",
                timestamp="",
                node_ids=depanalysis_nids,
                edge_ids=depanalysis_eids
            ),
            InvestStep(
                step_name="Risk Analysis — Computing blast radius",
                status="done",
                timestamp="",
                node_ids=risk_nids,
                edge_ids=risk_eids
            )
        ];
        nids: list[str] = planner_nids + callgraph_nids + depanalysis_nids + risk_nids;
        eids: list[str] = planner_eids + callgraph_eids + depanalysis_eids + risk_eids;
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
