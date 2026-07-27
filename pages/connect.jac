import from "@jac/runtime" { Link }
import from ..client.types { RepoGraph, InvestResponse }
import from ..client.InvestTypes { InvestStep }
import from ..client.QuestionInput { QuestionInput }
import from ..client.Timeline { Timeline }
import from ..client.GraphViz { GraphViz }
import from ..client.Explanation { Explanation }

glob CONNECT_CSS: str = (
    "@import url('https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400;0,500;1,400&display=swap'); "
    "@keyframes cardIn { to { opacity: 1; transform: translateY(0); } } "
    "@keyframes spin { to { transform: rotate(360deg); } } "
    ".connect-card { opacity: 0; transform: translateY(20px); "
    "  animation: cardIn 0.7s ease 0.1s forwards; "
    "  background: rgba(18,22,32,0.82); "
    "  backdrop-filter: blur(32px) saturate(160%); "
    "  -webkit-backdrop-filter: blur(32px) saturate(160%); "
    "  border: 1px solid rgba(255,255,255,0.1); border-radius: 24px; "
    "  box-shadow: 0 24px 64px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.07); } "
    ".connect-input { width: 100%; background: rgba(255,255,255,0.05); "
    "  border: 1px solid rgba(255,255,255,0.1); border-radius: 10px; "
    "  color: #E8EDF7; font-size: 14px; padding: 12px 16px; outline: none; "
    "  font-family: 'JetBrains Mono', ui-monospace, monospace; box-sizing: border-box; "
    "  transition: border-color 0.15s; } "
    ".connect-input:focus { border-color: rgba(200,81,32,0.5); } "
    ".connect-input::placeholder { color: #4D6080; } "
    ".btn-primary { background: #C85120; color: #F5F7FA; "
    "  font-size: 14px; font-weight: 600; padding: 12px 24px; border-radius: 10px; "
    "  border: none; cursor: pointer; letter-spacing: 0.01em; white-space: nowrap; "
    "  transition: opacity 0.15s, transform 0.15s; } "
    ".btn-primary:hover { opacity: 0.87; transform: translateY(-1px); } "
    ".btn-sample { width: 100%; background: #C85120; color: #F5F7FA; "
    "  font-size: 15px; font-weight: 600; padding: 14px 24px; border-radius: 10px; "
    "  border: none; cursor: pointer; letter-spacing: 0.01em; "
    "  transition: opacity 0.15s, transform 0.15s; } "
    ".btn-sample:hover { opacity: 0.87; transform: translateY(-1px); } "
    ".sample-badge { background: rgba(200,81,32,0.2); color: #C85120; "
    "  font-size: 10px; font-weight: 700; padding: 3px 10px; border-radius: 9999px; "
    "  letter-spacing: 0.08em; text-transform: uppercase; "
    "  font-family: 'JetBrains Mono', ui-monospace, monospace; "
    "  border: 1px solid rgba(200,81,32,0.3); } "
    ".back-link { color: rgba(232,237,247,0.55); text-decoration: none; font-size: 13px; "
    "  display: inline-flex; align-items: center; gap: 6px; "
    "  transition: color 0.15s; letter-spacing: 0.01em; } "
    ".back-link:hover { color: rgba(232,237,247,0.9); } "
    ".glass-panel { background: rgba(18,22,32,0.75); "
    "  backdrop-filter: blur(24px) saturate(160%); "
    "  -webkit-backdrop-filter: blur(24px) saturate(160%); "
    "  border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; "
    "  box-shadow: 0 8px 32px rgba(0,0,0,0.3); } "
    ".repo-chip { display: inline-flex; align-items: center; gap: 6px; "
    "  background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.1); "
    "  border-radius: 9999px; padding: 4px 12px; font-size: 12px; "
    "  font-family: 'JetBrains Mono', ui-monospace, monospace; color: #8A9BB8; } "
    ".spinner { width: 18px; height: 18px; border: 2px solid rgba(200,81,32,0.2); "
    "  border-top-color: #C85120; border-radius: 50%; display: inline-block; "
    "  animation: spin 0.8s linear infinite; } "
    "@media (prefers-reduced-motion: reduce) { "
    "  .connect-card { animation: none; opacity: 1; transform: none; } "
    "  .btn-primary:hover, .btn-sample:hover { transform: none; } "
    "  .spinner { animation: none; } "
    "} "
    "@media (max-width: 768px) { "
    "  .app-cols { flex-direction: column !important; } "
    "  .timeline-col { width: auto !important; } "
    "}"
);

