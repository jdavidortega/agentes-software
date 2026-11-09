#!/bin/sh
# Validador de transiciones sobre el HISTORIAL (viene con la plantilla; README §Enforcement).
# Reejecuta sobre cada commit de un rango lo que los hooks exigen al commitear: el contrato
# del commit-msg (trailers, recibos vigentes por huella, hito, código solo con Ref: I<n>) y
# las guardas de contenido del pre-commit (scripts/guardas.sh: secretos, append-only de
# revisiones.log, registros y suite que no se eliminan) más check_docs sobre el árbol del
# commit. Un MERGE limpio (árbol = fusión automática de sus padres) pasa sin trailer; uno que
# añade contenido al fusionar se valida como cualquier commit (commit-msg decide). Es lo que CI
# ejecuta para que un `git commit --no-verify` local no pase inadvertido en el remoto.
#
#   sh scripts/pruebas/validar_historial.sh                 → commits de origin/main..HEAD (o todo HEAD si no hay origin/main)
#   sh scripts/pruebas/validar_historial.sh <rango>         → p. ej. main..HEAD, abc123..HEAD, HEAD~5..HEAD
#
# Salida: 0 si todos los commits cumplen; 1 y la lista de commits con sus motivos si no.
# No ejecuta scripts/check.sh del producto (CI lo corre aparte sobre el árbol final).
# Los hooks que se aplican son los de ESTE checkout (scripts/ y .githooks/ actuales), salvo con
# --metodo: entonces son los de esa carpeta, que scripts/pruebas/replay_anclado.sh extrae del ancla
# (docs/convenciones.md §Git, «Replay anclado»). Del árbol de cada commit solo se leen datos.
#
#   sh scripts/pruebas/validar_historial.sh --metodo <carpeta absoluta> <rango>
#   sh scripts/pruebas/validar_historial.sh --materializa <commit> <carpeta nueva>
#
# Cada commit se materializa desde sus blobs (ls-tree + cat-file), no con git archive ni
# checkout-index: los atributos del propio árbol (export-ignore, export-subst, eol, ident, filtros,
# working-tree-encoding) no ocultan ni transforman nada. Cada archivo se comprueba por su id; los
# modos 100644/100755 se conservan; un enlace simbólico se crea y, si resuelve fuera de la carpeta,
# se detiene; un submódulo queda como carpeta vacía y se avisa; una ruta con un componente vacío,
# «.», «..» o «.git» detiene. Nada se omite en silencio.
MATERIALIZA_PY='
import hashlib, os, subprocess, sys, unicodedata
c, dest = sys.argv[1], sys.argv[2]
def muere(m): sys.stderr.write("materializa: %s\n" % m); sys.exit(3)
def git(*a, entrada=None):
    r = subprocess.run(["git", *a], input=entrada, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode: muere("git %s: %s" % (" ".join(a), r.stderr.decode(errors="replace").strip()))
    return r.stdout
if not os.path.isdir(dest) or os.listdir(dest): muere("la carpeta de destino debe existir y estar vacía: %s" % dest)
formato = git("rev-parse", "--show-object-format").decode().strip() or "sha1"
IGNORABLES = dict.fromkeys(map(ord, "\u200c\u200d\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u206a\u206b\u206c\u206d\u206e\u206f\ufeff"))
def es_git(x):
    t = unicodedata.normalize("NFC", x.decode("utf-8", "replace")).translate(IGNORABLES).casefold().rstrip(" .")
    return t == ".git"
entradas, vistas = [], set()
for rec in git("ls-tree", "-r", "-z", "--full-tree", c).split(b"\0"):
    if not rec: continue
    meta, ruta = rec.split(b"\t", 1)
    modo, tipo, oid = meta.decode().split(" ")
    if any(x in (b"", b".", b"..") or es_git(x) for x in ruta.split(b"/")): muere("ruta no materializable %r en %s" % (ruta, c))
    if ruta in vistas: muere("ruta duplicada %r en %s" % (ruta, c))
    vistas.add(ruta); entradas.append((modo, tipo, oid, ruta))
blobs = [e for e in entradas if e[1] == "blob"]
salida = git("cat-file", "--batch", entrada=b"".join(e[2].encode() + b"\n" for e in blobs))
datos, i = {}, 0
for _ in blobs:
    j = salida.index(b"\n", i); o, t, n = salida[i:j].decode().split(" "); n = int(n)
    datos[o] = salida[j + 1:j + 1 + n]; i = j + 2 + n
    if t != "blob" or hashlib.new(formato, b"blob %d\0" % n + datos[o]).hexdigest() != o: muere("el blob %s no corresponde a su id" % o)
base = os.fsencode(os.path.realpath(dest))
enlaces = []
for modo, tipo, oid, ruta in entradas:
    p = os.path.join(base, ruta)
    if tipo == "commit":
        os.makedirs(p); sys.stderr.write("materializa: submódulo %s (%s) queda como carpeta vacía\n" % (ruta.decode(errors="replace"), oid[:12])); continue
    if tipo != "blob": muere("entrada %s de tipo %s no materializable" % (ruta.decode(errors="replace"), tipo))
    if modo == "120000":
        if datos[oid].startswith(b"/"): muere("enlace simbólico %s con destino absoluto" % ruta.decode(errors="replace"))
        enlaces.append((p, datos[oid], ruta)); continue
    if modo not in ("100644", "100755"): muere("modo %s no materializable en %s" % (modo, ruta.decode(errors="replace")))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o755 if modo == "100755" else 0o644)
    with os.fdopen(fd, "wb") as f: f.write(datos[oid])
    os.chmod(p, 0o755 if modo == "100755" else 0o644)
