"""Mock API — stand-in for Ayaan's server endpoints.

SWAP GUIDE (one line per call site in client/App.impl.jac):
  Mock  : import from .mock_api { get_repo_graph }
  Real  : sv import from graph_export { get_repo_graph }

  Mock  : import from .mock_api { forward_trace, reverse_trace, find_symbol }
  Real  : sv import from investigation { forward_trace, reverse_trace, find_symbol }
  (investigation endpoint names are speculative — adjust to match Ayaan's actual module name)

Data matches sample_repo exactly: real filenames, real function names, real line
numbers, real call chains. The signup flow (POST /auth/signup -> signup ->
validate_signup_input -> create_user -> hash_password / build_record /
get_repository / persist / generate_token / public_view) is fully represented.
admin/seed.py's seed_demo_users is the second caller of create_user — the
reverse-traversal demo target.
"""

import from client.types {
    GraphNode, GraphEdge, RepoGraph,
    TraceStep, TraceResult, SymbolMatch
}

cl async def get_repo_graph(name: str) -> RepoGraph {
    if name != "sample_repo" {
        return RepoGraph();
    }

    nodes: list[GraphNode] = [
        # ----- Repository -----
        GraphNode(
            id="r-sample", node_type="Repository",
            name="sample_repo", path=".",
            ingested_at="2026-07-26T09:31:00", file_count=8
        ),

        # ----- Files -----
        GraphNode(id="f-app-main",    node_type="File", name="main.py",            path="app/main.py",                    language="python"),
        GraphNode(id="f-app-mw",      node_type="File", name="middleware.py",       path="app/middleware.py",              language="python"),
        GraphNode(id="f-svc-user",    node_type="File", name="user_service.py",     path="services/user_service.py",       language="python"),
        GraphNode(id="f-svc-sec",     node_type="File", name="security.py",         path="services/security.py",           language="python"),
        GraphNode(id="f-svc-val",     node_type="File", name="validation.py",       path="services/validation.py",         language="python"),
        GraphNode(id="f-repo-ur",     node_type="File", name="user_repository.py",  path="repository/user_repository.py",  language="python"),
        GraphNode(id="f-repo-db",     node_type="File", name="db.py",               path="repository/db.py",               language="python"),
        GraphNode(id="f-admin-seed",  node_type="File", name="seed.py",             path="admin/seed.py",                  language="python"),

        # ----- Symbols: app/main.py -----
        GraphNode(id="s-signup",    node_type="Symbol", name="signup",    path="app/main.py", kind="function",       line=12, source="def signup(payload: dict) -> dict: ..."),
        GraphNode(id="s-me",        node_type="Symbol", name="me",        path="app/main.py", kind="function",       line=20, source="def me(request: Request) -> dict: ..."),
        GraphNode(id="s-get-user",  node_type="Symbol", name="get_user",  path="app/main.py", kind="function",       line=27, source="def get_user(email: str) -> dict: ..."),
        GraphNode(id="s-healthz",   node_type="Symbol", name="healthz",   path="app/main.py", kind="function",       line=33, source="def healthz() -> dict: ..."),

        # ----- Symbols: app/middleware.py -----
        GraphNode(id="s-auth-error",   node_type="Symbol", name="AuthError",           path="app/middleware.py", kind="class",    line=9,  source="class AuthError(Exception): ..."),
        GraphNode(id="s-extract-brr",  node_type="Symbol", name="extract_bearer",      path="app/middleware.py", kind="function", line=13, source="def extract_bearer(headers: dict) -> str: ..."),
        GraphNode(id="s-authenticate", node_type="Symbol", name="authenticate_request", path="app/middleware.py", kind="function", line=20, source="def authenticate_request(headers: dict) -> dict: ..."),
        GraphNode(id="s-require-auth", node_type="Symbol", name="require_auth",         path="app/middleware.py", kind="function", line=28, source="def require_auth(headers: dict) -> dict: ..."),

        # ----- Symbols: services/user_service.py -----
        GraphNode(id="s-create-user",  node_type="Symbol", name="create_user",  path="services/user_service.py", kind="function", line=4,  source="def create_user(payload: dict) -> dict: ..."),
        GraphNode(id="s-build-record", node_type="Symbol", name="build_record", path="services/user_service.py", kind="function", line=13, source="def build_record(payload: dict, password_hash: str) -> dict: ..."),
        GraphNode(id="s-public-view",  node_type="Symbol", name="public_view",  path="services/user_service.py", kind="function", line=21, source="def public_view(stored: dict) -> dict: ..."),
        GraphNode(id="s-find-user",    node_type="Symbol", name="find_user",    path="services/user_service.py", kind="function", line=28, source="def find_user(email: str) -> dict: ..."),

        # ----- Symbols: services/security.py -----
        GraphNode(id="s-salt",         node_type="Symbol", name="_salt",          path="services/security.py", kind="function", line=13, source="def _salt(email: str) -> bytes: ..."),
        GraphNode(id="s-hash-pwd",     node_type="Symbol", name="hash_password",  path="services/security.py", kind="function", line=17, source="def hash_password(password: str, email: str) -> str: ..."),
        GraphNode(id="s-gen-token",    node_type="Symbol", name="generate_token", path="services/security.py", kind="function", line=23, source="def generate_token(user_id: int, email: str) -> str: ..."),
        GraphNode(id="s-sign",         node_type="Symbol", name="_sign",          path="services/security.py", kind="function", line=30, source="def _sign(body: str) -> str: ..."),
        GraphNode(id="s-verify-token", node_type="Symbol", name="verify_token",   path="services/security.py", kind="function", line=35, source="def verify_token(token: str) -> dict: ..."),
        GraphNode(id="s-decode-token", node_type="Symbol", name="decode_token",   path="services/security.py", kind="function", line=45, source="def decode_token(body: str) -> dict: ..."),

        # ----- Symbols: services/validation.py -----
        GraphNode(id="s-val-error",      node_type="Symbol", name="ValidationError",       path="services/validation.py", kind="class",    line=8,  source="class ValidationError(Exception): ..."),
        GraphNode(id="s-validate-signup",node_type="Symbol", name="validate_signup_input", path="services/validation.py", kind="function", line=12, source="def validate_signup_input(payload: dict) -> dict: ..."),
        GraphNode(id="s-check-email",    node_type="Symbol", name="check_email",           path="services/validation.py", kind="function", line=21, source="def check_email(email: str) -> str: ..."),
        GraphNode(id="s-check-password", node_type="Symbol", name="check_password",        path="services/validation.py", kind="function", line=26, source="def check_password(password: str) -> str: ..."),
        GraphNode(id="s-normalise-name", node_type="Symbol", name="normalise_name",        path="services/validation.py", kind="function", line=31, source="def normalise_name(display_name: str) -> str: ..."),

        # ----- Symbols: repository/user_repository.py -----
        GraphNode(id="s-user-repo",     node_type="Symbol", name="UserRepository",  path="repository/user_repository.py", kind="class",    line=6,  source="class UserRepository: ..."),
        GraphNode(id="s-persist",       node_type="Symbol", name="persist",         path="repository/user_repository.py", kind="method",   line=11, source="def persist(self, user: dict) -> dict: ..."),
        GraphNode(id="s-find-by-email", node_type="Symbol", name="find_by_email",   path="repository/user_repository.py", kind="method",   line=16, source="def find_by_email(self, email: str) -> dict: ..."),
        GraphNode(id="s-get-repo",      node_type="Symbol", name="get_repository",  path="repository/user_repository.py", kind="function", line=21, source="def get_repository() -> UserRepository: ..."),

        # ----- Symbols: repository/db.py -----
        GraphNode(id="s-connect",  node_type="Symbol", name="connect",   path="repository/db.py", kind="function", line=7,  source="def connect() -> dict: ..."),
        GraphNode(id="s-next-id",  node_type="Symbol", name="next_id",   path="repository/db.py", kind="function", line=12, source="def next_id(table: str) -> int: ..."),
        GraphNode(id="s-execute",  node_type="Symbol", name="execute",   path="repository/db.py", kind="function", line=16, source="def execute(table: str, row: dict) -> dict: ..."),
        GraphNode(id="s-query-by", node_type="Symbol", name="query_by",  path="repository/db.py", kind="function", line=23, source="def query_by(table: str, field: str, value: str) -> dict: ..."),

        # ----- Symbols: admin/seed.py -----
        GraphNode(id="s-seed-demo", node_type="Symbol", name="seed_demo_users", path="admin/seed.py", kind="function", line=12, source="def seed_demo_users() -> list: ..."),
        GraphNode(id="s-seed-main", node_type="Symbol", name="main",            path="admin/seed.py", kind="function", line=20, source="def main() -> None: ..."),

        # ----- Routes -----
        GraphNode(id="rt-signup",   node_type="Route", name="POST /auth/signup",      path="app/main.py", method="POST", pattern="/auth/signup",       line=11),
        GraphNode(id="rt-me",       node_type="Route", name="GET /auth/me",           path="app/main.py", method="GET",  pattern="/auth/me",            line=19),
        GraphNode(id="rt-get-user", node_type="Route", name="GET /users/{email}",     path="app/main.py", method="GET",  pattern="/users/{email}",      line=26),
        GraphNode(id="rt-healthz",  node_type="Route", name="GET /healthz",           path="app/main.py", method="GET",  pattern="/healthz",            line=32)
    ];

    edges: list[GraphEdge] = [
        # ----- RepositoryContainsFile -----
        GraphEdge(id="e-rcf-1", edge_type="RepositoryContainsFile", source="r-sample", target="f-app-main"),
        GraphEdge(id="e-rcf-2", edge_type="RepositoryContainsFile", source="r-sample", target="f-app-mw"),
        GraphEdge(id="e-rcf-3", edge_type="RepositoryContainsFile", source="r-sample", target="f-svc-user"),
        GraphEdge(id="e-rcf-4", edge_type="RepositoryContainsFile", source="r-sample", target="f-svc-sec"),
        GraphEdge(id="e-rcf-5", edge_type="RepositoryContainsFile", source="r-sample", target="f-svc-val"),
        GraphEdge(id="e-rcf-6", edge_type="RepositoryContainsFile", source="r-sample", target="f-repo-ur"),
        GraphEdge(id="e-rcf-7", edge_type="RepositoryContainsFile", source="r-sample", target="f-repo-db"),
        GraphEdge(id="e-rcf-8", edge_type="RepositoryContainsFile", source="r-sample", target="f-admin-seed"),

        # ----- RepositoryContainsRoute -----
        GraphEdge(id="e-rcr-1", edge_type="RepositoryContainsRoute", source="r-sample", target="rt-signup"),
        GraphEdge(id="e-rcr-2", edge_type="RepositoryContainsRoute", source="r-sample", target="rt-me"),
        GraphEdge(id="e-rcr-3", edge_type="RepositoryContainsRoute", source="r-sample", target="rt-get-user"),
        GraphEdge(id="e-rcr-4", edge_type="RepositoryContainsRoute", source="r-sample", target="rt-healthz"),

        # ----- FileContainsSymbol: app/main.py -----
        GraphEdge(id="e-fcs-1",  edge_type="FileContainsSymbol", source="f-app-main",   target="s-signup"),
        GraphEdge(id="e-fcs-2",  edge_type="FileContainsSymbol", source="f-app-main",   target="s-me"),
        GraphEdge(id="e-fcs-3",  edge_type="FileContainsSymbol", source="f-app-main",   target="s-get-user"),
        GraphEdge(id="e-fcs-4",  edge_type="FileContainsSymbol", source="f-app-main",   target="s-healthz"),

        # ----- FileContainsSymbol: app/middleware.py -----
        GraphEdge(id="e-fcs-5",  edge_type="FileContainsSymbol", source="f-app-mw",     target="s-auth-error"),
        GraphEdge(id="e-fcs-6",  edge_type="FileContainsSymbol", source="f-app-mw",     target="s-extract-brr"),
        GraphEdge(id="e-fcs-7",  edge_type="FileContainsSymbol", source="f-app-mw",     target="s-authenticate"),
        GraphEdge(id="e-fcs-8",  edge_type="FileContainsSymbol", source="f-app-mw",     target="s-require-auth"),

        # ----- FileContainsSymbol: services/user_service.py -----
        GraphEdge(id="e-fcs-9",  edge_type="FileContainsSymbol", source="f-svc-user",   target="s-create-user"),
        GraphEdge(id="e-fcs-10", edge_type="FileContainsSymbol", source="f-svc-user",   target="s-build-record"),
        GraphEdge(id="e-fcs-11", edge_type="FileContainsSymbol", source="f-svc-user",   target="s-public-view"),
        GraphEdge(id="e-fcs-12", edge_type="FileContainsSymbol", source="f-svc-user",   target="s-find-user"),

        # ----- FileContainsSymbol: services/security.py -----
        GraphEdge(id="e-fcs-13", edge_type="FileContainsSymbol", source="f-svc-sec",    target="s-salt"),
        GraphEdge(id="e-fcs-14", edge_type="FileContainsSymbol", source="f-svc-sec",    target="s-hash-pwd"),
        GraphEdge(id="e-fcs-15", edge_type="FileContainsSymbol", source="f-svc-sec",    target="s-gen-token"),
        GraphEdge(id="e-fcs-16", edge_type="FileContainsSymbol", source="f-svc-sec",    target="s-sign"),
        GraphEdge(id="e-fcs-17", edge_type="FileContainsSymbol", source="f-svc-sec",    target="s-verify-token"),
        GraphEdge(id="e-fcs-18", edge_type="FileContainsSymbol", source="f-svc-sec",    target="s-decode-token"),

        # ----- FileContainsSymbol: services/validation.py -----
        GraphEdge(id="e-fcs-19", edge_type="FileContainsSymbol", source="f-svc-val",    target="s-val-error"),
        GraphEdge(id="e-fcs-20", edge_type="FileContainsSymbol", source="f-svc-val",    target="s-validate-signup"),
        GraphEdge(id="e-fcs-21", edge_type="FileContainsSymbol", source="f-svc-val",    target="s-check-email"),
        GraphEdge(id="e-fcs-22", edge_type="FileContainsSymbol", source="f-svc-val",    target="s-check-password"),
        GraphEdge(id="e-fcs-23", edge_type="FileContainsSymbol", source="f-svc-val",    target="s-normalise-name"),

        # ----- FileContainsSymbol: repository/user_repository.py -----
        GraphEdge(id="e-fcs-24", edge_type="FileContainsSymbol", source="f-repo-ur",    target="s-user-repo"),
        GraphEdge(id="e-fcs-25", edge_type="FileContainsSymbol", source="f-repo-ur",    target="s-persist"),
        GraphEdge(id="e-fcs-26", edge_type="FileContainsSymbol", source="f-repo-ur",    target="s-find-by-email"),
        GraphEdge(id="e-fcs-27", edge_type="FileContainsSymbol", source="f-repo-ur",    target="s-get-repo"),

        # ----- FileContainsSymbol: repository/db.py -----
        GraphEdge(id="e-fcs-28", edge_type="FileContainsSymbol", source="f-repo-db",    target="s-connect"),
        GraphEdge(id="e-fcs-29", edge_type="FileContainsSymbol", source="f-repo-db",    target="s-next-id"),
        GraphEdge(id="e-fcs-30", edge_type="FileContainsSymbol", source="f-repo-db",    target="s-execute"),
        GraphEdge(id="e-fcs-31", edge_type="FileContainsSymbol", source="f-repo-db",    target="s-query-by"),

        # ----- FileContainsSymbol: admin/seed.py -----
        GraphEdge(id="e-fcs-32", edge_type="FileContainsSymbol", source="f-admin-seed", target="s-seed-demo"),
        GraphEdge(id="e-fcs-33", edge_type="FileContainsSymbol", source="f-admin-seed", target="s-seed-main"),

        # ----- FileImportsFile -----
        GraphEdge(id="e-fif-1",  edge_type="FileImportsFile", source="f-app-main",   target="f-app-mw"),
        GraphEdge(id="e-fif-2",  edge_type="FileImportsFile", source="f-app-main",   target="f-svc-user"),
        GraphEdge(id="e-fif-3",  edge_type="FileImportsFile", source="f-app-main",   target="f-svc-val"),
        GraphEdge(id="e-fif-4",  edge_type="FileImportsFile", source="f-app-mw",     target="f-svc-sec"),
        GraphEdge(id="e-fif-5",  edge_type="FileImportsFile", source="f-app-mw",     target="f-svc-user"),
        GraphEdge(id="e-fif-6",  edge_type="FileImportsFile", source="f-svc-user",   target="f-repo-ur"),
        GraphEdge(id="e-fif-7",  edge_type="FileImportsFile", source="f-svc-user",   target="f-svc-sec"),
        GraphEdge(id="e-fif-8",  edge_type="FileImportsFile", source="f-repo-ur",    target="f-repo-db"),
        GraphEdge(id="e-fif-9",  edge_type="FileImportsFile", source="f-admin-seed", target="f-svc-user"),
        GraphEdge(id="e-fif-10", edge_type="FileImportsFile", source="f-admin-seed", target="f-svc-val"),

        # ----- SymbolCallsSymbol: signup chain -----
        GraphEdge(id="e-scs-1",  edge_type="SymbolCallsSymbol", source="s-signup",      target="s-validate-signup", line=14),
        GraphEdge(id="e-scs-2",  edge_type="SymbolCallsSymbol", source="s-signup",      target="s-create-user",     line=15),
        GraphEdge(id="e-scs-3",  edge_type="SymbolCallsSymbol", source="s-create-user", target="s-hash-pwd",        line=5),
        GraphEdge(id="e-scs-4",  edge_type="SymbolCallsSymbol", source="s-create-user", target="s-build-record",    line=6),
        GraphEdge(id="e-scs-5",  edge_type="SymbolCallsSymbol", source="s-create-user", target="s-get-repo",        line=7),
        GraphEdge(id="e-scs-6",  edge_type="SymbolCallsSymbol", source="s-create-user", target="s-persist",         line=9),
        GraphEdge(id="e-scs-7",  edge_type="SymbolCallsSymbol", source="s-create-user", target="s-gen-token",       line=11),
        GraphEdge(id="e-scs-8",  edge_type="SymbolCallsSymbol", source="s-create-user", target="s-public-view",     line=12),

        # ----- SymbolCallsSymbol: admin/seed.py (reverse-traversal demo) -----
        GraphEdge(id="e-scs-9",  edge_type="SymbolCallsSymbol", source="s-seed-demo",   target="s-validate-signup", line=15),
        GraphEdge(id="e-scs-10", edge_type="SymbolCallsSymbol", source="s-seed-demo",   target="s-create-user",     line=16),

        # ----- SymbolCallsSymbol: auth chain -----
        GraphEdge(id="e-scs-11", edge_type="SymbolCallsSymbol", source="s-me",           target="s-require-auth",   line=21),
        GraphEdge(id="e-scs-12", edge_type="SymbolCallsSymbol", source="s-require-auth", target="s-authenticate",   line=29),
        GraphEdge(id="e-scs-13", edge_type="SymbolCallsSymbol", source="s-authenticate", target="s-extract-brr",    line=21),
        GraphEdge(id="e-scs-14", edge_type="SymbolCallsSymbol", source="s-authenticate", target="s-verify-token",   line=22),
        GraphEdge(id="e-scs-15", edge_type="SymbolCallsSymbol", source="s-authenticate", target="s-find-user",      line=23),

        # ----- SymbolCallsSymbol: security internals -----
        GraphEdge(id="e-scs-16", edge_type="SymbolCallsSymbol", source="s-hash-pwd",     target="s-salt",           line=18),
        GraphEdge(id="e-scs-17", edge_type="SymbolCallsSymbol", source="s-gen-token",    target="s-sign",           line=26),
        GraphEdge(id="e-scs-18", edge_type="SymbolCallsSymbol", source="s-verify-token", target="s-sign",           line=37),
        GraphEdge(id="e-scs-19", edge_type="SymbolCallsSymbol", source="s-verify-token", target="s-decode-token",   line=39),

        # ----- SymbolCallsSymbol: repository internals -----
        GraphEdge(id="e-scs-20", edge_type="SymbolCallsSymbol", source="s-persist",       target="s-execute",        line=12),
        GraphEdge(id="e-scs-21", edge_type="SymbolCallsSymbol", source="s-find-by-email", target="s-query-by",       line=17),
        GraphEdge(id="e-scs-22", edge_type="SymbolCallsSymbol", source="s-get-user",      target="s-find-user",      line=28),

        # ----- RouteHandledBySymbol -----
        GraphEdge(id="e-rhs-1", edge_type="RouteHandledBySymbol", source="rt-signup",   target="s-signup"),
        GraphEdge(id="e-rhs-2", edge_type="RouteHandledBySymbol", source="rt-me",       target="s-me"),
        GraphEdge(id="e-rhs-3", edge_type="RouteHandledBySymbol", source="rt-get-user", target="s-get-user"),
        GraphEdge(id="e-rhs-4", edge_type="RouteHandledBySymbol", source="rt-healthz",  target="s-healthz")
    ];

    return RepoGraph(nodes=nodes, edges=edges);
}

