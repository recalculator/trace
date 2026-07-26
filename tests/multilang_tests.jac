"""Trace - multi-language ingestion tests.

The point of these tests is not that TypeScript parses. It is that a
TypeScript repository produces the SAME graph shape as a Python one, so the
unmodified investigation walkers work on both.

Both fixtures are ingested in every test. They coexist deliberately - that
is the real deployment condition - and the assertions lean on the fact that
the two fixtures use different naming conventions (`create_user` vs
`createUser`), so a seed name is never ambiguous across languages.
"""

import os;

import from models {
    Repository,
    File,
    Symbol,
    RepositoryContainsFile,
    FileContainsSymbol,
    FileImportsFile,
    SymbolCallsSymbol
}
import from ingestion { ingest_repo }
import from investigation { forward_trace, reverse_trace }
import from langs { detect_language, supported_languages }

glob PY_REPO: str = os.path.join(os.path.dirname(__file__), "..", "sample_repo");

glob TS_REPO: str = os.path.join(
         os.path.dirname(__file__), "..", "sample_repo_ts"
     );

"""Ingest both fixtures and return (python_repo, typescript_repo)."""
def _ingest_both() -> list[Repository] {
    _p = ingest_repo(PY_REPO, name="sample_repo");
    _t = ingest_repo(TS_REPO, name="sample_repo_ts");
    py: list[Repository] = [];
    ts: list[Repository] = [];
    for r in [root-->[?:Repository]] {
        if r.name == "sample_repo" {
            py.append(r);
        }
        if r.name == "sample_repo_ts" {
            ts.append(r);
        }
    }
    assert len(py) == 1 , f"expected 1 python repo, got {len(py)}";
    assert len(ts) == 1 , f"expected 1 typescript repo, got {len(ts)}";
    return [py[0], ts[0]];
}

"""Every Symbol under a repository."""
def _symbols(repo: Repository) -> list[Symbol] {
    out: list[Symbol] = [];
    for f in [repo->:RepositoryContainsFile:->] {
        for s in [f->:FileContainsSymbol:->] {
            out.append(s);
        }
    }
    return out;
}

"""Find one symbol by name within a repository."""
def _symbol(repo: Repository, name: str) -> Symbol {
    hits = [
        s
        for s in _symbols(repo)
        if s.name == name
    ];
    assert len(hits) == 1 , f"expected 1 symbol '{name}', got {len(hits)}";
    return hits[0];
}

"""True when caller has a direct call edge to a symbol of the given name."""
def _calls(caller: Symbol, callee_name: str) -> bool {
    for t in [caller->:SymbolCallsSymbol:->] {
        if t.name == callee_name {
            return True;
        }
    }
    return False;
}

test "language detection maps extensions to parsers" {
    assert detect_language("main.py") == "python";
    assert detect_language("routes.ts") == "typescript";
    assert detect_language("Widget.tsx") == "typescript";
    assert detect_language("README.md") == "";
    assert detect_language("Makefile") == "";

    langs = supported_languages();
    assert "python" in langs;
    assert "typescript" in langs;
}

test "python ingestion still produces its original graph" {
    both = _ingest_both();
    py = both[0];

    files = [py->:RepositoryContainsFile:->];
    assert len(files) == 12 , f"python file count changed: {len(files)}";
    for f in files {
        assert f.language == "python" , f"{f.path} tagged {f.language}";
    }

    syms = _symbols(py);
    assert len(syms) == 33 , f"python symbol count changed: {len(syms)}";
    assert _symbol(py, "create_user").kind == "function";
    assert _symbol(py, "UserRepository").kind == "class";
    assert _symbol(py, "persist").kind == "method";
}

test "typescript ingestion produces symbols from .ts and .tsx" {
    both = _ingest_both();
    ts = both[1];

    files = [ts->:RepositoryContainsFile:->];
    assert len(files) == 9 , f"typescript file count: {len(files)}";
    for f in files {
        assert f.language == "typescript" , f"{f.path} tagged {f.language}";
        assert f.name.endswith(".ts") or f.name.endswith(".tsx");
    }

    paths = [f.path for f in files];
    assert "src/components/SignupForm.tsx" in paths , "the .tsx file was not ingested";

    syms = _symbols(ts);
    assert len(syms) > 25 , f"typescript symbols: {len(syms)}";
}

