import from "@jac/runtime" { Link }

glob LANDING_CSS: str = (
    "@import url('https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400;0,500;1,400&display=swap'); "
    "@keyframes heroFade { to { opacity: 1; transform: translateY(0); } } "
    ".hero-in { opacity: 0; transform: translateY(16px); "
    "  animation: heroFade 1s ease 0.1s forwards; } "
    ".hero-tag { display: inline-flex; align-items: center; gap: 8px; "
    "  background: rgba(255,255,255,0.1); backdrop-filter: blur(12px); "
    "  -webkit-backdrop-filter: blur(12px); "
    "  border: 1px solid rgba(255,255,255,0.2); border-radius: 9999px; "
    "  color: rgba(232,237,247,0.9); font-size: 10px; font-weight: 700; "
    "  letter-spacing: 0.12em; text-transform: uppercase; padding: 7px 16px; "
    "  margin-bottom: 28px; font-family: 'JetBrains Mono', ui-monospace, monospace; } "
    ".cta-primary { display: inline-block; background: #C85120; color: #F5F7FA; "
    "  font-size: 15px; font-weight: 600; padding: 14px 32px; border-radius: 12px; "
    "  text-decoration: none; letter-spacing: 0.01em; margin-top: 36px; "
    "  transition: opacity 0.18s, transform 0.18s; } "
    ".cta-primary:hover { opacity: 0.87; transform: translateY(-1px); } "
    ".cta-primary:focus-visible { outline: 2px solid #C85120; outline-offset: 4px; } "
    ".cta-outline { display: inline-block; background: transparent; color: #E8EDF7; "
    "  font-size: 14px; font-weight: 500; padding: 11px 24px; border-radius: 10px; "
    "  text-decoration: none; letter-spacing: 0.01em; margin-top: 28px; "
    "  border: 1px solid rgba(255,255,255,0.2); transition: border-color 0.18s, background 0.18s; } "
    ".cta-outline:hover { border-color: rgba(255,255,255,0.45); background: rgba(255,255,255,0.05); } "
    ".cta-outline:focus-visible { outline: 2px solid #C85120; outline-offset: 4px; } "
    ".glass-card { background: rgba(255,255,255,0.04); "
    "  backdrop-filter: blur(24px) saturate(160%); "
    "  -webkit-backdrop-filter: blur(24px) saturate(160%); "
    "  border: 1px solid rgba(255,255,255,0.08); border-radius: 20px; "
    "  box-shadow: 0 12px 40px rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.06); } "
    ".terminal-line { display: flex; gap: 10px; font-family: 'JetBrains Mono', ui-monospace, monospace; "
    "  font-size: 13px; line-height: 1.6; } "
    ".step-row { display: flex; align-items: baseline; gap: 16px; "
    "  padding: 18px 0; border-bottom: 1px solid rgba(255,255,255,0.07); } "
    ".step-row:last-child { border-bottom: none; } "
    ".mini-feat { padding: 0 0 24px 0; border-bottom: 1px solid rgba(255,255,255,0.07); "
    "  margin-bottom: 24px; } "
    ".mini-feat:last-child { border-bottom: none; margin-bottom: 0; padding-bottom: 0; } "
    "@media (prefers-reduced-motion: reduce) { "
    "  .hero-in { animation: none; opacity: 1; transform: none; } "
    "  .cta-primary:hover { transform: none; } "
    "} "
    "@media (max-width: 900px) { "
    "  .feature-row { flex-direction: column !important; } "
    "  .feature-left { max-width: 100% !important; } "
    "  .showcase-inner { flex-direction: column !important; } "
    "  .hero-headline { font-size: 40px !important; } "
    "  .hero-sub { font-size: 16px !important; } "
    "  .section-pad { padding: 64px 28px !important; } "
    "}"
);

