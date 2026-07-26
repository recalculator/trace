"""Trace - the code graph schema.

A repository is not a pile of files here; it is a graph. `Repository`,
`File`, `Symbol` and `Route` are the entities, and every relationship
between them is a typed `edge` with declared endpoints - never a list of
strings on a node. Declared endpoints are what let traversals such as
`[f ->:FileContainsSymbol:->]` infer `Symbol` without a per-read filter.

All four entity types share a `CodeEntity` base so that later phases can
resolve any investigation seed with a single `isinstance(target, CodeEntity)`
guard. Every field carries a default: Jac's dataclass machinery requires
that once a parent declares a defaulted field, every child field is
defaulted too - the mismatch passes `jac check` and only crashes at
construction time.
"""

"""Common base for anything that lives in the code graph."""
node CodeEntity {
    has name: str = "",
        path: str = "";
}

"""An ingested repository - the anchor every other node hangs beneath."""
node Repository(CodeEntity) {
    has ingested_at: str = "",
        file_count: int = 0;
}

"""A single source file inside a repository."""
node File(CodeEntity) {
    has language: str = "python";
}

"""A function, async function, class or method defined in a file."""
node Symbol(CodeEntity) {
    has kind: str = "",
        line: int = 0,
        source: str = "";
}

"""An HTTP route declared by a Flask or FastAPI decorator."""
node Route(CodeEntity) {
    has method: str = "",
        pattern: str = "",
        line: int = 0;
}

# --- Edges: every relationship is traversable, and reversible ---

edge RepositoryContainsFile: Repository --> File {}

edge FileContainsSymbol: File --> Symbol {}

edge FileImportsFile: File --> File {}

edge SymbolCallsSymbol: Symbol --> Symbol {
    has line: int = 0;
}

edge RouteHandledBySymbol: Route --> Symbol {}

# A Route is only ever the SOURCE of RouteHandledBySymbol, so nothing in the
# five-edge spec ever points AT it - which would leave every Route node
# unreachable from `root` and therefore never persisted. This sixth edge
# anchors routes to their repository.
edge RepositoryContainsRoute: Repository --> Route {}
