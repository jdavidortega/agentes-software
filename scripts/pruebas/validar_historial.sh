#!/bin/sh
# Validador de transiciones sobre el HISTORIAL (viene con la plantilla; README §Enforcement).
# Reejecuta sobre cada commit de un rango lo que los hooks exigen al commitear: el contrato
# del commit-msg (trailers, recibos vigentes por huella, hito, código solo con Ref: I<n>) y
# las guardas del pre-commit que dependen del contenido (append-only de revisiones.log,
# registros y suite que no se eliminan, check_docs sobre el árbol del commit). Es lo que CI
# ejecuta para que un `git commit --no-verify` local no pase inadvertido en el remoto.
#
#   sh scripts/pruebas/validar_historial.sh                 → commits de origin/main..HEAD (o todo HEAD si no hay origin/main)
#   sh scripts/pruebas/validar_historial.sh <rango>         → p. ej. main..HEAD, abc123..HEAD, HEAD~5..HEAD
#
# Salida: 0 si todos los commits cumplen; 1 y la lista de commits con sus motivos si no.
# No ejecuta scripts/check.sh del producto (CI lo corre aparte sobre el árbol final).
# Los hooks que se aplican son los de ESTE checkout (scripts/ y .githooks/ actuales).
RANGO="${1:-}"
if [ -z "$RANGO" ]; then
  if git rev-parse --verify -q origin/main >/dev/null 2>&1; then RANGO="origin/main..HEAD"; else RANGO="HEAD"; fi
fi
commits=$(git rev-list --reverse "$RANGO" 2>/dev/null) || { echo "validar_historial: rango inválido '$RANGO'" >&2; exit 2; }
[ -n "$commits" ] || { echo "validar_historial: ningún commit en $RANGO"; exit 0; }
MAL=0; TOTAL=0
fallo() { echo "  ✗ $1" >&2; ok=0; }
for c in $commits; do
  TOTAL=$((TOTAL+1)); ok=1
  corto=$(git log -1 --format='%h %s' "$c")
  base=$(git rev-parse --verify -q "$c^" 2>/dev/null || true)
  # a) revisiones.log: lo guardado en el padre es prefijo exacto; y ni el log ni la suite desaparecen.
  if [ -n "$base" ]; then
    for f in docs/revisiones.log scripts/check.sh; do
      if git cat-file -e "$base:$f" 2>/dev/null && ! git cat-file -e "$c:$f" 2>/dev/null; then
        fallo "$f estaba en el commit anterior y este lo elimina"
      fi
    done
    if git cat-file -e "$base:docs/revisiones.log" 2>/dev/null && git cat-file -e "$c:docs/revisiones.log" 2>/dev/null; then
      a=$(mktemp 2>/dev/null || mktemp -t vh); b=$(mktemp 2>/dev/null || mktemp -t vh)
      git show "$base:docs/revisiones.log" > "$a"
      git show "$c:docs/revisiones.log" | head -c "$(wc -c < "$a" | tr -d ' ')" > "$b"
      cmp -s "$a" "$b" || fallo "docs/revisiones.log alteró o perdió recibos ya guardados (append-only)"
      rm -f "$a" "$b"
    fi
  fi
  # b) check_docs sobre el árbol del commit, con la fase que declaraba el padre.
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t vh)
  git archive "$c" | tar -x -C "$tmp"
  prev=""; [ -n "$base" ] && prev=$(git show "$base:docs/estado.md" 2>/dev/null | grep -oE 'Fase actual:\*?\*?[[:space:]]*F[1-5]' | grep -oE 'F[1-5]' | head -1)
  ( cd "$tmp" && FASE_PREVIA="$prev" sh "$OLDPWD/scripts/check_docs.sh" commit ) 2>"$tmp/.err" || fallo "check_docs: $(tr '\n' ' ' < "$tmp/.err" | cut -c1-200)"
  rm -rf "$tmp"
  # c) El contrato del commit-msg sobre ese commit (mensaje, árbol e historial anteriores).
  err=$(REV="$c" sh .githooks/commit-msg /dev/null 2>&1) || fallo "commit-msg: $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-300)"
  if [ "$ok" -eq 1 ]; then echo "  ok    $corto"; else echo "  FALLO $corto"; MAL=$((MAL+1)); fi
done
echo "validar_historial: $((TOTAL-MAL))/$TOTAL commits cumplen el contrato ($RANGO)"
[ "$MAL" -eq 0 ]