def:pub ConnectPage() -> JsxPage {
    has phase: str = "connect";
    has github_url: str = "";
    has repo: str = "";
    has connect_error: str | None = None;
    has graph: RepoGraph | None = None;
    has invest_steps: list[InvestStep] = [];
    has result: InvestResponse | None = None;
    has investigating: bool = False;
    has invest_error: str | None = None;
    has active_node_ids: list[str] = [];
    has active_edge_ids: list[str] = [];

    async def on_connect_sample() -> None;
    async def on_connect_github(url: str) -> None;
    async def loadGraph() -> None;
    async def on_question_submit(q: str) -> None;

    n_nodes = 0 if graph is None else len(graph.nodes);
    n_edges = 0 if graph is None else len(graph.edges);

    return
        <div style={{"minHeight": "100vh", "background": "#0C0F15", "position": "relative",
                     "color": "#E8EDF7", "fontFamily": "system-ui, -apple-system, sans-serif"}}>
            <style dangerouslySetInnerHTML={{"__html": CONNECT_CSS}} />

            {#* Blurred bridge background — persists across both phases *#}
            <img
                src="http://localhost:8090/bridge.jpg"
                alt=""
                aria-hidden="true"
                style={{"position": "fixed", "inset": "0", "width": "100%", "height": "100%",
                        "objectFit": "cover", "objectPosition": "center 28%",
                        "filter": "blur(24px) brightness(0.2)", "transform": "scale(1.06)",
                        "zIndex": "0"}}
            />

            {#* ── CONNECT PHASE ── *#}
            {if phase == "connect" {
                <div style={{"position": "relative", "zIndex": "1", "display": "flex",
                             "flexDirection": "column", "minHeight": "100vh"}}>
                    <div style={{"padding": "28px 48px"}}>
                        <Link to="/" className="back-link">← Trace</Link>
                    </div>
                    <div style={{"flex": "1", "display": "flex", "alignItems": "center",
                                 "justifyContent": "center", "padding": "0 24px 60px"}}>
                        <div className="connect-card" style={{"width": "100%", "maxWidth": "460px"}}>
                            <div style={{"padding": "32px 36px 0"}}>
                                <h1 style={{"fontFamily": "'EB Garamond', Georgia, serif",
                                            "fontSize": "26px", "fontWeight": "400",
                                            "color": "#F5F7FA", "margin": "0 0 8px 0"}}>
                                    Where should Trace start?
                                </h1>
                                <p style={{"fontSize": "14px", "color": "#6B7FA0",
                                           "margin": "0", "lineHeight": "1.5"}}>
                                    Connect a repo and Trace builds the graph before it answers anything.
                                </p>
                            </div>
                            <div style={{"height": "1px", "background": "rgba(255,255,255,0.07)", "margin": "28px 0 0"}} />
                            <div style={{"padding": "28px 36px 36px"}}>
                                {if connect_error is not None {
                                    <p style={{"color": "#f87171", "fontSize": "13px",
                                               "margin": "0 0 16px 0", "fontFamily": "'JetBrains Mono', ui-monospace, monospace"}}>
                                        {connect_error if connect_error is not None else ""}
                                    </p>
                                }}
                                <p style={{"fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                           "fontSize": "10px", "fontWeight": "700", "letterSpacing": "0.1em",
                                           "textTransform": "uppercase", "color": "#6B7FA0",
                                           "margin": "0 0 10px 0"}}>
                                    GitHub URL
                                </p>
                                <div style={{"display": "flex", "gap": "10px"}}>
                                    <input
                                        type="text"
                                        value={github_url}
                                        placeholder="https://github.com/org/repo"
                                        className="connect-input"
                                        onChange={lambda (e: ChangeEvent) { github_url = e.target.value as str; }}
                                        onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Enter" and github_url != "" { on_connect_github(github_url); }}}
                                    />
                                    <button className="btn-primary"
                                        onClick={lambda (e: MouseEvent) { if github_url != "" { on_connect_github(github_url); }}}>
                                        Analyze
                                    </button>
                                </div>
                                <div style={{"display": "flex", "alignItems": "center", "margin": "24px 0"}}>
                                    <div style={{"flex": "1", "height": "1px", "background": "rgba(255,255,255,0.07)"}} />
                                    <span style={{"fontSize": "11px", "color": "#4D6080", "padding": "0 14px",
                                                  "fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                                  "letterSpacing": "0.06em"}}>or</span>
                                    <div style={{"flex": "1", "height": "1px", "background": "rgba(255,255,255,0.07)"}} />
                                </div>
                                <div style={{"background": "rgba(200,81,32,0.06)",
                                             "border": "1px solid rgba(200,81,32,0.2)",
                                             "borderRadius": "14px", "padding": "24px"}}>
                                    <div style={{"display": "flex", "alignItems": "center",
                                                 "gap": "10px", "marginBottom": "10px"}}>
                                        <p style={{"fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                                   "fontSize": "10px", "fontWeight": "700", "letterSpacing": "0.1em",
                                                   "textTransform": "uppercase", "color": "#8A9BB8", "margin": "0"}}>
                                            Sample repo
                                        </p>
                                        <span className="sample-badge">Demo ready</span>
                                    </div>
                                    <p style={{"fontSize": "13px", "color": "#8A9BB8",
                                               "margin": "0 0 18px 0", "lineHeight": "1.55"}}>
                                        Lexora — a full-stack AI document analysis app. Cloned and indexed on first load.
                                    </p>
                                    <button className="btn-sample"
                                        onClick={lambda (e: MouseEvent) { on_connect_sample(); }}>
                                        Use sample repo →
                                    </button>
                                </div>
                                <div style={{"marginTop": "12px", "opacity": "0.35", "textAlign": "center",
                                             "padding": "10px 0"}}>
                                    <span style={{"fontSize": "12px", "color": "#6B7FA0",
                                                  "fontFamily": "'JetBrains Mono', ui-monospace, monospace"}}>
                                        Local folder support coming soon
                                    </span>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            }}

            {#* ── LOADING PHASE ── *#}
            {if phase == "loading" {
                <div style={{"position": "relative", "zIndex": "1", "display": "flex",
                             "alignItems": "center", "justifyContent": "center", "minHeight": "100vh"}}>
                    <div className="connect-card" style={{"padding": "48px 56px", "textAlign": "center",
                                                          "minWidth": "320px"}}>
                        <div className="spinner" style={{"margin": "0 auto 20px"}} />
                        <p style={{"fontFamily": "'EB Garamond', Georgia, serif", "fontSize": "20px",
                                   "fontWeight": "400", "color": "#E8EDF7", "margin": "0 0 8px 0"}}>
                            Building graph…
                        </p>
                        <p style={{"fontSize": "13px", "color": "#6B7FA0", "margin": "0",
                                   "fontFamily": "'JetBrains Mono', ui-monospace, monospace"}}>
                            Parsing files, resolving imports, mapping call edges
                        </p>
                    </div>
                </div>
            }}

            {#* ── APP PHASE ── *#}
            {if phase == "app" {
                <div style={{"position": "relative", "zIndex": "1", "minHeight": "100vh",
                             "display": "flex", "flexDirection": "column"}}>

                    {#* Slim app header *#}
                    <header style={{"display": "flex", "alignItems": "center", "gap": "16px",
                                    "padding": "16px 32px", "borderBottom": "1px solid rgba(255,255,255,0.07)",
                                    "background": "rgba(12,15,21,0.6)",
                                    "backdropFilter": "blur(20px)",
                                    "WebkitBackdropFilter": "blur(20px)",
                                    "position": "sticky", "top": "0", "zIndex": "20"}}>
                        <button
                            onClick={lambda (e: MouseEvent) {
                                phase = "connect";
                                result = None;
                                invest_steps = [];
                                connect_error = None;
                            }}
                            style={{"background": "none", "border": "none", "color": "rgba(232,237,247,0.5)",
                                    "fontSize": "13px", "cursor": "pointer", "padding": "0",
                                    "letterSpacing": "0.01em", "transition": "color 0.15s"}}>
                            ← Reconnect
                        </button>
                        <span style={{"color": "rgba(255,255,255,0.12)", "fontSize": "16px"}}>|</span>
                        <span style={{"fontFamily": "'EB Garamond', Georgia, serif", "fontSize": "18px",
                                      "fontWeight": "500", "fontStyle": "italic", "color": "#F5F7FA"}}>
                            Trace
                        </span>
                        <div style={{"marginLeft": "auto", "display": "flex", "gap": "8px", "alignItems": "center"}}>
                            <span className="repo-chip">
                                <span style={{"width": "6px", "height": "6px", "borderRadius": "50%",
                                              "background": "#C85120", "display": "inline-block"}} />
                                {repo}
                            </span>
                            {if graph is not None {
                                <span className="repo-chip">
                                    {str(n_nodes) + " nodes · " + str(n_edges) + " edges"}
                                </span>
                            }}
                        </div>
                    </header>

                    {#* Main investigation area *#}
                    <main style={{"flex": "1", "padding": "24px 32px", "display": "flex",
                                  "flexDirection": "column", "gap": "20px"}}>

                        {#* Question input *#}
                        <div className="glass-panel" style={{"padding": "20px 24px"}}>
                            <QuestionInput on_submit={on_question_submit} />
                            {if invest_error is not None {
                                <p style={{"color": "#f87171", "fontSize": "13px", "margin": "10px 0 0 0",
                                           "fontFamily": "'JetBrains Mono', ui-monospace, monospace"}}>
                                    {"Error: " + (invest_error if invest_error is not None else "")}
                                </p>
                            }}
                        </div>

                        {#* Investigating spinner *#}
                        {if investigating {
                            <div className="glass-panel" style={{"padding": "24px", "display": "flex",
                                                                  "alignItems": "center", "gap": "14px"}}>
                                <div className="spinner" />
                                <span style={{"fontSize": "14px", "color": "#8A9BB8",
                                              "fontFamily": "'JetBrains Mono', ui-monospace, monospace"}}>
                                    Traversing the graph…
                                </span>
                            </div>
                        }}

                        {#* Graph + Timeline layout:
                             - Graph shows immediately once loaded (no investigation needed)
                             - Timeline column only appears after an investigation *#}
                        {if graph is not None {
                            <div className="app-cols"
                                 style={{"display": "flex", "gap": "20px", "alignItems": "flex-start"}}>
                                {if len(invest_steps) > 0 {
                                    <div className="glass-panel timeline-col"
                                         style={{"width": "280px", "flexShrink": "0", "padding": "20px"}}>
                                        <Timeline steps={invest_steps} />
                                    </div>
                                }}
                                <div className="glass-panel" style={{"flex": "1", "minWidth": "0", "padding": "12px",
                                                                      "overflow": "hidden"}}>
                                    <GraphViz
                                        graph={graph}
                                        ext_node_ids={active_node_ids}
                                        ext_edge_ids={active_edge_ids}
                                    />
                                </div>
                            </div>
                        }}

                        {#* Explanation / answer panel *#}
                        {if result is not None and result.status == "ok" {
                            <div className="glass-panel" style={{"padding": "24px"}}>
                                <Explanation result={result} />
                            </div>
                        }}

                        {if result is not None and result.status == "ambiguous" {
                            <div className="glass-panel" style={{"padding": "24px"}}>
                                <Explanation result={result} />
                            </div>
                        }}

                        {if result is not None and result.status == "not_found" {
                            <div className="glass-panel" style={{
                                "padding": "24px",
                                "background": "rgba(18,22,32,0.75)",
                                "backdropFilter": "blur(24px)",
                                "WebkitBackdropFilter": "blur(24px)"
                            }}>
                                <p style={{
                                    "margin": "0 0 6px 0",
                                    "fontSize": "11px", "fontWeight": "700",
                                    "letterSpacing": "0.08em", "textTransform": "uppercase",
                                    "color": "#f87171",
                                    "fontFamily": "'JetBrains Mono', ui-monospace, monospace"
                                }}>
                                    {"Not found"}
                                </p>
                                <p style={{"fontSize": "14px", "color": "#8A9BB8", "margin": "0", "lineHeight": "1.6"}}>
                                    {result.message}
                                </p>
                            </div>
                        }}
                    </main>
                </div>
            }}
        </div>;
}