# --- Speculative investigation mocks ---
# Signatures and return shapes below are inferred from the investigation brief.
# Ayaan's real endpoints may differ — treat these as placeholder contracts.

cl async def forward_trace(symbol_id: str) -> TraceResult {
    # Demo traces from create_user outward through the call graph.
    steps: list[TraceStep] = [
        TraceStep(
            step=0,
            node_ids=["s-create-user"],
            edge_ids=[],
            label="Entry: create_user (services/user_service.py:4)"
        ),
        TraceStep(
            step=1,
            node_ids=["s-hash-pwd", "s-build-record", "s-get-repo"],
            edge_ids=["e-scs-3", "e-scs-4", "e-scs-5"],
            label="Direct calls: hash_password, build_record, get_repository"
        ),
        TraceStep(
            step=2,
            node_ids=["s-salt", "s-user-repo"],
            edge_ids=["e-scs-16"],
            label="Transitive: _salt (via hash_password), UserRepository (via get_repository)"
        ),
        TraceStep(
            step=3,
            node_ids=["s-persist", "s-gen-token", "s-public-view"],
            edge_ids=["e-scs-6", "e-scs-7", "e-scs-8"],
            label="Continuation: persist, generate_token, public_view"
        ),
        TraceStep(
            step=4,
            node_ids=["s-execute", "s-sign"],
            edge_ids=["e-scs-20", "e-scs-17"],
            label="Final depth: execute (via persist), _sign (via generate_token)"
        )
    ];
    return TraceResult(
        symbol_id=symbol_id,
        direction="forward",
        steps=steps,
        total_steps=len(steps)
    );
}

