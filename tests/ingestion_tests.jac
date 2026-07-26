"""Trace - ingestion tests.

Run with:  jac test -d tests/

Each test re-ingests the sample repository. Ingestion purges any previous
`Repository` at the same path first, so tests are independent of each other
and of whatever the persisted root happens to be holding.

NOTE: this file is deliberately NOT named `test_*.jac` - that prefix
collides with Python's test-module import machinery.
"""

import os;

import from models {
    Repository,
    File,
    Symbol,
    Route,
    RepositoryContainsFile,
    FileContainsSymbol,
    FileImportsFile,
    SymbolCallsSymbol,
    RouteHandledBySymbol,
    RepositoryContainsRoute
}
import from ingestion { ingest_repo, IngestSummary }

glob SAMPLE: str = os.path.join(os.path.dirname(__file__), "..", "sample_repo");

"""Ingest the sample repo and return the fresh Repository node."""
def _ingest() -> Repository {
    _summary = ingest_repo(SAMPLE, name="sample_repo");
    repos = [root-->[?:Repository]];
    assert len(repos) == 1 , f"expected exactly 1 repository, got {len(repos)}";
    return repos[0];
}

"""Every File node under a repository."""
def _files(repo: Repository) -> list[File] {
    return [repo->:RepositoryContainsFile:->];
}

"""Every Symbol node under a repository."""
def _symbols(repo: Repository) -> list[Symbol] {
    out: list[Symbol] = [];
    for f in [repo->:RepositoryContainsFile:->] {
        for s in [f->:FileContainsSymbol:->] {
            out.append(s);
        }
    }
    return out;
}

"""Find one symbol by name, asserting it is unambiguous."""
def _symbol(repo: Repository, name: str) -> Symbol {
    hits = [
        s
        for s in _symbols(repo)
        if s.name == name
    ];
    assert len(hits) == 1 , f"expected 1 symbol named {name}, got {len(hits)}";
    return hits[0];
}

"""True when caller has a direct SymbolCallsSymbol edge to callee."""
def _calls(caller: Symbol, callee_name: str) -> bool {
    for target in [caller->:SymbolCallsSymbol:->] {
        if target.name == callee_name {
            return True;
        }
    }
    return False;
}

test "python files become File nodes" {
    repo = _ingest();
    files = _files(repo);
    paths = [f.path for f in files];

    assert len(files) == 12 , f"expected 12 python files, got {len(files)}: {paths}";
    assert "app/main.py" in paths;
    assert "services/user_service.py" in paths;
    assert "repository/db.py" in paths;

    for f in files {
        assert f.language == "python" , f"{f.path} language was {f.language}";
        assert f.name.endswith(".py") , f"{f.name} is not a .py file";
    }
}

test "ignored directories are not ingested" {
    repo = _ingest();
    paths = [f.path for f in _files(repo)];

    for bad in ["build", ".venv", "__pycache__", "node_modules"] {
        for p in paths {
            assert bad not in p , f"ingested an ignored directory: {p}";
        }
    }
}

test "functions classes and methods become Symbol nodes" {
    repo = _ingest();
    symbols = _symbols(repo);
    assert len(symbols) > 20 , f"expected a populated symbol set, got {len(symbols)}";

    assert _symbol(repo, "signup").kind == "function";
    assert _symbol(repo, "create_user").kind == "function";
    assert _symbol(repo, "hash_password").kind == "function";
    assert _symbol(repo, "UserRepository").kind == "class";
    assert _symbol(repo, "persist").kind == "method";
    assert _symbol(repo, "find_by_email").kind == "method";

    signup = _symbol(repo, "signup");
    assert signup.path == "app/main.py" , f"signup was at {signup.path}";
    assert signup.line > 0 , "signup has no line number";
    assert "def signup" in signup.source , "signup source was not captured";
}

