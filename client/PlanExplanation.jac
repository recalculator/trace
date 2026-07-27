import from .types { PlanResult, PlanEvidence, StepResult }

def ev_color(kind: str) -> str {
    if kind == "seed" { return "#C85120"; }
    if kind == "call_edge" { return "#c4b5fd"; }
    if kind == "definition" { return "#7dd3fc"; }
    if kind == "route" { return "#fdba74"; }
    return "#8A9BB8";
}

def ev_label(kind: str) -> str {
    if kind == "seed" { return "origin"; }
    if kind == "call_edge" { return "calls"; }
    if kind == "definition" { return "defined"; }
    if kind == "route" { return "route"; }
    return kind;
}

def status_color(status: str) -> str {
    if status == "ok" { return "#34d399"; }
    if status == "ambiguous" { return "#fbbf24"; }
    if status == "not_found" { return "#f87171"; }
    if status == "clarification_needed" { return "#818cf8"; }
    return "#6B7FA0";
}

def:pub PlanExplanation(result: PlanResult) -> JsxElement {
    all_ev: list[PlanEvidence] = [];
    for sr in result.steps {
        for ev in sr.evidence {
            all_ev = all_ev + [ev];
        }
    }
    shown = all_ev[0:30];
    extra = len(all_ev) - 30;

    return
        <div style={{"fontFamily": "system-ui, sans-serif"}}>
            {#* ── Status / clarification bar ── *#}
            {if result.status == "not_found" or result.status == "rejected" {
                <div style={{
                    "padding": "20px 24px",
                    "borderBottom": "1px solid rgba(255,255,255,0.07)"
                }}>
                    <p style={{
                        "margin": "0", "color": "#f87171",
                        "fontSize": "14px", "lineHeight": "1.6"
                    }}>
                        {result.message if result.message != "" else "Nothing matching that question was found."}
                    </p>
                </div>
            }}

            {if result.status == "clarification_needed" {
                <div style={{
                    "padding": "20px 24px",
                    "borderBottom": "1px solid rgba(255,255,255,0.07)"
                }}>
                    <p style={{
                        "margin": "0 0 6px 0", "color": "#818cf8",
                        "fontSize": "11px", "fontWeight": "700",
                        "letterSpacing": "0.08em", "textTransform": "uppercase"
                    }}>
                        {"Clarification needed"}
                    </p>
                    <p style={{"margin": "0", "color": "#E8EDF7", "fontSize": "14px", "lineHeight": "1.6"}}>
                        {result.clarification_question}
                    </p>
                </div>
            }}

            {if result.explanation != "" {
                <div style={{
                    "padding": "24px",
                    "borderBottom": "1px solid rgba(255,255,255,0.07)"
                }}>
                    <div style={{
                        "display": "flex", "alignItems": "center", "gap": "10px",
                        "marginBottom": "14px"
                    }}>
                        <p style={{
                            "margin": "0",
                            "color": "rgba(107,127,160,0.8)",
                            "fontSize": "9px", "fontWeight": "700",
                            "letterSpacing": "0.12em", "textTransform": "uppercase",
                            "fontFamily": "'JetBrains Mono', ui-monospace, monospace"
                        }}>
                            {"Answer"}
                        </p>
                        {if result.explained_by == "anthropic" or result.planner == "anthropic" {
                            <span style={{
                                "fontSize": "9px", "fontWeight": "700",
                                "letterSpacing": "0.08em", "textTransform": "uppercase",
                                "color": "#C85120",
                                "fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                "background": "rgba(200,81,32,0.12)",
                                "border": "1px solid rgba(200,81,32,0.25)",
                                "borderRadius": "9999px", "padding": "2px 8px"
                            }}>
                                {"Claude"}
                            </span>
                        }}
                    </div>
                    <p style={{
                        "margin": "0", "color": "#E8EDF7",
                        "fontSize": "15px", "lineHeight": "1.75",
                        "fontWeight": "400"
                    }}>
                        {result.explanation}
                    </p>
                    {if result.warnings != [] {
                        <p style={{
                            "margin": "12px 0 0 0", "color": "#fbbf24",
                            "fontSize": "12px", "lineHeight": "1.5",
                            "fontFamily": "'JetBrains Mono', ui-monospace, monospace"
                        }}>
                            {result.warnings[0]}
                        </p>
                    }}
                </div>
            }}

            {if len(shown) > 0 {
                <div style={{"padding": "16px 24px 8px"}}>
                    <p style={{
                        "margin": "0 0 12px 0",
                        "color": "rgba(107,127,160,0.8)",
                        "fontSize": "9px", "fontWeight": "700",
                        "letterSpacing": "0.12em", "textTransform": "uppercase",
                        "fontFamily": "'JetBrains Mono', ui-monospace, monospace"
                    }}>
                        {"Evidence  ·  " + str(len(all_ev)) + " items"}
                    </p>
                    {for (i, ev) in enumerate(shown) {
                        <div
                            key={str(i)}
                            style={{
                                "display": "flex", "gap": "10px",
                                "alignItems": "flex-start",
                                "padding": "8px 0",
                                "borderTop": "1px solid rgba(255,255,255,0.05)"
                            }}
                        >
                            <span style={{
                                "fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                "fontSize": "9px", "fontWeight": "700",
                                "letterSpacing": "0.06em",
                                "color": ev_color(ev.kind),
                                "background": "rgba(0,0,0,0.2)",
                                "border": "1px solid rgba(255,255,255,0.07)",
                                "borderRadius": "4px", "padding": "2px 6px",
                                "flexShrink": "0", "marginTop": "1px",
                                "textTransform": "uppercase"
                            }}>
                                {ev_label(ev.kind)}
                            </span>
                            <div style={{"flex": "1", "minWidth": "0"}}>
                                <div style={{
                                    "display": "flex", "gap": "8px",
                                    "alignItems": "baseline", "flexWrap": "wrap"
                                }}>
                                    <code style={{
                                        "fontSize": "13px",
                                        "color": ev_color(ev.kind),
                                        "fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                        "fontWeight": "600"
                                    }}>
                                        {ev.symbol}
                                    </code>
                                    {if ev.path != "" {
                                        <span style={{
                                            "fontSize": "11px", "color": "rgba(107,127,160,0.65)",
                                            "fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                            "overflow": "hidden", "textOverflow": "ellipsis",
                                            "whiteSpace": "nowrap", "maxWidth": "280px"
                                        }}>
                                            {ev.path + ((":" + str(ev.line)) if ev.line > 0 else "")}
                                        </span>
                                    }}
                                </div>
                                {if ev.detail != "" {
                                    <p style={{
                                        "margin": "3px 0 0 0",
                                        "color": "#8A9BB8", "fontSize": "12px",
                                        "lineHeight": "1.5"
                                    }}>
                                        {ev.detail}
                                    </p>
                                }}
                            </div>
                        </div>
                    }}
                    {if extra > 0 {
                        <p style={{
                            "color": "rgba(107,127,160,0.5)", "fontSize": "11px",
                            "margin": "8px 0 0 0",
                            "fontFamily": "'JetBrains Mono', ui-monospace, monospace"
                        }}>
                            {"+" + str(extra) + " more items not shown"}
                        </p>
                    }}
                </div>
            }}
        </div>;
}
