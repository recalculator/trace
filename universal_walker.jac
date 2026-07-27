"""Trace - the universal AST walker.

ONE walker for every language. It operates on generic Tree-sitter nodes and
takes all of its behaviour from a `LanguageSpec`. There is no language name,
no `if language == ...`, and no `visit_<language>` anywhere in this file -
that is the property worth preserving when extending it.

Everything it knows how to do is expressed in terms of the spec's vocabulary:
which node types declare symbols, which are calls, which are imports, which
field holds a name. Swap the spec and the same code reads a different
language.
"""

import os;

import from tree_sitter { Language, Parser }
import from lang_spec { CallRule, ImportRule, LanguageSpec, RouteRule, SymbolRule }
import from parser_types { RawCall, RawModule, RawRoute, RawSymbol, clip_source }

"""Parsers are cached per spec+extension: building a Language is expensive."""
glob PARSER_CACHE: dict[str, any] = {};

# --- Generic node helpers. None of these know a language. ---

"""Decoded source text of a node."""
def node_text(nd: any) -> str {
    return nd.text.decode("utf-8", "replace") as str;
}

"""1-based start line of a node."""
def node_line(nd: any) -> int {
    return (nd.start_point[0] as int) + 1;
}

"""Value of a named field, or None."""
def field(nd: any, name: str) -> any {
    if not name {
        return None;
    }
    return nd.child_by_field_name(name);
}

"""Text of a named field, or ""."""
def field_text(nd: any, name: str) -> str {
    f = field(nd, name);
    if f is None {
        return "";
    }
    return node_text(f);
}

"""Direct children whose type is in `types`."""
def children_of_type(nd: any, types: list[str]) -> list[any] {
    out: list[any] = [];
    for c in nd.children {
        if (c.type as str) in types {
            out.append(c);
        }
    }
    return out;
}

"""True when the node has a direct child token equal to `marker`."""
def has_marker(nd: any, marker: str) -> bool {
    if not marker {
        return False;
    }
    for c in nd.children {
        if (c.type as str) == marker {
            return True;
        }
    }
    return False;
}

"""Every descendant of `nd`, `nd` itself first."""
def descendants(nd: any) -> list[any] {
    out: list[any] = [];
    stack: list[any] = [nd];
    while stack {
        cur = stack.pop();
        out.append(cur);
        for c in cur.children {
            stack.append(c);
        }
    }
    return out;
}

# --- Spec-driven extraction ---

"""Bare callee name for one call node, per the spec's call rule."""
def callee_name(nd: any, rule: CallRule) -> str {
    fn = field(nd, rule.callee_field);
    if fn is None {
        return "";
    }
    kind = fn.type as str;
    if kind in rule.plain_types {
        return node_text(fn);
    }
    if kind in rule.member_types {
        member = field(fn, rule.member_field);
        if member is not None {
            return node_text(member);
        }
    }
    return "";
}

"""Every call made anywhere beneath `scope`.

Descends into nested closures on purpose: an anonymous function is not a
symbol, so its calls belong to the enclosing named one. Both currently
registered languages agree on this, and it is what keeps their graphs
comparable.
"""
def calls_in(scope: any, rule: CallRule) -> list[RawCall] {
    out: list[RawCall] = [];
    for nd in descendants(scope) {
        if (nd.type as str) in rule.node_types {
            name = callee_name(nd, rule);
            if name {
                out.append(RawCall(name=name, line=node_line(nd)));
            }
        }
    }
    return out;
}

"""Strip a declaration out of any wrapper nodes (decorators, `export`)."""
def unwrap(nd: any, spec: LanguageSpec) -> any {
    cur = nd;
    guard = 0;
    while (cur.type as str) in spec.unwrap_types and guard < 8 {
        guard += 1;
        inner = field(cur, spec.declaration_field);
        if inner is not None {
            cur = inner;
            continue;
        }
        # No declaration field: take the last non-decoration child.
        picked: any = None;
        for c in cur.children {
            ctype = c.type as str;
            if ctype != spec.route_rule.marker_type and c.is_named {
                picked = c;
            }
        }
        if picked is None {
            return cur;
        }
        cur = picked;
    }
    return cur;
}

"""The symbol rule matching a node type, or None."""
def rule_for(node_type: str, spec: LanguageSpec) -> SymbolRule | None {
    for r in spec.symbol_rules {
        if node_type in r.node_types {
            return r;
        }
    }
    return None;
}

