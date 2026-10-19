#!/bin/sh
# Integridad del rastro documental (viene con la plantilla; ver AGENTS.md §8).
#
# Modo "commit" (por defecto): lo corre el pre-commit sobre una exportación del ÍNDICE
# (lo que de verdad se versiona), y el agente lo corre a mano al inicio de sesión. Sobre
# la plantilla recién copiada (sin fase real en estado.md) solo aplica lo estructural;
# con el proyecto iniciado (estado.md en F2..F5) aplica además el CONTRATO POR FASE:
# archivos obligatorios, IDs únicos y existentes, hooks instalados.
# Modo "cierre": lo dispara el commit-msg cuando el trailer es Ref: F4 o Ref: F5, y se
# puede correr a mano. Añade las condiciones de salida del ciclo.
#
# Salida: 0 = PASA; 1 = FALLA (los motivos van a stderr, uno por línea).
# Un archivo obligatorio ausente es FALLA, nunca una sección omitida en silencio.

MODE="${1:-commit}"
FAIL=0
err() { echo "  ✗ check_docs: $1" >&2; FAIL=1; }
has() { [ -f "$1" ]; }

# --- Fase vigente -------------------------------------------------------------
FASE=""
if has docs/estado.md; then
  FASE=$(grep -oE 'Fase actual:\*?\*?[[:space:]]*F[0-9]' docs/estado.md | grep -oE 'F[0-9]' | head -1)
fi
INICIADO=0
case "$FASE" in F2|F3|F4|F5) INICIADO=1 ;; esac
[ "$MODE" = "cierre" ] && INICIADO=1

# --- 0) Contrato por fase: archivos obligatorios y hooks instalados --------------
if [ "$INICIADO" -eq 1 ]; then
  for f in AGENTS.md README.md contexto/README.md docs/estado.md docs/encuadre.md \
           docs/plan.md docs/trazabilidad.md docs/decisiones.md docs/convenciones.md \
           docs/definicion-de-hecho.md docs/despliegue.md docs/MEMORIA.md scripts/check_docs.sh; do
    has "$f" || err "falta $f (obligatorio con el proyecto iniciado)"
  done
  # scripts/check.sh es salida del diseño: existe desde el cierre de F2.
  has scripts/check.sh || err "falta scripts/check.sh (lint+formato+tests; salida obligatoria del diseño, F2)"
  # Hooks de la plantilla activos (solo verificable dentro de un repo; en la exportación
  # del índice no hay .git y el propio hook ya demuestra que están activos).
  if git rev-parse --git-dir >/dev/null 2>&1; then
    [ "$(git config core.hooksPath 2>/dev/null)" = ".githooks" ] \
      || err "core.hooksPath no es .githooks: los hooks de la plantilla no están activos (git config core.hooksPath .githooks)"
    for h in .githooks/pre-commit .githooks/commit-msg; do
      [ -x "$h" ] || err "$h no es ejecutable: git lo IGNORA en silencio (chmod +x $h && git update-index --chmod=+x $h)"
    done
  fi
fi

# --- 1) Criterios C#: únicos en encuadre.md y con fila en trazabilidad.md -------------
if has docs/encuadre.md; then
  dups=$(grep -oE '^- C[0-9]+:' docs/encuadre.md | grep -oE 'C[0-9]+' | sort | uniq -d)
  for c in $dups; do err "$c está definido más de una vez en encuadre.md"; done
  if has docs/trazabilidad.md; then
    for c in $(grep -oE '^- C[0-9]+:' docs/encuadre.md | grep -oE 'C[0-9]+' | sort -u); do
      grep -qE "^\| *$c *\|" docs/trazabilidad.md \
        || err "$c está en encuadre.md pero no tiene fila en trazabilidad.md"
    done
  fi
fi

