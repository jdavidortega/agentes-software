#!/bin/sh
# Replay ANCLADO (docs/convenciones.md §Git, «Replay anclado»): juzga los commits de <inicio>..<fin>
# con los validadores del commit <ancla>, ya aprobado en un gate, no con los del checkout. No se
# ejecuta desde el checkout: la orden de entrada de convenciones lo extrae del ancla con
# `git cat-file blob` a una carpeta nueva y lo lanza desde ahí.
#
#   sh <carpeta>/entrada.sh <ancla: SHA completo> <inicio> <fin> <carpeta>
#
# 1) Resuelve inicio y fin a SHA completos una sola vez (el informe y la ejecución nombran el mismo final).
# 2) Comprueba la relación: el ancla y el inicio son antecesores del fin, y el inicio es el ancla o
#    anterior (si fuera posterior, quedarían commits sin juzgar). Si no, se detiene sin veredicto.
# 3) Extrae del ancla la lista cerrada de validadores y la referencia del bloque de la suite, blob a
#    blob, comprobando su id; un enlace, un submódulo o una ausencia detienen.
# 4) Ejecuta el validar_historial.sh del ancla con --metodo, sin árbol de trabajo (GIT_DIR absoluto y
#    una carpeta vacía como directorio actual): ningún archivo del candidato se ejecuta; solo se leen.
# 5) Informa ancla, rango, final, validadores que el rango modifica y resultado.
# Salida: 0 PASA, 1 FALLA, 2 preparación (sin veredicto).
LISTA='scripts/pruebas/replay_anclado.sh scripts/pruebas/validar_historial.sh .githooks/commit-msg
scripts/guardas.sh scripts/check_docs.sh scripts/recibos.sh scripts/huella.sh scripts/trazabilidad.sh
scripts/contrato.py scripts/fallos_previos.py scripts/decisiones.py scripts/suite.py docs/convenciones.md'
TAB=$(printf '\t')
para() { echo "replay anclado: $1" >&2; exit 2; }
[ $# -eq 4 ] || para "uso: <ancla> <inicio> <fin> <carpeta> (lo lanza la orden de entrada de docs/convenciones.md §Git)"
ANCLA=$1; D=$4
printf '%s\n' "$ANCLA" | grep -Eqx '[0-9a-f]{40}([0-9a-f]{24})?' || para "el ancla debe ser un SHA completo, no '$ANCLA'"
[ "$(git cat-file -t "$ANCLA" 2>/dev/null)" = commit ] || para "el ancla $ANCLA no es un commit de este repositorio"
case "$D" in /*) [ -d "$D" ] ;; *) false ;; esac || para "la carpeta '$D' debe ser absoluta y existir"
# Es la carpeta que acaba de crear la orden de entrada: solo contiene entrada.sh. Se borra al salir.
[ "$(ls -A "$D")" = entrada.sh ] || para "la carpeta '$D' debe ser la recién creada por la orden de entrada (solo con entrada.sh)"
trap 'rm -rf "$D"' EXIT
INICIO=$(git rev-parse --verify -q "$2^{commit}") || para "el inicio '$2' no es un commit"
FIN=$(git rev-parse --verify -q "$3^{commit}") || para "el fin '$3' no es un commit"
GD=$(git rev-parse --absolute-git-dir) || para "no estoy dentro de un repositorio git"
# Desde aquí, sin árbol de trabajo: GIT_DIR absoluto y una carpeta vacía como directorio actual (las
# rutas se interpretan desde la raíz y ningún .gitattributes del checkout interviene).
mkdir "$D/vacio" || para "no pude preparar $D/vacio"
unset GIT_WORK_TREE GIT_INDEX_FILE; GIT_DIR=$GD; export GIT_DIR; cd "$D/vacio" || para "no pude entrar en $D/vacio"

git merge-base --is-ancestor "$ANCLA" "$FIN" || {
  comun=$(git merge-base "$ANCLA" "$FIN" 2>/dev/null || echo ninguna)
  para "el ancla $ANCLA no es antecesora del final $FIN: la historia se reescribió desde el gate, o la rama no parte del ancla.
  No elijas otra ancla por tu cuenta ni juzgues con los validadores del candidato. Base común (solo como dato): $comun.
  La persona revisa el rango desde esa base y decide en un gate qué commit es la nueva ancla (docs/convenciones.md §Git, «Replay anclado»)."; }
git merge-base --is-ancestor "$INICIO" "$FIN" || para "el inicio $INICIO no es antecesor del final $FIN"
git merge-base --is-ancestor "$INICIO" "$ANCLA" || para "el inicio $INICIO es posterior al ancla $ANCLA: los commits entre ambos quedarían sin juzgar. Usa como inicio el ancla o un antecesor suyo."

# Validadores del ancla, blob a blob y comprobados por su id.
MET="$D/metodo"; mkdir "$MET" || para "no pude preparar $MET"
for f in $LISTA; do
  e=$(git ls-tree --full-tree "$ANCLA" -- "$f")
  [ -n "$e" ] || para "el ancla $ANCLA no contiene $f: está incompleta, no tiene validadores confiables. No uses la copia del candidato (docs/convenciones.md §Git, «Primera ancla»)."
  modo=${e%% *}; resto=${e#* }; tipo=${resto%% *}; resto=${resto#* }; id=${resto%%"$TAB"*}
  case "$modo $tipo" in "100644 blob"|"100755 blob") ;; *) para "$f en el ancla es $modo $tipo, no un archivo: no lo ejecuto" ;; esac
  mkdir -p "$MET/$(dirname "$f")" && git cat-file blob "$id" > "$MET/$f" || para "no pude extraer $f del ancla"
  [ "$(git hash-object --no-filters "$MET/$f")" = "$id" ] || para "$f extraído no corresponde a su id $id"
  [ "$modo" = 100755 ] && chmod +x "$MET/$f"
done

N=$(git rev-list --count "$INICIO..$FIN")
echo "replay anclado"
echo "  ancla:  $ANCLA"
echo "  rango:  $INICIO..$FIN ($N commits)"
echo "  final:  $FIN"
# Validadores que modifica CUALQUIER commit juzgado (no solo la diferencia entre extremos: un cambio
# restaurado después también cuenta), con ramas laterales (--full-history: sin simplificar) y lo que un
# merge resuelve por su cuenta (--cc).
# shellcheck disable=SC2086
CAMBIOS=$(git log --full-history --no-renames --cc --name-only --format='@%h' "$INICIO..$FIN" -- $LISTA |
  awk '/^@/ { c = substr($0, 2); next } NF { v[$0] = v[$0] (v[$0] == "" ? "" : " ") c } END { for (f in v) print f " (" v[f] ")" }' | sort)
CAMBIADOS=$CAMBIOS
if [ -n "$CAMBIOS" ]; then
  echo "  el rango modifica validadores (se juzgó con los del ancla; los nuevos rigen cuando este rango se acepte):"
  printf '%s\n' "$CAMBIOS" | sed 's/^/    /'
fi

sh "$MET/scripts/pruebas/validar_historial.sh" --metodo "$MET" "$INICIO..$FIN"
rc=$?
case $rc in
  0) r=PASA ;;
  1) r=FALLA ;;
  *) r="sin veredicto (validar_historial salió con $rc)"; rc=2 ;;
esac
echo "replay anclado: ancla $ANCLA · rango $INICIO..$FIN · final $FIN · resultado $r"
[ -n "$CAMBIADOS" ] && [ "$rc" -eq 0 ] && echo "  Pasar con el contrato del ancla no acredita las reglas nuevas de los validadores modificados: su comportamiento se prueba aparte."
exit $rc
