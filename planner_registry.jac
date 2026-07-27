"""Trace - planner selection.

One place that answers "which planner should run?", so the endpoint does not
have to know what planners exist. Adding OpenAI, Gemini or a local model is a
new `Planner` subclass plus one branch here - no caller changes.

Selection is deliberately conservative: "auto" prefers Claude only when a key
is actually present, and every unrecognised name resolves to the
deterministic planner rather than raising. A misconfigured strategy must
degrade, not break the product.
"""

import from planner { DeterministicPlanner, FakePlanner, Planner }
import from planner_anthropic { AnthropicPlanner, has_api_key }

"""The strategies `ask()` accepts, in the order they are offered."""
glob PLANNER_NAMES: list[str] = ["auto", "anthropic", "deterministic"];

"""The planner for a strategy name.

"auto"          - Claude when ANTHROPIC_API_KEY is set, deterministic otherwise
"anthropic"     - Claude, which itself falls back when the key or API is absent
"deterministic" - pinned to the local planner, never touches the network
"""
def select_planner(name: str = "auto") -> Planner {
    choice = (name or "auto").strip().lower();
    if choice == "deterministic" {
        return DeterministicPlanner();
    }
    if choice == "anthropic" {
        # Explicitly requested: construct it even without a key, so its own
        # warning-and-fall-back path runs and the caller sees why.
        return AnthropicPlanner();
    }
    if choice == "auto" and has_api_key() {
        return AnthropicPlanner();
    }
    return DeterministicPlanner();
}

"""True when "auto" would currently route to a model rather than the fallback."""
def llm_planning_available() -> bool {
    return has_api_key();
}
