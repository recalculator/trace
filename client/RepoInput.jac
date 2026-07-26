"""GitHub repository picker.

Deliberately minimal - one field and one button, styled to match the
existing question bar. Redesigning the interface is a separate task.
"""

def:pub RepoInput(current: str, busy: bool, on_analyze: any) -> JsxElement {
    has value: str = "";

    return
        <div style={{"marginBottom": "16px"}}>
            <p
                style={{
                    "color": "#94a3b8",
                    "fontSize": "11px",
                    "fontWeight": "600",
                    "letterSpacing": "0.08em",
                    "margin": "0 0 8px 0",
                    "textTransform": "uppercase",
                    "fontFamily": "system-ui, sans-serif"
                }}
            >
                {"GitHub Repository"}
            </p>
            <div style={{"display": "flex", "gap": "12px", "alignItems": "center"}}>
                <input
                    value={value}
                    disabled={busy}
                    placeholder="https://github.com/pallets/flask"
                    onChange={lambda (e: ChangeEvent) { value = e.target.value; }}
                    onKeyDown={lambda (e: KeyboardEvent) { if e.key == "Enter"
                    and value != ""
                    and not busy {
                        on_analyze(value);
                    }}}
                    style={{
                        "flex": "1",
                        "background": "#0f172a",
                        "border": "1px solid #1e293b",
                        "borderRadius": "8px",
                        "padding": "12px 16px",
                        "color": "#e2e8f0",
                        "fontSize": "14px",
                        "fontFamily": "monospace",
                        "outline": "none"
                    }}
                />
                <button
                    disabled={busy}
                    onClick={lambda { if value != "" and not busy {
                        on_analyze(value);
                    }}}
                    style={{
                        "background": "#334155" if busy else "#6366f1",
                        "border": "none",
                        "borderRadius": "8px",
                        "padding": "12px 22px",
                        "color": "#ffffff",
                        "fontSize": "14px",
                        "fontWeight": "600",
                        "cursor": "default" if busy else "pointer",
                        "fontFamily": "system-ui, sans-serif",
                        "flexShrink": "0"
                    }}
                >
                    {"Analyzing…" if busy else "Analyze"}
                </button>
            </div>
            <p
                style={{
                    "color": "#475569",
                    "fontSize": "12px",
                    "fontFamily": "monospace",
                    "margin": "8px 0 0 0"
                }}
            >
                {"analyzing: " + current}
            </p>
        </div>;
}