# --- 2) Incrementos I#: únicos en plan.md; todo I# citado en el rastro existe allí --------
if has docs/plan.md; then
  plan_ids=$(grep -oE '^- \[[ xX]\] I[0-9]+' docs/plan.md | grep -oE 'I[0-9]+')
  for i in $(printf '%s\n' "$plan_ids" | sort | uniq -d); do
    err "$i está definido más de una vez en plan.md"
  done
  if [ "$INICIADO" -eq 1 ]; then
    cited=$( { has docs/trazabilidad.md && grep -E '^\|' docs/trazabilidad.md | grep -oE '(^|[^A-Za-z0-9-])I[0-9]+' ; \
               has docs/estado.md && grep -oE 'incremento activo:[[:space:]]*I[0-9]+' docs/estado.md ; } \
             | grep -oE 'I[0-9]+' | sort -u)
    for i in $cited; do
      printf '%s\n' "$plan_ids" | grep -qx "$i" \
        || err "$i se cita en trazabilidad/estado pero no existe como incremento en plan.md"
    done
  fi
fi

# --- 3) ADR-NNN referenciados existen en decisiones.md (ADR-000 es la plantilla) ---------
if has docs/decisiones.md; then
  for a in $(grep -rhoE 'ADR-[0-9]{3}' docs/ README.md 2>/dev/null | grep -v 'ADR-000' | sort -u); do
    grep -qE "^## $a" docs/decisiones.md \
      || err "$a se referencia pero no existe (o no tiene encabezado '## $a') en decisiones.md"
  done
  # Ningún ADR en 'propuesta' sin 'Se resuelve en:' diligenciado.
  ids=$(awk '
    /^## ADR-/ { if (prop && !res) print id; id=$2; prop=0; res=0 }
    /\*\*Estado:\*\*[[:space:]]*propuesta[[:space:]]*$/ { prop=1 }
    /\*\*Se resuelve en:\*\*[[:space:]]*[^_[:space:]]/ { res=1 }
    END { if (prop && !res) print id }
  ' docs/decisiones.md)
  for id in $ids; do err "$id está en 'propuesta' sin 'Se resuelve en:' diligenciado"; done
fi

# --- 4) Placeholders de plantilla con el proyecto iniciado --------------------------------
if [ "$INICIADO" -eq 1 ] && has AGENTS.md; then
  grep -qE '_\[[^]]+\]_' AGENTS.md \
    && err "AGENTS.md conserva placeholders de plantilla (_[...]_) con el proyecto ya iniciado"
fi

# --- Frontmatter: gramática estricta (sin parser YAML; cada línea debe ser válida) ---------
# Acepta: `clave: valor` (con comentario # opcional), `clave:` seguida de ítems `  - valor`,
# y líneas en blanco. Rechaza tabuladores, claves desconocidas y cualquier otra forma.
check_frontmatter() {  # $1 archivo, $2 claves permitidas (regex alternativa). Deja el bloque en $FM.
  # Se invoca SIN sustitución de comando: así `err` fija FAIL en este shell, no en un subshell.
  f="$1"; keys="$2"; FM=""
  head -1 "$f" | grep -qx -- '---' || { err "$f no abre con frontmatter YAML (---)"; return 1; }
  awk 'NR==1 {next} $0=="---" {found=1; exit} END {exit !found}' "$f" \
    || { err "$f: frontmatter sin cierre (---)"; return 1; }
  FM=$(awk 'NR==1 {next} $0=="---" {exit} {print}' "$f")
  printf '%s\n' "$FM" | grep -q "$(printf '\t')" && err "$f: tabuladores en el frontmatter (YAML inválido)"
  bad=$(printf '%s\n' "$FM" | grep -vE "^($keys):([[:space:]].*)?$|^[[:space:]]+-[[:space:]]+[^[:space:]]|^[[:space:]]*$|^[[:space:]]*#")
  [ -z "$bad" ] || err "$f: líneas de frontmatter no válidas o claves desconocidas: $(printf '%s' "$bad" | head -2 | tr '\n' '|')"
  return 0
}

# --- 5) Skills: carpeta con SKILL.md, name == carpeta, description no vacía ≤1024 ---------
if [ -d .claude/skills ]; then
  for d in .claude/skills/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d"); f="${d}SKILL.md"
    if ! has "$f"; then err ".claude/skills/$name/ no tiene SKILL.md (una skill es una carpeta con SKILL.md)"; continue; fi
    echo "$name" | grep -qE '^[a-z0-9][a-z0-9-]{0,63}$' \
      || err ".claude/skills/$name: el nombre debe ser minúsculas, números y guiones (≤64 chars)"
    check_frontmatter "$f" 'name|description|allowed-tools' || continue
    fm="$FM"
    fm_name=$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)
    [ "$fm_name" = "$name" ] || err "$f: name '$fm_name' no coincide con la carpeta '$name'"
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

