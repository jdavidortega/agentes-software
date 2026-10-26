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
A script that opens files itself (python, git internals, `python3 -c 'open(...)'`) is invisible to it.
Quoted text is ignored to DETECT commands (`grep "rm -rf"` is a read) but kept to RESOLVE destinations
(`touch "/x"` writes /x). git global options (-C, -c, --git-dir, --work-tree) are parsed before the
subcommand, and its explicit targets (init, clone, worktree add, config --file, -o) count after
consuming each option with its arity (an unknown option makes the target unknown); mv judges source
and target; cd moves the rest of its && chain, and later segments only if the directory already
exists (never from a pipeline);
a write whose destination cannot be placed, in any segment, is rejected. Procedure and report fields: .claude/skills/dirigiendo-revisiones.
"""
import json
import os
import re
import shlex
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


# --- Análisis por destino: tramos, comillas conservadas, opciones globales de git -------------
# Cada escritura se juzga por SU destino: que otro tramo nombre el directorio autorizado no autoriza
# nada. Los tramos se tokenizan con shlex CONSERVANDO el contenido de las comillas (`touch "/x"`
# escribe en /x); un destino con $ o comillas invertidas es desconocido. Lo que el filtro no sabe
# interpretar ($( ), comillas invertidas, <<, eval, xargs, -c, find -exec) junto a una escritura se
# rechaza. Sigue siendo una heurística sobre el texto: no ve lo que escribe un programa lanzado.
NO_INTERPRETABLE = re.compile(r"\$\(|`|<<|(^|[\s;&|(])(eval|xargs|bash\s+-c|sh\s+-c|zsh\s+-c|python3?\s+-c|find\s.*-(exec|delete))(\s|$)")
TODOS_LOS_ARGS = {"touch", "mkdir", "rm", "rmdir", "truncate", "tee", "mv"}   # mv: el origen también se modifica
SALVO_EL_PRIMERO = {"chmod", "chown", "sed", "perl"}
EL_ULTIMO = {"cp", "ln", "install"}
EN_EL_DIRECTORIO = {"patch", "pip", "pip3", "python", "python3", "npm", "uv"}
OPCION_CON_VALOR = {"truncate": {"-s", "--size"}, "install": {"-m", "-o", "-g"}, "cp": {"-t"}, "mv": {"-t"}, "ln": {"-t"}}
# Envoltorios: se analiza la orden que envuelven, consumiendo sus opciones con su aridad. `env -C` y
# `sudo -D` cambian el directorio: lo que sigue tiene directorio desconocido.
ENVOLTORIOS = {"env": {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}, "nice": {"-n", "--adjustment"},
               "nohup": set(), "command": set(), "time": set(), "exec": {"-a"}, "builtin": set(),
               "stdbuf": {"-i", "-o", "-e"}, "timeout": {"-s", "--signal", "-k", "--kill-after"},
               "sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-U", "-r", "-t", "-R"}, "caffeinate": {"-t", "-w"}}
CAMBIA_DIR = {("env", "-C"), ("env", "--chdir"), ("sudo", "-D")}
# Órdenes que SIEMPRE escriben: si aparecen en un tramo que el análisis no supo ubicar (p. ej. tras un
# envoltorio con opciones desconocidas), ese tramo tiene un destino desconocido. git, sed, pip… se
# juzgan por su propio análisis (pueden ser lecturas).
ESCRITORES = {"touch", "mkdir", "rm", "rmdir", "truncate", "tee", "mv", "chmod", "chown", "cp", "ln", "install", "dd"}
GIT_ESCRIBE = {"add", "commit", "reset", "checkout", "switch", "restore", "stash", "rm", "mv", "clean", "push",
               "tag", "branch", "merge", "rebase", "apply", "am", "update-index", "worktree", "init", "clone",
               "pull", "fetch", "cherry-pick", "revert", "notes", "update-ref", "gc", "prune", "submodule", "replace"}
GIT_OPCION_CON_VALOR = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
# Opciones de los subcomandos de git cuyos operandos son destinos: (sin valor, con valor). Una opción
# que no está en ninguna de las dos hace que el destino quede desconocido (no se adivina su aridad).
GIT_OPCIONES = {
    # --shared[=<permisos>]: valor OPCIONAL, solo unido con «=»; sin él no consume el siguiente argumento.
    "init": ({"-q", "--quiet", "--bare", "--shared"},
             {"--template", "--separate-git-dir", "-b", "--initial-branch", "--object-format", "--ref-format"}),
    "clone": ({"-q", "--quiet", "-v", "--verbose", "--bare", "--mirror", "-n", "--no-checkout", "-l", "--local",
               "--no-hardlinks", "-s", "--shared", "--recursive", "--recurse-submodules", "--single-branch",
               "--no-single-branch", "--no-tags", "--shallow-submodules", "--no-shallow-submodules", "--progress",
               "--sparse", "--dissociate", "--reject-shallow", "--also-filter-submodules", "--remote-submodules"},
              {"-b", "--branch", "-o", "--origin", "--depth", "-c", "--config", "--reference", "--reference-if-able",
               "--separate-git-dir", "-u", "--upload-pack", "--template", "--filter", "-j", "--jobs",
               "--shallow-since", "--shallow-exclude", "--server-option", "--bundle-uri", "--revision", "--ref-format"}),
    "worktree": ({"-f", "--force", "-d", "--detach", "--checkout", "--no-checkout", "--lock", "-q", "--quiet",
                  "--track", "--no-track", "--guess-remote", "--no-guess-remote", "--orphan", "--relative-paths"},
                 {"-b", "-B", "--reason"}),
}
SEPARADORES_T = {";", "&&", "||", "|", "&", "|&"}
REDIRECCIONES_T = {">", ">>", "&>", "&>>", ">|", ">&", "<>"}
ENTRADAS_T = {"<", "<<", "<<<", "<&"}


def resolver(ruta: str, cwd: str | None) -> str | None:
    """Ruta absoluta normalizada, o None si no se puede saber a dónde apunta."""
    if not ruta or "$" in ruta or "`" in ruta or ruta.startswith("~"):
        return None
    if not os.path.isabs(ruta):
        if cwd is None:
            return None
        ruta = os.path.join(cwd, ruta)
    return os.path.normpath(ruta)


def dentro(ruta: str | None, permitido: str) -> bool:
    return ruta is not None and (ruta == permitido or ruta.startswith(permitido + "/"))


def lineas_a_tramos(cmd: str) -> str:
    """Saltos de línea fuera de comillas → ';' (y la continuación con barra se une)."""
    out, q, i = [], None, 0
    while i < len(cmd):
        c = cmd[i]
        if q is None and c == "\\" and cmd[i + 1:i + 2] == "\n":
            i += 2
            continue
        if q is None and c == "\\" and i + 1 < len(cmd):
            out.append(cmd[i:i + 2]); i += 2
            continue
        if c in "'\"":
            q = None if q == c else (c if q is None else q)
        out.append(" ; " if c == "\n" and q is None else c)
        i += 1
    return "".join(out)


OPERADORES = sorted(SEPARADORES_T | REDIRECCIONES_T | ENTRADAS_T | {"(", ")"}, key=len, reverse=True)


def partir(t: str) -> list[str] | None:
    """shlex agrupa la puntuación contigua (`);`, `)&&`): se parte en operadores conocidos, el más
    largo primero. Un resto que no es un operador conocido hace el texto no interpretable."""
    out = []
    while t:
        op = next((o for o in OPERADORES if t.startswith(o)), None)
        if op is None:
            return None
        out.append(op)
        t = t[len(op):]
    return out


def tokens(cmd: str) -> list[str] | None:
    try:
        lex = shlex.shlex(lineas_a_tramos(cmd), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = ""
        crudos = list(lex)
    except ValueError:
        return None
    out = []
    for t in crudos:
        if t and all(c in lex.punctuation_chars for c in t) and t not in OPERADORES:
            partes = partir(t)
            if partes is None:
                return None
            out.extend(partes)
        else:
            out.append(t)
    return out


def operandos(args: list[str], sin_valor: set[str], con_valor: set[str]) -> list[str] | None:
    """Operandos tras consumir las opciones con su aridad; None si aparece una opción desconocida."""
    out, i, fin = [], 0, False
    while i < len(args):
        a = args[i]
        if fin or not a.startswith("-") or a == "-":
            out.append(a); i += 1
        elif a == "--":
            fin = True; i += 1
        elif a in sin_valor or ("=" in a and a.split("=", 1)[0] in con_valor | sin_valor):
            i += 1
        elif a in con_valor:
            i += 2
        elif re.fullmatch(r"-[A-Za-z]{2,}", a) and all(f"-{c}" in sin_valor for c in a[1:]):
            i += 1   # banderas cortas agrupadas (-qf)
        else:
            return None   # opción desconocida: no se adivina su aridad
    return out


def git_destino(args: list[str], cwd: str | None) -> tuple[bool, list[str | None]]:
    """(¿escribe?, destinos) de `git <opciones globales> <subcomando> …`."""
    d, i, raro = cwd, 0, False
    while i < len(args):
        a = args[i]
        base = a.split("=", 1)[0]
        if a == "-C":
            d = resolver(args[i + 1], d) if i + 1 < len(args) else None
            i += 2
        elif base in GIT_OPCION_CON_VALOR:
            raro = raro or base in {"--git-dir", "--work-tree"}
            i += 1 if "=" in a else 2
        elif a.startswith("-"):
            i += 1
        else:
            break
    if i >= len(args):
        return False, []
    sub, resto = args[i], args[i + 1:]
    salida = []   # -o/--output/--output-directory escriben donde dicen, sea cual sea el subcomando
    for j, a in enumerate(resto):
        if a in ("-o", "--output", "--output-directory") and j + 1 < len(resto):
            salida.append(resolver(resto[j + 1], d))
        elif a.startswith(("--output=", "--output-directory=")):
            salida.append(resolver(a.split("=", 1)[1], d))
    escribe = sub in GIT_ESCRIBE or (sub == "config" and git_config_writes("git config " + " ".join(resto)))
    if not escribe:
        return bool(salida), salida
    if raro:
        return True, [None]
    posicionales = operandos(resto, *GIT_OPCIONES[sub]) if sub in GIT_OPCIONES else [a for a in resto if not a.startswith("-")]
    if posicionales is None:
        return True, [None]   # una opción que no se sabe si consume valor: destino desconocido
    ds: list[str | None] = [d] + salida
    if sub == "init":   # git init [dir] [--separate-git-dir X]
        ds += [resolver(a, d) for a in posicionales]
    elif sub == "clone":   # git clone <repo> [dir]
        ds += [resolver(posicionales[1], d)] if len(posicionales) > 1 else []
    elif sub == "worktree":   # git worktree add <ruta> …
        ds += [resolver(posicionales[1], d)] if posicionales[:1] == ["add"] and len(posicionales) > 1 else ([None] if posicionales[:1] in (["add"], ["move"]) else [])
    elif sub == "config":   # --file/-f escribe ese archivo; --global/--system escriben fuera
        for j, a in enumerate(resto):
            if a in ("--file", "-f") and j + 1 < len(resto):
                ds.append(resolver(resto[j + 1], d))
            elif a.startswith("--file="):
                ds.append(resolver(a.split("=", 1)[1], d))
            elif a in ("--global", "--system"):
                ds.append(None)
    elif sub == "submodule":
        ds.append(None)   # rutas y clones internos: no se modelan
    for a in resto:
        if a.startswith("--separate-git-dir"):
            ds.append(resolver(a.split("=", 1)[1], d) if "=" in a else None)
    return True, ds


def destinos(palabras: list[str], cwd: str | None) -> tuple[str | None, list[str | None]]:
    """(comando que escribe, destinos) de las palabras de un tramo; (None, []) si no escribe."""
    while palabras and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", palabras[0]):
        palabras = palabras[1:]   # asignaciones de entorno (TMPDIR=…) no escriben
    if not palabras:
        return None, []
    cmd, args = os.path.basename(palabras[0]), palabras[1:]
    if cmd in ENVOLTORIOS:
        resto, d = list(args), cwd
        while resto:
            a = resto[0]
            if a in ENVOLTORIOS[cmd]:
                if (cmd, a) in CAMBIA_DIR:
                    d = None
                resto = resto[2:]
            elif a.startswith("-") or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", a) \
                    or (cmd == "timeout" and re.fullmatch(r"[0-9.]+[smhd]?", a)):
                if a.split("=", 1)[0] in {"--chdir"}:
                    d = None
                resto = resto[1:]
            else:
                break
        return destinos(resto, d)
    if cmd == "git":
        escribe, ds = git_destino(args, cwd)
        return ("git", ds) if escribe else (None, [])
    if cmd == "dd":
        ds = [resolver(a[3:], cwd) for a in args if a.startswith("of=")]
        return ("dd", ds) if ds else (None, [])
    if cmd in EN_EL_DIRECTORIO:
        return (cmd, [cwd]) if WRITE_COMMANDS.search(" ".join([cmd] + args)) else (None, [])
    if cmd not in TODOS_LOS_ARGS | SALVO_EL_PRIMERO | EL_ULTIMO:
        return None, []
    if cmd in ("sed", "perl") and not any(re.fullmatch(r"-[a-zA-Z]*i.*|--in-place.*", a) for a in args):
        return None, []   # sed sin -i, perl sin -i: lectura
    pos, saltar, fin_opciones = [], False, False
    for a in args:
        if saltar:
            if cmd in EL_ULTIMO or cmd == "mv":
                pos.append(a)
            saltar = False
            continue
        if not fin_opciones and a == "--":
            fin_opciones = True
            continue
        if not fin_opciones and a in OPCION_CON_VALOR.get(cmd, set()):
            saltar = True
            continue
        if not fin_opciones and a.startswith("-") and a != "-":
            continue
        pos.append(a)
    if cmd in SALVO_EL_PRIMERO:
        pos = pos[1:]
    elif cmd in EL_ULTIMO:
        pos = pos[-1:]
    return cmd, [resolver(p, cwd) for p in pos]


def analiza(cmd: str, cwd: str | None) -> list[tuple[str, str | None]] | None:
    """Escrituras (comando, destino) por tramo; None si el texto no se puede tokenizar."""
    toks = tokens(cmd)
    if toks is None:
        return None
    escrituras, pila = [], []
    tramo: list[str] = []
    TUBERIA = {"|", "|&"}
    incierto_al_cortar = [False]

    def cierra(t: list[str], cwd_t: str | None, antes: str | None = None, despues: str | None = None) -> str | None:
        palabras, i = [], 0
        while i < len(t):
            x = t[i]
            if x in REDIRECCIONES_T:
                if palabras and palabras[-1].isdigit():
                    palabras.pop()   # 2> : el número es el descriptor, no un argumento
                obj = t[i + 1] if i + 1 < len(t) else ""
                if not (x == ">&" and (obj.isdigit() or obj == "-")) and obj not in HARMLESS_TARGETS:
                    escrituras.append((f"> {obj}", resolver(obj, cwd_t)))
                i += 2
                continue
            if x in ENTRADAS_T:
                if palabras and palabras[-1].isdigit():
                    palabras.pop()
                i += 2
                continue
            palabras.append(x)
            i += 1
        if palabras[:1] == ["cd"]:
            r = resolver(palabras[1], cwd_t) if len(palabras) > 1 and palabras[1] != "-" else None
            if antes in TUBERIA or despues in TUBERIA or despues == "&":
                return cwd_t                 # en una tubería o en segundo plano no cambia el directorio de fuera
            if despues == "&&":
                if r is None or not os.path.isdir(r):
                    incierto_al_cortar[0] = True   # si el cd falla, lo que sigue a la cadena corre en el de antes
                return r                     # lo que sigue en la cadena solo corre si el cd funcionó
            if despues == "||":
                return None                  # lo que sigue corre si el cd FALLÓ: directorio incierto
            return r if r is not None and os.path.isdir(r) else None   # ; o fin: si puede fallar, incierto
        c, ds = destinos(palabras, cwd_t)
        if c is None and any(w in ESCRITORES for w in palabras):
            ds, c = [None], next(w for w in palabras if w in ESCRITORES)   # escritor que no se sabe ubicar
        escrituras.extend((c, d) for d in ds)
        return cwd_t

    antes = None
    for x in toks:
        if x in SEPARADORES_T:
            cwd = cierra(tramo, cwd, antes, x); tramo = []; antes = x
            if x != "&&" and incierto_al_cortar[0]:
                cwd, incierto_al_cortar[0] = None, False   # la cadena && terminó: el cd pudo fallar
        elif x == "(":
            cwd = cierra(tramo, cwd, antes, ";"); tramo = []; pila.append((cwd, incierto_al_cortar[0])); antes = None
            incierto_al_cortar[0] = False
        elif x == ")":
            cierra(tramo, cwd, antes, ";"); tramo = []
            if pila:   # un cd dentro de ( ) no cambia el directorio de fuera ni su incertidumbre
                cwd, incierto_al_cortar[0] = pila.pop()
        else:
            tramo.append(x)
    cierra(tramo, cwd, antes, None)
    return escrituras


def escrituras_fuera(cmd: str, permitido: str, cwd: str | None) -> list[str]:
    """Escrituras cuyo destino no está (o no se sabe si está) dentro del directorio autorizado."""
    if NO_INTERPRETABLE.search(strip_quotes(cmd)):
        return ["construcción que el filtro no interpreta ($( ), comillas invertidas, <<, eval, xargs, -c, find -exec) junto a una escritura"]
    esc = analiza(cmd, cwd)
    if esc is None:
        return ["comando que el filtro no puede tokenizar (comillas sin cerrar) junto a una escritura"]
    if not esc:
        return ["escritura detectada con destino indeterminable"]   # el texto escribe y el análisis no la ubicó
    return [f"{c} → {d or 'destino desconocido'}" for c, d in esc if not dentro(d, permitido)]


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
    esc = analiza(cmd, data.get("cwd") or None)
    if esc:   # lo que el análisis por tramos ve (git -C …, destinos entre comillas) también cuenta
        hits += [f"{c} → {d or 'destino desconocido'}" for c, d in esc]
    elif esc is None and NO_INTERPRETABLE.search(strip_quotes(cmd)) is None and WRITE_COMMANDS.search(cmd):
        hits.append("comando sin tokenizar con un patrón de escritura")
    crudo = re.sub(r"[\"']", " ", cmd)   # el texto que sh -c / eval / xargs ejecutarían, sin comillas pegadas
    if NO_INTERPRETABLE.search(strip_quotes(cmd)) and (WRITE_COMMANDS.search(crudo) or REDIRECTION.search(crudo)):
        hits.append("construcción que el filtro no interpreta con una escritura en su texto")
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
