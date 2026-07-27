import from .types { RepoGraph, GraphNode, GraphEdge }

# ---------------------------------------------------------------------------
# Visual helper functions — all pure, no assignments in JSX slot bodies
# ---------------------------------------------------------------------------

def node_grad(node_type: str, kind: str) -> str {
    if node_type == "Repository" { return "gn-repo"; }
    if node_type == "File" { return "gn-file"; }
    if node_type == "Route" { return "gn-route"; }
    if kind == "class" { return "gn-class"; }
    if kind == "async_function" { return "gn-async"; }
    if kind == "function" { return "gn-fn"; }
    return "gn-method";
}

def node_r(node_type: str) -> int {
    if node_type == "Repository" { return 24; }
    if node_type == "File" { return 16; }
    if node_type == "Route" { return 13; }
    return 9;
}

def node_op(
    selected_id: str, highlighted_ids: list[str], ext_node_ids: list[str], node_id: str
) -> str {
    if len(highlighted_ids) == 0 and len(ext_node_ids) == 0 { return "1"; }
    if node_id == selected_id { return "1"; }
    if node_id in ext_node_ids { return "1"; }
    if node_id in highlighted_ids { return "0.85"; }
    return "0.05";
}

def node_stroke_c(
    selected_id: str, highlighted_ids: list[str], ext_node_ids: list[str], node_id: str
) -> str {
    if node_id == selected_id { return "rgba(255,255,255,0.9)"; }
    if node_id in ext_node_ids { return "#C85120"; }
    if node_id in highlighted_ids { return "rgba(255,255,255,0.35)"; }
    return "rgba(255,255,255,0.1)";
}

def node_stroke_w(
    selected_id: str, highlighted_ids: list[str], ext_node_ids: list[str], node_id: str
) -> str {
    if node_id == selected_id { return "2.5"; }
    if node_id in ext_node_ids { return "2"; }
    if node_id in highlighted_ids { return "1.5"; }
    return "0.6";
}

def glow_opacity(
    selected_id: str, ext_node_ids: list[str], node_id: str
) -> str {
    if node_id == selected_id { return "1"; }
    if node_id in ext_node_ids { return "1"; }
    return "0";
}

def glow_fill(selected_id: str, node_id: str) -> str {
    if node_id == selected_id { return "rgba(255,255,255,0.15)"; }
    return "rgba(200,81,32,0.2)";
}

def highlight_opacity(
    selected_id: str, highlighted_ids: list[str], ext_node_ids: list[str], node_id: str
) -> str {
    op = node_op(selected_id, highlighted_ids, ext_node_ids, node_id);
    if op == "0.05" { return "0"; }
    return "0.42";
}

def edge_stroke(edge_type: str) -> str {
    if edge_type == "RepositoryContainsFile" { return "#818cf8"; }
    if edge_type == "FileContainsSymbol" { return "#7dd3fc"; }
    if edge_type == "FileImportsFile" { return "#fdba74"; }
    if edge_type == "SymbolCallsSymbol" { return "#c4b5fd"; }
    if edge_type == "RouteHandledBySymbol" { return "#6ee7b7"; }
    if edge_type == "RepositoryContainsRoute" { return "#fbbf24"; }
    return "#64748b";
}

def active_edge_stroke(ext_edge_ids: list[str], edge_id: str, edge_type: str) -> str {
    if edge_id in ext_edge_ids { return "#C85120"; }
    return edge_stroke(edge_type);
}

def edge_dash(edge_type: str) -> str {
    if edge_type == "FileImportsFile" { return "6 3"; }
    if edge_type == "SymbolCallsSymbol" { return "2 3"; }
    return "";
}

def active_edge_dash(ext_edge_ids: list[str], edge_id: str, edge_type: str) -> str {
    if edge_id in ext_edge_ids { return ""; }
    return edge_dash(edge_type);
}

def edge_width(ext_edge_ids: list[str], edge_id: str) -> str {
    if edge_id in ext_edge_ids { return "2.5"; }
    return "1.2";
}

def edge_marker(edge_type: str) -> str {
    if edge_type == "RepositoryContainsFile" { return "arr0"; }
    if edge_type == "FileContainsSymbol" { return "arr1"; }
    if edge_type == "FileImportsFile" { return "arr2"; }
    if edge_type == "SymbolCallsSymbol" { return "arr3"; }
    if edge_type == "RouteHandledBySymbol" { return "arr4"; }
    return "arr5";
}

