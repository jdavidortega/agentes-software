#!/bin/sh
# Huella del contenido revisable (viene con la plantilla; ver AGENTS.md §9).
#
# Hash de (blob, ruta) de TODO el contenido del proyecto —archivos rastreados y no
# rastreados no ignorados— EXCLUYENDO solo los REGISTROS que el cierre escribe después de
# la revisión: docs/revisiones.log (recibos), docs/revisiones/ (evidencia de cada revisión, atada
# a su recibo por su propia huella: ver modo evidencia y scripts/guardas.sh), docs/trazabilidad.md (filas de hallazgos),
# docs/estado.md (resumen regenerado) y docs/MEMORIA.md (lecciones y obstáculos).
# plan.md y convenciones.md SÍ cuentan: arquitectura, contratos, plan de pruebas y reglas
# son contenido que el revisor juzga; la bitácora narrativa del incremento se escribe
# ANTES de pedir la revisión (AGENTS.md §9).
#
#   sh scripts/huella.sh              → VIGENCIA: árbol de trabajo sin registros (lo que ve el revisor);
#                                       git no escribe nada (ni temporales, ni índice, ni objetos en .git);
#                                       un filtro clean/process configurado sí corre (se avisa)
#   sh scripts/huella.sh indice       → VIGENCIA sobre el ÍNDICE (lo que va al commit; commit-msg)
#   sh scripts/huella.sh integridad   → INTEGRIDAD: árbol COMPLETO, registros incluidos; sin escrituras. El
#                                       principal la toma antes y después de cada revisor: si
#                                       cambia, el revisor escribió algo (en lo que sea).
#   sh scripts/huella.sh commit <sha> → VIGENCIA del árbol de ese commit (el commit-msg la usa
#                                       para comprobar que el recibo de un hito corresponde a
#                                       un commit real del historial, no a una huella inventada).
# Son dos preguntas distintas: "¿sigue valiendo el recibo?" (vigencia) y "¿tocó algo el
# revisor?" (integridad). Ninguna observa la red ni los archivos ignorados por git.
#
# Si el árbol coincide con el índice en los rastreados y no hay no-rastreados pendientes,
# ambas huellas son iguales: el recibo de la revisión (línea de docs/revisiones.log con `huella=…`)
# solo es válido para el commit que guarda exactamente ese contenido.
MODE="${1:-arbol}"
# EVIDENCIA de una revisión: huella del CONTENIDO de una carpeta (rutas relativas + blob de cada
# archivo), igual se calcule en disco (el revisor, sobre su directorio autorizado) o en un árbol de
# git (guardas.sh: `git ls-tree -r <árbol>:<carpeta>`). Solo archivos regulares con nombres
# [A-Za-z0-9._/-]; un enlace simbólico o una carpeta vacía no son evidencia.
#   sh scripts/huella.sh evidencia <carpeta>      → 12 hex
if [ "$MODE" = "evidencia" ]; then
  d="${2:?huella: falta la carpeta de evidencia}"
  [ -d "$d" ] || { echo "huella: $d no es una carpeta" >&2; exit 2; }
  [ -z "$(find "$d" -type l | head -1)" ] || { echo "huella: $d contiene enlaces simbólicos; la evidencia son archivos regulares" >&2; exit 2; }
  lst=$(cd "$d" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
  [ -n "$lst" ] || { echo "huella: $d está vacía" >&2; exit 2; }
  printf '%s\n' "$lst" | grep -qvE '^[A-Za-z0-9._/-]+$' && { echo "huella: nombre de archivo fuera de [A-Za-z0-9._/-] en $d" >&2; exit 2; }
  printf '%s\n' "$lst" | while IFS= read -r f; do printf '%s %s\n' "$f" "$(git hash-object -- "$d/$f")"; done | git hash-object --stdin | cut -c1-12
  exit 0
fi
case "$MODE" in arbol|indice|integridad|commit) ;; *) echo "huella: modo desconocido '$MODE' (arbol | indice | integridad | commit <sha> | evidencia <carpeta>)" >&2; exit 2 ;; esac
EXCL='	docs/((revisiones\.log|trazabilidad\.md|estado\.md|MEMORIA\.md)$|revisiones/)'
[ "$MODE" = "integridad" ] && EXCL='^$'
git rev-parse --git-dir >/dev/null 2>&1 || { echo "huella: no es un repositorio git" >&2; exit 2; }
# assume-unchanged (h) / skip-worktree (S) harían que el índice copiado conserve contenido
# viejo y la huella mienta. No se calcula nada mientras existan.
flags=$(git ls-files -v | grep -E '^[a-z]|^S' || true)
[ -z "$flags" ] || { echo "huella: archivos con assume-unchanged/skip-worktree; quítalos (git update-index --no-assume-unchanged/--no-skip-worktree):" >&2; printf '%s\n' "$flags" >&2; exit 2; }
if [ "$MODE" = "indice" ]; then
  tree=$(git write-tree) || exit 2
