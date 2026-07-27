import from "@jac/runtime" { Navigate }

def:pub AppPage() -> JsxPage {
    return <Navigate to="/connect" replace={True} />;
}