"""Import specifiers declared by one node, per one import rule."""
def imports_from(nd: any, rule: ImportRule) -> list[str] {
    out: list[str] = [];

    # Shape 1: a quoted literal in a named field.
    if rule.source_field {
        src = field(nd, rule.source_field);
        if src is not None {
            out.append(node_text(src).strip(rule.strip_chars));
            return out;
        }
    }

    # Shape 2: the module is the first matching child; later matching
    # children are imported members worth resolving in their own right.
    if rule.module_types {
        parts = children_of_type(nd, rule.module_types);
        members = children_of_type(nd, rule.member_types);
        if not parts {
            return out;
        }
        base = node_text(parts[0]);
        out.append(base);
        if rule.expand_members {
            for m in members {
                text = node_text(m);
                if text == base {
                    continue;
                }
                joined = base + "." + text if not base.endswith(".") else base + text;
                out.append(joined);
            }
        }
    }
    return out;
}

"""Every import specifier in a file."""
def collect_imports(tree_root: any, spec: LanguageSpec) -> list[str] {
    out: list[str] = [];
    for nd in descendants(tree_root) {
        ntype = nd.type as str;
        for rule in spec.import_rules {
            if ntype in rule.node_types {
                for spec_str in imports_from(nd, rule) {
                    if spec_str {
                        out.append(spec_str);
                    }
                }
            }
        }
    }
    return out;
}

"""Routes declared by the decorations attached to one wrapper node."""
def routes_from(wrapper: any, handler: str, rule: RouteRule) -> list[RawRoute] {
    out: list[RawRoute] = [];
    if not rule.wrapper_type {
        return out;
    }
    for marker in children_of_type(wrapper, [rule.marker_type]) {
        for call in descendants(marker) {
            if (call.type as str) != rule.call_type {
                continue;
            }
            fn = field(call, rule.callee_field);
            if fn is None {
                continue;
            }
            verb = field_text(fn, rule.member_field);
            if not verb {
                continue;
            }

            args = field(call, rule.arguments_field);
            if args is None {
                continue;
            }
            pattern = "";
            for a in args.children {
                if (a.type as str) in rule.string_types {
                    pattern = node_text(a).strip("\"'`");
                    break;
                }
            }
            if not pattern {
                continue;
            }

            lowered = verb.lower();
            if lowered in rule.verbs {
                out.append(
                    RawRoute(
                        method=lowered.upper(),
                        pattern=pattern,
                        line=node_line(call),
                        handler=handler
                    )
                );
            } elif lowered == rule.any_verb {
                method = "GET";
                for kw in descendants(args) {
                    if (kw.type as str) != rule.keyword_type {
                        continue;
                    }
                    if field_text(kw, "name") != rule.methods_keyword {
                        continue;
                    }
                    value = field(kw, "value");
                    if value is None {
                        continue;
                    }
                    for lit in descendants(value) {
                        if (lit.type as str) in rule.string_types {
                            method = node_text(lit).strip("\"'`").upper();
                        }
                    }
                }
                out.append(
                    RawRoute(
                        method=method,
                        pattern=pattern,
                        line=node_line(call),
                        handler=handler
                    )
                );
            }
        }
    }
    return out;
}

"""Build one RawSymbol from a declaration node."""
def make_symbol(decl: any, rule: SymbolRule, spec: LanguageSpec) -> RawSymbol | None {
    name = field_text(decl, rule.name_field);
    if not name {
        return None;
    }

    # Some declarations hold their callable under another field (a
    # declarator's `value`). Follow it before reading async/body.
    carrier = decl;
    if rule.value_field {
        inner = field(decl, rule.value_field);
        if inner is None {
            return None;
        }
        if rule.value_types and (inner.type as str) not in rule.value_types {
            return None;
        }
        carrier = inner;
    }

    kind = rule.kind;
    if kind == "function" and has_marker(carrier, spec.async_marker) {
        kind = "async_function";
    }
    calls: list[RawCall] = [];
    if rule.collect_calls {
        body = field(carrier, spec.body_field);
        target = body if body is not None else carrier;
        calls = calls_in(target, spec.call_rule);
    }
    return RawSymbol(
        name=name,
        kind=kind,
        line=node_line(decl),
        source=clip_source(node_text(decl)),
        calls=calls
    );
}