test "the signup call chain is a connected path of symbols" {
    repo = _ingest();

    signup = _symbol(repo, "signup");
    create_user = _symbol(repo, "create_user");
    persist = _symbol(repo, "persist");

    # signup -> validate input -> create user
    assert _calls(signup, "validate_signup_input") , "signup does not call validate_signup_input";
    assert _calls(signup, "create_user") , "signup does not call create_user";

    # create user -> hash password -> persist -> generate token
    assert _calls(create_user, "hash_password") , "create_user does not call hash_password";
    assert _calls(create_user, "persist") , "create_user does not reach the repository";
    assert _calls(create_user, "generate_token") , "create_user does not call generate_token";

    # persist -> database execute
    assert _calls(persist, "execute") , "persist does not call execute";

    # The chain is genuinely multi-hop, not one fan-out from signup.
    depth_two = [t.name for t in [create_user->:SymbolCallsSymbol:->]];
    assert len(depth_two) >= 4 , f"create_user fans out to only {depth_two}";
}

test "authentication entry point is reachable from a route" {
    repo = _ingest();

    routes = [repo->:RepositoryContainsRoute:->];
    assert len(routes) == 4 , f"expected 4 routes, got {[r.name for r in routes]}";

    me_route = [
        r
        for r in routes
        if r.pattern == "/auth/me"
    ][0];
    assert me_route.method == "GET";

    handlers = [me_route->:RouteHandledBySymbol:->];
    assert len(handlers) == 1 , "the /auth/me route has no handler symbol";
    assert handlers[0].name == "me";

    assert _calls(handlers[0], "require_auth") , "me does not call require_auth";
    assert _calls(_symbol(repo, "require_auth"), "authenticate_request");
    assert _calls(_symbol(repo, "authenticate_request"), "verify_token");
}

test "reverse traversal finds every caller of create_user" {
    repo = _ingest();
    create_user = _symbol(repo, "create_user");

    callers = [create_user<-:SymbolCallsSymbol:<-];
    names = [c.name for c in callers];
    names.sort();

    assert names == ["seed_demo_users", "signup"] , f"blast radius was {names}";
}

test "imports resolve to files inside the repository" {
    repo = _ingest();
    by_path: dict[str, File] = {};
    for f in _files(repo) {
        by_path[f.path] = f;
    }

    imported = [t.path for t in [by_path["app/main.py"]->:FileImportsFile:->]];
    imported.sort();
    assert imported == [
        "app/middleware.py",
        "services/user_service.py",
        "services/validation.py"
    ] , f"main.py imports resolved to {imported}";

    # Stdlib and third-party imports must NOT become edges.
    db_imports = [t.path for t in [by_path["repository/db.py"]->:FileImportsFile:->]];
    assert db_imports == [] , f"db.py should import nothing local, got {db_imports}";
}

test "re-ingesting the same repository creates no duplicates" {
    first = ingest_repo(SAMPLE, name="sample_repo");
    repos_after_first = len([root-->[?:Repository]]);
    files_after_first = len(_files([root-->[?:Repository]][0]));
    symbols_after_first = len(_symbols([root-->[?:Repository]][0]));

    second = ingest_repo(SAMPLE, name="sample_repo");
    repo = [root-->[?:Repository]][0];

    assert len([root-->[?:Repository]]) == repos_after_first , "re-ingestion added a second Repository node";
    assert len(_files(repo)) == files_after_first , f"file count drifted: {files_after_first} -> {len(
        _files(repo)
    )}";
    assert len(_symbols(repo)) == symbols_after_first , f"symbol count drifted: {symbols_after_first} -> {len(
        _symbols(repo)
    )}";

    assert first.files == second.files;
    assert first.symbols == second.symbols;
    assert first.call_edges == second.call_edges;
    assert first.import_edges == second.import_edges;
    assert first.route_edges == second.route_edges;

    # Symbol names must still be unambiguous - the real duplicate-node symptom.
    _sym = _symbol(repo, "create_user");
    assert len([_sym<-:SymbolCallsSymbol:<-]) == 2 , "duplicate call edges after re-ingestion";
}
