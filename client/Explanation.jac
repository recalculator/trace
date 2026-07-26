def:pub Explanation -> JsxElement {
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
                {"When a POST request arrives at "}
                <code
                    style={{
                        "background": "#0f172a",
                        "color": "#f472b6",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace"
                    }}
                >
                    {"/auth/signup"}
                </code>
                {", it is handled by "}
                <code
                    style={{
                        "background": "#0f172a",
                        "color": "#a78bfa",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace"
                    }}
                >
                    {"signup"}
                </code>
                <span style={{"color": "#64748b", "fontSize": "12px"}}>
                    {" (app/main.py)"}
                </span>
                {". "}
                <code
                    style={{
                        "background": "#0f172a",
                        "color": "#a78bfa",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace"
                    }}
                >
                    {"signup"}
                </code>
                {" first calls "}
                <code
                    style={{
                        "background": "#0f172a",
                        "color": "#a78bfa",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace"
                    }}
                >
                    {"validate_signup_input"}
                </code>
                <span style={{"color": "#64748b", "fontSize": "12px"}}>
                    {" (services/validation.py)"}
                </span>
                {" to enforce field constraints, then delegates user creation to "}
                <code
                    style={{
                        "background": "#0f172a",
                        "color": "#a78bfa",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace"
                    }}
                >
                    {"create_user"}
                </code>
                <span style={{"color": "#64748b", "fontSize": "12px"}}>
                    {" (services/user_service.py)"}
                </span>
                {". "}
                <code
                    style={{
                        "background": "#0f172a",
                        "color": "#a78bfa",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace"
                    }}
                >
                    {"create_user"}
                </code>
                {" hashes credentials via "}
                <code
                    style={{
                        "background": "#0f172a",
                        "color": "#a78bfa",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace"
                    }}
                >
                    {"hash_password"}
                </code>
                {", persists the record through "}
                <code
                    style={{
                        "background": "#0f172a",
                        "color": "#a78bfa",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace"
                    }}
                >
                    {"persist"}
                </code>
                {", and issues a JWT via "}
                <code
                    style={{
                        "background": "#0f172a",
                        "color": "#a78bfa",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace"
                    }}
                >
                    {"generate_token"}
                </code>
                {". A second entry point, "}
                <code
                    style={{
                        "background": "#0f172a",
                        "color": "#34d399",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace"
                    }}
                >
                    {"seed_demo_users"}
                </code>
                <span style={{"color": "#64748b", "fontSize": "12px"}}>
                    {" (admin/seed.py)"}
                </span>
                {", also calls "}
                <code
                    style={{
                        "background": "#0f172a",
                        "color": "#a78bfa",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace"
                    }}
                >
                    {"create_user"}
                </code>
                {" directly — any changes to "}
                <code
                    style={{
                        "background": "#0f172a",
                        "color": "#f59e0b",
                        "padding": "1px 5px",
                        "borderRadius": "3px",
                        "fontSize": "13px",
                        "fontFamily": "monospace"
                    }}
                >
                    {"create_user"}
                </code>
                {" affect both the HTTP signup path and the admin seeding tool."}
            </p>
        </div>;
}
