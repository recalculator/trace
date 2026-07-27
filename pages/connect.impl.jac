sv import from github_ingest { analyze_github_repo }
sv import from graph_export { get_repo_graph }
sv import from investigation_api { investigate }

glob DEMO_REPO_URL: str = "https://github.com/recalculator/lexora";
glob DEMO_REPO_NAME: str = "recalculator/lexora";

impl ConnectPage.on_connect_sample -> None {
    connect_error = None;
    phase = "loading";
    try {
        res = await analyze_github_repo(DEMO_REPO_URL, False);
        if res.status != "ok" {
            connect_error = res.message;
            phase = "connect";
            return;
        }
        repo = DEMO_REPO_NAME;
        fetched = await get_repo_graph(DEMO_REPO_NAME);
        graph = fetched;
        phase = "app";
    } except Exception as e {
        connect_error = "Failed to load demo repo: " + str(e);
        phase = "connect";
    }
}

impl ConnectPage.on_connect_github(url: str) -> None {
    connect_error = None;
    phase = "loading";
    try {
        res = await analyze_github_repo(url, True);
        if res.status != "ok" {
            connect_error = res.message;
            phase = "connect";
            return;
        }
        repo = res.repo_name;
        # Pass res.repo_name directly — same stale-state reason as above.
        fetched = await get_repo_graph(res.repo_name);
        graph = fetched;
        phase = "app";
    } except Exception as e {
        connect_error = "Failed to clone repo: " + str(e);
        phase = "connect";
    }
}

impl ConnectPage.loadGraph -> None {
    try {
        fetched = await get_repo_graph(repo);
        graph = fetched;
        phase = "app";
    } except Exception as e {
        connect_error = "Failed to load graph: " + str(e);
        phase = "connect";
    }
}

impl ConnectPage.on_question_submit(q: str) -> None {
    invest_error = None;
    result = None;
    active_node_ids = [];
    active_edge_ids = [];
    investigating = True;
    invest_steps = [
        InvestStep(step_name="Planning…", status="running", timestamp="", node_ids=[], edge_ids=[])
    ];

    try {
        # planner="auto" uses Anthropic when ANTHROPIC_API_KEY is set,
        # falls back to deterministic otherwise
        res = await investigate(q, repo, "auto");
        result = res;

        if res.status not in ["ok", "ambiguous"] {
            invest_steps = [];
            investigating = False;
            return;
        }

        evs = res.evidence;
        n = len(evs);

        nids: list[str] = [];
        eids: list[str] = [];
        for ev in evs {
            if ev.node_id != "" and ev.node_id not in nids {
                nids.append(ev.node_id);
            }
            if ev.edge_id != "" and ev.edge_id not in eids {
                eids.append(ev.edge_id);
            }
        }
        active_node_ids = nids;
        active_edge_ids = eids;

        # Bucket evidence into 4 narrative stages
        bucket0: list = [];
        bucket1: list = [];
        bucket2: list = [];
        bucket3: list = [];
        for ev in evs {
            d = ev.depth;
            if d == 0 {
                bucket0.append(ev);
            } elif n > 2 and d == n - 1 {
                bucket3.append(ev);
            } elif d == 1 and n > 3 {
                bucket1.append(ev);
            } else {
                bucket2.append(ev);
            }
        }

        steps: list[InvestStep] = [
            InvestStep(
                step_name="Planner — Started investigation",
                status="done",
                timestamp=str(len(bucket0)) + " seed",
                node_ids=[ev.node_id for ev in bucket0],
                edge_ids=[ev.edge_id for ev in bucket0]
            ),
            InvestStep(
                step_name="Call Graph — Execution path",
                status="done",
                timestamp=str(len(bucket1)) + " nodes",
                node_ids=[ev.node_id for ev in bucket1],
                edge_ids=[ev.edge_id for ev in bucket1]
            ),
            InvestStep(
                step_name="Dependency Analysis — Imports",
                status="done",
                timestamp=str(len(bucket2)) + " nodes",
                node_ids=[ev.node_id for ev in bucket2],
                edge_ids=[ev.edge_id for ev in bucket2]
            ),
            InvestStep(
                step_name="Risk Analysis — Blast radius",
                status="done",
                timestamp=str(len(bucket3)) + " nodes",
                node_ids=[ev.node_id for ev in bucket3],
                edge_ids=[ev.edge_id for ev in bucket3]
            )
        ];
        invest_steps = steps;
        investigating = False;

    } except Exception as e {
        invest_error = str(e);
        invest_steps = [];
        investigating = False;
    }
}
