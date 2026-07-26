"""Async handler implementations for App.jac.

SWAP GUIDE — when Ayaan's graph_export endpoint lands, change ONE line here:
  Remove : import from .mock_api { get_repo_graph }
  Add    : sv import from graph_export { get_repo_graph }
All other code in this file stays identical.
"""

import from .mock_api { get_repo_graph }

impl app.loadGraph -> None {
    try {
        result = await get_repo_graph("sample_repo");
        graph = result;
        loading = False;
    } except Exception as e {
        error = str(e);
        loading = False;
    }
}
