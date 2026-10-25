#!/usr/bin/env python3
"""Preventive filter for reviewer subagents (PreToolUse hook on Bash). NOT a security boundary.

Registered in .claude/settings.json for every agent; it only acts when `agent_type` is one of the
four reviewers. It reads the hook JSON from stdin and blocks (exit 2, reason on stderr) Bash commands
that OBVIOUSLY write, according to the review mode the principal set in `.git/revision-modalidad`:

    lectura                      (default when the file is missing) no obvious write is allowed
    experimentos <absolute dir>  each obvious write is judged by ITS destination (segments, cd,
                                 redirections, per-command targets); naming the dir elsewhere in
                                 the line authorizes nothing; constructs it cannot interpret
                                 ($( ), backticks, <<, eval, xargs, -c, find -exec) next to a
                                 write are rejected

Limits, by design (docs: Bash rules "aren't a security boundary"): it is a HEURISTIC over the
command text only.
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
    r"git\s+(add|commit|reset|checkout|switch|restore|stash|rm|mv|clean|push|tag|branch|merge|rebase|apply|am|update-index|worktree|init|clone)|"
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


GIT_CONFIG = re.compile(r"(^|[\s;&|(])git\s+config((\s+[^\s;&|<>]+)*)")  # a redirection ends the args
GIT_CONFIG_WRITE_OPTS = {"--unset", "--unset-all", "--add", "--replace-all", "--rename-section",
                         "--remove-section", "-e", "--edit"}
GIT_CONFIG_VALUE_OPTS = {"--file", "-f", "--blob", "--type", "--default"}


def git_config_writes(bare: str) -> bool:
    """`git config` reads (`--get`, `--list`, `<key>`) pass; writes (`<key> <value>`, --unset…) do not."""
    for m in GIT_CONFIG.finditer(bare):
        args, positional, skip = m.group(2).split(), 0, False
        for a in args:
            if skip:
                skip = False
                continue
            if a in GIT_CONFIG_WRITE_OPTS:
                return True
            if a in GIT_CONFIG_VALUE_OPTS:
                skip = True
                continue
            if not a.startswith("-"):
                positional += 1
        if positional >= 2:
            return True
    return False


def writes(cmd: str) -> list[str]:
    bare = strip_quotes(cmd)
    found = [m.group(2).split()[0] for m in WRITE_COMMANDS.finditer(bare)]
    if git_config_writes(bare):
        found.append("git config (escritura)")
    found += [f"> {m.group(2)}" for m in REDIRECTION.finditer(bare) if m.group(2) not in HARMLESS_TARGETS]
    return found


# --- «experimentos»: cada escritura se juzga por SU destino, no por la línea entera -----------
# Que otro tramo del comando nombre el directorio autorizado (p. ej. `TMPDIR=<dir> sh doctor`) no
# autoriza un `touch` en otro sitio. Lo que el filtro no sabe interpretar no se da por permitido.
SEPARADORES = re.compile(r"\|\||&&|;|\n|\|(?!\|)|(?<![<>&])&(?![>&])")
NO_INTERPRETABLE = re.compile(r"\$\(|`|<<|(^|[\s;&|(])(eval|xargs|bash\s+-c|sh\s+-c|zsh\s+-c|python3?\s+-c|find\s.*-(exec|delete))(\s|$)")
TODOS_LOS_ARGS = {"touch", "mkdir", "rm", "rmdir", "truncate", "tee"}
SALVO_EL_PRIMERO = {"chmod", "chown", "sed", "perl"}
EL_ULTIMO = {"cp", "mv", "ln", "install"}
EN_EL_DIRECTORIO = {"patch", "pip", "pip3", "python", "python3", "npm", "uv"}
OPCION_CON_VALOR = {"truncate": {"-s", "--size"}, "install": {"-m", "-o", "-g"}, "cp": {"-t"}, "mv": {"-t"}, "ln": {"-t"}}


def resolver(ruta: str, cwd: str | None) -> str | None:
    """Ruta absoluta normalizada, o None si no se puede saber a dónde apunta."""
    if not ruta or "$" in ruta or ruta.startswith("~"):
        return None
    if not os.path.isabs(ruta):
        if cwd is None:
            return None
        ruta = os.path.join(cwd, ruta)
    return os.path.normpath(ruta)


def dentro(ruta: str | None, permitido: str) -> bool:
    return ruta is not None and (ruta == permitido or ruta.startswith(permitido + "/"))


def destinos(palabras: list[str], cwd: str | None) -> list[str | None] | None:
    """Destinos de escritura del comando de un tramo; None si no hay comando que escriba."""
    while palabras and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=\S*", palabras[0]):
        palabras = palabras[1:]   # asignaciones de entorno (TMPDIR=…) no escriben
    if not palabras:
        return None
    cmd, args = palabras[0], palabras[1:]
    if cmd == "git":
        sub = [a for a in args if not a.startswith("-")]
        dir_c = args[args.index("-C") + 1] if "-C" in args and args.index("-C") + 1 < len(args) else None
        escribe = bool(WRITE_COMMANDS.search(" ".join(["git"] + sub[:1]))) or git_config_writes(" ".join(palabras))
        return [resolver(dir_c, cwd) if dir_c else cwd] if escribe else None
    if cmd == "dd":
        return [resolver(a[3:], cwd) for a in args if a.startswith("of=")] or None
    if cmd in EN_EL_DIRECTORIO:
        return [cwd] if WRITE_COMMANDS.search(" ".join(palabras)) else None
    if cmd not in TODOS_LOS_ARGS | SALVO_EL_PRIMERO | EL_ULTIMO:
        return None
    if cmd in ("sed", "perl") and not WRITE_COMMANDS.search(" ".join(palabras)):
        return None   # sed sin -i, perl sin -i: lectura
    pos, saltar = [], False
    for a in args:
        if saltar:
            pos.append(a) if a and cmd in EL_ULTIMO else None
            saltar = False
            continue
        if a in OPCION_CON_VALOR.get(cmd, set()):
            saltar = True
            continue
        if a.startswith("-") or a == "''" or a == '""':
            continue
        pos.append(a)
    if cmd in SALVO_EL_PRIMERO:
        pos = pos[1:]
    elif cmd in EL_ULTIMO:
        pos = pos[-1:]
    return [resolver(p, cwd) for p in pos]


def escrituras_fuera(cmd: str, permitido: str, cwd: str | None) -> list[str]:
    """Escrituras cuyo destino no está (o no se sabe si está) dentro del directorio autorizado."""
    bare = strip_quotes(cmd)
    if NO_INTERPRETABLE.search(bare):
        return ["construcción que el filtro no interpreta ($( ), comillas invertidas, <<, eval, xargs, -c, find -exec) junto a una escritura"]
    fuera = []
    for tramo in SEPARADORES.split(bare):
        for m in REDIRECTION.finditer(tramo):
            if m.group(2) not in HARMLESS_TARGETS and not dentro(resolver(m.group(2), cwd), permitido):
                fuera.append(f"> {m.group(2)}")
        palabras = REDIRECTION.sub(" ", tramo).split()
        if palabras[:1] == ["cd"]:
            cwd = resolver(palabras[1], cwd) if len(palabras) > 1 else None
            continue
        for d in destinos(palabras, cwd) or []:
            if not dentro(d, permitido):
                fuera.append(f"{palabras[0] if palabras else '?'} → {d or 'destino desconocido'}")
    return fuera


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
    if kind == "experimentos" and allowed:
        fuera = escrituras_fuera(cmd, allowed, data.get("cwd") or None)
        if not fuera:
            return 0
        hits = fuera
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
