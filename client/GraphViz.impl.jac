# `GraphNode` is NOT re-imported here: an impl annex already sees its head
# module's imports (GraphViz.jac line 1), and re-importing emits a duplicate
# `import { GraphNode }` into the merged GraphViz.js - a hard JS
# "already declared" error once the client bundle is actually built.

impl GraphViz.layout_graph -> None {
    W: float = 1100.0;

    # Partition nodes by type
    repos: list[GraphNode] = [
        n
        for n in graph.nodes
        if n.node_type == "Repository"
    ];
    files: list[GraphNode] = [
        n
        for n in graph.nodes
        if n.node_type == "File"
    ];
    syms: list[GraphNode] = [
        n
        for n in graph.nodes
        if n.node_type == "Symbol"
    ];
    routes: list[GraphNode] = [
        n
        for n in graph.nodes
        if n.node_type == "Route"
    ];

    # Build symbol → parent-file map from FileContainsSymbol edges
    sym_file: dict = {};
    for edge in graph.edges {
        if edge.edge_type == "FileContainsSymbol" {
            sym_file[edge.target] = edge.source;
        }
    }

    # Repository: top centre
    n_repos: int = len(repos);
    for (i, nd) in enumerate(repos) {
        px: float = W / 2.0;
        if n_repos > 1 {
            px = (i as float + 1.0) * W / (n_repos as float + 1.0);
        }
        pos_x[nd.id] = px;
        pos_y[nd.id] = 52.0;
    }

    # Files: y = 155, evenly spaced across width
    n_files: int = len(files);
    for (i, f) in enumerate(files) {
        pos_x[f.id] = (i as float + 1.0) * W / (n_files as float + 1.0);
        pos_y[f.id] = 155.0;
    }

    # Symbols: clustered below their parent file, up to 4 per row
    for f in files {
        fx: float = pos_x[f.id] as float;

        # Collect this file's symbols by scanning the sym_file map
        fsyms: list[str] = [];
        for sym in syms {
            fid: str = "";
            if sym.id in sym_file {
                fid = sym_file[sym.id] as str;
            }
            if fid == f.id {
                fsyms = fsyms + [sym.id];
            }
        }

        n_fs: int = len(fsyms);
        cols: int = 4;
        for (j, sid) in enumerate(fsyms) {
            col_j: int = j % cols;
            row_j: int = j // cols;
            n_in_row: int = n_fs - row_j * cols;
            if n_in_row > cols {
                n_in_row = cols;
            }
            col_offset: float = (
                (col_j as float) - ((n_in_row as float) - 1.0) / 2.0
            ) * 26.0;
            pos_x[sid] = fx + col_offset;
            pos_y[sid] = 285.0 + (row_j as float) * 68.0;
        }
    }

    # Routes: bottom row, evenly spaced
    n_routes: int = len(routes);
    for (i, nd) in enumerate(routes) {
        pos_x[nd.id] = (i as float + 1.0) * W / (n_routes as float + 1.0);
        pos_y[nd.id] = 618.0;
    }

    simulated = True;
}
