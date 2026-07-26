"""Trace - the language-neutral parser contract.

Everything above this layer (the graph builder, the walkers, the UI) is
language-agnostic. Everything below it is language-specific. The boundary is
`RawModule`: whatever a parser does internally, it must hand back one of
these, and the graph builder never learns which language produced it.

These intermediate types are deliberately free of any parser's node types -
no Python `ast`, no Tree-sitter `Node`. That is what lets a Python function,
a TypeScript function, a Java method and a Go function all land in the graph
as the same `Symbol`.

To add a language: subclass `LanguageParser`, implement `parse_file` and
`module_candidates`, and register it in `langs.jac`. Nothing else changes.
"""

glob MAX_SOURCE_CHARS: int = 1200;

"""A call site found inside a function body, normalised to a bare callee name."""
obj RawCall {
    has name: str = "",
        line: int = 0;
}

"""A callable or type declaration.

`kind` is the normalised vocabulary shared by every language:
  "function"       - a free function            (py def, ts function, go func)
  "async_function" - an async free function     (py async def, ts async function)
  "class"          - a class or interface       (py class, ts class/interface)
  "method"         - a member function          (py method, ts method)
"""
obj RawSymbol {
    has name: str = "",
        kind: str = "",
        line: int = 0,
        source: str = "",
        calls: list[RawCall] = [];
}

"""An HTTP route declaration, however the language spells it."""
obj RawRoute {
    has method: str = "",
        pattern: str = "",
        line: int = 0,
        handler: str = "";
}

"""Everything a parser learned about one source file.

`imports` holds raw, language-specific module specifiers ("services.security",
"./util"). They stay unresolved here on purpose - resolving a specifier to a
file is itself language-specific, so the graph builder asks the owning parser
via `module_candidates`.
"""
obj RawModule {
    has rel_path: str = "",
        name: str = "",
        language: str = "",
        symbols: list[RawSymbol] = [],
        imports: list[str] = [],
        routes: list[RawRoute] = [],
        error: str = "";
}

"""The contract every language implementation fulfils.

The base returns empty results rather than raising, so an unregistered or
half-implemented language degrades to "no symbols found" instead of taking
down an ingestion run.
"""
obj LanguageParser {
    has name: str = "",
        extensions: list[str] = [];

    """True when this parser owns the given file."""
    def handles(filename: str) -> bool {
        for ext in self.extensions {
            if filename.endswith(ext) {
                return True;
            }
        }
        return False;
    }

    """Parse one file into the neutral representation. Never raises."""
    def parse_file(abs_path: str, rel_path: str) -> RawModule {
        return RawModule(rel_path=rel_path, language=self.name);
    }

    """Repo-relative paths an import specifier could refer to, best first."""
    def module_candidates(spec: str, importer_rel: str) -> list[str] {
        return [];
    }
}

"""Truncate captured source so the graph stays light."""
def clip_source(text: str) -> str {
    if len(text) > MAX_SOURCE_CHARS {
        return text[:MAX_SOURCE_CHARS];
    }
    return text;
}