elif [ "$MODE" = "commit" ]; then
  tree=$(git rev-parse --verify "${2:?huella: falta el commit}^{tree}" 2>/dev/null) || { echo "huella: commit desconocido $2" >&2; exit 2; }
else
  # Árbol de trabajo (vigencia o integridad) SIN ESCRIBIR NADA: ni temporales, ni índice, ni objetos
  # en .git. Reproduce línea a línea lo que daría `git add -A` + `git write-tree` + `git ls-tree -r`
  # (modo, tipo, blob con los filtros de git vía `hash-object` sin -w, rutas con las comillas de
  # core.quotePath), así la huella es la misma que la del índice cuando el índice está al día. Lo usan
  # el revisor en modalidad lectura (recibos.sh linea) y el principal antes y después de él.
  # LÍMITE: git no escribe, pero un filtro clean/process configurado (git-lfs, uno propio) es un
  # programa que corre al hashear y puede escribir; con filtros así no se certifica lectura estricta.
  filtros=$(git config --get-regexp '^filter\..*\.(clean|process)$' 2>/dev/null | cut -d' ' -f1 | tr '\n' ' ')
  [ -z "$filtros" ] || echo "huella: aviso: filtros de git configurados (${filtros% }); sus programas corren al calcular y pueden escribir: la huella no certifica lectura estricta" >&2
  lineas=$(python3 -I - <<'PY'
import os, stat, subprocess, sys, hashlib
def git(*a, inp=None):
    return subprocess.run(["git", *a], input=inp, capture_output=True, check=True).stdout
def flag(name, default):
    r = subprocess.run(["git", "config", "--bool", name], capture_output=True, text=True)
    return default if r.returncode else r.stdout.strip() == "true"
root = git("rev-parse", "--show-toplevel").decode().rstrip("\n")
os.chdir(root)
quote_path, file_mode = flag("core.quotePath", True), flag("core.fileMode", True)
index = {}
for rec in git("ls-files", "-z", "-s").split(b"\0"):
    if rec:
        meta, path = rec.split(b"\t", 1)
        mode, sha, _ = meta.split(b" ")
        index[path] = (mode.decode(), sha.decode())
paths = sorted({p.rstrip(b"/") for p in git("ls-files", "-z", "-c", "-o", "--exclude-standard").split(b"\0") if p})
ESC = {7: b"a", 8: b"b", 9: b"t", 10: b"n", 11: b"v", 12: b"f", 13: b"r", 34: b'"', 92: b"\\"}
def cquote(p, always=False, high=True):
    # Comillas al estilo C de git, en BYTES (nunca se reinterpreta un byte como otro carácter).
    if not always and not any(c < 32 or c in (34, 92, 127) or (high and c >= 128) for c in p):
        return p
    out = bytearray(b'"')
    for c in p:
        if c in ESC: out += b"\\" + ESC[c]
        elif c < 32 or c == 127 or (high and c >= 128): out += b"\\%03o" % c
        else: out.append(c)
    return bytes(out + b'"')
rows, regular = [], []
for p in paths:
    try:
        st = os.lstat(p)
    except FileNotFoundError:
        continue  # borrado del árbol: git add -A lo retira
    if stat.S_ISLNK(st.st_mode):
        data = os.readlink(p)
        rows.append([p, "120000", "blob", hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()])
    elif stat.S_ISDIR(st.st_mode):
        r = subprocess.run(["git", "-C", p, "rev-parse", "--verify", "-q", "HEAD"], capture_output=True, text=True)
        sha = r.stdout.strip() or index.get(p, ("", ""))[1]
        if sha:
            rows.append([p, "160000", "commit", sha])
    elif stat.S_ISREG(st.st_mode):
        if file_mode:
            mode = "100755" if st.st_mode & 0o100 else "100644"
        else:
            mode = index[p][0] if index.get(p, ("",))[0] in ("100644", "100755") else "100644"
        row = [p, mode, "blob", None]
        rows.append(row); regular.append(row)
if regular:
    # Todas las rutas entre comillas: --stdin-paths desentrecomilla toda línea que empieza por '"'.
    shas = git("hash-object", "--stdin-paths", inp=b"".join(cquote(r[0], always=True) + b"\n" for r in regular)).split()
    if len(shas) != len(regular):
        sys.exit("huella: hash-object no devolvió un blob por archivo")
    for row, sha in zip(regular, shas):
        row[3] = sha.decode()
for p, mode, typ, sha in rows:
    sys.stdout.buffer.write(f"{mode} {typ} {sha}\t".encode() + cquote(p, high=quote_path) + b"\n")
PY
) || exit 2
  { [ -z "$lineas" ] || printf '%s\n' "$lineas"; } | grep -vE "$EXCL" | git hash-object --stdin | cut -c1-12
  exit 0
fi
git ls-tree -r "$tree" | grep -vE "$EXCL" | git hash-object --stdin | cut -c1-12