def active_marker(ext_edge_ids: list[str], edge_id: str, edge_type: str) -> str {
    if edge_id in ext_edge_ids { return "url(#arr-trace)"; }
    return "url(#" + edge_marker(edge_type) + ")";
}

def edge_op(
    selected_id: str, highlighted_ids: list[str],
    ext_edge_ids: list[str], edge_id: str, src: str, tgt: str
) -> str {
    if len(highlighted_ids) == 0 and len(ext_edge_ids) == 0 { return "0.3"; }
    if edge_id in ext_edge_ids { return "0.92"; }
    if src == selected_id or tgt == selected_id { return "0.78"; }
    if src in highlighted_ids or tgt in highlighted_ids { return "0.5"; }
    return "0.04";
}

def short_label(name: str) -> str {
    if len(name) > 15 { return name[0:14] + "…"; }
    return name;
}

def label_opacity(
    node_type: str, selected_id: str, highlighted_ids: list[str],
    ext_node_ids: list[str], node_id: str
) -> str {
    if node_type != "Symbol" {
        return node_op(selected_id, highlighted_ids, ext_node_ids, node_id);
    }
    # Symbols: hidden by default — only appear when relevant
    if node_id == selected_id { return "1"; }
    if node_id in ext_node_ids { return "1"; }
    if node_id in highlighted_ids { return "0.75"; }
    return "0";
}

def label_font_size(node_type: str) -> str {
    if node_type == "Repository" { return "11"; }
    if node_type == "File" { return "10"; }
    if node_type == "Route" { return "10"; }
    return "8";
}

def label_fill(
    node_type: str, ext_node_ids: list[str], selected_id: str, node_id: str
) -> str {
    if node_id == selected_id { return "#F5F7FA"; }
    if node_id in ext_node_ids { return "#C85120"; }
    if node_type == "Repository" { return "#C8D0E0"; }
    if node_type == "File" { return "#A8B4C8"; }
    if node_type == "Route" { return "#A8C8B4"; }
    return "#8A9BB8";
}

def edge_path(x1: float, y1: float, x2: float, y2: float) -> str {
    mx: float = (x1 + x2) / 2.0;
    my: float = (y1 + y2) / 2.0;
    dx: float = x2 - x1;
    dy: float = y2 - y1;
    cx: float = mx - dy * 0.1;
    cy: float = my + dx * 0.1;
    return "M" + str(x1) + " " + str(y1) + " Q" + str(cx) + " " + str(cy) + " " + str(x2) + " " + str(y2);
}

def tooltip_subtext(node_type: str, kind: str) -> str {
    if kind != "" { return node_type + "  ·  " + kind; }
    return node_type;
}

# ---------------------------------------------------------------------------
# GraphViz component
# ---------------------------------------------------------------------------

