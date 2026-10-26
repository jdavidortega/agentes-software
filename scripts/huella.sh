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
#   sh scripts/huella.sh              → VIGENCIA: árbol de trabajo sin registros (lo que ve el revisor)
#   sh scripts/huella.sh indice       → VIGENCIA sobre el ÍNDICE (lo que va al commit; commit-msg)
#   sh scripts/huella.sh integridad   → INTEGRIDAD: árbol COMPLETO, registros incluidos. El
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
  tmp=$(mktemp 2>/dev/null || mktemp -t huella); trap 'rm -f "$tmp"' EXIT INT TERM
  real=$(git rev-parse --git-path index)
  [ -f "$real" ] && cp "$real" "$tmp"
  GIT_INDEX_FILE="$tmp" git add -A >/dev/null 2>&1 || exit 2
  tree=$(GIT_INDEX_FILE="$tmp" git write-tree) || exit 2
fi
git ls-tree -r "$tree" | grep -vE "$EXCL" | git hash-object --stdin | cut -c1-12
