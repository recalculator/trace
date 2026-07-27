"""Trace - entry module.

Every endpoint Trace exposes must be named in this module's import list:
Jac registers `def:pub` functions at `/function/<name>` and walkers at
`/walker/<name>`, and registration tracks the exact name. An endpoint that
exists but is not imported here returns 405.

  jac start                 serve the API
  jac run main.jac          ingest ./sample_repo and print the graph counts
  jac dot main.jac -o g.dot render the resulting graph
"""

# NOTE: the `models` archetypes are deliberately NOT imported here. This
# module now carries a client section, and a bare `import from models`
# makes the compiler emit a native binding for those names into the client
# bundle (`__na_bind` -> `@jac/wasm_host`), which Rollup cannot resolve.
# The archetypes are registered via `ingestion` / `graph_export` /
# `investigation`, which import them server-side.

import from ingestion {
    IngestSummary,
    GraphStats,
    ingest_repo,
    list_repositories,
    reset_graph,
    graph_summary
}

import from investigation {
    Evidence,
    InvestigationContext,
    InvestigationResult,
    SymbolMatch,
    find_symbol,
    forward_trace,
    reverse_trace
}

import from graph_export { get_repo_graph }

import from investigation_api { investigate }

import from github_ingest { CloneResult, analyze_github_repo, cleanup_clones }

# NOTE: do not import archetypes from `plan_types` here. `main.jac` is the
# `[serve] base_route_app` module, so the client compiler emits an unused
# archetype import as `__na_bind(...)` from `@jac/wasm_host`, which Rollup
# cannot resolve - the client bundle then fails to build and `/` serves 503.
# The plan archetypes register via the modules that actually use them
# (`planner_api`, `executor`, `investigation_api`). Same reason the `models`
# import was removed from this file earlier.
import from planner_api { ask, plan_only, run_plan }

# --- Client mount. The JSX below infers this section client-side; the
#     runtime mounts the literal name `app`, and `[serve] base_route_app`
#     in jac.toml serves it at `/`. ---
import from .client.App { app as ClientApp }

def:pub app -> JsxElement {
    return <ClientApp/>;
}

glob SAMPLE_REPO: str = "sample_repo";

with entry:__main__ {
    summary = ingest_repo(SAMPLE_REPO, name="sample_repo");

    print(f"repository      : {summary.repo_name}");
    print(f"path            : {summary.repo_path}");
    print(f"files           : {summary.files}");
    print(f"symbols         : {summary.symbols}");
    print(f"routes          : {summary.routes}");
    print("--- edges ---");
    print(f"RepositoryContainsFile  : {summary.contains_file_edges}");
    print(f"FileContainsSymbol      : {summary.contains_symbol_edges}");
    print(f"FileImportsFile         : {summary.import_edges}");
    print(f"SymbolCallsSymbol       : {summary.call_edges}");
    print(f"RouteHandledBySymbol    : {summary.route_edges}");
    print(f"unresolved call sites   : {summary.unresolved_calls}");

    if summary.parse_errors {
        print("--- parse errors ---");
        for err in summary.parse_errors {
            print(f"  {err}");
        }
    }

    # Read the counts back by traversing the graph, independent of the ingester.
    walked = root spawn graph_summary();
    stats = walked.reports[0];
    print("--- verified by traversal ---");
    print(
        f"repositories={stats.repositories} files={stats.files} "
        f"symbols={stats.symbols} routes={stats.routes}"
    );
}
