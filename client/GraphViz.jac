import from .types { RepoGraph, GraphNode, GraphEdge }

# ---------------------------------------------------------------------------
# Per-type colour / style helpers — all pure functions, no assignments in
# JSX slot bodies (Jac slot bodies only accept JSX element statements).
# ---------------------------------------------------------------------------

def node_fill(node_type: str, kind: str) -> str {
    if node_type == "Repository" { return "#6366f1"; }
    if node_type == "File" { return "#38bdf8"; }
    if node_type == "Route" { return "#fb923c"; }
    if kind == "class" { return "#34d399"; }
    if kind == "async_function" { return "#f472b6"; }
    if kind == "function" { return "#a78bfa"; }
    return "#94a3b8";
}

def edge_stroke(edge_type: str) -> str {
    if edge_type == "RepositoryContainsFile" { return "#6366f1"; }
    if edge_type == "FileContainsSymbol" { return "#38bdf8"; }
    if edge_type == "FileImportsFile" { return "#fb923c"; }
    if edge_type == "SymbolCallsSymbol" { return "#f472b6"; }
    if edge_type == "RouteHandledBySymbol" { return "#34d399"; }
    if edge_type == "RepositoryContainsRoute" { return "#fbbf24"; }
    return "#64748b";
}

def edge_dash(edge_type: str) -> str {
    if edge_type == "FileImportsFile" { return "5 3"; }
    if edge_type == "SymbolCallsSymbol" { return "2 2"; }
    return "";
}

def node_r(node_type: str) -> int {
    if node_type == "Repository" { return 22; }
    if node_type == "File" { return 14; }
    if node_type == "Route" { return 12; }
    return 7;
}

def edge_marker(edge_type: str) -> str {
    if edge_type == "RepositoryContainsFile" { return "arr0"; }
    if edge_type == "FileContainsSymbol" { return "arr1"; }
    if edge_type == "FileImportsFile" { return "arr2"; }
    if edge_type == "SymbolCallsSymbol" { return "arr3"; }
    if edge_type == "RouteHandledBySymbol" { return "arr4"; }
    return "arr5";
}

def node_op(selected_id: str, highlighted_ids: list[str], ext_node_ids: list[str], node_id: str) -> str {
    if len(highlighted_ids) == 0 and len(ext_node_ids) == 0 { return "1"; }
    if node_id == selected_id { return "1"; }
    if node_id in ext_node_ids { return "1"; }
    if node_id in highlighted_ids { return "0.9"; }
    return "0.15";
}

def node_stroke_c(selected_id: str, highlighted_ids: list[str], ext_node_ids: list[str], node_id: str) -> str {
    if node_id == selected_id { return "#ffffff"; }
    if node_id in ext_node_ids { return "#f59e0b"; }
    if node_id in highlighted_ids { return "#e2e8f0"; }
    return "none";
}

def node_stroke_w(selected_id: str, highlighted_ids: list[str], ext_node_ids: list[str], node_id: str) -> str {
    if node_id == selected_id { return "3"; }
    if node_id in ext_node_ids { return "2.5"; }
    if node_id in highlighted_ids { return "2"; }
    return "0";
}

def edge_op(selected_id: str, highlighted_ids: list[str], ext_edge_ids: list[str], edge_id: str, src: str, tgt: str) -> str {
    if len(highlighted_ids) == 0 and len(ext_edge_ids) == 0 { return "0.5"; }
    if edge_id in ext_edge_ids { return "0.85"; }
    if src == selected_id or tgt == selected_id { return "0.95"; }
    if src in highlighted_ids or tgt in highlighted_ids { return "0.65"; }
    return "0.05";
}

def short_label(name: str) -> str {
    if len(name) > 16 { return name[0:15] + "…"; }
    return name;
}

# ---------------------------------------------------------------------------
# GraphViz component
# ---------------------------------------------------------------------------