"""Symbols declared inside a container's body (a class's methods)."""
def member_symbols(decl: any, rule: SymbolRule, spec: LanguageSpec) -> list[RawSymbol] {
    out: list[RawSymbol] = [];
    if not rule.member_types {
        return out;
    }
    body = field(decl, spec.body_field);
    container = body if body is not None else decl;
    member_rule = SymbolRule(
        node_types=rule.member_types,
        kind=rule.member_kind,
        name_field=rule.name_field,
        collect_calls=True,
        value_field=rule.value_field,
        value_types=rule.value_types
    );
    for nd in container.children {
        inner = unwrap(nd, spec);
        if (inner.type as str) not in rule.member_types {
            continue;
        }
        sym = make_symbol(inner, member_rule, spec);
        if sym is not None {
            out.append(sym);
        }
    }
    return out;
}

# --- Entry point ---

"""A cached Tree-sitter parser for this spec and file extension."""
def parser_for(spec: LanguageSpec, rel_path: str) -> any {
    grammar = spec.grammar;
    key = spec.name;
    for (ext, alt) in spec.grammar_by_extension.items() {
        if rel_path.endswith(ext) {
            grammar = alt;
            key = spec.name + ":" + ext;
        }
    }
    if key not in PARSER_CACHE {
        PARSER_CACHE[key] = Parser(Language(grammar()));
    }
    return PARSER_CACHE[key];
}

"""Parse one file into the normalised IR, driven entirely by `spec`."""
def walk_file(spec: LanguageSpec, abs_path: str, rel_path: str) -> RawModule {
    mod = RawModule(
        rel_path=rel_path, name=os.path.basename(abs_path), language=spec.name
    );
    try {
        handle = open(abs_path, "rb");
        raw = handle.read();
        handle.close();
        tree = parser_for(spec, rel_path).parse(raw);
    } except Exception as e {
        mod.error = f"{rel_path}: {str(e)}";
        return mod;
    }

    tree_root = tree.root_node;
    mod.imports = collect_imports(tree_root, spec);

    # Only top-level declarations become symbols. Nested functions are not
    # separate symbols in any registered language; their calls are attributed
    # to the enclosing declaration by `calls_in`.
    for raw_node in tree_root.children {
        decl = unwrap(raw_node, spec);
        rule = rule_for(decl.type as str, spec);
        if rule is None {
            continue;
        }

        members = member_symbols(decl, rule, spec);

        if not rule.emit_self {
            # The container is not itself a symbol (a `const` statement is
            # not a function); only its declarators are.
            for member in members {
                mod.symbols.append(member);
            }
            continue;
        }

        sym = make_symbol(decl, rule, spec);
        if sym is None {
            continue;
        }
        mod.symbols.append(sym);
        for member in members {
            mod.symbols.append(member);
        }

        # Routes hang off the wrapper, not the unwrapped declaration.
        for route in routes_from(raw_node, sym.name, spec.route_rule) {
            mod.routes.append(route);
        }
    }
    return mod;
}

"""Repo-relative paths an import specifier could name, per the spec."""
def resolve_candidates(
    spec: LanguageSpec, spec_str: str, importer_rel: str
) -> list[str] {
    rule = spec.resolve;
    if not spec_str {
        return [];
    }

    is_relative = bool(rule.relative_marker)
    and spec_str.startswith(rule.relative_marker);
    if not is_relative and not rule.allow_bare {
        return [];
    }

    if rule.path_relative {
        # Specifiers are filesystem paths already ("./util", "../a/b").
        base = os.path.normpath(os.path.join(os.path.dirname(importer_rel), spec_str));
    } elif is_relative {
        # Leading markers count how far up the package tree to walk.
        depth = len(spec_str) - len(spec_str.lstrip(rule.relative_marker));
        tail = spec_str[depth:];
        pkg = os.path.dirname(importer_rel);
        for _i in range(depth - 1) {
            pkg = os.path.dirname(pkg);
        }
        base = os.path.join(pkg, tail.replace(rule.separator, "/")) if tail else pkg;
    } else {
        base = spec_str.replace(rule.separator, "/");
    }

    base = base.strip("/");
    if not base or base.startswith("..") {
        return [];
    }

    out: list[str] = [];
    for ext in rule.extensions {
        if base.endswith(ext) {
            out.append(base);
        }
    }
    if out {
        return out;
    }
    for ext in rule.extensions {
        out.append(base + ext);
    }
    for index_name in rule.index_names {
        out.append(base + "/" + index_name);
    }
    return out;
}
