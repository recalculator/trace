"""Trace - the language registry.

The only place that knows which languages exist. `ingestion.jac` asks this
module which files to read and gets normalised IR back; it never names a
language and never touches a parser.

Every entry here is a `LanguageSpec` - declarative data plus a Tree-sitter
grammar handle. There is one walker, `universal_walker.jac`, shared by all
of them.

Adding a language: install its grammar, write one `lang_<name>.jac` spec,
add it to `SPECS`. No parser code.
"""

import os;

import from lang_spec { LanguageSpec }
import from lang_python { PYTHON_SPEC }
import from lang_typescript { TYPESCRIPT_SPEC }
import from parser_types { RawModule }
import from universal_walker { resolve_candidates, walk_file }

"""Every registered language mapping, in priority order."""
glob SPECS: list[LanguageSpec] = [PYTHON_SPEC, TYPESCRIPT_SPEC];

"""Directories never worth walking into."""
glob IGNORED_DIRS: list[str] = [
         ".git",
         ".venv",
         "venv",
         "__pycache__",
         "node_modules",
         "build",
         "dist",
         ".tox",
         ".mypy_cache",
         ".pytest_cache",
         ".eggs",
         "site-packages",
         ".jac",
         ".next",
         "out",
         "coverage",
         "vendor",
         "target"
     ];

"""A source file paired with the language that claims it."""
obj SourceFile {
    has abs_path: str = "",
        rel_path: str = "",
        language: str = "";
}

"""The spec whose extensions claim this filename, or None."""
def spec_for(filename: str) -> LanguageSpec | None {
    for s in SPECS {
        for ext in s.extensions {
            if filename.endswith(ext) {
                return s;
            }
        }
    }
    return None;
}

"""The language a file belongs to, or "" when nothing claims it."""
def detect_language(filename: str) -> str {
    s = spec_for(filename);
    if s is None {
        return "";
    }
    return s.name;
}

"""Every language Trace can currently ingest."""
def supported_languages() -> list[str] {
    return [s.name for s in SPECS];
}

"""Walk a repository and return every file some language claims."""
def find_source_files(root_path: str) -> list[SourceFile] {
    found: list[SourceFile] = [];
    for (dirpath, dirnames, filenames) in os.walk(root_path) {
        keep = [
            d
            for d in dirnames
            if d not in IGNORED_DIRS and not d.startswith(".")
        ];
        dirnames[:] = keep;
        for fn in filenames {
            lang = detect_language(fn);
            if lang {
                abs_path = os.path.join(dirpath, fn);
                found.append(
                    SourceFile(
                        abs_path=abs_path,
                        rel_path=os.path.relpath(abs_path, root_path),
                        language=lang
                    )
                );
            }
        }
    }
    found.sort(key=lambda (f: SourceFile) { f.rel_path; });
    return found;
}

"""Parse one discovered file with the universal walker."""
def parse_source_file(src: SourceFile) -> RawModule {
    s = spec_for(os.path.basename(src.abs_path));
    if s is None {
        return RawModule(
            rel_path=src.rel_path, error=f"{src.rel_path}: no language registered"
        );
    }
    return walk_file(s, src.abs_path, src.rel_path);
}

"""Resolve an import specifier using the importing language's rules."""
def module_candidates(spec_str: str, importer_rel: str, language: str) -> list[str] {
    for s in SPECS {
        if s.name == language {
            return resolve_candidates(s, spec_str, importer_rel);
        }
    }
    return [];
}