def:pub LandingPage() -> JsxPage {
    return
        <div style={{"background": "#0C0F15", "color": "#E8EDF7", "fontFamily": "system-ui, -apple-system, sans-serif"}}>
            <style dangerouslySetInnerHTML={{"__html": LANDING_CSS}} />

            {#* ── HERO ── *#}
            <div style={{"position": "relative", "width": "100%", "height": "100vh", "overflow": "hidden"}}>
                <img
                    src="http://localhost:8090/bridge.jpg"
                    alt="Golden Gate Bridge"
                    style={{"position": "absolute", "inset": "0", "width": "100%", "height": "100%",
                            "objectFit": "cover", "objectPosition": "center 28%"}}
                />
                <div style={{"position": "absolute", "inset": "0",
                             "background": "linear-gradient(to bottom, rgba(12,15,21,0.48) 0%, rgba(12,15,21,0.08) 38%, rgba(12,15,21,0.82) 100%)"}} />

                {#* Floating wordmark — no bar *#}
                <div style={{"position": "absolute", "top": "32px", "left": "48px", "zIndex": "10"}}>
                    <span style={{"fontFamily": "'EB Garamond', Georgia, serif", "fontSize": "20px",
                                  "fontWeight": "500", "fontStyle": "italic", "color": "rgba(245,247,250,0.9)",
                                  "letterSpacing": "0.02em"}}>
                        Trace
                    </span>
                </div>

                {#* Centered hero copy *#}
                <div
                    className="hero-in"
                    style={{"position": "absolute", "inset": "0", "display": "flex",
                            "flexDirection": "column", "alignItems": "center",
                            "justifyContent": "center", "textAlign": "center", "padding": "0 40px"}}
                >
                    <div className="hero-tag">
                        <span style={{"width": "5px", "height": "5px", "borderRadius": "50%",
                                      "background": "#C85120", "display": "inline-block", "flexShrink": "0"}} />
                        Autonomous code investigation
                    </div>
                    <h1
                        className="hero-headline"
                        style={{"fontFamily": "'EB Garamond', Georgia, serif",
                                "fontSize": "clamp(44px, 5.5vw, 76px)", "fontWeight": "400",
                                "color": "#F5F7FA", "lineHeight": "1.1", "margin": "0 0 20px 0",
                                "maxWidth": "860px", "letterSpacing": "-0.5px"}}
                    >
                        The graph does the reasoning.
                    </h1>
                    <p
                        className="hero-sub"
                        style={{"fontSize": "18px", "color": "rgba(232,237,247,0.7)",
                                "lineHeight": "1.65", "margin": "0", "maxWidth": "440px"}}
                    >
                        Ask what happens when a function runs.
                        Get an answer from your actual code — not a guess.
                    </p>
                    <Link to="/connect" className="cta-primary">
                        Start Investigating
                    </Link>
                </div>
            </div>

            {#* ── FEATURES SECTION ── *#}
            <div
                className="section-pad feature-row"
                style={{"padding": "100px 72px", "display": "flex", "gap": "80px", "alignItems": "flex-start"}}
            >
                {#* Left: headline + description + CTA *#}
                <div className="feature-left" style={{"flex": "0 0 380px", "maxWidth": "380px"}}>
                    <p style={{"fontFamily": "'JetBrains Mono', ui-monospace, monospace", "fontSize": "10px",
                               "fontWeight": "700", "letterSpacing": "0.14em", "textTransform": "uppercase",
                               "color": "#C85120", "margin": "0 0 20px 0"}}>
                        Graph intelligence
                    </p>
                    <h2 style={{"fontFamily": "'EB Garamond', Georgia, serif", "fontSize": "clamp(32px, 3.5vw, 48px)",
                                "fontWeight": "400", "color": "#E8EDF7", "lineHeight": "1.15",
                                "margin": "0 0 20px 0", "letterSpacing": "-0.3px"}}>
                        Understand any codebase, instantly.
                    </h2>
                    <p style={{"fontSize": "15px", "color": "#8A9BB8", "lineHeight": "1.75",
                               "margin": "0"}}>
                        Trace builds a persistent graph of your entire repo — every function,
                        import, route, and call edge. When you ask a question, it walks that
                        graph instead of guessing.
                    </p>
                    <Link to="/connect" className="cta-outline">
                        Connect your repo →
                    </Link>
                </div>

                {#* Right: 3 mini feature rows *#}
                <div style={{"flex": "1", "paddingTop": "8px"}}>
                    <div className="mini-feat">
                        <p style={{"fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                   "fontSize": "10px", "color": "#C85120", "letterSpacing": "0.08em",
                                   "textTransform": "uppercase", "margin": "0 0 8px 0"}}>
                            ↳ traversal
                        </p>
                        <h3 style={{"fontSize": "17px", "fontWeight": "600", "color": "#E8EDF7",
                                    "margin": "0 0 8px 0"}}>
                            Zero hallucination
                        </h3>
                        <p style={{"fontSize": "14px", "color": "#8A9BB8", "lineHeight": "1.7", "margin": "0",
                                   "maxWidth": "420px"}}>
                            Answers come from graph traversal — not LLM inference. Every result
                            is traceable to a real file, function, or call edge.
                        </p>
                    </div>
                    <div className="mini-feat">
                        <p style={{"fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                   "fontSize": "10px", "color": "#C85120", "letterSpacing": "0.08em",
                                   "textTransform": "uppercase", "margin": "0 0 8px 0"}}>
                            ↳ call graph
                        </p>
                        <h3 style={{"fontSize": "17px", "fontWeight": "600", "color": "#E8EDF7",
                                    "margin": "0 0 8px 0"}}>
                            Exact execution paths
                        </h3>
                        <p style={{"fontSize": "14px", "color": "#8A9BB8", "lineHeight": "1.7", "margin": "0",
                                   "maxWidth": "420px"}}>
                            See every function called, every import resolved, in the exact order
                            your code runs. Not a summary — the real path.
                        </p>
                    </div>
                    <div className="mini-feat">
                        <p style={{"fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                   "fontSize": "10px", "color": "#C85120", "letterSpacing": "0.08em",
                                   "textTransform": "uppercase", "margin": "0 0 8px 0"}}>
                            ↳ blast radius
                        </p>
                        <h3 style={{"fontSize": "17px", "fontWeight": "600", "color": "#E8EDF7",
                                    "margin": "0 0 8px 0"}}>
                            Know what breaks first
                        </h3>
                        <p style={{"fontSize": "14px", "color": "#8A9BB8", "lineHeight": "1.7", "margin": "0",
                                   "maxWidth": "420px"}}>
                            Before you change anything, Trace maps what depends on it —
                            callers, importers, routes — so nothing is a surprise.
                        </p>
                    </div>
                </div>
            </div>

            {#* ── SHOWCASE CARD ── *#}
            <div className="section-pad" style={{"padding": "0 72px 100px"}}>
                <div
                    className="glass-card showcase-inner"
                    style={{"display": "flex", "overflow": "hidden"}}
                >
                    {#* Left: terminal simulation *#}
                    <div style={{"flex": "0 0 55%", "background": "rgba(6,9,14,0.85)",
                                 "padding": "40px 40px", "borderRight": "1px solid rgba(255,255,255,0.07)"}}>
                        <p style={{"fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                   "fontSize": "11px", "color": "#6B7FA0", "margin": "0 0 24px 0",
                                   "letterSpacing": "0.06em"}}>
                            trace / investigation
                        </p>
                        <div className="terminal-line" style={{"marginBottom": "20px"}}>
                            <span style={{"color": "#6B7FA0"}}>›</span>
                            <span style={{"color": "#8A9BB8"}}>What happens when a user signs up?</span>
                        </div>
                        <div style={{"display": "flex", "flexDirection": "column", "gap": "14px"}}>
                            <div className="terminal-line">
                                <span style={{"color": "#C85120", "marginTop": "1px"}}>●</span>
                                <div>
                                    <span style={{"color": "#E8EDF7", "fontWeight": "600"}}>Planner</span>
                                    <span style={{"color": "#4D6080"}}> — Started investigation</span>
                                </div>
                            </div>
                            <div className="terminal-line">
                                <span style={{"color": "#C85120", "marginTop": "1px"}}>●</span>
                                <div>
                                    <span style={{"color": "#E8EDF7", "fontWeight": "600"}}>Call Graph</span>
                                    <span style={{"color": "#4D6080"}}> — Following execution path</span>
                                    <div style={{"paddingLeft": "16px", "marginTop": "6px", "display": "flex",
                                                 "flexDirection": "column", "gap": "3px"}}>
                                        <span style={{"color": "#6B7FA0"}}>→ validate_signup_input</span>
                                        <span style={{"color": "#6B7FA0"}}>→ create_user</span>
                                    </div>
                                </div>
                            </div>
                            <div className="terminal-line">
                                <span style={{"color": "#C85120", "marginTop": "1px"}}>●</span>
                                <div>
                                    <span style={{"color": "#E8EDF7", "fontWeight": "600"}}>Dependency Analysis</span>
                                    <span style={{"color": "#4D6080"}}> — Following imports</span>
                                    <div style={{"paddingLeft": "16px", "marginTop": "6px", "display": "flex",
                                                 "flexDirection": "column", "gap": "3px"}}>
                                        <span style={{"color": "#6B7FA0"}}>→ hash_password</span>
                                        <span style={{"color": "#6B7FA0"}}>→ get_repository</span>
                                        <span style={{"color": "#6B7FA0"}}>→ build_record</span>
                                    </div>
                                </div>
                            </div>
                            <div className="terminal-line">
                                <span style={{"color": "#C85120", "marginTop": "1px"}}>●</span>
                                <div>
                                    <span style={{"color": "#E8EDF7", "fontWeight": "600"}}>Risk Analysis</span>
                                    <span style={{"color": "#4D6080"}}> — Computing blast radius</span>
                                    <div style={{"paddingLeft": "16px", "marginTop": "6px"}}>
                                        <span style={{"color": "#6B7FA0"}}>→ seed_demo_users</span>
                                        <span style={{"color": "#4D6080", "fontSize": "12px", "marginLeft": "8px"}}>
                                            (also calls create_user)
                                        </span>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>

                    {#* Right: steps *#}
                    <div style={{"flex": "1", "padding": "40px 44px", "display": "flex",
                                 "flexDirection": "column", "justifyContent": "center"}}>
                        <p style={{"fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                   "fontSize": "10px", "fontWeight": "700", "letterSpacing": "0.14em",
                                   "textTransform": "uppercase", "color": "#C85120", "margin": "0 0 20px 0"}}>
                            How to use it
                        </p>
                        <h2 style={{"fontFamily": "'EB Garamond', Georgia, serif", "fontSize": "28px",
                                    "fontWeight": "400", "color": "#E8EDF7", "lineHeight": "1.25",
                                    "margin": "0 0 32px 0"}}>
                            Ask in plain English. Get graph-backed answers.
                        </h2>
                        <div className="step-row">
                            <span style={{"fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                          "fontSize": "11px", "color": "#C85120", "flexShrink": "0",
                                          "minWidth": "24px"}}>01</span>
                            <div>
                                <p style={{"fontSize": "14px", "fontWeight": "600", "color": "#E8EDF7", "margin": "0 0 4px 0"}}>
                                    Connect your repo
                                </p>
                                <p style={{"fontSize": "13px", "color": "#8A9BB8", "margin": "0", "lineHeight": "1.6"}}>
                                    Paste a GitHub URL or use the sample repo. Trace ingests it in seconds.
                                </p>
                            </div>
                        </div>
                        <div className="step-row">
                            <span style={{"fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                          "fontSize": "11px", "color": "#C85120", "flexShrink": "0",
                                          "minWidth": "24px"}}>02</span>
                            <div>
                                <p style={{"fontSize": "14px", "fontWeight": "600", "color": "#E8EDF7", "margin": "0 0 4px 0"}}>
                                    Ask a question
                                </p>
                                <p style={{"fontSize": "13px", "color": "#8A9BB8", "margin": "0", "lineHeight": "1.6"}}>
                                    "What happens when a user signs up?" Trace turns it into a graph walk.
                                </p>
                            </div>
                        </div>
                        <div className="step-row">
                            <span style={{"fontFamily": "'JetBrains Mono', ui-monospace, monospace",
                                          "fontSize": "11px", "color": "#C85120", "flexShrink": "0",
                                          "minWidth": "24px"}}>03</span>
                            <div>
                                <p style={{"fontSize": "14px", "fontWeight": "600", "color": "#E8EDF7", "margin": "0 0 4px 0"}}>
                                    Read the evidence
                                </p>
                                <p style={{"fontSize": "13px", "color": "#8A9BB8", "margin": "0", "lineHeight": "1.6"}}>
                                    Every step is traceable to a real node in the graph. No black boxes.
                                </p>
                            </div>
                        </div>
                        <div style={{"marginTop": "32px"}}>
                            <Link to="/connect" className="cta-primary" style={{"marginTop": "0", "display": "inline-block"}}>
                                Try it now
                            </Link>
                        </div>
                    </div>
                </div>
            </div>

            {#* ── CLOSING ── *#}
            <div style={{"paddingBottom": "100px", "textAlign": "center", "padding": "0 72px 100px"}}>
                <p style={{"fontFamily": "'EB Garamond', Georgia, serif",
                           "fontSize": "clamp(24px, 2.8vw, 36px)", "fontWeight": "400",
                           "fontStyle": "italic", "color": "#8A9BB8", "lineHeight": "1.5",
                           "margin": "0 auto 36px", "maxWidth": "640px"}}>
                    Most AI tools guess. Trace doesn't. It walks your actual call graph —
                    no hallucination, no summary of a summary.
                </p>
                <Link to="/connect" className="cta-primary" style={{"marginTop": "0", "display": "inline-block"}}>
                    Start Investigating
                </Link>
            </div>
        </div>;
}
