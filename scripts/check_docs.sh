#!/bin/sh
# Integridad del rastro documental (viene con la plantilla; ver AGENTS.md §8).
# Modo "commit" (por defecto): lo corre el pre-commit; chequeos seguros en cualquier
# momento del ciclo, diseñados para NO fallar sobre la plantilla recién copiada.
# Modo "cierre": se ejecuta al cerrar F4/F5 (scripts/check_docs.sh cierre); añade los
# chequeos de ciclo completo (hallazgos cerrados, plantilla ADR-000 eliminada).

MODE="${1:-commit}"
FAIL=0
err() { echo "  ✗ check_docs: $1" >&2; FAIL=1; }

# --- Chequeos de modo commit (siempre) ---------------------------------------

# 1) Todo C# definido en contexto.md tiene su fila en trazabilidad.md.
if [ -f docs/contexto.md ] && [ -f docs/trazabilidad.md ]; then
  for c in $(grep -oE '^- C[0-9]+:' docs/contexto.md | grep -oE 'C[0-9]+' | sort -u); do
    grep -qE "^\| *$c *\|" docs/trazabilidad.md \
      || err "$c está en contexto.md pero no tiene fila en trazabilidad.md"
  done
fi

# 2) Todo ADR-NNN referenciado en docs/ o README existe con encabezado '## ADR-NNN'
#    en decisiones.md (ADR-000 es la plantilla y se excluye).
if [ -f docs/decisiones.md ]; then
  for a in $(grep -rhoE 'ADR-[0-9]{3}' docs/ README.md 2>/dev/null | grep -v 'ADR-000' | sort -u); do
    grep -qE "^## $a" docs/decisiones.md \
      || err "$a se referencia pero no existe (o no tiene encabezado '## $a') en decisiones.md"
  done
fi

# 3) Ningún ADR en estado 'propuesta' sin 'Se resuelve en:' diligenciado.
if [ -f docs/decisiones.md ]; then
  ids=$(awk '
    /^## ADR-/ { if (prop && !res) print id; id=$2; prop=0; res=0 }
    /\*\*Estado:\*\*[[:space:]]*propuesta[[:space:]]*$/ { prop=1 }
    /\*\*Se resuelve en:\*\*[[:space:]]*[^_[:space:]]/ { res=1 }
    END { if (prop && !res) print id }
  ' docs/decisiones.md)
  for id in $ids; do
    err "$id está en 'propuesta' sin 'Se resuelve en:' diligenciado"
  done
fi

# 4) Placeholders de la plantilla sin llenar, solo cuando el proyecto ya arrancó
#    (estado.md sembrado con una fase real F2..F5).
if [ -f docs/estado.md ] && grep -qE 'Fase actual:\*?\*?[[:space:]]*F[2-5]' docs/estado.md; then
  grep -qE '_\[[^]]+\]_' AGENTS.md 2>/dev/null \
    && err "AGENTS.md conserva placeholders de plantilla (_[...]_) con el proyecto ya arrancado"
fi

# --- Chequeos de modo cierre (F4/F5) ------------------------------------------

if [ "$MODE" = "cierre" ]; then
  if [ -f docs/trazabilidad.md ]; then
    n_abiertos=$(grep -E '^\| *R-' docs/trazabilidad.md | grep -cE '\| *abierto *\|')
    [ "$n_abiertos" -gt 0 ] && err "hay $n_abiertos hallazgo(s)/vacío(s) en estado 'abierto' al cierre"
    n_resueltos=$(grep -E '^\| *R-I' docs/trazabilidad.md | grep -cE '\| *resuelto\b')
    [ "$n_resueltos" -gt 0 ] && err "hay $n_resueltos hallazgo(s) en 'resuelto' que nunca pasaron a 'verificado' (condición de salida de la Fase 3)"
  fi
  if [ -f docs/decisiones.md ] && grep -q '^## ADR-000' docs/decisiones.md; then
    err "la plantilla ADR-000 sigue en decisiones.md al cierre (bórrala)"
  fi
  if [ -f docs/estado.md ] && ! grep -qE 'Fase actual:\*?\*?[[:space:]]*F[0-9]' docs/estado.md; then
    err "docs/estado.md no refleja la fase actual (¿se regeneró en la compactación?)"
  fi
fi

if [ "$FAIL" -eq 1 ]; then
  echo "✗ check_docs.sh ($MODE): el rastro documental tiene inconsistencias (arriba)." >&2
  exit 1
fi
exit 0