for p, destino, ruta in enlaces:
    os.makedirs(os.path.dirname(p), exist_ok=True); os.symlink(destino, p)
for p, destino, ruta in enlaces:
    r = os.path.realpath(p)
    if r != base and not r.startswith(base + b"/"): muere("enlace simbólico %s resuelve fuera de la carpeta (%s)" % (ruta.decode(errors="replace"), destino.decode(errors="replace")))
'
if [ "${1:-}" = --materializa ]; then
  [ $# -eq 3 ] || { echo "validar_historial: --materializa <commit> <carpeta nueva>" >&2; exit 2; }
  exec python3 -I -c "$MATERIALIZA_PY" "$2" "$3"
fi
# METODO_DIR solo lo fija --metodo (nunca se hereda): de él salen los validadores y sus auxiliares.
unset METODO_DIR
if [ "${1:-}" = --metodo ]; then
  case "${2:-}" in /*) [ -d "$2" ] ;; *) false ;; esac || { echo "validar_historial: --metodo exige una carpeta absoluta existente" >&2; exit 2; }
  METODO_DIR=$2; export METODO_DIR; shift 2
fi
MET=${METODO_DIR:-.}
RANGO="${1:-}"
if [ -z "$RANGO" ]; then
  if git rev-parse --verify -q origin/main >/dev/null 2>&1; then RANGO="origin/main..HEAD"; else RANGO="HEAD"; fi
fi
# Base del método (solo proyectos ADOPTADOS, docs/arranque-existente.md): si docs/convenciones.md
# declara `- **Base del método:** <sha>` (el último commit previo a la adopción), la selección es el
# rango MENOS lo alcanzable desde la base: el historial anterior al método no se juzga y el commit
# de instalación sí. Sin declaración, nada cambia. Una declaración duplicada o malformada, una base
# ajena a la historia del extremo final o una base en o después de un commit con fase (moverla
# hacia adelante ocultaría commits ya sujetos a revisión) FALLAN; nunca equivalen a «sin base».
EXCLUIR=""
nb() { echo "validar_historial: base del método: $1" >&2; exit 2; }
# Con --metodo (replay anclado) la declaración que fija lo excluido es la del ANCLA (su docs/convenciones.md,
# extraído en METODO_DIR), no la del candidato; la del extremo final tiene que ser la misma (la base nace una
# vez y no cambia: lo comprueba el commit-msg en cada commit). Leer cualquiera de las dos con error, o que no
# coincidan, detiene: nunca equivale a «sin base».
if [ -n "${METODO_DIR:-}" ]; then
  case "$RANGO" in *..*) FIN_DECL=${RANGO#*..} ;; *) FIN_DECL=$RANGO ;; esac
  [ -f "$METODO_DIR/docs/convenciones.md" ] || nb "la carpeta del ancla no trae docs/convenciones.md: no sé qué base declaraba el ancla"
  DECL=$(grep -E '^- \*\*Base del método:\*\*' "$METODO_DIR/docs/convenciones.md")
  [ $? -le 1 ] || nb "no pude leer docs/convenciones.md del ancla"
  e=$(git ls-tree "${FIN_DECL:-HEAD}" -- docs/convenciones.md 2>/dev/null) || nb "no pude leer docs/convenciones.md del final del rango (${FIN_DECL:-HEAD})"
  DECL_FIN=""
  if [ -n "$e" ]; then
    t=$(git cat-file blob "$(printf '%s' "$e" | awk '{print $3}')" 2>/dev/null) || nb "no pude leer docs/convenciones.md del final del rango (${FIN_DECL:-HEAD})"
    DECL_FIN=$(printf '%s\n' "$t" | grep -E '^- \*\*Base del método:\*\*')
  fi
  resuelve_decl() { x=$(printf '%s' "$1" | sed -nE 's/^- \*\*Base del método:\*\* `?([0-9a-f]{7,40})`?[[:space:]]*$/\1/p'); [ -n "$x" ] && git rev-parse --verify -q --end-of-options "$x^{commit}" 2>/dev/null; }
  if [ -n "$DECL" ] || [ -n "$DECL_FIN" ]; then
    ra=$(resuelve_decl "$DECL"); rf=$(resuelve_decl "$DECL_FIN")
    { [ -n "$ra" ] && [ "$ra" = "$rf" ]; } || nb "el final del rango declara '${DECL_FIN:-ninguna}' y el ancla '${DECL:-ninguna}': la base se lee del ancla y no cambia ni desaparece (docs/convenciones.md §Git)"
  fi
else
  DECL=$(grep -E '^- \*\*Base del método:\*\*' docs/convenciones.md 2>/dev/null || true)
fi
if [ -n "$DECL" ]; then
  [ "$(printf '%s\n' "$DECL" | grep -c .)" -eq 1 ] || nb "hay más de una declaración en docs/convenciones.md; debe haber una"
  sha=$(printf '%s' "$DECL" | sed -nE 's/^- \*\*Base del método:\*\* `?([0-9a-f]{7,40})`?[[:space:]]*$/\1/p')
  [ -n "$sha" ] || nb "declaración malformada ('$DECL'); forma: - **Base del método:** <sha de 7 a 40 hexadecimales>"
  BASE=$(git rev-parse --verify -q --end-of-options "$sha^{commit}" 2>/dev/null) || nb "$sha no resuelve a un commit"
  case "$RANGO" in
    *...*|*..*..*) nb "con base declarada el rango debe ser <rev> o <a>..<b> (recibido '$RANGO')" ;;
    *..*) FIN=${RANGO#*..}; [ -n "$FIN" ] || FIN=HEAD ;;
    *) FIN=$RANGO ;;
  esac
  git merge-base --is-ancestor "$BASE" "$FIN" 2>/dev/null || nb "$sha no es ancestro de $FIN: no pertenece a esta historia"
  [ -z "$(sh "$MET/scripts/check_docs.sh" fase-historica "$BASE" 2>/dev/null)" ] \
    || nb "$sha ya tiene un commit con fase en su historia: la base es el último commit PREVIO a la adopción y no se mueve hacia adelante"
  EXCLUIR="^$BASE"
  echo "base del método: $(git rev-parse --short "$BASE") (se excluye lo alcanzable desde ahí)"
fi
# shellcheck disable=SC2086
commits=$(git rev-list --reverse "$RANGO" $EXCLUIR 2>/dev/null) || { echo "validar_historial: rango inválido '$RANGO'" >&2; exit 2; }
[ -n "$commits" ] || { echo "validar_historial: ningún commit en $RANGO"; exit 0; }
MAL=0; TOTAL=0
fallo() { echo "  ✗ $1" >&2; ok=0; }
# check_docs corre DENTRO del árbol materializado (sin repositorio, como el pre-commit sobre su
# exportación); sin --metodo es el del checkout, con --metodo el de esa carpeta.
if [ -n "${METODO_DIR:-}" ]; then CHK="$METODO_DIR/scripts/check_docs.sh"; else CHK="$PWD/scripts/check_docs.sh"; fi
# El contrato de recibos con que se hizo cada commit lo derivan guardas.sh y el commit-msg (REV) del
# propio commit; check_docs usa el recibos.sh del árbol del commit. Nada se pasa por el entorno.
for c in $commits; do
  TOTAL=$((TOTAL+1)); ok=1
  corto=$(git log -1 --format='%h %s' "$c")
  base=$(git rev-parse --verify -q "$c^" 2>/dev/null || true)
  # a) Guardas de contenido: las MISMAS del pre-commit (scripts/guardas.sh): secretos, registros
  #    y suite que no desaparecen, append-only de los recibos. Base = padre (o árbol vacío).
  gb=${base:-$(git hash-object -t tree /dev/null)}
  err=$(sh "$MET/scripts/guardas.sh" "$gb" "$c" 2>&1) || fallo "guardas: $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-300)"
  # b) check_docs sobre el árbol del commit, con la fase que declaraba el padre.
  trabajo=$(mktemp -d "${TMPDIR:-/tmp}/vh.XXXXXX"); tmp="$trabajo/arbol"; mkdir "$tmp"
  if ! python3 -I -c "$MATERIALIZA_PY" "$c" "$tmp" 2>"$trabajo/mat"; then
    fallo "$(tr '\n' ' ' < "$trabajo/mat" | cut -c1-300)"
  else
    [ -s "$trabajo/mat" ] && sed 's/^/  · /' "$trabajo/mat" >&2
    prev=""; [ -n "$base" ] && prev=$(git show "$base:docs/estado.md" 2>/dev/null | grep -oE 'Fase actual:\*?\*?[[:space:]]*F[1-5]' | grep -oE 'F[1-5]' | head -1)
    hist=""; [ -n "$base" ] && hist=$(sh "$MET/scripts/check_docs.sh" fase-historica "$base" 2>/dev/null)
    ( cd "$tmp" && env -u GIT_DIR FASE_PREVIA="$prev" FASE_HISTORICA="$hist" sh "$CHK" commit ) 2>"$trabajo/err" || fallo "check_docs: $(tr '\n' ' ' < "$trabajo/err" | cut -c1-400)"
  fi
  rm -rf "$trabajo"
  # c) El contrato del commit-msg sobre ese commit (mensaje, árbol e historial anteriores).
  #    Para un merge, el propio commit-msg decide: limpio (árbol = fusión automática de los
  #    padres) pasa sin trailer; si añade contenido, se le exige como a cualquier commit.
  err=$(REV="$c" sh "$MET/.githooks/commit-msg" /dev/null 2>&1) || fallo "commit-msg: $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-300)"
  [ "$(git rev-list --parents -n 1 "$c" | wc -w | tr -d ' ')" -gt 2 ] && corto="$corto (merge)"
  if [ "$ok" -eq 1 ]; then echo "  ok    $corto"; else echo "  FALLO $corto"; MAL=$((MAL+1)); fi
done
echo "validar_historial: $((TOTAL-MAL))/$TOTAL commits cumplen el contrato ($RANGO)"
[ "$MAL" -eq 0 ]
