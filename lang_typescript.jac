"""Trace - TypeScript / TSX language mapping.

Data only. `.tsx` needs a different grammar from `.ts` (JSX ambiguity), which
is why `grammar_by_extension` exists - it is still configuration, not a
branch in the walker.
"""

import tree_sitter_typescript as tsts;

import from lang_spec {
    CallRule,
    ImportRule,
    LanguageSpec,
    ResolveRule,
    RouteRule,
    SymbolRule
}

glob TYPESCRIPT_SPEC: LanguageSpec = LanguageSpec(
         name="typescript",
         extensions=[".ts", ".tsx"],
         grammar=tsts.language_typescript,
         grammar_by_extension={".tsx": tsts.language_tsx},
         # `export function f() {}` wraps the declaration.
         unwrap_types=["export_statement"],
         declaration_field="declaration",
         body_field="body",
         async_marker="async",
         symbol_rules=[
             SymbolRule(
                 node_types=["function_declaration", "generator_function_declaration"],
                 kind="function",
                 name_field="name"
             ),
             SymbolRule(
                 node_types=["class_declaration", "interface_declaration"],
                 kind="class",
                 name_field="name",
                 member_types=["method_definition", "method_signature"],
                 member_kind="method",
                 collect_calls=False
             ),
             # `const handler = () => {}` - the declarator carries the name and
             # the function body, so it behaves as one declaration.
             SymbolRule(
                 node_types=["lexical_declaration", "variable_declaration"],
                 kind="function",
                 name_field="name",
                 member_types=["variable_declarator"],
                 member_kind="function",
                 collect_calls=False,
                 # A `const` statement is not itself a function - only the
                 # declarators that bind a function literal are.
                 emit_self=False,
                 value_field="value",
                 value_types=["arrow_function", "function_expression"]
             )
         ],
         call_rule=CallRule(
             node_types=["call_expression"],
             callee_field="function",
             plain_types=["identifier"],
             # `service.createUser()` -> "createUser"
             member_types=["member_expression"],
             member_field="property"
         ),
         import_rules=[
             ImportRule(
                 node_types=["import_statement", "export_statement"],
                 source_field="source"
             )
         ],
         resolve=ResolveRule(
             separator="/",
             extensions=[".ts", ".tsx"],
             index_names=["index.ts", "index.tsx"],
             relative_marker=".",
             # Bare specifiers ("react", "@scope/pkg") are third-party.
             allow_bare=False,
             path_relative=True
         )
     );
