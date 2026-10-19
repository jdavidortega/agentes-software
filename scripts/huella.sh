#!/bin/sh
# Huella del contenido revisable (viene con la plantilla; ver AGENTS.md §9).
#
# Hash de (blob, ruta) de TODO el contenido del proyecto —archivos rastreados y no
# rastreados no ignorados— EXCLUYENDO solo los REGISTROS que el cierre escribe después de
# la revisión: docs/revisiones.log (recibos), docs/trazabilidad.md (filas de hallazgos),
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
# Son dos preguntas distintas: "¿sigue valiendo el recibo?" (vigencia) y "¿tocó algo el
# revisor?" (integridad). Ninguna observa la red ni los archivos ignorados por git.
#
# Si el árbol coincide con el índice en los rastreados y no hay no-rastreados pendientes,
# ambas huellas son iguales: el recibo de la revisión (línea de docs/revisiones.log con `huella=…`)
# solo es válido para el commit que guarda exactamente ese contenido.
MODE="${1:-arbol}"
EXCL='	docs/(revisiones\.log|trazabilidad\.md|estado\.md|MEMORIA\.md)$'
[ "$MODE" = "integridad" ] && EXCL='^$'
git rev-parse --git-dir >/dev/null 2>&1 || { echo "huella: no es un repositorio git" >&2; exit 2; }
# assume-unchanged (h) / skip-worktree (S) harían que el índice copiado conserve contenido
# viejo y la huella mienta. No se calcula nada mientras existan.
flags=$(git ls-files -v | grep -E '^[a-z]|^S' || true)
[ -z "$flags" ] || { echo "huella: archivos con assume-unchanged/skip-worktree; quítalos (git update-index --no-assume-unchanged/--no-skip-worktree):" >&2; printf '%s\n' "$flags" >&2; exit 2; }
if [ "$MODE" = "indice" ]; then
  tree=$(git write-tree) || exit 2
else
  tmp=$(mktemp 2>/dev/null || mktemp -t huella); trap 'rm -f "$tmp"' EXIT INT TERM
  real=$(git rev-parse --git-path index)
  [ -f "$real" ] && cp "$real" "$tmp"
  GIT_INDEX_FILE="$tmp" git add -A >/dev/null 2>&1 || exit 2
  tree=$(GIT_INDEX_FILE="$tmp" git write-tree) || exit 2
fi
git ls-tree -r "$tree" | grep -vE "$EXCL" | git hash-object --stdin | cut -c1-12
