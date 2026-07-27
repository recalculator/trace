"""Trace - Python language mapping.

Data only. Every entry names a Tree-sitter node type or field from the
`tree-sitter-python` grammar. There is no parsing code in this file.
"""

import tree_sitter_python as tsp;

import from lang_spec {
    CallRule,
    ImportRule,
    LanguageSpec,
    ResolveRule,
    RouteRule,
    SymbolRule
}

glob PYTHON_SPEC: LanguageSpec = LanguageSpec(
         name="python",
         extensions=[".py"],
         grammar=tsp.language,
         # `@decorator` + `def f(): ...` is one `decorated_definition` node.
         unwrap_types=["decorated_definition"],
         declaration_field="definition",
         body_field="body",
         async_marker="async",
         symbol_rules=[
             SymbolRule(
                 node_types=["function_definition"], kind="function", name_field="name"
             ),
             SymbolRule(
                 node_types=["class_definition"],
                 kind="class",
                 name_field="name",
                 member_types=["function_definition"],
                 member_kind="method",
                 # A class's own calls belong to its methods, which are emitted
                 # separately; collecting here would double-count them.
                 collect_calls=False
             )
         ],
         call_rule=CallRule(
             node_types=["call"],
             callee_field="function",
             plain_types=["identifier"],
             # `service.create_user()` -> "create_user"
             member_types=["attribute"],
             member_field="attribute"
         ),
         import_rules=[
             ImportRule(
                 node_types=["import_statement"],
                 module_types=["dotted_name", "aliased_import"]
             ),
             ImportRule(
                 node_types=["import_from_statement"],
                 module_types=["dotted_name", "relative_import"],
                 member_types=["dotted_name"],
                 # `from repository import db` should also try "repository.db".
                 expand_members=True
             )
         ],
         route_rule=RouteRule(
             wrapper_type="decorated_definition",
             marker_type="decorator",
             call_type="call",
             callee_field="function",
             member_field="attribute",
             arguments_field="arguments",
             string_types=["string"],
             keyword_type="keyword_argument",
             verbs=["get", "post", "put", "patch", "delete", "head", "options"],
             any_verb="route",
             methods_keyword="methods"
         ),
         resolve=ResolveRule(
             separator=".",
             extensions=[".py"],
             index_names=["__init__.py"],
             relative_marker=".",
             allow_bare=True,
             path_relative=False
         )
     );
