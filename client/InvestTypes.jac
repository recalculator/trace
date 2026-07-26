obj InvestStep {
    has step_name: str = "",
        status: str = "pending",
        timestamp: str = "",
        node_ids: list[str] = [],
        edge_ids: list[str] = [];
}
