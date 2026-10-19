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

# 1) Todo C# definido en encuadre.md tiene su fila en trazabilidad.md.
if [ -f docs/encuadre.md ] && [ -f docs/trazabilidad.md ]; then
  for c in $(grep -oE '^- C[0-9]+:' docs/encuadre.md | grep -oE 'C[0-9]+' | sort -u); do
    grep -qE "^\| *$c *\|" docs/trazabilidad.md \
      || err "$c está en encuadre.md pero no tiene fila en trazabilidad.md"
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

# 5) Estructura de las skills (.claude/skills/, su ubicación nativa): carpeta con
#    SKILL.md, frontmatter con name (== carpeta) y description no vacía dentro del límite.
if [ -d .claude/skills ]; then
  for d in .claude/skills/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    f="${d}SKILL.md"
    if [ ! -f "$f" ]; then
      err ".claude/skills/$name/ no tiene SKILL.md (una skill es una carpeta con SKILL.md)"
      continue
    fi
    echo "$name" | grep -qE '^[a-z0-9][a-z0-9-]{0,63}$' \
      || err ".claude/skills/$name: el nombre debe ser minúsculas, números y guiones (≤64 chars)"
    head -1 "$f" | grep -qx -- '---' \
      || err "$f no abre con frontmatter YAML (---)"
    fm=$(awk 'NR==1 && $0=="---" {inb=1; next} inb && $0=="---" {exit} inb {print}' "$f")
    fm_name=$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)
    [ "$fm_name" = "$name" ] \
      || err "$f: name '$fm_name' no coincide con la carpeta '$name'"
    desc=$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1 \
           | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
    if [ -z "$desc" ]; then
      err "$f: falta description (es el campo con que el agente decide si la abre)"
    else
      n=$(printf '%s' "$desc" | wc -m | tr -d ' ')
      [ "$n" -le 1024 ] || err "$f: description de $n caracteres (máximo 1024)"
    fi
  done
fi

# 6) Agentes declarados (.claude/agents/): frontmatter con name (== archivo),
#    description no vacía, y cada skill precargada existe en .claude/skills/.
if [ -d .claude/agents ]; then
  for f in .claude/agents/*.md; do
    [ -f "$f" ] || continue
    aname=$(basename "$f" .md)
    head -1 "$f" | grep -qx -- '---' \
      || err "$f no abre con frontmatter YAML (---)"
    afm=$(awk 'NR==1 && $0=="---" {inb=1; next} inb && $0=="---" {exit} inb {print}' "$f")
    afm_name=$(printf '%s\n' "$afm" | sed -n 's/^name:[[:space:]]*//p' | head -1)
    [ "$afm_name" = "$aname" ] \
      || err "$f: name '$afm_name' no coincide con el archivo '$aname'"
    printf '%s\n' "$afm" | grep -qE '^description:[[:space:]]*[^[:space:]]' \
      || err "$f: falta description (con ella Claude Code decide cuándo delegar)"
    askills=$(printf '%s\n' "$afm" \
      | awk '/^skills:/ {insk=1; next} insk && /^[^ ]/ {insk=0} insk {print}' \
      | sed -n 's/^[[:space:]]*-[[:space:]]*//p')
    for s in $askills; do
      [ -f ".claude/skills/$s/SKILL.md" ] \
        || err "$f precarga la skill '$s' pero .claude/skills/$s/SKILL.md no existe"
    done
  done
fi

# --- Chequeos de modo cierre (F4/F5) ------------------------------------------

if [ "$MODE" = "cierre" ]; then
  if [ -f docs/trazabilidad.md ]; then
    n_abiertos=$(grep -E '^\| *R-' docs/trazabilidad.md | grep -cE '\| *abierto *\|')
    [ "$n_abiertos" -gt 0 ] && err "hay $n_abiertos hallazgo(s)/vacío(s) en estado 'abierto' al cierre"
    n_resueltos=$(grep -E '^\| *R-[IS]' docs/trazabilidad.md | grep -cE '\| *resuelto\b')
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
