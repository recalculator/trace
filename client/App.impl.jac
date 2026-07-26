"""Async handler implementations for App.jac.

SWAP GUIDE — when Ayaan's graph_export endpoint lands, change ONE line here:
  Remove : import from .mock_api { get_repo_graph }
  Add    : sv import from graph_export { get_repo_graph }
All other code in this file stays identical.
"""

import from .mock_api { get_repo_graph }
import from .InvestTypes { InvestStep }

impl app.loadGraph -> None {
    try {
        result = await get_repo_graph("sample_repo");
        graph = result;
        loading = False;
    } except Exception as e {
        error = str(e);
        loading = False;
    }
}

impl app.on_question_submit(q: str) -> None {
    question = q;
    active_node_ids = [];
    active_edge_ids = [];

    step0 = InvestStep(step_name="Planner",            status="running", timestamp="", node_ids=[], edge_ids=[]);
    step1 = InvestStep(step_name="Call Graph",          status="pending", timestamp="", node_ids=[], edge_ids=[]);
    step2 = InvestStep(step_name="Dependency Analysis", status="pending", timestamp="", node_ids=[], edge_ids=[]);
    step3 = InvestStep(step_name="Risk Analysis",       status="pending", timestamp="", node_ids=[], edge_ids=[]);
    invest_steps = [step0, step1, step2, step3];

    cg_nodes: list[str] = ["rt-signup", "s-signup", "s-validate-signup", "s-create-user", "s-hash-pwd", "s-persist", "s-gen-token"];
    cg_edges: list[str] = ["e-rhs-1", "e-scs-1", "e-scs-2", "e-scs-6"];
    dep_nodes: list[str] = ["rt-signup", "s-signup", "s-validate-signup", "s-create-user", "s-hash-pwd", "s-persist", "s-gen-token", "s-seed-demo"];
    dep_edges: list[str] = ["e-rhs-1", "e-scs-1", "e-scs-2", "e-scs-6", "e-scs-10"];

    setTimeout(lambda {
        invest_steps = [
            InvestStep(step_name="Planner",            status="done",    timestamp="0.3s", node_ids=[], edge_ids=[]),
            InvestStep(step_name="Call Graph",          status="running", timestamp="",     node_ids=[], edge_ids=[]),
            InvestStep(step_name="Dependency Analysis", status="pending", timestamp="",     node_ids=[], edge_ids=[]),
            InvestStep(step_name="Risk Analysis",       status="pending", timestamp="",     node_ids=[], edge_ids=[])
        ];
    }, 300);

    setTimeout(lambda {
        invest_steps = [
            InvestStep(step_name="Planner",            status="done",    timestamp="0.3s", node_ids=[], edge_ids=[]),
            InvestStep(step_name="Call Graph",          status="done",    timestamp="1.2s", node_ids=cg_nodes, edge_ids=cg_edges),
            InvestStep(step_name="Dependency Analysis", status="running", timestamp="",     node_ids=[], edge_ids=[]),
            InvestStep(step_name="Risk Analysis",       status="pending", timestamp="",     node_ids=[], edge_ids=[])
        ];
        active_node_ids = cg_nodes;
        active_edge_ids = cg_edges;
    }, 1200);

    setTimeout(lambda {
        invest_steps = [
            InvestStep(step_name="Planner",            status="done",    timestamp="0.3s", node_ids=[], edge_ids=[]),
            InvestStep(step_name="Call Graph",          status="done",    timestamp="1.2s", node_ids=cg_nodes, edge_ids=cg_edges),
            InvestStep(step_name="Dependency Analysis", status="done",    timestamp="2.5s", node_ids=dep_nodes, edge_ids=dep_edges),
            InvestStep(step_name="Risk Analysis",       status="running", timestamp="",     node_ids=[], edge_ids=[])
        ];
        active_node_ids = dep_nodes;
        active_edge_ids = dep_edges;
    }, 2500);

    setTimeout(lambda {
        invest_steps = [
            InvestStep(step_name="Planner",            status="done", timestamp="0.3s", node_ids=[], edge_ids=[]),
            InvestStep(step_name="Call Graph",          status="done", timestamp="1.2s", node_ids=cg_nodes, edge_ids=cg_edges),
            InvestStep(step_name="Dependency Analysis", status="done", timestamp="2.5s", node_ids=dep_nodes, edge_ids=dep_edges),
            InvestStep(step_name="Risk Analysis",       status="done", timestamp="4.0s", node_ids=dep_nodes, edge_ids=dep_edges)
        ];
    }, 4000);
}
