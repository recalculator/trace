# Trace

Ask a question about a codebase in English. Get an answer backed by the code graph, with every claim traceable to a node or an edge.

Trace ingests a repository into an Object-Spatial graph, then answers questions by walking it. A language model may choose *which* investigation to run; it never traverses the graph, never sees source code, and never produces evidence. Traversal is deterministic Jac walkers, end to end.

## Quickstart

```bash
jac install                     # dependencies from jac.toml
export ANTHROPIC_API_KEY=...    # optional - see "Without a key" below
jac start --port 8300           # serves the UI and the API at /
```

Open <http://127.0.0.1:8300>, point it at a local path or a public GitHub URL, and ask.

## How it works

```
question
   -> planner        picks tools from a fixed allowlist        (LLM optional)
   -> validator      rejects anything not in the graph         (deterministic)
   -> executor       spawns the real walkers                   (deterministic)
   -> evidence       graph facts, each carrying its own jid
   -> explainer      prose from evidence alone                 (LLM optional)
```

A plan is **data**, never code. It names tools from a registry of ten and the arguments they take; it can never name a walker or a Jac expression. The worst a bad or adversarial plan can do is fail validation.

**Ingestion** is one universal Tree-sitter walker driven by declarative `LanguageSpec`s (`lang_python.jac`, `lang_typescript.jac`). Adding a language is a spec, not a parser.

**The graph** holds `Repository`, `File`, `Symbol` and `Route` nodes, linked by edges including `SymbolCallsSymbol`, `RouteHandledBySymbol` and `RepositoryContainsRoute`. Symbol resolution is repository-scoped; identical names across repositories resolve correctly, and ambiguity is surfaced to the caller rather than silently resolved.

**Investigation** is two walkers over one shared base — `forward_trace` (what does this reach?) and `reverse_trace` (what depends on this?) — plus route-anchored tracing that follows an HTTP endpoint through its handler to the data layer.

## Without a key

Everything works. The planner falls back to a deterministic phrase/token matcher and the explanation is generated from evidence alone. Missing key, timeout, rate limit, malformed JSON, a refusal, a rejected plan — every one of them lands on the deterministic path. You never lose functionality because the model was unavailable.

`ANTHROPIC_API_KEY` is the only environment variable the application reads, and it is read from the environment only — never from a file, an argument or a config entry. Copy `.env.example` to `.env` (gitignored) to keep it out of shell history.

## Tools

The planner may request exactly these, and nothing else:

| Tool | Target | What it does |
|---|---|---|
| `find_symbol` | symbol | Where a symbol is defined |
| `inspect_symbol` | symbol | Kind, file, line, immediate neighbours |
| `find_callees` | symbol | What it calls, one hop |
| `find_callers` | symbol | What calls it, one hop |
| `trace_call_flow` | symbol | Execution forward through the call graph |
| `impact_analysis` | symbol | Everything transitively depending on it |
| `dependency_analysis` | symbol | Which files its file imports |
| `trace_from_route` | route | An endpoint through its handler to the data layer |
| `find_routes` | — | Every HTTP route and its handler |
| `repo_summary` | — | Counts of files, symbols and routes |

Whether a question needs a symbol, a route, or nothing is a property of the **tool**, recorded as `target_kind`. A question is never rejected for lacking a symbol unless the selected tool actually requires one.

## API

| Endpoint | Purpose |
|---|---|
| `POST /function/investigate` | Question in, evidence out (the UI's path) |
| `POST /function/ask` | The full planner pipeline, with explanation |
| `POST /function/ingest_repo` | Ingest a local path |
| `POST /function/get_repo_graph` | Flat graph for rendering |
| `GET /graph` | Graph viewer |

## Development

```bash
jac check .            # type-check every module
jac test -d tests/     # 127 tests, no network required
jac fmt <files>        # format
```

Tests never call a live model: the planner's single network call is isolated behind an overridable method, so success, retries, malformed output, timeouts and refusals are all exercised with no key and no network.

**One trap worth knowing.** `main.jac` is the `[serve] base_route_app` module, so any unused archetype import there compiles into the client entry as `__na_bind(...)` from `@jac/wasm_host`, which Rollup cannot resolve — the client bundle fails to build and `/` serves 503. Neither `jac check` nor `jac test` catches it; only an actual client build does. If `/` returns 503, look at `main.jac`'s imports first.

Equally: `jac start` holds the graph in a long-lived process. After changing server code, **restart it** — a stale process will happily serve code from before your fix.

## Layout

| Path | Contents |
|---|---|
| `ingestion.jac`, `universal_walker.jac`, `lang_*.jac` | Repository to graph |
| `investigation.jac` | The traversal walkers |
| `plan_types.jac`, `planner*.jac` | Plan schema, tool registry, planners |
| `executor.jac`, `explainer.jac` | Validation, execution, explanation |
| `investigation_api.jac`, `graph_export.jac` | Endpoints the client calls |
| `client/`, `pages/` | UI |
| `sample_repo/`, `sample_repo_ts/` | Fixtures the tests assert against |
