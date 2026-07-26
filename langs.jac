"""Trace - the language registry.

The single place that knows which languages exist. `ingestion.jac` asks this
module which files to read and who should parse them; it never imports a
parser directly and never names a language.

Adding a language is a two-line change here plus one new parser module.
"""

import os;

import from parser_types { LanguageParser, RawModule }
import from parser_python { PythonParser }
import from parser_typescript { TypeScriptParser }

"""Every registered parser, in priority order."""
glob PARSERS: list[LanguageParser] = [PythonParser(), TypeScriptParser()];

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

"""A source file paired with the parser that owns it."""
obj SourceFile {
    has abs_path: str = "",
        rel_path: str = "",
        language: str = "";
}

"""The parser registered for a filename, or None when the file is not source."""
def parser_for(filename: str) -> LanguageParser | None {
    for p in PARSERS {
        if p.handles(filename) {
            return p;
        }
    }
    return None;
}

"""The language a file belongs to, or "" when no parser claims it."""
def detect_language(filename: str) -> str {
    p = parser_for(filename);
    if p is None {
        return "";
    }
    return p.name;
}

"""Every language Trace can currently ingest."""
def supported_languages() -> list[str] {
    return [p.name for p in PARSERS];
}

"""Walk a repository and return every file some parser can handle.

Replaces the old Python-only `.py` glob: discovery is now driven by the
registry, so a new parser makes its files visible automatically.
"""
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

"""Parse one discovered file with whichever parser owns it."""
def parse_source_file(src: SourceFile) -> RawModule {
    p = parser_for(os.path.basename(src.abs_path));
    if p is None {
        return RawModule(
            rel_path=src.rel_path, error=f"{src.rel_path}: no parser registered"
        );
    }
    return p.parse_file(src.abs_path, src.rel_path);
}

"""Resolve an import specifier using the rules of the importing file's language."""
def module_candidates(spec: str, importer_rel: str, language: str) -> list[str] {
    for p in PARSERS {
        if p.name == language {
            return p.module_candidates(spec, importer_rel);
        }
    }
    return [];
}
