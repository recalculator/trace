import from .InvestTypes { InvestStep }

def step_icon(status: str) -> str {
    if status == "done" {
        return "✓";
    }
    if status == "running" {
        return "◌";
    }
    return "○";
}

def step_icon_color(status: str) -> str {
    if status == "done" {
        return "#34d399";
    }
    if status == "running" {
        return "#f59e0b";
    }
    return "#475569";
}

def step_row_opacity(status: str) -> str {
    if status == "pending" {
        return "0.4";
    }
    return "1";
}

def:pub Timeline(steps: list[InvestStep]) -> JsxElement {
    return
        <div
            style={{
                "background": "#0f172a",
                "borderRadius": "8px",
                "padding": "16px",
                "border": "1px solid #1e293b"
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
                {"Investigation"}
            </p>
            {for (i, s) in enumerate(steps) {
                <div
                    key={str(i)}
                    style={{
                        "display": "flex",
                        "alignItems": "center",
                        "gap": "10px",
                        "padding": "8px 0",
                        "opacity": step_row_opacity(s.status),
                        "borderBottom": "1px solid #1e293b"
                    }}
                >
                    <span
                        style={{
                            "color": step_icon_color(s.status),
                            "fontSize": "14px",
                            "width": "16px",
                            "textAlign": "center",
                            "flexShrink": "0",
                            "fontFamily": "monospace"
                        }}
                    >
                        {step_icon(s.status)}
                    </span>
                    <span
                        style={{
                            "color": "#e2e8f0",
                            "fontSize": "13px",
                            "flex": "1",
                            "fontFamily": "system-ui, sans-serif"
                        }}
                    >
                        {s.step_name}
                    </span>
                    {if s.status == "done" {
                        <span
                            style={{
                                "color": "#475569",
                                "fontSize": "11px",
                                "fontFamily": "monospace",
                                "flexShrink": "0"
                            }}
                        >
                            {s.timestamp}
                        </span>
                    }}
                </div>
            }}
        </div>;
}
