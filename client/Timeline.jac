import from .InvestTypes { InvestStep }

def step_color(status: str) -> str {
    if status == "done" { return "#34d399"; }
    if status == "running" { return "#C85120"; }
    return "rgba(107,127,160,0.4)";
}

def step_bg(status: str) -> str {
    if status == "done" { return "rgba(52,211,153,0.1)"; }
    if status == "running" { return "rgba(200,81,32,0.12)"; }
    return "transparent";
}

def row_opacity(status: str) -> str {
    if status == "pending" { return "0.38"; }
    return "1";
}

def:pub Timeline(steps: list[InvestStep]) -> JsxElement {
    return
        <div style={{"fontFamily": "system-ui, sans-serif", "padding": "4px 0"}}>
            <p style={{
                "margin": "0 0 14px 0",
                "color": "rgba(107,127,160,0.8)",
                "fontSize": "9px", "fontWeight": "700",
                "letterSpacing": "0.12em", "textTransform": "uppercase",
                "fontFamily": "'JetBrains Mono', ui-monospace, monospace"
            }}>
                {"Investigation"}
            </p>
            {for (i, s) in enumerate(steps) {
                <div
                    key={str(i)}
                    style={{
                        "display": "flex",
                        "alignItems": "flex-start",
                        "gap": "10px",
                        "padding": "10px 12px",
                        "borderRadius": "10px",
                        "background": step_bg(s.status),
                        "marginBottom": "4px",
                        "opacity": row_opacity(s.status),
                        "transition": "opacity 0.2s"
                    }}
                >
                    {#* Status dot *#}
                    <div style={{
                        "width": "7px", "height": "7px",
                        "borderRadius": "50%",
                        "background": step_color(s.status),
                        "flexShrink": "0",
                        "marginTop": "4px",
                        "boxShadow": "0 0 6px " + step_color(s.status)
                    }}/>
                    {#* Step name + count *#}
                    <div style={{"flex": "1", "minWidth": "0"}}>
                        <p style={{
                            "margin": "0",
                            "color": "#E8EDF7",
                            "fontSize": "13px",
                            "lineHeight": "1.4",
                            "overflow": "hidden",
                            "textOverflow": "ellipsis",
                            "whiteSpace": "nowrap"
                        }}>
                            {s.step_name}
                        </p>
                        {if s.status == "done" and s.timestamp != "" {
                            <p style={{
                                "margin": "2px 0 0 0",
                                "color": "rgba(107,127,160,0.65)",
                                "fontSize": "10px",
                                "fontFamily": "'JetBrains Mono', ui-monospace, monospace"
                            }}>
                                {s.timestamp}
                            </p>
                        }}
                    </div>
                </div>
            }}
        </div>;
}