cl async def reverse_trace(symbol_id: str) -> TraceResult {
    # Demo: who calls create_user? signup (HTTP) and seed_demo_users (CLI).
    steps: list[TraceStep] = [
        TraceStep(
            step=0,
            node_ids=["s-create-user"],
            edge_ids=[],
            label="Target: create_user"
        ),
        TraceStep(
            step=1,
            node_ids=["s-signup", "s-seed-demo"],
            edge_ids=["e-scs-2", "e-scs-10"],
            label="Direct callers: signup (HTTP handler), seed_demo_users (CLI)"
        ),
        TraceStep(
            step=2,
            node_ids=["rt-signup"],
            edge_ids=["e-rhs-1"],
            label="Entry point: POST /auth/signup"
        )
    ];
    return TraceResult(
        symbol_id=symbol_id,
        direction="reverse",
        steps=steps,
        total_steps=len(steps)
    );
}

cl async def find_symbol(name: str, _repo_name: str) -> list[SymbolMatch] {
    all_syms: list[SymbolMatch] = [
        SymbolMatch(node_id="s-signup",         name="signup",                path="app/main.py",                   kind="function", line=12),
        SymbolMatch(node_id="s-create-user",    name="create_user",           path="services/user_service.py",      kind="function", line=4),
        SymbolMatch(node_id="s-validate-signup",name="validate_signup_input", path="services/validation.py",        kind="function", line=12),
        SymbolMatch(node_id="s-hash-pwd",       name="hash_password",         path="services/security.py",          kind="function", line=17),
        SymbolMatch(node_id="s-gen-token",      name="generate_token",        path="services/security.py",          kind="function", line=23),
        SymbolMatch(node_id="s-verify-token",   name="verify_token",          path="services/security.py",          kind="function", line=35),
        SymbolMatch(node_id="s-require-auth",   name="require_auth",          path="app/middleware.py",             kind="function", line=28),
        SymbolMatch(node_id="s-authenticate",   name="authenticate_request",  path="app/middleware.py",             kind="function", line=20),
        SymbolMatch(node_id="s-get-repo",       name="get_repository",        path="repository/user_repository.py", kind="function", line=21),
        SymbolMatch(node_id="s-persist",        name="persist",               path="repository/user_repository.py", kind="method",   line=11),
        SymbolMatch(node_id="s-seed-demo",      name="seed_demo_users",       path="admin/seed.py",                 kind="function", line=12)
    ];
    if not name {
        return all_syms;
    }
    lower = name.lower();
    return [s for s in all_syms if lower in s.name.lower()];
}
