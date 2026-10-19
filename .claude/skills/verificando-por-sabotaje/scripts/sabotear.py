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
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ENVIRONMENT = {
    "PYTHONDONTWRITEBYTECODE": "1",
    # Single-worker hints: the suite must not fan out while we mutate (RAM).
    "SABOTAJE_SERIE": "1",
    "PYTEST_XDIST_AUTO_NUM_WORKERS": "1",
    "CARGO_BUILD_JOBS": "1",
    "MAKEFLAGS": "-j1",
    "GOFLAGS": "-p=1",
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
KILL_PATTERN = (
    r"AssertionError|assert |assertion failed|^\s*assert\b|"            # python, c, rust, shell asserts
    r"\bFAILED\b.*(test|::|\.py|\.js|\.ts|\.rb|\.go)|FAIL:|^--- FAIL|test result: FAILED|"  # pytest/unittest/go/cargo
    r"✗ |✕ |● .* › |Expected: |Received: |expect\(|toEqual|toBe\(|"      # jest/mocha/vitest
    r"^not ok \d|Failures:|Failure/Error:|\d+ failures?, |\d+ failing\b|"  # tap/rspec/minitest/mocha
    r"Assertion.*failed|assertEquals|assertThat|expected .* but (was|got)"  # junit & friends
)


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
        tree.mkdir()
        subprocess.run(f"git archive {commit} | tar -x -C {tree}", shell=True, cwd=root, check=True)
        return prune(tree)
    # `symlinks=True`: links are copied as links, never dereferenced -- and `contained()`
    # below refuses to mutate through any of them.
    shutil.copytree(root, tree, ignore=ignore, symlinks=True)
    return []


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
    command = arguments.suite.split()
    # A relative PATH in the command (`./gate.sh`, `scripts/run`) is resolved AFTER the copy
    # exists (below): inside the copy when the file is part of the project, so a mutation of
    # the suite script itself is the one that runs; against the root only when the copy does
    # not contain it (an excluded tool such as `.venv/bin/pytest`). A bare name names PATH.

    if not arguments.commit:
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
        pruned = plant(tree, root, arguments.commit)
        if "/" in command[0] and not Path(command[0]).is_absolute():
            if not (tree / command[0]).is_file():
                command[0] = str(root / command[0])
                print(f"suite command {arguments.suite.split()[0]} is not in the copy: using the original tree's")
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

        died, survived, invalid = [], [], []
        base = tree
        for index, mutation in enumerate(mutations):
            label = mutation["label"]
            # Each mutation runs on a FRESH copy of the green base: a test that fails can leave
            # fixtures, caches or state behind, and that residue must never become the reason the
            # next mutant "dies" (measured: an equivalent mutant read as DIES after another one).
            tree = Path(temporary) / f"mut{index}"
            shutil.copytree(base, tree, symlinks=True)
            path = contained(tree, mutation["file"])
            if path is None:
                kind = "ESCAPES " if (tree / mutation["file"]).is_symlink() else "MISSING "
                print(f"  {kind} {label}: {mutation['file']} (not a regular file inside the copy)")
                invalid.append(label)
                shutil.rmtree(tree, ignore_errors=True)
                continue
            original = path.read_text(encoding="utf-8")
            if mutation["before"] not in original:
                # A stale anchor is a different problem from a guarantee that does not hold,
                # and it is never a kill.
                print(f"  ANCHOR LOST {label}: {mutation['file']}")
                invalid.append(label)
                shutil.rmtree(tree, ignore_errors=True)
                continue
            path.write_text(original.replace(mutation["before"], mutation["after"], 1), encoding="utf-8")
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
            if not arguments.trust_exit_code and not re.search(arguments.kill_pattern, run.output, re.MULTILINE):
                # Red, but nothing says a test asserted anything: the behavior may never have run.
                print(f"  UNVERIFIED {label}: red without a failed-assertion signature; not a kill "
                      f"(pass --kill-pattern for this stack, or --trust-exit-code deliberately) -- {run.tail(2)}")
                invalid.append(label)
                continue
            print(f"  DIES     {label} -- {run.tail(2)}")
            died.append(label)

    print(f"\napplied {len(died) + len(survived)}/{len(mutations)}: {len(died)} die, {len(survived)} survive; "
          f"{len(invalid)} not applied, invalid or unverified"
          + (" [kills accepted on exit code alone: --trust-exit-code]" if arguments.trust_exit_code else ""))
    if survived:
        print("guarantees no test protects: " + ", ".join(survived))
    if invalid:
        print("not applied (stale or unsafe spec, fix it): " + ", ".join(invalid))
        return 2
    return 1 if survived else 0


if __name__ == "__main__":
    sys.exit(main())
