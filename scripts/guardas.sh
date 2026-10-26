#!/bin/sh
# Guardas de CONTENIDO entre dos estados del repositorio (viene con la plantilla; README
# §Enforcement). Una sola implementación para el pre-commit (base = HEAD, candidato = el
# ÍNDICE) y para el replay en CI (base = padre, candidato = el commit): lo que rechaza el
# hook local lo rechaza el remoto, con las mismas excepciones.
#
#   sh scripts/guardas.sh <base> <candidato>
#     base       commit (HEAD, un sha) o el árbol vacío (git hash-object -t tree /dev/null)
#     candidato  commit (sha) o la palabra INDICE (lo que está staged ahora mismo)
#
# Rechaza (salida 1, motivos en stderr):
#   1) añadir o cambiar un .env o variante (.env.example SÍ se permite: es la plantilla sin
#      valores; ELIMINAR uno ya versionado se permite: es la corrección)
#   2) añadir una llave privada (PEM/OpenSSH/PKCS8) en cualquier archivo salvo .githooks/
#   3) eliminar docs/revisiones.log o scripts/check.sh si el base los tiene (registros y suite
#      son obligaciones adquiridas, en cualquier fase)
#   4) alterar o perder recibos: lo guardado en el base es PREFIJO exacto de revisiones.log
#   5) un recibo NUEVO (lo que sigue a ese prefijo) sin modalidad=, filtro= y aislamiento=, aunque
#      quede antes del marcador «# contrato-recibos: 2» o declare una fecha antigua: solo lo que ya
#      estaba en el base puede ser histórico (scripts/recibos.sh)
#   6) evidencia que no corresponde: todo `evidencia=docs/revisiones/<id>@<h>` del registro candidato
#      (nuevo o ya guardado) resuelve en el candidato a una carpeta con esa huella exacta
#      (`sh scripts/huella.sh evidencia`); sustituir, modificar o borrar evidencia registrada se rechaza
#   7) que la instrumentación retroceda: si el base o CUALQUIER padre (un merge) tiene un
#      scripts/recibos.sh que conoce el marcador «# contrato-recibos: 2», el candidato también (si
#      no, la excepción histórica del replay sería un atajo para colar recibos sin modalidad)
# La excepción histórica (5) se deriva del CANDIDATO: un commit cuyo propio recibos.sh no conoce el
# marcador; el índice (pre-commit) nunca la tiene. No se lee del entorno.
# No corre check_docs ni check.sh: eso lo hacen el pre-commit y el replay por su cuenta.
B="$1"; C="$2"
[ -n "$B" ] && [ -n "$C" ] || { echo "guardas: uso: guardas.sh <base> <candidato|INDICE>" >&2; exit 2; }
FAIL=0
fail() { echo "✗ guardas: $1" >&2; FAIL=1; }
if [ "$C" = "INDICE" ]; then
  nombres() { git diff --cached --name-only --diff-filter=d "$B"; }   # quitar un .env es la corrección, no la falta
  diff_mas() { git diff --cached "$B" -- . ':(exclude).githooks'; }
  tiene_c() { git ls-files --error-unmatch "$1" >/dev/null 2>&1; }
  blob_c() { git show ":$1" 2>/dev/null; }
else
  nombres() { git diff --name-only --diff-filter=d "$B" "$C"; }
  diff_mas() { git diff "$B" "$C" -- . ':(exclude).githooks'; }
  tiene_c() { git cat-file -e "$C:$1" 2>/dev/null; }
  blob_c() { git show "$C:$1" 2>/dev/null; }
fi
tiene_b() { git cat-file -e "$B:$1" 2>/dev/null; }
if [ "$C" = "INDICE" ]; then ARBOL_C=$(git write-tree 2>/dev/null); else ARBOL_C=$(git rev-parse --verify -q "$C^{tree}"); fi
conoce() { grep -q 'contrato-recibos: 2' 2>/dev/null; }
PREVIO_C=""; [ "$C" != "INDICE" ] && ! blob_c scripts/recibos.sh | conoce && PREVIO_C=1

# 1) .env y variantes (por nombre), .env.example exento.
env=$(nombres | grep -E '(^|/)\.env($|\.)' | grep -vE '(^|/)\.env\.example$' || true)
[ -z "$env" ] || fail "intenta versionar un .env ($(printf '%s' "$env" | head -1)). Va en .gitignore, nunca al repo."

# 2) Llave privada por CONTENIDO añadido (patrón partido para no detectarse a sí mismo).
key_re='BEGIN .*PRIVATE K''EY'
if diff_mas | grep -Eq "^\+.*$key_re"; then
  fail "lo que entra añade una llave privada (PEM/OpenSSH/PKCS8). Nunca al repo."