def:pub GraphViz(
    graph: RepoGraph, ext_node_ids: list[str], ext_edge_ids: list[str]
) -> JsxElement {
    has pos_x: dict = {},
        pos_y: dict = {},
        pan_x: float = 0.0,
        pan_y: float = 0.0,
        zoom: float = 0.85,
        selected_id: str = "",
        highlighted_ids: list[str] = [],
        hovered_id: str = "",
        hover_mx: float = 0.0,
        hover_my: float = 0.0,
        canvas_w: float = 1200.0,
        simulated: bool = False;

    has dragging: Ref[bool] = Ref(False),
        drag_sx: Ref[float] = Ref(0.0),
        drag_sy: Ref[float] = Ref(0.0),
        pan_sx: Ref[float] = Ref(0.0),
        pan_sy: Ref[float] = Ref(0.0);

    can with entry { layout_graph(); }
    async def layout_graph -> None;

    def on_wheel(e: Event) {
        delta = e.deltaY as float;  # jac:ignore[E1030]
        nz = zoom - delta * 0.001;
        if nz < 0.15 { nz = 0.15; }
        if nz > 5.0 { nz = 5.0; }
        zoom = nz;
    }

    def zoom_in -> None {
        nz = zoom + 0.15;
        if nz > 5.0 { nz = 5.0; }
        zoom = nz;
    }

    def zoom_out -> None {
        nz = zoom - 0.15;
        if nz < 0.15 { nz = 0.15; }
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
        hover_mx = e.clientX as float;
        hover_my = e.clientY as float;
        if dragging.current {
            pan_x = (pan_sx.current as float) + (
                (e.clientX as float) - (drag_sx.current as float)
            );
            pan_y = (pan_sy.current as float) + (
                (e.clientY as float) - (drag_sy.current as float)
            );
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
            if edge.source == node_id { nbrs = nbrs + [edge.target]; }
            if edge.target == node_id { nbrs = nbrs + [edge.source]; }
        }
        highlighted_ids = nbrs;
    }

    hovered_node: GraphNode | None = None;
    for nd in graph.nodes {
        if nd.id == hovered_id { hovered_node = nd; }
    }
    hn_name: str = "";
    hn_sub: str = "";
    if hovered_node is not None {
        hn_name = (hovered_node as GraphNode).name;
        hn_sub = tooltip_subtext(
            (hovered_node as GraphNode).node_type,
            (hovered_node as GraphNode).kind
        );
    }

    xform = "translate(" + str(pan_x) + " " + str(pan_y) + ") scale(" + str(zoom) + ")";

    return
        <div
            style={{
                "position": "relative",
                "width": "100%",
                "height": "720px",
                "background": "rgba(9,12,19,0.65)",
                "backdropFilter": "blur(24px) saturate(140%)",
                "WebkitBackdropFilter": "blur(24px) saturate(140%)",
                "borderRadius": "16px",
                "overflow": "hidden"
            }}
        >
            {if not simulated {
                <div
                    style={{
                        "position": "absolute", "inset": "0",
                        "display": "flex", "alignItems": "center",
                        "justifyContent": "center", "flexDirection": "column", "gap": "14px"
                    }}
                >
                    <div style={{
                        "width": "20px", "height": "20px",
                        "border": "2px solid rgba(200,81,32,0.2)",
                        "borderTopColor": "#C85120",
                        "borderRadius": "50%",
                        "animation": "spin 0.8s linear infinite"
                    }}/>
                    <span style={{
                        "color": "#6B7FA0", "fontSize": "12px",
                        "fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                        "letterSpacing": "0.06em"
                    }}>
                        {"Computing layout…"}
                    </span>
                </div>
            }}

            {if simulated {
                <svg
                    width="100%"
                    height="720"
                    viewBox={"0 0 " + str(canvas_w) + " 720"}
                    onWheel={on_wheel}
                    onMouseDown={on_mouse_down}
                    onMouseMove={on_mouse_move}
                    onMouseUp={on_mouse_up}
                    onMouseLeave={on_mouse_up}
                    style={{"display": "block", "cursor": "grab", "userSelect": "none"}}
                >
                    <defs>
                        {#* Glass-sphere radial gradients — light from top-left *#}
                        <radialGradient id="gn-repo" cx="35%" cy="30%" r="65%">
                            <stop offset="0%" stopColor="#a5b4fc"/>
                            <stop offset="100%" stopColor="#3730a3"/>
                        </radialGradient>
                        <radialGradient id="gn-file" cx="35%" cy="30%" r="65%">
                            <stop offset="0%" stopColor="#bae6fd"/>
                            <stop offset="100%" stopColor="#0c4a6e"/>
                        </radialGradient>
                        <radialGradient id="gn-route" cx="35%" cy="30%" r="65%">
                            <stop offset="0%" stopColor="#fed7aa"/>
                            <stop offset="100%" stopColor="#9a3412"/>
                        </radialGradient>
                        <radialGradient id="gn-fn" cx="35%" cy="30%" r="65%">
                            <stop offset="0%" stopColor="#ddd6fe"/>
                            <stop offset="100%" stopColor="#4c1d95"/>
                        </radialGradient>
                        <radialGradient id="gn-class" cx="35%" cy="30%" r="65%">
                            <stop offset="0%" stopColor="#a7f3d0"/>
                            <stop offset="100%" stopColor="#064e3b"/>
                        </radialGradient>
                        <radialGradient id="gn-async" cx="35%" cy="30%" r="65%">
                            <stop offset="0%" stopColor="#fbcfe8"/>
                            <stop offset="100%" stopColor="#831843"/>
                        </radialGradient>
                        <radialGradient id="gn-method" cx="35%" cy="30%" r="65%">
                            <stop offset="0%" stopColor="#e2e8f0"/>
                            <stop offset="100%" stopColor="#1e293b"/>
                        </radialGradient>

                        {#* Slim arrowhead markers *#}
                        <marker id="arr0" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
                            <polygon points="0 0,6 2.5,0 5" fill="#818cf8" fillOpacity="0.85"/>
                        </marker>
                        <marker id="arr1" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
                            <polygon points="0 0,6 2.5,0 5" fill="#7dd3fc" fillOpacity="0.85"/>
                        </marker>
                        <marker id="arr2" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
                            <polygon points="0 0,6 2.5,0 5" fill="#fdba74" fillOpacity="0.85"/>
                        </marker>
                        <marker id="arr3" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
                            <polygon points="0 0,6 2.5,0 5" fill="#c4b5fd" fillOpacity="0.85"/>
                        </marker>
                        <marker id="arr4" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
                            <polygon points="0 0,6 2.5,0 5" fill="#6ee7b7" fillOpacity="0.85"/>
                        </marker>
                        <marker id="arr5" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
                            <polygon points="0 0,6 2.5,0 5" fill="#fbbf24" fillOpacity="0.85"/>
                        </marker>
                        <marker id="arr-trace" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
                            <polygon points="0 0,6 2.5,0 5" fill="#C85120"/>
                        </marker>
                    </defs>

                    <g transform={xform}>

                        {#* ── 1. Curved edges ── *#}
                        {for edge in graph.edges {
                            <path
                                key={edge.id}
                                d={edge_path(
                                    pos_x[edge.source] as float,
                                    pos_y[edge.source] as float,
                                    pos_x[edge.target] as float,
                                    pos_y[edge.target] as float
                                )}
                                stroke={active_edge_stroke(ext_edge_ids, edge.id, edge.edge_type)}
                                strokeWidth={edge_width(ext_edge_ids, edge.id)}
                                strokeDasharray={active_edge_dash(ext_edge_ids, edge.id, edge.edge_type)}
                                fill="none"
                                markerEnd={active_marker(ext_edge_ids, edge.id, edge.edge_type)}
                                opacity={edge_op(
                                    selected_id, highlighted_ids, ext_edge_ids,
                                    edge.id, edge.source, edge.target
                                )}
                            />
                        }}

                        {#* ── 2. Glow rings (always present; opacity = 0 when idle) ── *#}
                        {for nd in graph.nodes {
                            <circle
                                key={nd.id + "-gw"}
                                cx={pos_x[nd.id] as float}
                                cy={pos_y[nd.id] as float}
                                r={(node_r(nd.node_type) as float) + 8.0}
                                fill={glow_fill(selected_id, nd.id)}
                                stroke="none"
                                opacity={glow_opacity(selected_id, ext_node_ids, nd.id)}
                            />
                        }}

                        {#* ── 3. Node circles ── *#}
                        {for nd in graph.nodes {
                            <circle
                                key={nd.id}
                                cx={pos_x[nd.id] as float}
                                cy={pos_y[nd.id] as float}
                                r={node_r(nd.node_type)}
                                fill={"url(#" + node_grad(nd.node_type, nd.kind) + ")"}
                                stroke={node_stroke_c(selected_id, highlighted_ids, ext_node_ids, nd.id)}
                                strokeWidth={node_stroke_w(selected_id, highlighted_ids, ext_node_ids, nd.id)}
                                opacity={node_op(selected_id, highlighted_ids, ext_node_ids, nd.id)}
                                style={{"cursor": "pointer"}}
                                onClick={lambda (e: MouseEvent) { on_node_click(nd.id); }}
                                onMouseEnter={lambda (e: MouseEvent) { hovered_id = nd.id; }}
                                onMouseLeave={lambda (e: MouseEvent) { hovered_id = ""; }}
                            />
                        }}

                        {#* ── 4. Glass highlight dot (light reflection — always present) ── *#}
                        {for nd in graph.nodes {
                            <circle
                                key={nd.id + "-hl"}
                                cx={(pos_x[nd.id] as float) - (node_r(nd.node_type) as float) * 0.28}
                                cy={(pos_y[nd.id] as float) - (node_r(nd.node_type) as float) * 0.28}
                                r={(node_r(nd.node_type) as float) * 0.3}
                                fill="white"
                                opacity={highlight_opacity(selected_id, highlighted_ids, ext_node_ids, nd.id)}
                                style={{"pointerEvents": "none"}}
                            />
                        }}

                        {#* ── 5. Labels ── *#}
                        {for nd in graph.nodes {
                            <text
                                key={nd.id + "-t"}
                                x={pos_x[nd.id] as float}
                                y={(pos_y[nd.id] as float) + (node_r(nd.node_type) as float) + 13.0}
                                textAnchor="middle"
                                fontSize={label_font_size(nd.node_type)}
                                fill={label_fill(nd.node_type, ext_node_ids, selected_id, nd.id)}
                                opacity={label_opacity(nd.node_type, selected_id, highlighted_ids, ext_node_ids, nd.id)}
                                style={{"pointerEvents": "none", "userSelect": "none",
                                        "fontFamily": "system-ui, sans-serif", "fontWeight": "500",
                                        "letterSpacing": "0.01em"}}
                            >
                                {short_label(nd.name)}
                            </text>
                        }}
                    </g>

                    {#* ── Glass legend (fixed, not panned) ── *#}
                    <g transform="translate(16,16)">
                        <rect x="0" y="0" width="158" height="206" rx="10"
                            fill="rgba(9,12,19,0.8)"
                            stroke="rgba(255,255,255,0.09)" strokeWidth="1"/>
                        <text x="12" y="22" fontSize="9" fontWeight="700"
                            fill="rgba(107,127,160,0.8)"
                            style={{"letterSpacing": "0.1em", "fontFamily": "system-ui, sans-serif",
                                    "textTransform": "uppercase"}}>
                            {"NODES"}
                        </text>
                        <circle cx="20" cy="38" r="5" fill="url(#gn-repo)"/>
                        <circle cx="29.4" cy="31.4" r="1.5" fill="white" fillOpacity="0.5"/>
                        <text x="32" y="42" fontSize="9" fill="#8A9BB8" fontFamily="system-ui, sans-serif">{"Repository"}</text>
                        <circle cx="20" cy="56" r="5" fill="url(#gn-file)"/>
                        <circle cx="29.4" cy="49.4" r="1.5" fill="white" fillOpacity="0.5"/>
                        <text x="32" y="60" fontSize="9" fill="#8A9BB8" fontFamily="system-ui, sans-serif">{"File"}</text>
                        <circle cx="20" cy="74" r="5" fill="url(#gn-fn)"/>
                        <circle cx="29.4" cy="67.4" r="1.5" fill="white" fillOpacity="0.5"/>
                        <text x="32" y="78" fontSize="9" fill="#8A9BB8" fontFamily="system-ui, sans-serif">{"Function"}</text>
                        <circle cx="20" cy="92" r="5" fill="url(#gn-class)"/>
                        <circle cx="29.4" cy="85.4" r="1.5" fill="white" fillOpacity="0.5"/>
                        <text x="32" y="96" fontSize="9" fill="#8A9BB8" fontFamily="system-ui, sans-serif">{"Class"}</text>
                        <circle cx="20" cy="110" r="5" fill="url(#gn-async)"/>
                        <circle cx="29.4" cy="103.4" r="1.5" fill="white" fillOpacity="0.5"/>
                        <text x="32" y="114" fontSize="9" fill="#8A9BB8" fontFamily="system-ui, sans-serif">{"Async fn"}</text>
                        <circle cx="20" cy="128" r="5" fill="url(#gn-method)"/>
                        <circle cx="29.4" cy="121.4" r="1.5" fill="white" fillOpacity="0.5"/>
                        <text x="32" y="132" fontSize="9" fill="#8A9BB8" fontFamily="system-ui, sans-serif">{"Method"}</text>
                        <circle cx="20" cy="146" r="5" fill="url(#gn-route)"/>
                        <circle cx="29.4" cy="139.4" r="1.5" fill="white" fillOpacity="0.5"/>
                        <text x="32" y="150" fontSize="9" fill="#8A9BB8" fontFamily="system-ui, sans-serif">{"Route"}</text>
                        <text x="12" y="170" fontSize="9" fontWeight="700"
                            fill="rgba(107,127,160,0.8)"
                            style={{"letterSpacing": "0.1em", "fontFamily": "system-ui, sans-serif",
                                    "textTransform": "uppercase"}}>
                            {"EDGES"}
                        </text>
                        <path d="M10 182 Q18 176 26 182" stroke="#fdba74" strokeWidth="1.4" fill="none" strokeDasharray="5 3"/>
                        <text x="32" y="186" fontSize="9" fill="#8A9BB8" fontFamily="system-ui, sans-serif">{"Imports"}</text>
                        <path d="M10 198 Q18 192 26 198" stroke="#c4b5fd" strokeWidth="1.4" fill="none" strokeDasharray="2 3"/>
                        <text x="32" y="202" fontSize="9" fill="#8A9BB8" fontFamily="system-ui, sans-serif">{"Calls"}</text>
                        <path d="M10 214 Q18 208 26 214" stroke="#C85120" strokeWidth="2" fill="none"/>
                        <text x="32" y="218" fontSize="9" fill="#C85120" fontFamily="system-ui, sans-serif">{"Trace"}</text>
                    </g>

                    {#* Controls hint — bottom right *#}
                    <text x={str(canvas_w - 14.0)} y="714" textAnchor="end" fontSize="8"
                        fill="rgba(107,127,160,0.45)"
                        fontFamily="system-ui, sans-serif">
                        {"scroll · zoom   drag · pan   click · focus"}
                    </text>
                </svg>
            }}

            {#* Zoom buttons — top right *#}
            {if simulated {
                <div style={{
                    "position": "absolute",
                    "top": "12px",
                    "right": "12px",
                    "display": "flex",
                    "flexDirection": "column",
                    "gap": "4px",
                    "zIndex": "10"
                }}>
                    <button
                        onClick={lambda (e: MouseEvent) { zoom_in(); }}
                        style={{
                            "width": "32px",
                            "height": "32px",
                            "background": "rgba(9,12,19,0.82)",
                            "backdropFilter": "blur(16px)",
                            "WebkitBackdropFilter": "blur(16px)",
                            "border": "1px solid rgba(255,255,255,0.12)",
                            "borderRadius": "8px",
                            "color": "#C8D0E0",
                            "fontSize": "18px",
                            "lineHeight": "1",
                            "cursor": "pointer",
                            "display": "flex",
                            "alignItems": "center",
                            "justifyContent": "center",
                            "fontFamily": "system-ui, sans-serif",
                            "userSelect": "none"
                        }}
                    >
                        {"+"}
                    </button>
                    <button
                        onClick={lambda (e: MouseEvent) { zoom_out(); }}
                        style={{
                            "width": "32px",
                            "height": "32px",
                            "background": "rgba(9,12,19,0.82)",
                            "backdropFilter": "blur(16px)",
                            "WebkitBackdropFilter": "blur(16px)",
                            "border": "1px solid rgba(255,255,255,0.12)",
                            "borderRadius": "8px",
                            "color": "#C8D0E0",
                            "fontSize": "18px",
                            "lineHeight": "1",
                            "cursor": "pointer",
                            "display": "flex",
                            "alignItems": "center",
                            "justifyContent": "center",
                            "fontFamily": "system-ui, sans-serif",
                            "userSelect": "none"
                        }}
                    >
                        {"−"}
                    </button>
                </div>
            }}

            {#* Hover tooltip *#}
            {if hovered_node is not None {
                <div
                    style={{
                        "position": "fixed",
                        "left": str(hover_mx + 16.0) + "px",
                        "top": str(hover_my + 16.0) + "px",
                        "background": "rgba(9,12,19,0.92)",
                        "backdropFilter": "blur(24px) saturate(160%)",
                        "WebkitBackdropFilter": "blur(24px) saturate(160%)",
                        "border": "1px solid rgba(255,255,255,0.1)",
                        "borderRadius": "10px",
                        "padding": "10px 14px",
                        "pointerEvents": "none",
                        "zIndex": "200",
                        "minWidth": "140px",
                        "maxWidth": "240px",
                        "boxShadow": "0 8px 24px rgba(0,0,0,0.5)"
                    }}
                >
                    <p
                        style={{
                            "margin": "0 0 3px 0", "color": "#F5F7FA",
                            "fontSize": "13px", "fontWeight": "600",
                            "fontFamily": "system-ui, sans-serif",
                            "overflow": "hidden", "textOverflow": "ellipsis",
                            "whiteSpace": "nowrap"
                        }}
                    >
                        {hn_name}
                    </p>
                    <p
                        style={{
                            "margin": "0", "color": "#6B7FA0",
                            "fontSize": "11px",
                            "fontFamily": "'JetBrains Mono', ui-monospace, monospace"
                        }}
                    >
                        {hn_sub}
                    </p>
                </div>
            }}
        </div>;
}
