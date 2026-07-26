# `get_repo_graph` wire shape

**Status:** proposed by @dide1 — needs one-line confirm from @recalculator before landing.  
**Pending:** Ayaan's `graph_export.jac` and registration of `get_repo_graph` in `main.jac`.  
**Jac types:** `client/types.jac`

---

## Endpoint

```
POST /function/get_repo_graph
Body: { "name": "<repository-name>" }
```

Returns a `RepoGraph` — a flat snapshot of all nodes and edges in the named
repository subgraph. The client uses this for the live graph visualisation.

---

## `RepoGraph`

| field   | type            |
|---------|-----------------|
| `nodes` | `list[GraphNode]` |
| `edges` | `list[GraphEdge]` |

---

## `GraphNode`

One object covers all four node types. Type-specific fields default to `""` /
`0` for node types that don't have them — the client discriminates on
`node_type`.

| field         | type  | source in `models.jac`     | present on           |
|---------------|-------|----------------------------|----------------------|
| `id`          | `str` | `jid(node)`                | all                  |
| `node_type`   | `str` | archetype name             | all                  |
| `name`        | `str` | `CodeEntity.name`          | all                  |
| `path`        | `str` | `CodeEntity.path`          | all                  |
| `ingested_at` | `str` | `Repository.ingested_at`   | `Repository` only    |
| `file_count`  | `int` | `Repository.file_count`    | `Repository` only    |
| `language`    | `str` | `File.language`            | `File` only          |
| `kind`        | `str` | `Symbol.kind`              | `Symbol` only        |
| `line`        | `int` | `Symbol.line`, `Route.line`| `Symbol`, `Route`    |
| `source`      | `str` | `Symbol.source`            | `Symbol` only (≤1200 chars) |
| `method`      | `str` | `Route.method`             | `Route` only         |
| `pattern`     | `str` | `Route.pattern`            | `Route` only         |

`node_type` values: `"Repository"` · `"File"` · `"Symbol"` · `"Route"`

`Symbol.kind` values: `"function"` · `"async_function"` · `"class"` · `"method"`

`Route.method` values: `"GET"` · `"POST"` · `"PUT"` · `"PATCH"` · `"DELETE"` · etc.

---

## `GraphEdge`

| field       | type  | source in `models.jac`         | present on                  |
|-------------|-------|--------------------------------|-----------------------------|
| `id`        | `str` | `jid(edge)`                    | all                          |
| `edge_type` | `str` | archetype name                 | all                          |
| `source`    | `str` | source node `jid`              | all                          |
| `target`    | `str` | target node `jid`              | all                          |
| `line`      | `int` | `SymbolCallsSymbol.line`       | `SymbolCallsSymbol` only     |

`edge_type` values:
- `"RepositoryContainsFile"`
- `"FileContainsSymbol"`
- `"FileImportsFile"`
- `"SymbolCallsSymbol"`
- `"RouteHandledBySymbol"`
- `"RepositoryContainsRoute"`

---

## Notes

- All `id` values are stable `jid()` strings — use them as React `key` props
  and for highlight lookups during investigation animations.
- `GraphEdge.source` / `.target` are node ids, not the same as `GraphNode.source`
  (which is symbol source code). Different fields on different types — no collision.
- The `source` field on `GraphNode` (Symbol source text) can be up to 1200 chars;
  the visualisation should truncate or hide it by default.
- Investigation endpoints (`forward_trace`, `reverse_trace`, `find_symbol`)
  return node/edge id sets that index into this graph — the client highlights
  matching nodes/edges in-place rather than receiving a second graph.

---

## Swap guide (one line per call site in `client/App.impl.jac`)

| Phase | Import line |
|-------|------------|
| Mock (now) | `import from .mock_api { get_repo_graph }` |
| Real (after merge) | `sv import from graph_export { get_repo_graph }` |