fi

# 3) Registros y suite: obligaciones adquiridas.
for f in docs/revisiones.log scripts/check.sh; do
  if tiene_b "$f" && ! tiene_c "$f"; then
    fail "$f está en el estado anterior y aquí desaparece. Los recibos no se borran y la suite es obligación adquirida desde el diseño; volver a F1 no la retira."
  fi
done

# 4) Append-only de los recibos.
if tiene_b docs/revisiones.log && tiene_c docs/revisiones.log; then
  a=$(mktemp 2>/dev/null || mktemp -t g); b=$(mktemp 2>/dev/null || mktemp -t g)
  git show "$B:docs/revisiones.log" > "$a"
  blob_c docs/revisiones.log | head -c "$(wc -c < "$a" | tr -d ' ')" > "$b"
  cmp -s "$a" "$b" || fail "docs/revisiones.log perdió o alteró recibos ya guardados (es append-only). Un FALLA no se borra: se añade la revisión nueva debajo."
  rm -f "$a" "$b"
fi

# 5) Recibos nuevos con la modalidad declarada (lo posterior al contenido del base).
if tiene_c docs/revisiones.log && [ -z "$PREVIO_C" ]; then
  nb=0; tiene_b docs/revisiones.log && nb=$(git show "$B:docs/revisiones.log" | wc -c | tr -d ' ')
  incompletos=$(blob_c docs/revisiones.log | tail -c +"$((nb+1))" | awk '
    /^[ \t]*(#|$)/ { next }
    !/(^|[ \t])modalidad=/ || !/(^|[ \t])filtro=/ || !/(^|[ \t])aislamiento=/ { n++ }
    END { print n+0 }')
  [ "$incompletos" -eq 0 ] || fail "docs/revisiones.log añade $incompletos recibo(s) sin modalidad=, filtro= y aislamiento=. Un recibo nuevo los declara siempre, aunque quede antes del marcador «# contrato-recibos: 2» o lleve una fecha antigua: solo los recibos ya guardados son históricos (.claude/skills/dirigiendo-revisiones)."
fi

# 6) Evidencia registrada: resuelve en el candidato con su huella exacta.
huella_evid() {  # $1 ruta → huella de la carpeta en el árbol candidato, o nada si no es una carpeta válida
  l=$(git ls-tree -r "$ARBOL_C:$1" 2>/dev/null) || return 0
  [ -n "$l" ] || return 0
  printf '%s\n' "$l" | awk '$1 !~ /^100(644|755)$/ {bad=1} END {exit bad}' || return 0
  printf '%s\n' "$l" | awk -F'\t' '{ split($1, a, " "); print $2, a[3] }' | LC_ALL=C sort | git hash-object --stdin | cut -c1-12
}
if tiene_c docs/revisiones.log; then
  for ev in $(blob_c docs/revisiones.log | grep -v '^[[:space:]]*#' | tr -s '[:space:]' '\n' | sed -n 's/^evidencia=//p' | sort -u); do
    ruta=${ev%@*}; h=${ev##*@}
    real=$(huella_evid "$ruta")
    if [ -z "$real" ]; then fail "la evidencia $ruta registrada en docs/revisiones.log no existe en lo que se guarda como carpeta de archivos regulares: la evidencia de un recibo no se borra ni se sustituye."
    elif [ "$real" != "$h" ]; then fail "la evidencia $ruta tiene huella $real y su recibo registra $h: cambió después de registrarse (o se registró otra cosa). La evidencia de un recibo no se modifica; una revisión nueva deja su propia carpeta."
    fi
  done
fi

# 7) La instrumentación del contrato de recibos no retrocede respecto del base ni de ningún padre.
if [ "$C" = "INDICE" ]; then
  mh=$(git rev-parse --git-path MERGE_HEAD)
  padres="$B $( [ -f "$mh" ] && cat "$mh" )"
else
  padres="$B $(git rev-list --parents -n 1 "$C" 2>/dev/null | cut -d' ' -f2-)"
fi
if ! blob_c scripts/recibos.sh | conoce; then
  for p in $padres; do
    if git show "$p:scripts/recibos.sh" 2>/dev/null | conoce; then
      fail "scripts/recibos.sh deja de conocer el marcador «# contrato-recibos: 2» que $(git rev-parse --short "$p" 2>/dev/null || echo 'el estado anterior') ya conocía: la instrumentación del contrato de recibos no retrocede, tampoco al fusionar (se actualiza con adoptar.sh actualizar o desde la plantilla)."
      break
    fi
  done
fi
exit $FAIL
