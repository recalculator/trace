"""Trace - the declarative language specification.

A `LanguageSpec` is DATA. It names Tree-sitter node types and fields; it
contains no logic, no conditionals and no language name outside its own
`name` field. `universal_walker.jac` interprets one of these to turn any
Tree-sitter parse tree into the normalised IR.

Adding a language means writing one of these plus a grammar loader. It does
not mean writing a walker.

The vocabulary is deliberately small. Anything a spec cannot express is a
real limit of the design, documented rather than papered over with a
language check in the walker.
"""

"""How one family of declaration nodes becomes symbols.

`node_types`   Tree-sitter types that declare this concept.
`kind`         normalised kind emitted into RawSymbol.
`name_field`   field holding the declared name.
`member_types` node types inside the body that become symbols in their own
               right (a class's methods). Empty for non-containers.
`member_kind`  kind emitted for those members.
`collect_calls` False for containers whose members own the call sites, so a
               class does not double-count every method's calls.
`emit_self`    False when the container itself is not a symbol and only its
               members are (`const a = () => {}` - the declaration statement
               is not a function, the declarator is).
`value_field`  when a member holds its callable under another field rather
               than directly (a declarator's `value`), the field to follow
               before looking for the body.
`value_types`  restricts which member values qualify, so a plain `const x = 1`
               does not become a function.
"""
obj SymbolRule {
    has node_types: list[str] = [],
        kind: str = "",
        name_field: str = "name",
        member_types: list[str] = [],
        member_kind: str = "method",
        collect_calls: bool = True,
        emit_self: bool = True,
        value_field: str = "",
        value_types: list[str] = [];
}

"""How call expressions expose their callee.

`node_types`   Tree-sitter types that are calls.
`callee_field` field holding the thing being called.
`plain_types`  callee node types whose whole text is the name (`identifier`).
`member_field` on a qualified callee (`a.b.c()`), the field holding the
               trailing member. Both Python's `attribute` and TypeScript's
               `member_expression` expose it, under different field names.
`member_types` callee node types to read `member_field` from.
"""
obj CallRule {
    has node_types: list[str] = [],
        callee_field: str = "function",
        plain_types: list[str] = ["identifier"],
        member_types: list[str] = [],
        member_field: str = "";
}

"""How import statements expose the module they refer to.

Two shapes cover every language checked so far:

  string  - the target is a quoted literal in one field (TypeScript, Rust,
            Go). Set `source_field` and `strip_chars`.
  parts   - the target is a sequence of child nodes, optionally followed by
            imported member names that are themselves worth resolving
            (Python, Java). Set `module_types` / `member_types`.

Both can be declared at once; the walker uses whichever matches the node.
"""
obj ImportRule {
    has node_types: list[str] = [],
        source_field: str = "",
        strip_chars: str = "\"'`",
        module_types: list[str] = [],
        member_types: list[str] = [],
        expand_members: bool = False;
}

"""How a decorator/annotation declares an HTTP route.

`wrapper_type`  node that pairs a decoration with the declaration it
                decorates (Python's `decorated_definition`).
`marker_type`   the decoration node itself.
`verb_field` /  where the verb lives on the decorator's call expression.
`pattern is the first string argument.
`verbs`         decorator names that ARE the HTTP method.
`any_verb`      decorator name that takes the method as a keyword argument.
`methods_keyword` that keyword's name.
"""
obj RouteRule {
    has wrapper_type: str = "",
        marker_type: str = "",
        call_type: str = "",
        callee_field: str = "function",
        member_field: str = "",
        arguments_field: str = "arguments",
        string_types: list[str] = [],
        keyword_type: str = "",
        verbs: list[str] = [],
        any_verb: str = "",
        methods_keyword: str = "methods";
}

"""How an import specifier maps onto repo-relative file paths."""
obj ResolveRule {
    has separator: str = ".",
        extensions: list[str] = [],
        index_names: list[str] = [],
        relative_marker: str = "",
        allow_bare: bool = True,
        path_relative: bool = False;
}

"""Everything the universal walker needs to read one language.

`grammar` is the only executable member: a zero-argument callable returning
the Tree-sitter language handle. Everything else is data.
"""
obj LanguageSpec {
    has name: str = "",
        extensions: list[str] = [],
        grammar: any = None,
        grammar_by_extension: dict[str, any] = {},
        unwrap_types: list[str] = [],
        declaration_field: str = "declaration",
        body_field: str = "body",
        async_marker: str = "async",
        symbol_rules: list[SymbolRule] = [],
        call_rule: CallRule = CallRule(),
        import_rules: list[ImportRule] = [],
        route_rule: RouteRule = RouteRule(),
        resolve: ResolveRule = ResolveRule();
}
