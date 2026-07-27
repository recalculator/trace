import from "@jac/runtime" { Outlet }

def:pub RootLayout() -> JsxLayout {
    return
        <div
            style={{
                "background": "#0C0F15",
                "minHeight": "100vh",
                "color": "#E8EDF7",
                "fontFamily": "system-ui, -apple-system, sans-serif"
            }}
        >
            <Outlet />
        </div>;
}
