"""Trace - entry module.

Every endpoint Trace exposes must be named in this module's import list:
Jac registers `def:pub` functions at `/function/<name>` and walkers at
`/walker/<name>`, and registration tracks the exact name. An endpoint that
exists but is not imported here returns 405.

  jac start                 serve the API
  jac run main.jac          ingest ./sample_repo and print the graph counts
  jac dot main.jac -o g.dot render the resulting graph
"""

import from models { Repository, File, Symbol, Route }

import from ingestion {
    IngestSummary,
    GraphStats,
    ingest_repo,
    list_repositories,
    reset_graph,
    graph_summary
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
