#!/usr/bin/env python3
"""Preventive filter for reviewer subagents (PreToolUse hook on Bash). NOT a security boundary.

Registered in .claude/settings.json for every agent; it only acts when `agent_type` is one of the
four reviewers. It reads the hook JSON from stdin and blocks (exit 2, reason on stderr) Bash commands
that OBVIOUSLY write, according to the review mode the principal set in `.git/revision-modalidad`:

    lectura                      (default when the file is missing) no obvious write is allowed
    experimentos <absolute dir>  obvious writes are allowed only if the command names that dir

Limits, by design (docs: Bash rules "aren't a security boundary"): it sees the command text only.
A script that opens files itself (python, git internals) is invisible to it. Quoted text is ignored,
so `grep "rm -rf"` is a read. Procedure and report fields: .claude/skills/dirigiendo-revisiones.
"""
import json
import os
import re
import sys

REVIEWERS = {"revisor-funcional", "juez-codigo", "juez-conjunto", "juez-seguridad"}
WRITE_COMMANDS = re.compile(
    r"(^|[\s;&|(])("
    r"rm|rmdir|mv|cp|mkdir|touch|tee|ln|chmod|chown|truncate|dd|install|patch|"
    r"sed\s+(-[a-zA-Z]*i|--in-place)|perl\s+-[a-zA-Z]*i|"
    r"git\s+(add|commit|reset|checkout|switch|restore|stash|rm|mv|clean|push|tag|branch|merge|rebase|apply|am|config|update-index|worktree|init|clone)|"
    r"pip3?\s+install|python3?\s+-m\s+pip\s+install|npm\s+(install|ci)|uv\s+(pip|add|sync)"
    r")(\s|$)"
)
REDIRECTION = re.compile(r"(\d*>>?|&>>?)\s*([^\s;&|]+)")
HARMLESS_TARGETS = {"/dev/null", "&1", "&2", "/dev/stdout", "/dev/stderr"}


def strip_quotes(cmd: str) -> str:
    """Drop quoted text so patterns inside arguments (grep "rm") are not taken as commands."""
    cmd = re.sub(r"'[^']*'", "''", cmd)
    return re.sub(r'"(\\.|[^"\\])*"', '""', cmd)


def mode(project_dir: str) -> tuple[str, str]:
    path = os.path.join(project_dir, ".git", "revision-modalidad")
    try:
        with open(path, encoding="utf-8") as fh:
            parts = fh.read().split(maxsplit=1)
    except OSError:
        return "lectura", ""
    if parts and parts[0] == "experimentos" and len(parts) == 2 and os.path.isabs(parts[1].strip()):
        return "experimentos", parts[1].strip().rstrip("/")
    return "lectura", ""


def writes(cmd: str) -> list[str]:
    bare = strip_quotes(cmd)
    found = [m.group(2).split()[0] for m in WRITE_COMMANDS.finditer(bare)]
    found += [f"> {m.group(2)}" for m in REDIRECTION.finditer(bare) if m.group(2) not in HARMLESS_TARGETS]
    return found


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    if data.get("agent_type") not in REVIEWERS or data.get("tool_name") != "Bash":
        return 0
    cmd = str((data.get("tool_input") or {}).get("command", ""))
    project = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
    kind, allowed = mode(project)
    hits = writes(cmd)
    if not hits:
        return 0
    if kind == "experimentos" and allowed and allowed in cmd:
        return 0
    where = f"solo en {allowed}" if kind == "experimentos" else "en ningún sitio"
    print(
        f"guarda-revisor (filtro preventivo, no frontera): modalidad «{kind}» leída de "
        f"{os.path.join(project, '.git', 'revision-modalidad')}, escritura permitida {where}. "
        f"Bloqueado por: {', '.join(sorted(set(hits)))}. Si la revisión necesita escribir, pide al "
        f"principal la modalidad «experimentos» con su directorio autorizado.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
