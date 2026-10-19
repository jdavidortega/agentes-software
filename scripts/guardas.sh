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
#   1) versionar un .env o variante (.env.example SÍ se permite: es la plantilla sin valores)
#   2) añadir una llave privada (PEM/OpenSSH/PKCS8) en cualquier archivo salvo .githooks/
#   3) eliminar docs/revisiones.log o scripts/check.sh si el base los tiene (registros y suite
#      son obligaciones adquiridas, en cualquier fase)
#   4) alterar o perder recibos: lo guardado en el base es PREFIJO exacto de revisiones.log
# No corre check_docs ni check.sh: eso lo hacen el pre-commit y el replay por su cuenta.
B="$1"; C="$2"
[ -n "$B" ] && [ -n "$C" ] || { echo "guardas: uso: guardas.sh <base> <candidato|INDICE>" >&2; exit 2; }
FAIL=0
fail() { echo "✗ guardas: $1" >&2; FAIL=1; }
if [ "$C" = "INDICE" ]; then
  nombres() { git diff --cached --name-only "$B"; }
  diff_mas() { git diff --cached "$B" -- . ':(exclude).githooks'; }
  tiene_c() { git ls-files --error-unmatch "$1" >/dev/null 2>&1; }
  blob_c() { git show ":$1" 2>/dev/null; }
else
  nombres() { git diff --name-only "$B" "$C"; }
  diff_mas() { git diff "$B" "$C" -- . ':(exclude).githooks'; }
  tiene_c() { git cat-file -e "$C:$1" 2>/dev/null; }
  blob_c() { git show "$C:$1" 2>/dev/null; }
fi
tiene_b() { git cat-file -e "$B:$1" 2>/dev/null; }

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
exit $FAIL
