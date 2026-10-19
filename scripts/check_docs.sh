#!/bin/sh
# Integridad del rastro documental (viene con la plantilla; ver AGENTS.md §8).
#
# Modo "commit" (por defecto): lo corre el pre-commit sobre una exportación del ÍNDICE
# (lo que de verdad se versiona), y el agente lo corre a mano al inicio de sesión. Sobre
# la plantilla recién copiada (sin fase real en estado.md) aplica lo estructural y la
# INSTALACIÓN (hooks activos y ejecutables: un clon nuevo FALLA hasta el Bootstrap, a
# propósito); con el proyecto iniciado (estado.md en F2..F5) aplica además el CONTRATO
# POR FASE: archivos obligatorios, IDs únicos y existentes, estados leídos por columna.
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
case "$FASE" in
  "" ) ;;
  F1) ;;
  F2|F3|F4|F5) INICIADO=1 ;;
  *) err "docs/estado.md declara una fase inválida ($FASE): solo F1..F5. Una fase desconocida no es 'modo plantilla'."; INICIADO=1 ;;
esac
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
fi

# --- 0b) Instalación: siempre que haya repo, en cualquier fase y modo (V01). En la
#     exportación del índice no hay .git y el propio hook ya demuestra que corre.
if git rev-parse --git-dir >/dev/null 2>&1; then
  [ "$(git config core.hooksPath 2>/dev/null)" = ".githooks" ] \
    || err "core.hooksPath no es .githooks: los hooks de la plantilla no están activos (git config core.hooksPath .githooks)"
  for h in .githooks/pre-commit .githooks/commit-msg; do
    [ -x "$h" ] || err "$h no es ejecutable: git lo IGNORA en silencio (chmod +x $h && git update-index --chmod=+x $h)"
    git ls-files -s "$h" 2>/dev/null | grep -q '^100755' \
      || err "$h está versionado sin bit ejecutable (git update-index --chmod=+x $h): un clon nuevo lo recibiría ignorado"
  done
fi

# --- Trazabilidad leída por TABLA y COLUMNA (no por patrones sueltos) ----------------------
# Produce líneas "TIPO ID INCR ESTADO": TIPO=C (cobertura) | E (vacíos) | R (juez). Las
# columnas se identifican por su encabezado real, así `verificado` en la Nota no cuenta.
filas_trazabilidad() {
  [ -f docs/trazabilidad.md ] || return 0
  awk -F'|' '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^\|/ {
      n=0; for(i=2;i<NF;i++){ n++; f[n]=trim($i) }
      if (f[1] ~ /^-+$/) next                         # separador
      if (f[1]=="Criterio"||f[1]=="Vacío"||f[1]=="Hallazgo") {  # encabezado: ubicar columnas
        tipo = (f[1]=="Criterio") ? "C" : (f[1]=="Vacío") ? "E" : "R"
        ce=0; ci=0
        for(k=1;k<=n;k++){ if(f[k]=="Estado") ce=k; if(f[k] ~ /^Incr/) ci=k }
        next
      }
      if (tipo=="" || ce==0) next
      id=f[1]; if (id !~ /^(C[0-9]+|R-)/) next           # filas de ejemplo (C1 «…» cuenta; R-E._ no)
      if (id ~ /_/) next
      incr = (ci>0) ? f[ci] : "-"; gsub(/ /,"",incr); if(incr=="") incr="-"
      est=f[ce]; sub(/ .*$/,"",est)                       # primera palabra: "pendiente / cubierto" → pendiente
      print tipo, id, incr, est
    }' docs/trazabilidad.md
}
FILAS=$(filas_trazabilidad)

# Unicidad: un C# o un hallazgo con dos filas es un registro ambiguo (V04/V10).
for dup in $(printf '%s\n' "$FILAS" | awk 'NF{print $2}' | sort | uniq -d); do
  err "trazabilidad.md tiene más de una fila para $dup: un ID se registra una sola vez (en cualquier tabla); una pasada nueva continúa la numeración, no la repite"
done

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
    cited=$( { printf '%s\n' "$FILAS" | awk 'NF{print $3}' | grep -oE 'I[0-9]+' ; \
               has docs/estado.md && grep -oE 'incremento activo:[[:space:]]*I[0-9]+' docs/estado.md | grep -oE 'I[0-9]+' ; } \
             | sort -u)
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
  # Un valor que abre comillas tiene que cerrarlas en la misma línea (YAML inválido si no).
  unq=$(printf '%s\n' "$FM" | sed -n -E 's/^[a-z-]+:[[:space:]]+(["'"'"'].*)$/\1/p' | sed -E 's/[[:space:]]*#[^"'"'"']*$//' \
        | awk '{ q=substr($0,1,1); if (substr($0,length($0),1)!=q || length($0)<2) print }')
  [ -z "$unq" ] || err "$f: valor entre comillas sin cerrar en el frontmatter: $(printf '%s' "$unq" | head -1 | cut -c1-60)…"
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
    n_abiertos=$(printf '%s\n' "$FILAS" | awk '$1!="C" && $4=="abierto"' | grep -c .)
    [ "$n_abiertos" -gt 0 ] && err "hay $n_abiertos hallazgo(s)/vacío(s) con Estado 'abierto' al cierre"
    n_resueltos=$(printf '%s\n' "$FILAS" | awk '$1=="R" && $4=="resuelto"' | grep -c .)
    [ "$n_resueltos" -gt 0 ] && err "hay $n_resueltos hallazgo(s) con Estado 'resuelto' que nunca pasaron a 'verificado' (condición de salida de las Fases 3 y 4)"
    # Todo C# con incremento (columna Incremento) y Estado 'verificado' (columna Estado).
    for c in $(grep -oE '^- C[0-9]+:' docs/encuadre.md 2>/dev/null | grep -oE 'C[0-9]+' | sort -u); do
      row=$(printf '%s\n' "$FILAS" | awk -v c="$c" '$1=="C" && $2==c' | head -1)
      [ -n "$row" ] || { err "$c no tiene fila en trazabilidad.md al cierre"; continue; }
      printf '%s' "$row" | awk '{exit ($3 ~ /I[0-9]+/) ? 0 : 1}' \
        || err "$c no tiene incremento asignado (columna Incremento) en trazabilidad.md al cierre"
      printf '%s' "$row" | awk '{exit ($4=="verificado") ? 0 : 1}' \
        || err "$c no está en Estado 'verificado' al cierre (la columna Estado manda, no la Nota)"
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