def:pub GraphViz(graph: RepoGraph, ext_node_ids: list[str], ext_edge_ids: list[str]) -> JsxElement {
    has pos_x: dict = {},
        pos_y: dict = {},
        pan_x: float = 0.0,
        pan_y: float = 0.0,
        zoom: float = 0.85,
        selected_id: str = "",
        highlighted_ids: list[str] = [],
        simulated: bool = False;

    has dragging: Ref[bool] = Ref(False),
        drag_sx: Ref[float] = Ref(0.0),
        drag_sy: Ref[float] = Ref(0.0),
        pan_sx: Ref[float] = Ref(0.0),
        pan_sy: Ref[float] = Ref(0.0);

    can with entry { layout_graph(); }
    async def layout_graph -> None;

    def on_wheel(e: Event) {
        delta = e.deltaY as float;  # jac:ignore[E1030] WheelEvent.deltaY not in base Event stubs
        nz = zoom - delta * 0.001;
        if nz < 0.15 { nz = 0.15; }
        if nz > 5.0 { nz = 5.0; }
        zoom = nz;
    }

    def on_mouse_down(e: MouseEvent) {
        dragging.current = True;
        drag_sx.current = e.clientX as float;
        drag_sy.current = e.clientY as float;
        pan_sx.current = pan_x;
        pan_sy.current = pan_y;
    }

    def on_mouse_move(e: MouseEvent) {
        if dragging.current {
            pan_x = (pan_sx.current as float) + ((e.clientX as float) - (drag_sx.current as float));
            pan_y = (pan_sy.current as float) + ((e.clientY as float) - (drag_sy.current as float));
        }
    }

    def on_mouse_up(e: MouseEvent) {
        dragging.current = False;
    }

    def on_node_click(node_id: str) -> None {
        if selected_id == node_id {
            selected_id = "";
            highlighted_ids = [];
            return;
        }
        selected_id = node_id;
        nbrs: list[str] = [];
        for edge in graph.edges {
            if edge.source == node_id {
                nbrs = nbrs + [edge.target];
            }
            if edge.target == node_id {
                nbrs = nbrs + [edge.source];
            }
        }
        highlighted_ids = nbrs;
    }

    xform = "translate(" + str(pan_x) + " " + str(pan_y) + ") scale(" + str(zoom) + ")";

    return <div style={{"position": "relative", "width": "100%", "height": "700px", "background": "#0f172a", "borderRadius": "8px", "overflow": "hidden"}}>
        {if not simulated {
            <div style={{"color": "#94a3b8", "padding": "24px", "fontFamily": "monospace"}}>Computing layout…</div>
        }}
        {if simulated {
            <svg
                width="100%"
                height="700"
                viewBox="0 0 1100 700"
                onWheel={on_wheel}
                onMouseDown={on_mouse_down}
                onMouseMove={on_mouse_move}
                onMouseUp={on_mouse_up}
                style={{"display": "block", "cursor": "grab", "userSelect": "none"}}
            >
                <defs>
                    <marker id="arr0" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
                        <polygon points="0 0,8 3,0 6" fill="#6366f1" />
                    </marker>
                    <marker id="arr1" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
                        <polygon points="0 0,8 3,0 6" fill="#38bdf8" />
                    </marker>
                    <marker id="arr2" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
                        <polygon points="0 0,8 3,0 6" fill="#fb923c" />
                    </marker>
                    <marker id="arr3" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
                        <polygon points="0 0,8 3,0 6" fill="#f472b6" />
                    </marker>
                    <marker id="arr4" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
                        <polygon points="0 0,8 3,0 6" fill="#34d399" />
                    </marker>
                    <marker id="arr5" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
                        <polygon points="0 0,8 3,0 6" fill="#fbbf24" />
                    </marker>
                </defs>

                {#* Pan+zoom group *#}
                <g transform={xform}>

                    {#* Edges rendered first (below nodes) *#}
                    {for edge in graph.edges {
                        <line
                            key={edge.id}
                            x1={pos_x[edge.source] as float}
                            y1={pos_y[edge.source] as float}
                            x2={pos_x[edge.target] as float}
                            y2={pos_y[edge.target] as float}
                            stroke={edge_stroke(edge.edge_type)}
                            strokeWidth="1.5"
                            strokeDasharray={edge_dash(edge.edge_type)}
                            markerEnd={"url(#" + edge_marker(edge.edge_type) + ")"}
                            opacity={edge_op(selected_id, highlighted_ids, ext_edge_ids, edge.id, edge.source, edge.target)}
                        />
                    }}

                    {#* Node circles *#}
                    {for nd in graph.nodes {
                        <circle
                            key={nd.id}
                            cx={pos_x[nd.id] as float}
                            cy={pos_y[nd.id] as float}
                            r={node_r(nd.node_type)}
                            fill={node_fill(nd.node_type, nd.kind)}
                            stroke={node_stroke_c(selected_id, highlighted_ids, ext_node_ids, nd.id)}
                            strokeWidth={node_stroke_w(selected_id, highlighted_ids, ext_node_ids, nd.id)}
                            opacity={node_op(selected_id, highlighted_ids, ext_node_ids, nd.id)}
                            style={{"cursor": "pointer"}}
                            onClick={lambda (e: MouseEvent) { on_node_click(nd.id); }}
                        />
                    }}

                    {#* Labels below each node *#}
                    {for nd in graph.nodes {
                        <text
                            key={nd.id + "-t"}
                            x={pos_x[nd.id] as float}
                            y={(pos_y[nd.id] as float) + (node_r(nd.node_type) as float) + 11.0}
                            textAnchor="middle"
                            fontSize="8"
                            fill="#94a3b8"
                            opacity={node_op(selected_id, highlighted_ids, ext_node_ids, nd.id)}
                            style={{"pointerEvents": "none", "userSelect": "none"}}
                        >{short_label(nd.name)}</text>
                    }}

                </g>

                {#* Fixed legend overlay (does NOT move with pan/zoom) *#}
                <g transform="translate(12,12)">
                    <rect x="0" y="0" width="182" height="224" rx="6" fill="#1e293b" opacity="0.92" />
                    <text x="8" y="18" fontSize="10" fontWeight="bold" fill="#e2e8f0">Nodes</text>
                    <circle cx="16" cy="32" r="6" fill="#6366f1" /><text x="28" y="36" fontSize="9" fill="#94a3b8">Repository</text>
                    <circle cx="16" cy="50" r="6" fill="#38bdf8" /><text x="28" y="54" fontSize="9" fill="#94a3b8">File</text>
                    <circle cx="16" cy="68" r="6" fill="#a78bfa" /><text x="28" y="72" fontSize="9" fill="#94a3b8">Symbol / function</text>
                    <circle cx="16" cy="86" r="6" fill="#34d399" /><text x="28" y="90" fontSize="9" fill="#94a3b8">Symbol / class</text>
                    <circle cx="16" cy="104" r="6" fill="#f472b6" /><text x="28" y="108" fontSize="9" fill="#94a3b8">Symbol / async fn</text>
                    <circle cx="16" cy="122" r="6" fill="#94a3b8" /><text x="28" y="126" fontSize="9" fill="#94a3b8">Symbol / method</text>
                    <circle cx="16" cy="140" r="6" fill="#fb923c" /><text x="28" y="144" fontSize="9" fill="#94a3b8">Route</text>
                    <text x="8" y="164" fontSize="10" fontWeight="bold" fill="#e2e8f0">Edges</text>
                    <line x1="8" y1="178" x2="26" y2="178" stroke="#fb923c" strokeWidth="1.5" strokeDasharray="5 3" /><text x="32" y="182" fontSize="9" fill="#94a3b8">FileImports</text>
                    <line x1="8" y1="194" x2="26" y2="194" stroke="#f472b6" strokeWidth="1.5" strokeDasharray="2 2" /><text x="32" y="198" fontSize="9" fill="#94a3b8">SymbolCalls</text>
                    <line x1="8" y1="210" x2="26" y2="210" stroke="#34d399" strokeWidth="1.5" /><text x="32" y="214" fontSize="9" fill="#94a3b8">RouteHandled</text>
                    <line x1="8" y1="226" x2="26" y2="226" stroke="#6366f1" strokeWidth="1.5" /><text x="32" y="230" fontSize="9" fill="#94a3b8">RepoCont…</text>
                </g>

                {#* Hint *#}
                <text x="1090" y="694" textAnchor="end" fontSize="8" fill="#475569">scroll = zoom · drag = pan · click node = highlight</text>

            </svg>
        }}
    </div>;
}
