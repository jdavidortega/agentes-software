#!/usr/bin/env python
"""Undo a guarantee on purpose and prove the suite goes red.

Usage:
    python .claude/skills/verificando-por-sabotaje/scripts/sabotear.py mutaciones.json
    python .claude/skills/verificando-por-sabotaje/scripts/sabotear.py mutaciones.json --commit 9922e25

The spec is a JSON list, one object per mutation:

    [
      {"label": "the freshness filter over the window",
       "file": "src/consolidate.py",
       "before": "if item.seen_at >= window_start:",
       "after":  "if True:"}
    ]

Each mutation is applied alone to a FRESH copy of the green base tree (never to a copy
another mutation already ran on: a failing test can leave state behind), the suite runs,
and the copy is discarded. `DIES` means the suite went red, which is the answer you want:
the guarantee is real. `SURVIVES` means the guarantee is a comment.

A mutation that could NOT be applied (`ANCHOR LOST`: the `before` text is not in the file;
`MISSING`: the file does not exist; `ESCAPES`: the path resolves outside the copy, e.g. a
symlink) is reported apart and NEVER counted as a kill. Neither is a red suite that is red
for the WRONG reason: a mutant that does not compile or import (`INVALID`), or a run that
timed out (`TIMEOUT`), proves nothing about the behavior the test allegedly protects -- it
is reported apart with the lines of output that explain it, and the spec must be fixed.
A kill needs POSITIVE evidence: `DIES` is reported only when the red output carries the
signature of a failed assertion (`--kill-pattern`, a regex; the default covers pytest,
unittest, jest, go test, cargo, rspec, TAP and plain `assert`). A red run with no such
signature (a SQL parse error, a crashed helper, a silent `exit 1`) is `UNVERIFIED`: not a
kill and exit 2, because the suite never reached the behavior it claims to protect. For a
stack whose runner prints something else, pass `--kill-pattern`; `--trust-exit-code` makes
any red count as a kill and says so in the report (a declared choice, not a default).
Every `DIES` keeps the tail of the suite output as evidence of *why* it went red.
Exit codes: 0 = every mutation was applied, valid and died; 1 = at least one survived;
2 = at least one could not be applied or was invalid (fix the spec; never read 2 as a pass).

Resources: the copy skips dependency and build directories and every `.env*` except
`.env.example` (recursively); it refuses trees above `--max-mb` (default 500) unless
`--force`; mutations run strictly one at a time with single-worker hints in the environment
(`SABOTAJE_SERIE=1`, plus the common knobs). Never run it while another suite or a mutation
testing tool is running: two suites in parallel is how a laptop runs out of RAM.

Three things here are not decoration, and each cost this project a wrong measurement:

* **The copy.** With several reviews in flight, mutating the working tree turns the suite red
  for everyone else. And a mutation left behind by a crashed helper is worse than no check.
* **`PYTHONDONTWRITEBYTECODE`.** CPython validates a cached `.pyc` against the source mtime
  **truncated to whole seconds** plus its size, and this loop rewrites the same file several
  times per second: without it, a mutation of equal length inside the same second runs the
  *previous* bytecode and is reported as surviving. Two identical runs used to disagree.
* **The base run.** If the suite is not green before mutating, every result is noise. This
  refuses to continue.

By default the copy is made from the **working tree**, because that is where a remediation
you just wrote lives. `--commit` copies from a commit instead, and then the mutation is only
meaningful if the remediation is *in* that commit -- a judge nearly reported five false
negatives by verifying a commit that did not have the fixes yet.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ENVIRONMENT = {
    "PYTHONDONTWRITEBYTECODE": "1",
    # Single-worker hints: the suite must not fan out while we mutate (RAM).
    "SABOTAJE_SERIE": "1",
    "PYTEST_XDIST_AUTO_NUM_WORKERS": "1",
    "CARGO_BUILD_JOBS": "1",
    "MAKEFLAGS": "-j1",
    "GOFLAGS": "-p=1",
    # Readability only: a wide terminal keeps runner summaries whole in the evidence (pytest cuts
    # `FAILED x::t - ...` at the width). Classification never depends on it (it reads `E` lines).
    "COLUMNS": "200",
}
IGNORED = (
    ".venv", "venv", ".git", "__pycache__", "*.pyc", ".pytest_cache", ".ruff_cache",
    ".mypy_cache", ".tox", "node_modules", "dist", "build", "target", ".next", ".nuxt",
    "coverage", ".gradle", ".idea", ".vscode",
)
# Dot-entries DO travel -- `.claude/`, `.githooks/`, `.env.example` are part of the tree, and a
# check that reads one of them would pass vacuously in a copy that lacks it. Real secrets never
# travel: `.env` and every `.env.*` variant are excluded at EVERY depth; `.env.example` is the
# values-free template and is the one exception.


def is_secret(name: str) -> bool:
    return name == ".env" or (name.startswith(".env.") and name != ".env.example")


def ignore(directory: str, names: list[str]) -> set[str]:
    skipped = set()
    for name in names:
        if is_secret(name) or any(fnmatch.fnmatch(name, pattern) for pattern in IGNORED):
            skipped.add(name)
    return skipped


def measure(root: Path) -> tuple[int, int]:
    """(bytes, files) that the copy would contain, honoring the same exclusions."""
    total = 0
    count = 0
    for directory, dirs, files in os.walk(root):
        skip = ignore(directory, dirs + files)
        dirs[:] = [d for d in dirs if d not in skip]
        for f in files:
            if f in skip:
                continue
            try:
                total += (Path(directory) / f).lstat().st_size
            except OSError:
                continue
            count += 1
    return total, count


class Run:
    """One suite execution: whether it was green, and why not when it was not."""

    def __init__(self, green: bool, timed_out: bool, output: str) -> None:
        self.green, self.timed_out, self.output = green, timed_out, output

    def tail(self, lines: int = 3) -> str:
        rows = [r for r in self.output.strip().splitlines() if r.strip()]
        return " | ".join(r.strip()[:120] for r in rows[-lines:]) if rows else "(no output)"


# Output that means the mutant never got to run the behavior: a broken file, a missing
# module or interpreter, a build error. Red for these reasons is not a detection.
INVALID_PATTERNS = (
    "SyntaxError", "IndentationError", "ImportError", "ModuleNotFoundError",
    "cannot find module", "Cannot find module", "command not found", "No such file or directory",
    "compilation failed", "error[E", "error TS", "SyntaxError:", "Unexpected token",
    "could not compile", "undefined: ", "panic: ", "NameError:",
    # Shells (sh/dash/bash): a mutant that is not even parseable never ran the behavior.
    "Syntax error:", "syntax error:", "syntax error near unexpected token", "unexpected end of file",
    "unexpected EOF", "Unterminated quoted string",
    # Interpreted inputs (SQL, templates, configs): a parser rejecting the mutant is not a test.
    "syntax error", "OperationalError", "ParseError", "parse error", "JSONDecodeError",
)

# What a FAILED ASSERTION looks like in the common runners. Only output matching this (and
# none of INVALID_PATTERNS) accredits a kill. Override with --kill-pattern for another stack.
# Only ASSERTION signatures: a generic traceback, a "failed" verb or a helper's RuntimeError
# say that something broke, not that a test asserted on the behavior (measured: a fixture
# helper raising RuntimeError used to read as DIES). What is not an assertion is UNVERIFIED.
# Generic signatures for runners that are NOT Python (Python is decided by the terminal
# exception, below). Matched against the output WITHOUT quoted source lines, so a traceback
# that merely quotes `assert helper()` is not evidence (measured: R9-13).
KILL_PATTERN = (
    r"AssertionError|assertion failed|assertion `.*` failed|Assertion.*failed|"   # node, rust, C
    r"FAIL:|^--- FAIL|"                                                          # shell gates, go test
    r"✗ |✕ |● .* › |Expected: |Received: |expect\(|toEqual|toBe\(|"              # jest/mocha/vitest
    r"^not ok \d|Failures:|Failure/Error:|\d+ failures?, |\d+ failing\b|"          # tap/rspec/minitest/mocha
    r"assertEquals|assertThat|expected .* but (was|got)"                          # junit & friends
)



def strip_quoted_source(output: str) -> list[str]:
    """Output lines without the source code a Python traceback quotes: after each
    `  File "...", line N` header, the indented lines that follow are the program's own text
    (and the ^~~~ markers), not what happened."""
    lines, in_frame = [], False
    for line in output.splitlines():
        if re.match(r'^\s+File "', line):
            in_frame = True
            continue
        if in_frame and line.startswith("    "):
            continue
        in_frame = False
        lines.append(line)
    return lines


CHAINED = ("The above exception was the direct cause", "During handling of the above exception")


def python_terminals(lines: list[str]) -> list[str]:
    """The TERMINAL exception of each Python traceback chain. A chain (`raise X from exc`, or
    an exception raised while handling another) prints several tracebacks joined by one of
    CHAINED; only the last one is what ended the run. An AssertionError that a helper caught
    and re-raised (as RuntimeError, as a bare Exception, as anything) is an intermediate
    step, not the cause. The exception line is recognized by POSITION (the first unindented
    line after the frames), not by a name suffix; one that cannot be parsed counts as "?",
    never as an assertion."""
    terminals, current, in_tb, chained = [], None, False, False
    for line in lines:
        if line.startswith("Traceback (most recent call last)"):
            in_tb = True
            continue
        if any(line.startswith(c) for c in CHAINED):
            chained = True
            continue
        if in_tb and line.strip() and not line[0].isspace():
            m = re.match(r"^([A-Za-z_][\w.]*)(?::|$)", line)
            if current is not None and not chained:
                terminals.append(current)
            current, in_tb, chained = (m.group(1) if m else "?"), False, False
    if current is not None:
        terminals.append(current)
    return terminals


def pytest_terminal_assertion(lines: list[str]) -> bool:
    """pytest: the short summary (`FAILED x::t - <terminal exception>`) names the terminal
    cause; without a summary, each test section counts only after its last chaining line."""
    summary = [l for l in lines if re.match(r"^FAILED \S+::\S+ - ", l)]
    if summary:
        return any(re.match(r"^FAILED \S+::\S+ - (assert\b|AssertionError|Failed: DID NOT RAISE\b)", l) for l in summary)
    sections, part = [], []
    for line in lines:
        if re.match(r"^_{3,} .* _{3,}$", line) and part:
            sections.append(part)
            part = []
        part.append(line)
    sections.append(part)
    for section in sections:
        cut = max((i for i, l in enumerate(section) if any(c in l for c in CHAINED)), default=-1)
        if any(re.match(r"^E\s+(assert\b|AssertionError|Failed: DID NOT RAISE\b)", l) for l in section[cut + 1:]):
            return True
    return False


def assertion_evidence(output: str, pattern: str) -> bool:
    """True only when the red run carries a FAILED ASSERTION as its TERMINAL cause.

    * Python tracebacks: the last exception of each chain decides. One that ends in
      something other than AssertionError (RuntimeError of a helper, a fixture that fails to
      load, an AssertionError re-raised as another exception) is an execution error,
      whatever line of source it quotes.
    * pytest: the summary `FAILED x::t - assert ...` / `- AssertionError` (pytest names the
      terminal exception there); `FAILED x::t - RuntimeError` is an error inside a test.
    * Anything else: `pattern` (the runner's assertion signature), matched without quoted
      source lines; a Go/Rust `panic:` that is not an assertion is not evidence.
    """
    lines = strip_quoted_source(output)
    text = "\n".join(lines)
    pytest_like = any(re.match(r"^(FAILED|ERROR) \S+::", l) or re.match(r"^E\s{2,}\S", l) for l in lines)
    if pytest_like:
        return pytest_terminal_assertion(lines)
    if "Traceback (most recent call last)" in output:
        return any(t.split(".")[-1] == "AssertionError" for t in python_terminals(lines))
    if re.search(r"^panic: ", text, re.MULTILINE) and not re.search(r"assertion", text):
        return False
    return re.search(pattern, text, re.MULTILINE) is not None


def suite(tree: Path, command: list[str], timeout: int) -> Run:
    """Run the suite in `tree`. A crash or a timeout counts as red, with its output kept."""
    try:
        done = subprocess.run(
            command,
            cwd=tree,
            capture_output=True,
            timeout=timeout,
            env={**os.environ, **ENVIRONMENT},
        )
    except subprocess.TimeoutExpired as exc:
        out = (exc.stdout or b"").decode("utf-8", "replace") + (exc.stderr or b"").decode("utf-8", "replace")
        return Run(False, True, out)
    out = done.stdout.decode("utf-8", "replace") + done.stderr.decode("utf-8", "replace")
    return Run(done.returncode == 0, False, out)


def looks_invalid(run: Run) -> str | None:
    """The pattern that marks this red run as a broken mutant rather than a detection."""
    for pattern in INVALID_PATTERNS:
        if pattern in run.output:
            return pattern
    return None


# Syntax checkers by extension: a mutant that does not parse is INVALID before the suite
# runs, whatever the suite then prints (a shell `if` without `fi` used to read as DIES).
CHECKERS = {
    ".sh": ["sh", "-n"], ".bash": ["bash", "-n"],
    ".js": ["node", "--check"], ".mjs": ["node", "--check"], ".cjs": ["node", "--check"],
    ".rb": ["ruby", "-c"],
}


def compiles(path: Path) -> str | None:
    """The parse error of the mutated file, or None if it parses (or no checker applies)."""
    if path.suffix == ".py":
        try:
            compile(path.read_text(encoding="utf-8"), str(path), "exec")
        except SyntaxError as exc:
            return f"SyntaxError line {exc.lineno}: {exc.msg}"
        return None
    checker = CHECKERS.get(path.suffix)
    # Shell scripts: the shebang decides the dialect (`bash -n` accepts what `sh -n` rejects).
    if path.suffix in (".sh", ".bash", "") and path.read_bytes()[:2] == b"#!":
        first = path.read_text(encoding="utf-8", errors="replace").splitlines()[0]
        if "bash" in first:
            checker = ["bash", "-n"]
        elif "sh" in first:
            checker = ["sh", "-n"]
    if checker is None:
        return None
    if shutil.which(checker[0]) is None:
        return None  # no checker on this machine: the suite's own output still gets screened
    done = subprocess.run([*checker, str(path)], capture_output=True, text=True)
    if done.returncode != 0:
        msg = (done.stderr or done.stdout).strip().splitlines()
        return f"{checker[0]} -n: {msg[-1][:120] if msg else 'parse error'}"
    return None


def prune(tree: Path) -> list[str]:
    """Remove from an extracted tree what the working-tree copy never includes (IGNORED
    patterns and every secret `.env*`). Returns what was removed: a secret that was
    versioned in the commit is a finding in itself."""
    removed = []
    for directory, dirs, files in os.walk(tree, topdown=True):
        skip = ignore(directory, dirs + files)
        for name in list(dirs):
            if name in skip:
                shutil.rmtree(Path(directory) / name, ignore_errors=True)
                dirs.remove(name)
                removed.append(str(Path(directory, name).relative_to(tree)))
        for name in files:
            if name in skip:
                (Path(directory) / name).unlink(missing_ok=True)
                removed.append(str(Path(directory, name).relative_to(tree)))
    return removed


def plant(tree: Path, root: Path, commit: str | None) -> list[str]:
    """Fill `tree` with the code to mutate: a commit, or the working tree as it stands.
    Both paths honor the same exclusions; returns what had to be pruned (commit mode)."""
    if commit:
        # `commit` is already a resolved SHA (resolve_commit); no shell ever sees it.
        tree.mkdir()
        archive = subprocess.Popen(["git", "archive", "--format=tar", commit], cwd=root, stdout=subprocess.PIPE)
        extract = subprocess.run(["tar", "-x", "-C", str(tree)], stdin=archive.stdout)
        archive.stdout.close()
        if archive.wait() != 0 or extract.returncode != 0:
            raise RuntimeError(f"could not extract commit {commit} into the copy")
        return prune(tree)
    # `symlinks=True`: links are copied as links, never dereferenced -- and `contained()`
    # below refuses to mutate through any of them.
    shutil.copytree(root, tree, ignore=ignore, symlinks=True)
    return []


TABLE_HEADER = re.compile(r"^\s*\|\s*Ruta\s*\|\s*Propósito\s*\|\s*Cómo se reproduce\s*\|")
EDITABLE_MARKERS = ("direct_url.json",)


def declared_externals(root: Path) -> list[str]:
    """Folders declared in docs/convenciones.md (table `| Ruta | Propósito | Cómo se reproduce |`),
    the same table the pre-commit reads: ignored folders the suite needs (a virtualenv)."""
    conv = root / "docs" / "convenciones.md"
    if not conv.is_file():
        return []
    rows, inside = [], False
    for line in conv.read_text(encoding="utf-8", errors="replace").splitlines():
        if TABLE_HEADER.match(line):
            inside = True
            continue
        if inside and re.match(r"^\s*\|[- |]+$", line):
            continue
        if inside and line.lstrip().startswith("|"):
            cell = line.split("|")[1].replace("`", "").strip()
            if cell:
                rows.append(cell)
            continue
        inside = False
    return rows


def external_problem(root: Path, entry: str) -> str | None:
    """Why a declared external folder may NOT be shared with the copies, or None. Same rules as
    the pre-commit: relative, ignored, nothing versioned, and nothing that runs the ORIGINAL tree
    (an editable install or a link into it would test intact code while the copy is mutated)."""
    if entry.startswith("/") or ".." in Path(entry).parts:
        return "must be a path relative to the repository, without '..'"
    folder = root / entry
    if not folder.is_dir() or folder.is_symlink():
        return "is not an existing folder of the working tree"
    if subprocess.run(["git", "check-ignore", "-q", entry], cwd=root).returncode != 0:
        return "is not ignored by git (what is not ignored is versioned)"
    tracked = subprocess.run(["git", "ls-files", "--", entry], cwd=root, capture_output=True, text=True).stdout
    if tracked.strip():
        return "contains versioned files"
    real, own = str(root.resolve()), str(folder.resolve())
    for directory, _, files in os.walk(folder):  # every depth, like the pre-commit's grep -r
        for name in files:
            if name.endswith(".pth") or name.startswith("__editable__") or name in EDITABLE_MARKERS:
                text = (Path(directory) / name).read_text(encoding="utf-8", errors="replace")
                if real in text:
                    return f"points at the original tree ({Path(directory) / name}): an editable install runs unmutated code"
    for directory, dirs, files in os.walk(folder):  # links: three levels, like the pre-commit's find
        if len(Path(directory).relative_to(folder).parts) >= 3:
            dirs[:] = []
        for name in dirs + files:
            link = Path(directory) / name
            if link.is_symlink():
                target = str(link.resolve())
                inside_repo = target == real or target.startswith(real + os.sep)
                if inside_repo and not (target == own or target.startswith(own + os.sep)):
                    return f"has a link into the original tree ({link})"
    return None


def link_externals(tree: Path, root: Path, entries: list[str]) -> None:
    """Share each declared external folder with a copy as a link to the original (never copied)."""
    for entry in entries:
        target = tree / entry
        if target.is_symlink() or target.is_file():
            target.unlink()
        elif target.exists():
            shutil.rmtree(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(root / entry)


def resolve_commit(root: Path, commit: str) -> str | None:
    """The full SHA that `commit` names, or None. Validated with git BEFORE anything runs:
    the value is data, never shell (a `--commit` with `;` used to execute in the source repo)."""
    if not commit or commit.startswith("-") or any(c.isspace() or ord(c) < 32 for c in commit):
        return None
    done = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", "--end-of-options", f"{commit}^{{commit}}"],
        cwd=root, capture_output=True, text=True,
    )
    sha = done.stdout.strip()
    return sha if done.returncode == 0 and re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", sha) else None


def contained(tree: Path, relative: str) -> Path | None:
    """The real path of `relative` inside `tree`, or None if it is missing or escapes."""
    target = tree / relative
    if target.is_symlink() or not target.is_file():
        return None
    real = target.resolve()
    try:
        real.relative_to(tree.resolve())
    except ValueError:
        return None
    return real


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("spec", type=Path, help="JSON list of mutations")
    parser.add_argument("--commit", help="copy from this commit instead of the working tree")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="repository root")
    parser.add_argument(
        "--suite",
        default="sh scripts/check.sh",
        help="command that must go red; run from inside the copy (default: the "
        "project's scripts/check.sh; pass your stack's test command if it differs)",
    )
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument(
        "--kill-pattern",
        default=KILL_PATTERN,
        help="regex that a red run must match to count as DIES (failed-assertion signature of "
        "your runner); anything else red is UNVERIFIED (default covers the common runners)",
    )
    parser.add_argument(
        "--trust-exit-code",
        action="store_true",
        help="count any red run as DIES without the assertion signature (declared, not default)",
    )
    parser.add_argument("--max-mb", type=int, default=500, help="refuse to copy a tree above this size")
    parser.add_argument("--force", action="store_true", help="copy even above --max-mb")
    arguments = parser.parse_args()

    root = arguments.root.resolve()
    mutations = json.loads(arguments.spec.read_text(encoding="utf-8"))
    if not mutations:
        print("the spec has no mutations: nothing to prove", file=sys.stderr)
        return 2
    for m in mutations:
        if not all(k in m and isinstance(m[k], str) and m[k] for k in ("label", "file", "before", "after")):
            print(f"malformed mutation (needs label/file/before/after): {m}", file=sys.stderr)
            return 2
    try:
        # Quoted arguments stay whole; no shell, no eval: the list goes straight to subprocess.
        command = shlex.split(arguments.suite)
    except ValueError as exc:
        print(f"--suite cannot be split into arguments ({exc}): check its quotes", file=sys.stderr)
        return 2
    if not command:
        print("--suite is empty", file=sys.stderr)
        return 2
    first = command[0]
    externals = declared_externals(root)
    for entry in externals:
        problem = external_problem(root, entry)
        if problem:
            print(f"external input {entry!r} declared in docs/convenciones.md {problem}", file=sys.stderr)
            return 2
    # A relative PATH in the command (`./gate.sh`, `scripts/run`) is resolved AFTER the copy
    # exists (below): inside the copy when the file is part of the project, so a mutation of
    # the suite script itself is the one that runs; against the root only when the copy does
    # not contain it (an excluded tool such as `.venv/bin/pytest`). A bare name names PATH.

    sha = None
    if arguments.commit:
        # Resolved before anything runs: the value names a commit or the run stops here.
        sha = resolve_commit(root, arguments.commit)
        if sha is None:
            print(f"--commit does not name a valid commit: {arguments.commit!r}", file=sys.stderr)
            return 2
    else:
        size, files = measure(root)
        mb = size / 1_000_000
        print(f"copy: {files} files, {mb:.0f} MB (dependencies, builds and .env* excluded)")
        if mb > arguments.max_mb and not arguments.force:
            print(
                f"refusing to copy {mb:.0f} MB (> --max-mb {arguments.max_mb}): check IGNORED or pass --force",
                file=sys.stderr,
            )
            return 2

    with tempfile.TemporaryDirectory() as temporary:
        tree = Path(temporary) / "tree"
        pruned = plant(tree, root, sha)
        link_externals(tree, root, externals)
        if externals:
            print("external inputs linked into every copy (docs/convenciones.md): " + ", ".join(externals))
        if "/" in command[0] and not Path(command[0]).is_absolute():
            if not (tree / command[0]).is_file():
                command[0] = str(root / command[0])
                print(f"suite command {first} is not in the copy: using the original tree's")
        if arguments.commit:
            size, files = measure(tree)
            mb = size / 1_000_000
            print(f"copy from commit {arguments.commit}: {files} files, {mb:.0f} MB after pruning")
            secrets = [p for p in pruned if is_secret(Path(p).name)]
            if secrets:
                print(f"  WARNING the commit versions secret files (removed from the copy): {', '.join(secrets)}")
            if mb > arguments.max_mb and not arguments.force:
                print(
                    f"refusing: the commit tree is {mb:.0f} MB (> --max-mb {arguments.max_mb}) even after pruning; pass --force",
                    file=sys.stderr,
                )
                return 2
        base = suite(tree, command, arguments.timeout)
        if not base.green:
            print("the suite is not green before mutating: every result would be noise", file=sys.stderr)
            print("  " + base.tail(), file=sys.stderr)
            return 2
        origin = f"commit {arguments.commit}" if arguments.commit else "the working tree"
        print(f"base green over {origin}")

        died, survived, invalid, unapplied = [], [], [], []
        base = tree
        for index, mutation in enumerate(mutations):
            label = mutation["label"]
            # Each mutation runs on a FRESH copy of the green base: a test that fails can leave
            # fixtures, caches or state behind, and that residue must never become the reason the
            # next mutant "dies" (measured: an equivalent mutant read as DIES after another one).
            # The green run leaves bytecode and build caches in the base (`python3 -I` ignores
            # PYTHONDONTWRITEBYTECODE); they never travel into a mutant: a cache keyed on
            # size+mtime would serve the ORIGINAL code for a same-size mutation written within
            # the same second, and the mutant would "survive" without ever running (measured).
            tree = Path(temporary) / f"mut{index}"
            shutil.copytree(base, tree, symlinks=True, ignore=shutil.ignore_patterns(*IGNORED))
            link_externals(tree, root, externals)
            path = contained(tree, mutation["file"])
            if path is None:
                kind = "ESCAPES " if (tree / mutation["file"]).is_symlink() else "MISSING "
                print(f"  {kind} {label}: {mutation['file']} (not a regular file inside the copy)")
                unapplied.append(label)
                shutil.rmtree(tree, ignore_errors=True)
                continue
            original = path.read_text(encoding="utf-8")
            if mutation["before"] not in original:
                # A stale anchor is a different problem from a guarantee that does not hold,
                # and it is never a kill.
                print(f"  ANCHOR LOST {label}: {mutation['file']}")
                unapplied.append(label)
                shutil.rmtree(tree, ignore_errors=True)
                continue
            path.write_text(original.replace(mutation["before"], mutation["after"], 1), encoding="utf-8")
            # And the mutant's mtime moves forward by 2 s, so any incremental tool that keys on
            # mtime sees a changed file even on a filesystem with 1 s resolution.
            stamp = max(path.stat().st_mtime, time.time()) + 2
            os.utime(path, (stamp, stamp))
            try:
                error = compiles(path)
                run = None if error else suite(tree, command, arguments.timeout)
            finally:
                shutil.rmtree(tree, ignore_errors=True)  # the copy is disposable; the base stays clean
            if error:
                # The mutant never ran: a red suite here would say nothing about behavior.
                print(f"  INVALID  {label}: mutant does not compile ({error})")
                invalid.append(label)
                continue
            if run.green:
                print(f"  SURVIVES {label}")
                survived.append(label)
                continue
            if run.timed_out:
                print(f"  TIMEOUT  {label}: the suite exceeded {arguments.timeout}s; not a detection ({run.tail(1)})")
                invalid.append(label)
                continue
            reason = looks_invalid(run)
            if reason:
                print(f"  INVALID  {label}: red for the wrong reason ({reason}) -- {run.tail(2)}")
                invalid.append(label)
                continue
            if not arguments.trust_exit_code and not assertion_evidence(run.output, arguments.kill_pattern):
                # Red, but nothing says a test asserted anything: the behavior may never have run.
                print(f"  UNVERIFIED {label}: red without a failed-assertion signature; not a kill "
                      f"(pass --kill-pattern for this stack, or --trust-exit-code deliberately) -- {run.tail(2)}")
                invalid.append(label)
                continue
            print(f"  DIES     {label} -- {run.tail(2)}")
            died.append(label)

    print(f"\napplied {len(died) + len(survived) + len(invalid)}/{len(mutations)}: {len(died)} die, "
          f"{len(survived)} survive, {len(invalid)} without a valid verdict; {len(unapplied)} not applied"
          + (" [kills accepted on exit code alone: --trust-exit-code]" if arguments.trust_exit_code else ""))
    if survived:
        print("guarantees no test protects: " + ", ".join(survived))
    if unapplied:
        print("not applied (stale or unsafe spec, fix it): " + ", ".join(unapplied))
    if invalid:
        print("applied, no valid verdict (invalid mutant, timeout or no assertion signature): " + ", ".join(invalid))
    if unapplied or invalid:
        return 2
    return 1 if survived else 0


if __name__ == "__main__":
    sys.exit(main())