test "both languages normalise onto the same symbol vocabulary" {
    both = _ingest_both();
    py = both[0];
    ts = both[1];

    # A free function, a class and a method exist in both, spelled per language.
    assert _symbol(py, "create_user").kind == _symbol(ts, "createUser").kind == "function";
    assert _symbol(py, "UserRepository").kind == _symbol(ts, "UserRepository").kind == "class";
    assert _symbol(py, "persist").kind == _symbol(ts, "persist").kind == "method";

    # A TypeScript interface normalises to "class" - the graph has no
    # separate interface concept, by design.
    assert _symbol(ts, "SignupFormProps").kind == "class";

    # An arrow function assigned to a const is still a function.
    assert _symbol(ts, "getUser").kind == "function";

    # Every kind emitted by either language is in the shared vocabulary.
    allowed = ["function", "async_function", "class", "method"];
    for s in _symbols(py) + _symbols(ts) {
        assert s.kind in allowed , f"{s.name} has unknown kind '{s.kind}'";
    }
}

test "graph schema is identical regardless of language" {
    both = _ingest_both();
    for repo in both {
        # Same node types, same edge types, same required fields.
        for f in [repo->:RepositoryContainsFile:->] {
            assert f.path != "";
            assert f.language != "";
            for s in [f->:FileContainsSymbol:->] {
                assert s.name != "";
                assert s.path != "";
                assert s.line > 0 , f"{s.name} has no line number";
                assert s.source != "" , f"{s.name} captured no source";
            }
        }
        # Both must have produced call edges and import edges.
        calls = 0;
        imports = 0;
        for f in [repo->:RepositoryContainsFile:->] {
            imports += len([f->:FileImportsFile:->]);
            for s in [f->:FileContainsSymbol:->] {
                calls += len([s->:SymbolCallsSymbol:->]);
            }
        }
        assert calls > 0 , f"{repo.name} produced no call edges";
        assert imports > 0 , f"{repo.name} produced no import edges";
    }
}

test "typescript imports resolve to files inside the repository" {
    both = _ingest_both();
    ts = both[1];
    by_path: dict[str, File] = {};
    for f in [ts->:RepositoryContainsFile:->] {
        by_path[f.path] = f;
    }

    targets = [
        t.path for t in [by_path["src/services/userService.ts"]->:FileImportsFile:->]
    ];
    targets.sort();
    assert targets == [
        "src/repository/userRepository.ts",
        "src/services/security.ts"
    ] , f"userService imports resolved to {targets}";

    # Bare specifiers ("crypto") are third-party and must NOT become edges.
    sec = [t.path for t in [by_path["src/services/security.ts"]->:FileImportsFile:->]];
    assert sec == [] , f"security.ts should import nothing local, got {sec}";
}

test "the same forward walker traces both languages" {
    both = _ingest_both();

    # Python: snake_case names are unique to the python fixture.
    py_res = (root spawn forward_trace(target_name="create_user")).reports[0];
    assert py_res.status == "ok";
    py_names = [e.node_name for e in py_res.evidence];
    assert "hash_password" in py_names;
    assert "persist" in py_names;
    assert "generate_token" in py_names;

    # TypeScript: camelCase names are unique to the typescript fixture.
    ts_res = (root spawn forward_trace(target_name="createUser")).reports[0];
    assert ts_res.status == "ok";
    ts_names = [e.node_name for e in ts_res.evidence];
    assert "hashPassword" in ts_names;
    assert "persist" in ts_names;
    assert "generateToken" in ts_names;

    # Same engine, same evidence shape.
    for e in ts_res.evidence {
        assert e.node_id != "";
        if e.depth > 0 {
            assert e.edge_type == "SymbolCallsSymbol";
            assert e.from_name != "";
        }
    }
}

test "the same reverse walker traces both languages" {
    both = _ingest_both();

    py_res = (root spawn reverse_trace(target_name="create_user")).reports[0];
    py_callers = [
        e.node_name
        for e in py_res.evidence
        if e.depth == 1
    ];
    py_callers.sort();
    assert py_callers == ["seed_demo_users", "signup"] , f"python blast: {py_callers}";

    ts_res = (root spawn reverse_trace(target_name="createUser")).reports[0];
    ts_callers = [
        e.node_name
        for e in ts_res.evidence
        if e.depth == 1
    ];
    ts_callers.sort();
    assert ts_callers == ["seedDemoUsers", "signup"] , f"typescript blast: {ts_callers}";

    # The .tsx component reaches createUser transitively - cross-file and
    # cross-extension traversal both work.
    ts_all = [e.node_name for e in ts_res.evidence];
    assert "SignupForm" in ts_all , f"tsx caller missing: {ts_all}";
}

test "typescript call attribution matches python semantics" {
    both = _ingest_both();
    ts = both[1];

    # `seedDemoUsers` calls createUser inside `DEMO_USERS.map((raw) => ...)`.
    # An anonymous arrow is not a symbol, so - exactly as Python's ast.walk
    # does - the call belongs to the enclosing named function.
    assert _calls(_symbol(ts, "seedDemoUsers"), "createUser");

    # A method call through an object resolves to the bare method name,
    # matching the python parser's attribute handling.
    assert _calls(_symbol(ts, "createUser"), "persist");
}
