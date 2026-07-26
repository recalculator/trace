def get_placeholder(idx: int) -> str {
    placeholders: list[str] = [
        "What happens when a user signs up?",
        "What breaks if I modify create_user?"
    ];
    return placeholders[idx % len(placeholders)];
}

def:pub QuestionInput(on_submit: Callable[[str], None]) -> JsxElement {
    has value: str = "",
        placeholder_idx: int = 0;

    has interval_ref: Ref[any] = Ref(None);

    can with entry {
        interval_ref.current = setInterval(lambda {
            placeholder_idx = placeholder_idx + 1;
        }, 3000);
    }

    def on_key_down(e: KeyboardEvent) {
        if e.key == "Enter" and value != "" {
            on_submit(value);
            value = "";
        }
    }

    return <div style={{"marginBottom": "0px"}}>
        <div style={{"display": "flex", "gap": "8px", "alignItems": "stretch"}}>
            <input
                type="text"
                value={value}
                placeholder={get_placeholder(placeholder_idx)}
                onKeyDown={on_key_down}
                onChange={lambda (e: ChangeEvent) { value = e.target.value as str; }}
                style={{
                    "flex": "1",
                    "background": "#0f172a",
                    "border": "1px solid #334155",
                    "borderRadius": "6px",
                    "color": "#f1f5f9",
                    "fontSize": "14px",
                    "padding": "10px 14px",
                    "outline": "none",
                    "fontFamily": "system-ui, sans-serif"
                }}
            />
            <button
                onClick={lambda (e: MouseEvent) { if value != "" { on_submit(value); value = ""; } }}
                style={{
                    "background": "#6366f1",
                    "color": "#ffffff",
                    "border": "none",
                    "borderRadius": "6px",
                    "padding": "10px 18px",
                    "fontSize": "14px",
                    "cursor": "pointer",
                    "fontWeight": "600",
                    "fontFamily": "system-ui, sans-serif",
                    "whiteSpace": "nowrap"
                }}
            >{"Investigate →"}</button>
        </div>
        <p style={{"color": "#475569", "fontSize": "12px", "marginTop": "6px", "fontFamily": "monospace"}}>
            {"e.g. " + get_placeholder(placeholder_idx)}
        </p>
    </div>;
}
