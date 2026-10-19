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

Each mutation is applied alone to a copy of the tree, the suite runs, and the mutation is
reverted before the next one. `DIES` means the suite went red, which is the answer you want:
the guarantee is real. `SURVIVES` means the guarantee is a comment.

A mutation that could NOT be applied (`ANCHOR LOST`: the `before` text is not in the file;
`MISSING`: the file does not exist; `ESCAPES`: the path resolves outside the copy, e.g. a
symlink) is reported apart and NEVER counted as a kill. Exit codes: 0 = every mutation was
applied and died; 1 = at least one survived; 2 = at least one could not be applied (the spec
is stale or unsafe -- fix the spec, do not read it as a pass).

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


def suite(tree: Path, command: list[str], timeout: int) -> bool:
    """True when the suite is green in `tree`. A crash or a timeout counts as red."""
    try:
        done = subprocess.run(
            command,
            cwd=tree,
            capture_output=True,
            timeout=timeout,
            env={**os.environ, **ENVIRONMENT},
        )
    except subprocess.TimeoutExpired:
        return False
    return done.returncode == 0


def plant(tree: Path, root: Path, commit: str | None) -> None:
    """Fill `tree` with the code to mutate: a commit, or the working tree as it stands."""
    if commit:
        tree.mkdir()
        subprocess.run(f"git archive {commit} | tar -x -C {tree}", shell=True, cwd=root, check=True)
        return
    # `symlinks=True`: links are copied as links, never dereferenced -- and `contained()`
    # below refuses to mutate through any of them.
    shutil.copytree(root, tree, ignore=ignore, symlinks=True)


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
    # The suite runs from inside the copy, so a relative interpreter has to be resolved here.
    # Only a path, though: `--suite "bash scripts/x.sh"` names a program on PATH.
    if "/" in command[0] and not Path(command[0]).is_absolute():
        command[0] = str(root / command[0])

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
        plant(tree, root, arguments.commit)
        if not suite(tree, command, arguments.timeout):
            print("the suite is not green before mutating: every result would be noise", file=sys.stderr)
            return 2
        origin = f"commit {arguments.commit}" if arguments.commit else "the working tree"
        print(f"base green over {origin}")

        died, survived, invalid = [], [], []
        for mutation in mutations:
            label = mutation["label"]
            path = contained(tree, mutation["file"])
            if path is None:
                kind = "ESCAPES " if (tree / mutation["file"]).is_symlink() else "MISSING "
                print(f"  {kind} {label}: {mutation['file']} (not a regular file inside the copy)")
                invalid.append(label)
                continue
            original = path.read_text(encoding="utf-8")
            if mutation["before"] not in original:
                # A stale anchor is a different problem from a guarantee that does not hold,
                # and it is never a kill.
                print(f"  ANCHOR LOST {label}: {mutation['file']}")
                invalid.append(label)
                continue
            path.write_text(original.replace(mutation["before"], mutation["after"], 1), encoding="utf-8")
            try:
                green = suite(tree, command, arguments.timeout)
            finally:
                path.write_text(original, encoding="utf-8")
            print(f"  {'SURVIVES' if green else 'DIES    '} {label}")
            (survived if green else died).append(label)

    print(f"\napplied {len(died) + len(survived)}/{len(mutations)}: {len(died)} die, {len(survived)} survive; "
          f"{len(invalid)} not applied")
    if survived:
        print("guarantees no test protects: " + ", ".join(survived))
    if invalid:
        print("not applied (stale or unsafe spec, fix it): " + ", ".join(invalid))
        return 2
    return 1 if survived else 0


if __name__ == "__main__":
    sys.exit(main())
