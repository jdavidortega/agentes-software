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
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ENVIRONMENT = {"PYTHONDONTWRITEBYTECODE": "1"}
IGNORED = (
    ".venv", ".git", "__pycache__", "*.pyc", ".pytest_cache", ".ruff_cache",
    ".mypy_cache", "node_modules", "dist", "build", "target",
)
# Dot-entries DO travel -- `.claude/`, `.githooks/`, `.env.example` are part of the tree, and a
# check that reads one of them would pass vacuously in a copy that lacks it (measured: the guard
# over the skill symlinks turned the base red, which reads as "the suite was broken" and is really
# "the copy was incomplete"). Real secrets never travel: a mutation harness has no business
# planting an `.env` in a temporary directory, and `.env.example` covers what a check needs.
SECRETS = (".env", ".env.local", ".env.prod", ".env.production")


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
        subprocess.run(f"git archive {commit} | tar -x -C {tree}", shell=True, cwd=root, check=True)
        return
    for entry in root.iterdir():
        if entry.name in IGNORED or entry.name in SECRETS:
            continue
        target = tree / entry.name
        if entry.is_dir():
            # `symlinks=True`: if the tree contains symlinks, copy them as links --
            # dereferencing can turn link-aware guards red in the copy for reasons
            # that have nothing to do with the mutation.
            shutil.copytree(entry, target, ignore=shutil.ignore_patterns(*IGNORED), symlinks=True)
        else:
            shutil.copy(entry, target)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
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
    arguments = parser.parse_args()

    root = arguments.root.resolve()
    mutations = json.loads(arguments.spec.read_text(encoding="utf-8"))
    if not mutations:
        print("the spec has no mutations: nothing to prove", file=sys.stderr)
        return 1
    command = arguments.suite.split()
    # The suite runs from inside the copy, so a relative interpreter has to be resolved here.
    # Only a path, though: `--suite "bash scripts/x.sh"` names a program on PATH, and prefixing it
    # with the root produced a FileNotFoundError for `<root>/bash` that read as a broken harness.
    if "/" in command[0] and not Path(command[0]).is_absolute():
        command[0] = str(root / command[0])

    with tempfile.TemporaryDirectory() as temporary:
        tree = Path(temporary) / "tree"
        tree.mkdir()
        plant(tree, root, arguments.commit)
        if not suite(tree, command, arguments.timeout):
            print(
                "the suite is not green before mutating: every result would be noise",
                file=sys.stderr,
            )
            return 1
        origin = f"commit {arguments.commit}" if arguments.commit else "the working tree"
        print(f"base green over {origin}")

        survivors = []
        for mutation in mutations:
            path = tree / mutation["file"]
            original = path.read_text(encoding="utf-8")
            if mutation["before"] not in original:
                # Loudly, and not as a survivor: an anchor that moved means the spec is stale,
                # which is a different problem from a guarantee that does not hold.
                print(f"  ANCHOR LOST {mutation['label']}: {mutation['file']}")
                continue
            path.write_text(
                original.replace(mutation["before"], mutation["after"], 1), encoding="utf-8"
            )
            green = suite(tree, command, arguments.timeout)
            print(f"  {'SURVIVES' if green else 'DIES    '} {mutation['label']}")
            if green:
                survivors.append(mutation["label"])
            path.write_text(original, encoding="utf-8")

    print(f"\n{len(mutations) - len(survivors)}/{len(mutations)} die")
    if survivors:
        print("guarantees no test protects: " + ", ".join(survivors))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
