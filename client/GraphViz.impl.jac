# `GraphNode` is NOT re-imported here: an impl annex already sees its head
# module's imports (GraphViz.jac line 1), and re-importing emits a duplicate
# `import { GraphNode }` into the merged GraphViz.js - a hard JS
# "already declared" error once the client bundle is actually built.

impl GraphViz.layout_graph -> None {
    cols: int = 4;
    col_gap: float = 36.0;
    row_gap: float = 58.0;
    sym_top: float = 300.0;

    # Cluster half-width: (cols-1)/2 * col_gap + node radius
    cluster_hw: float = ((cols as float - 1.0) / 2.0) * col_gap + 12.0;
    min_file_spacing: float = cluster_hw * 2.0 + 28.0;

    n_files_est: int = len([n for n in graph.nodes if n.node_type == "File"]);
    W: float = 1200.0;
    if n_files_est > 1 {
        W_needed: float = min_file_spacing * (n_files_est as float - 1.0) + 120.0;
        if W_needed > W { W = W_needed; }
    }
    canvas_w = W;

    # ── Partition nodes by type ──
    repos: list[GraphNode] = [n for n in graph.nodes if n.node_type == "Repository"];
    files: list[GraphNode] = [n for n in graph.nodes if n.node_type == "File"];
    syms: list[GraphNode]  = [n for n in graph.nodes if n.node_type == "Symbol"];
    routes: list[GraphNode] = [n for n in graph.nodes if n.node_type == "Route"];

    # ─��� Build symbol → parent-file map from FileContainsSymbol edges ──
    sym_file: dict = {};
    for edge in graph.edges {
        if edge.edge_type == "FileContainsSymbol" {
            sym_file[edge.target] = edge.source;
        }
    }

    # ── Repository: top centre, spread if multiple ──
    n_repos: int = len(repos);
    for (i, nd) in enumerate(repos) {
        px: float = W / 2.0;
        if n_repos > 1 {
            px = (i as float + 1.0) * W / (n_repos as float + 1.0);
        }
        pos_x[nd.id] = px;
        pos_y[nd.id] = 60.0;
    }

    # ── Files: spread across width at y=175, guaranteed non-overlapping clusters ──
    n_files: int = len(files);
    file_spacing: float = min_file_spacing;
    if n_files > 1 {
        avail: float = W - 80.0;
        file_spacing = avail / (n_files as float - 1.0);
        if file_spacing < min_file_spacing { file_spacing = min_file_spacing; }
    }
    file_start: float = W / 2.0 - file_spacing * ((n_files as float - 1.0) / 2.0);
    for (i, f) in enumerate(files) {
        pos_x[f.id] = file_start + (i as float) * file_spacing;
        pos_y[f.id] = 175.0;
    }

    # ── Symbols: clustered below their parent file ──

    for f in files {
        fx: float = pos_x[f.id] as float;

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
        for (j, sid) in enumerate(fsyms) {
            col_j: int = j % cols;
            row_j: int = j // cols;
            n_in_row: int = n_fs - row_j * cols;
            if n_in_row > cols { n_in_row = cols; }
            col_offset: float = (
                (col_j as float) - ((n_in_row as float) - 1.0) / 2.0
            ) * col_gap;
            pos_x[sid] = fx + col_offset;
            pos_y[sid] = sym_top + (row_j as float) * row_gap;
        }
    }

    # ── Symbols with no parent file: row at bottom of symbol band ──
    orphans: list[str] = [];
    for sym in syms {
        if sym.id not in sym_file {
            orphans = orphans + [sym.id];
        }
    }
    n_orphans: int = len(orphans);
    orphan_top: float = sym_top + 260.0;
    for (i, sid) in enumerate(orphans) {
        pos_x[sid] = (i as float + 1.0) * W / (n_orphans as float + 1.0);
        pos_y[sid] = orphan_top;
    }

    # ── Routes: bottom row ──
    n_routes: int = len(routes);
    route_y: float = 660.0;
    for (i, nd) in enumerate(routes) {
        pos_x[nd.id] = (i as float + 1.0) * W / (n_routes as float + 1.0);
        pos_y[nd.id] = route_y;
    }

    simulated = True;
}
