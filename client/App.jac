import from .types { RepoGraph }
import from .GraphViz { GraphViz }
import from .InvestTypes { InvestStep }
import from .QuestionInput { QuestionInput }
import from .Timeline { Timeline }
import from .Explanation { Explanation }

def all_done(steps: list[InvestStep]) -> bool {
    if len(steps) == 0 { return False; }
    for s in steps {
        if s.status != "done" { return False; }
    }
    return True;
}

def:pub app -> JsxElement {
    has graph: RepoGraph | None = None,
        loading: bool = True,
        error: str | None = None,
        question: str = "",
        invest_steps: list[InvestStep] = [],
        active_node_ids: list[str] = [],
        active_edge_ids: list[str] = [];

    can with entry { loadGraph(); }

    async def loadGraph -> None;
    async def on_question_submit(q: str) -> None;

    n_nodes = 0 if graph is None else len(graph.nodes);
    n_edges = 0 if graph is None else len(graph.edges);

    return <div style={{"fontFamily": "system-ui, sans-serif", "background": "#020617", "minHeight": "100vh", "color": "#f1f5f9"}}>
        <header style={{"padding": "20px 32px", "borderBottom": "1px solid #1e293b", "display": "flex", "alignItems": "center", "gap": "16px"}}>
            <h1 style={{"margin": "0", "fontSize": "22px", "fontWeight": "700", "color": "#f8fafc", "letterSpacing": "-0.5px"}}>Trace</h1>
            <span style={{"color": "#475569", "fontSize": "13px"}}>Autonomous software investigation.</span>
            {if not loading and error is None {
                <span style={{"marginLeft": "auto", "fontSize": "12px", "color": "#64748b", "fontFamily": "monospace"}}>
                    {str(n_nodes) + " nodes · " + str(n_edges) + " edges"}
                </span>
            }}
        </header>

        <main style={{"padding": "24px 32px"}}>
            <QuestionInput on_submit={on_question_submit} />
            <div style={{"display": "flex", "gap": "24px", "marginTop": "24px", "alignItems": "flex-start"}}>
                {if len(invest_steps) > 0 {
                    <div style={{"width": "280px", "flexShrink": "0"}}>
                        <Timeline steps={invest_steps} />
                    </div>
                }}
                <div style={{"flex": "1", "minWidth": "0"}}>
                    {if loading { <p style={{"color": "#475569", "fontFamily": "monospace"}}>Loading graph…</p> }}
                    {if not loading and error is not None { <p style={{"color": "#f87171"}}>{"Error: " + (error if error is not None else "")}</p> }}
                    {if not loading and error is None and graph is not None {
                        <GraphViz graph={graph} ext_node_ids={active_node_ids} ext_edge_ids={active_edge_ids} />
                    }}
                </div>
            </div>
            {if all_done(invest_steps) {
                <Explanation />
            }}
        </main>
    </div>;
}
