import from .types { InvestResponse }

def chip_color(kind: str, depth: int) -> str {
    if depth == 0 {
        return "#f59e0b";
    }
    if kind == "class" {
        return "#34d399";
    }
    if kind == "async_function" {
        return "#f472b6";
    }
    if kind == "method" {
        return "#94a3b8";
    }
    return "#a78bfa";
}

def:pub Explanation(result: InvestResponse) -> JsxElement {
    shown = result.evidence[0:25];
    extra = len(result.evidence) - 25;

    return
        <div
            style={{
                "background": "#1e293b",
                "borderRadius": "8px",
                "padding": "20px 24px",
                "marginTop": "24px",
                "border": "1px solid #334155"
            }}
        >
            <p
                style={{
                    "color": "#94a3b8",
                    "fontSize": "11px",
                    "fontWeight": "600",
                    "letterSpacing": "0.08em",
                    "margin": "0 0 12px 0",
                    "textTransform": "uppercase",
                    "fontFamily": "system-ui, sans-serif"
                }}
            >
                {"Answer"}
            </p>
            <p
                style={{
                    "color": "#e2e8f0",
                    "fontSize": "14px",
                    "lineHeight": "1.7",
                    "margin": "0",
                    "fontFamily": "system-ui, sans-serif"
                }}
            >
                {if result.direction == "forward" {
                    <span>{"Tracing forward from "}</span>
                }}
                {if result.direction == "reverse" {
                    <span>{"Tracing backward from "}</span>
                }}
                <code
                    style={{
                        "background": "#0f172a",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace",
                        "color": "#f59e0b"
                    }}
                >
                    {result.seed_name}
                </code>
                <span style={{"color": "#64748b", "fontSize": "12px"}}>
                    {" (" + result.seed_path + ")"}
                </span>
                {if result.direction == "forward" {
                    <span>
                        {", Trace followed SymbolCallsSymbol edges and reached "}
                    </span>
                }}
                {if result.direction == "reverse" {
                    <span>{", Trace found "}</span>
                }}
                <code
                    style={{
                        "background": "#0f172a",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace",
                        "color": "#a78bfa"
                    }}
                >
                    {str(result.node_count - 1)}
                </code>
                {if result.direction == "forward" {
                    <span>{" downstream symbols across "}</span>
                }}
                {if result.direction == "reverse" {
                    <span>{" symbols that would be affected, across "}</span>
                }}
                <code
                    style={{
                        "background": "#0f172a",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace",
                        "color": "#a78bfa"
                    }}
                >
                    {str(result.depth_reached)}
                </code>
                {if result.direction == "forward" {
                    <span>{" call levels."}</span>
                }}
                {if result.direction == "reverse" {
                    <span>{" caller levels."}</span>
                }}
            </p>
            {for (i, ev) in enumerate(shown) {
                <div
                    key={str(i)}
                    style={{
                        "display": "flex",
                        "gap": "8px",
                        "alignItems": "baseline",
                        "padding": "5px 0",
                        "borderTop": "1px solid #334155"
                    }}
                >
                    <code
                        style={{
                            "background": "#0f172a",
                            "padding": "1px 5px",
                            "borderRadius": "3px",
                            "fontSize": "13px",
                            "fontFamily": "monospace",
                            "color": chip_color(ev.node_kind, ev.depth)
                        }}
                    >
                        {ev.node_path + ":" + str(ev.node_line)}
                    </code>
                    <span
                        style={{
                            "color": "#94a3b8",
                            "fontSize": "13px",
                            "fontFamily": "system-ui, sans-serif"
                        }}
                    >
                        {ev.explanation}
                    </span>
                </div>
            }}
            {if len(result.evidence) > 25 {
                <p style={{"color": "#64748b", "fontSize": "12px"}}>
                    {"+" + str(extra) + " more steps not shown"}
                </p>
            }}
            {if result.ambiguous {
                <p
                    style={{
                        "color": "#64748b",
                        "fontSize": "12px",
                        "margin": "8px 0 0 0"
                    }}
                >
                    {"Ambiguous name — also matches: "}
                    {for (i, c) in enumerate(result.candidates) {
                        <code
                            key={str(i)}
                            style={{
                                "background": "#0f172a",
                                "padding": "1px 5px",
                                "borderRadius": "3px",
                                "fontSize": "13px",
                                "fontFamily": "monospace",
                                "color": "#a78bfa"
                            }}
                        >
                            {c}
                        </code>
                    }}
                </p>
            }}
            {if result.depth_capped {
                <p
                    style={{
                        "color": "#64748b",
                        "fontSize": "12px",
                        "margin": "8px 0 0 0"
                    }}
                >
                    {"Depth capped at " + str(result.max_depth) + "."}
                </p>
            }}
            {if result.budget_exhausted {
                <p
                    style={{
                        "color": "#64748b",
                        "fontSize": "12px",
                        "margin": "8px 0 0 0"
                    }}
                >
                    {"Node budget exhausted; the trace is partial."}
                </p>
            }}
            {if result.duplicates_skipped > 0 {
                <p
                    style={{
                        "color": "#64748b",
                        "fontSize": "12px",
                        "margin": "8px 0 0 0"
                    }}
                >
                    {str(result.duplicates_skipped) + " already-visited symbols skipped (cycles)."}
                </p>
            }}
        </div>;
}
