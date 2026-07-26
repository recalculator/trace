"""Trace - ingest a public GitHub repository by URL.

This module is a THIN WRAPPER. It clones a repository and then hands the
directory to the existing `ingest_repo` pipeline unchanged - it contains no
parser logic, no graph construction and no investigation logic of its own.
Everything downstream (graph export, forward/reverse tracing, the UI) works
on a cloned repository exactly as it does on a local one, because they all
key off the same `Repository` nodes.

Two design points worth knowing:

  Stable clone paths. Each URL clones to a deterministic directory
  (`<tmp>/trace_clones/<owner>__<repo>`) rather than a random one. That
  makes duplicate ingestion free: `ingest_repo` already purges any previous
  `Repository` sharing the same path, so re-analysing a URL replaces its
  subgraph instead of accumulating copies. A random temp dir would defeat
  that and silently duplicate the whole repository.

  The URL is never passed through to the shell. `git` is invoked with an
  argument list (never `shell=True`), and the clone URL is RECONSTRUCTED
  from a strictly-validated owner/repo pair rather than forwarded verbatim.
  This endpoint is public and unauthenticated, so a raw pass-through would
  let a caller smuggle `git` options (`--upload-pack=...`) into the command.
"""

import os;
import re;
import shutil;
import subprocess;
import tempfile;

import from ingestion { ingest_repo }
import from client.types { CloneResult }

glob GITHUB_HOSTS: list[str] = ["github.com", "www.github.com"];

glob CLONE_TIMEOUT_SECONDS: int = 180;

"""Owner/repo segments: no slashes, no leading dash (which `git` reads as a flag)."""
glob SEGMENT_PATTERN: str = "^[A-Za-z0-9_.][A-Za-z0-9_.-]*$";

"""A validated GitHub repository reference."""
obj RepoRef {
    has owner: str = "",
        repo: str = "",
        ok: bool = False,
        reason: str = "";
}

"""Directory every clone lands in, one stable subdirectory per repository."""
def _clone_root() -> str {
    return os.path.join(tempfile.gettempdir(), "trace_clones");
}

"""Validate a GitHub URL and split it into owner / repo.

Accepts the forms a user actually pastes - with or without scheme, `.git`
suffix, trailing slash, or extra path segments such as `/tree/main`.
"""
def _parse_github_url(url: str) -> RepoRef {
    raw = url.strip();
    if not raw {
        return RepoRef(reason="No URL provided.");
    }

    # Normalise scheme and the scp-style git@github.com:owner/repo form.
    body = raw;
    if body.startswith("git@") {
        body = body.replace(":", "/", 1);
        body = body[len("git@"):];
    } else {
        for prefix in ["https://", "http://", "ssh://", "git://"] {
            if body.startswith(prefix) {
                body = body[len(prefix):];
            }
        }
    }
    body = body.rstrip("/");

    parts = [
        p
        for p in body.split("/")
        if p
    ];
    if len(parts) < 3 {
        return RepoRef(
            reason="Not a GitHub repository URL. Expected https://github.com/<owner>/<repo>."
        );
    }

    host = parts[0].lower();
    if host not in GITHUB_HOSTS {
        return RepoRef(reason=f"Only github.com URLs are supported (got '{host}').");
    }

    owner = parts[1];
    repo = parts[2];
    if repo.endswith(".git") {
        repo = repo[:-len(".git")];
    }

    # Strict validation. The clone URL is rebuilt from these values, so
    # anything that could be read as a git option must be rejected here.
    if not re.match(SEGMENT_PATTERN, owner) or not re.match(SEGMENT_PATTERN, repo) {
        return RepoRef(reason="Invalid owner or repository name in URL.");
    }

    return RepoRef(owner=owner, repo=repo, ok=True);
}

"""Shallow-clone a repository. Returns "" on success, else an error message."""
def _clone(owner: str, repo: str, dest: str) -> str {
    if os.path.isdir(dest) {
        shutil.rmtree(dest, ignore_errors=True);
    }
    os.makedirs(os.path.dirname(dest), exist_ok=True);

    # URL rebuilt from validated segments - the caller's string never
    # reaches the command line.
    url = f"https://github.com/{owner}/{repo}.git";
    try {
        proc = subprocess.run(
            ["git", "clone", "--depth", "1", "--quiet", "--", url, dest],
            capture_output=True,
            text=True,
            timeout=CLONE_TIMEOUT_SECONDS
        );
    } except Exception as e {
        return f"git clone failed: {str(e)}";
    }

    if (proc.returncode as int) != 0 {
        detail = (proc.stderr as str).strip();
        if not detail {
            detail = "git exited with a non-zero status.";
        }
        return f"Could not clone {owner}/{repo}. {detail}";
    }
    if not os.path.isdir(dest) {
        return f"Clone reported success but {dest} does not exist.";
    }
    return "";
}

"""Look up the jid of the Repository node just created for `path`."""
def _repo_id_for_path(path: str) -> str {
    for r in [root-->[?:Repository]] {
        if r.path == path {
            return jid(r);
        }
    }
    return "";
}

"""Clone a public GitHub repository and ingest it into the code graph.

`cleanup` removes the working tree once ingestion has finished. This is safe:
ingestion copies every symbol's source text into the graph, so nothing
downstream re-reads the files.
"""
def:pub analyze_github_repo(url: str, cleanup: bool = True) -> CloneResult {
    ref = _parse_github_url(url);
    if not ref.ok {
        return CloneResult(status="invalid_url", message=ref.reason, url=url);
    }

    full_name = f"{ref.owner}/{ref.repo}";
    dest = os.path.join(_clone_root(), f"{ref.owner}__{ref.repo}");

    clone_error = _clone(ref.owner, ref.repo, dest);
    if clone_error {
        shutil.rmtree(dest, ignore_errors=True);
        return CloneResult(
            status="clone_failed", message=clone_error, url=url, repo_name=full_name
        );
    }

    # The one call that matters: the existing pipeline, unchanged. Because
    # `dest` is stable per URL, re-analysing the same repository replaces
    # its previous subgraph rather than duplicating it.
    summary = ingest_repo(dest, name=full_name);

    if summary.parse_errors and summary.files == 0 {
        shutil.rmtree(dest, ignore_errors=True);
        return CloneResult(
            status="error",
            message=f"Ingestion failed: {summary.parse_errors[0]}",
            url=url,
            repo_name=full_name
        );
    }

    if summary.files == 0 {
        shutil.rmtree(dest, ignore_errors=True);
        return CloneResult(
            status="unsupported",
            message=f"{full_name} contains no Python files. Trace currently analyses Python repositories only.",
            url=url,
            repo_name=full_name
        );
    }

    repo_id = _repo_id_for_path(os.path.abspath(dest));

    did_clean = False;
    if cleanup {
        shutil.rmtree(dest, ignore_errors=True);
        did_clean = True;
    }

    return CloneResult(
        status="ok",
        message=f"Analysed {full_name}: {summary.files} files, {summary.symbols} symbols.",
        repo_name=full_name,
        repo_id=repo_id,
        url=url,
        files=summary.files,
        symbols=summary.symbols,
        routes=summary.routes,
        call_edges=summary.call_edges,
        cleaned_up=did_clean
    );
}

"""Delete every cached clone working tree. The ingested graphs are unaffected."""
def:pub cleanup_clones() -> int {
    root_dir = _clone_root();
    if not os.path.isdir(root_dir) {
        return 0;
    }
    removed = 0;
    for entry in os.listdir(root_dir) {
        shutil.rmtree(os.path.join(root_dir, entry), ignore_errors=True);
        removed += 1;
    }
    return removed;
}