# --- 6) Agentes: name == archivo, description, skills precargadas existentes ---------------
if [ -d .claude/agents ]; then
  for f in .claude/agents/*.md; do
    has "$f" || continue
    aname=$(basename "$f" .md)
    check_frontmatter "$f" 'name|description|tools|model|skills' || continue
    afm="$FM"
    afm_name=$(printf '%s\n' "$afm" | sed -n 's/^name:[[:space:]]*//p' | head -1)
    [ "$afm_name" = "$aname" ] || err "$f: name '$afm_name' no coincide con el archivo '$aname'"
    printf '%s\n' "$afm" | grep -qE '^description:[[:space:]]*[^[:space:]]' \
      || err "$f: falta description (con ella Claude Code decide cuándo delegar)"
    askills=$(printf '%s\n' "$afm" \
      | awk '/^skills:/ {insk=1; next} insk && /^[^ ]/ {insk=0} insk {print}' \
      | sed -n 's/^[[:space:]]*-[[:space:]]*//p')
    for s in $askills; do
      has ".claude/skills/$s/SKILL.md" || err "$f precarga la skill '$s' pero .claude/skills/$s/SKILL.md no existe"
    done
  done
fi

# --- Modo cierre (F4/F5): condiciones de salida del ciclo ----------------------------------
if [ "$MODE" = "cierre" ]; then
  if has docs/trazabilidad.md; then
    n_abiertos=$(grep -E '^\| *R-' docs/trazabilidad.md | grep -cE '\| *abierto *\|')
    [ "$n_abiertos" -gt 0 ] && err "hay $n_abiertos hallazgo(s)/vacío(s) en estado 'abierto' al cierre"
    n_resueltos=$(grep -E '^\| *R-(I|S|F4)' docs/trazabilidad.md | grep -cE '\| *resuelto\b')
    [ "$n_resueltos" -gt 0 ] && err "hay $n_resueltos hallazgo(s) en 'resuelto' que nunca pasaron a 'verificado' (condición de salida de las Fases 3 y 4)"
    # Todo C# verificado y con incremento (fila: | C# | alias | I# | estado | nota |).
    for c in $(grep -oE '^- C[0-9]+:' docs/encuadre.md 2>/dev/null | grep -oE 'C[0-9]+' | sort -u); do
      row=$(grep -E "^\| *$c *\|" docs/trazabilidad.md | head -1)
      printf '%s' "$row" | grep -qE '^\|[^|]*\|[^|]*\|[^|]*I[0-9]+' \
        || err "$c no tiene incremento asignado en trazabilidad.md al cierre"
      printf '%s' "$row" | grep -qE '\| *verificado *\|' \
        || err "$c no está en estado 'verificado' al cierre"
    done
  fi
  if has docs/decisiones.md; then
    grep -q '^## ADR-000' docs/decisiones.md && err "la plantilla ADR-000 sigue en decisiones.md al cierre (bórrala)"
    grep -qE '\*\*Estado:\*\*[[:space:]]*propuesta[[:space:]]*$' docs/decisiones.md \
      && err "hay ADR en estado 'propuesta' al cierre: toda decisión diferida debe estar 'aceptada'"
  fi
  if has docs/estado.md; then
    case "$FASE" in F4|F5) ;; *) err "docs/estado.md no refleja la fase de cierre (Fase actual: F4|F5); ¿se regeneró en la compactación?" ;; esac
  fi
fi

if [ "$FAIL" -eq 1 ]; then
  echo "✗ check_docs.sh ($MODE): el rastro documental tiene inconsistencias (arriba)." >&2
  exit 1
fi
exit 0
