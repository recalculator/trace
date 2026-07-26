"""Trace investigation dashboard — root client component.

Step 1 (this file): loads graph on mount, renders node/edge counts to prove
the client-component wiring against the mock works before any visualisation
is built.

Subsequent steps will add:
  - question input
  - investigation timeline (planner / call-graph / dependency / risk steps)
  - live graph visualisation (the demo's wow moment)
  - synthesised explanation panel
"""

import from .types { RepoGraph }

def:pub app -> JsxElement {
    has graph: RepoGraph | None = None,
        loading: bool = True,
        error: str | None = None;

    can with entry { loadGraph(); }

    async def loadGraph -> None;

    return <div className="trace-app">
        <header className="trace-header">
            <h1>Trace</h1>
            <p>Autonomous software investigation.</p>
        </header>

        <main className="trace-main">
            {if loading {
                <p className="trace-status">Loading graph…</p>
            }}
            {if not loading and error is not None {
                <p className="trace-error">Error: {error}</p>
            }}
            {if not loading and error is None and graph is not None {
                <section className="graph-summary">
                    <h2>Graph loaded</h2>
                    <dl>
                        <dt>Nodes</dt>
                        <dd>{len(graph.nodes)}</dd>
                        <dt>Edges</dt>
                        <dd>{len(graph.edges)}</dd>
                    </dl>
                </section>
            }}
        </main>
    </div>;
}
