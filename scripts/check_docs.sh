#!/bin/sh
# Integridad del rastro documental (viene con la plantilla; ver AGENTS.md §8).
#
# Modo "commit" (por defecto): lo corre el pre-commit sobre una exportación del ÍNDICE
# (lo que de verdad se versiona), y el agente lo corre a mano al inicio de sesión. Siempre
# aplica lo estructural (archivos de la plantilla, roles, skills, frontmatter, recibos) y,
# dentro de un repo, la INSTALACIÓN (hooks activos y ejecutables: un clon nuevo FALLA hasta
# el Bootstrap, a propósito). "Plantilla sin iniciar" es SOLO: estado.md sin fase legible Y
# ningún commit anterior con fase (FASE_PREVIA, que el pre-commit toma de HEAD, o HEAD aquí
# mismo). Una vez iniciado, una fase ausente o ilegible (F_, vacía) es FALLA, no plantilla.
# Con el proyecto iniciado (F2..F5) aplica además el CONTRATO POR FASE: scripts/check.sh,
# sin placeholders ni filas de ejemplo, IDs únicos y existentes, estados leídos por columna.
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
FASE=""; FASE_LINEA=""
if has docs/estado.md; then
  FASE_LINEA=$(grep -m1 'Fase actual:' docs/estado.md || true)
  FASE=$(printf '%s' "$FASE_LINEA" | grep -oE 'Fase actual:\*?\*?[[:space:]]*F[0-9]+' | grep -oE 'F[0-9]+' | head -1)
fi
# Fase previa estable: la pasa el pre-commit (FASE_PREVIA, de HEAD) o se lee aquí de HEAD.
PREVIA="${FASE_PREVIA:-}"
if [ -z "$PREVIA" ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
  PREVIA=$(git show HEAD:docs/estado.md 2>/dev/null | grep -oE 'Fase actual:\*?\*?[[:space:]]*F[1-5]' | grep -oE 'F[1-5]' | head -1)
fi
INICIADO=0
case "$FASE" in
  F1) ;;
  F2|F3|F4|F5) INICIADO=1 ;;
  "") if [ -n "$PREVIA" ]; then
        err "docs/estado.md no declara una fase legible (línea: '${FASE_LINEA:-sin «Fase actual:»}') y el proyecto ya estaba iniciado (HEAD: $PREVIA). Una fase ausente o F_ no es 'modo plantilla': escribe 'Fase actual: F1..F5'."
        FASE="$PREVIA"; case "$FASE" in F2|F3|F4|F5) INICIADO=1 ;; esac
      fi ;;
  *) err "docs/estado.md declara una fase inválida ($FASE): solo F1..F5. Una fase desconocida no es 'modo plantilla'."; INICIADO=1 ;;
esac
[ "$MODE" = "cierre" ] && INICIADO=1

# --- 0) Archivos de la plantilla: obligatorios SIEMPRE (vienen con ella; en F1 también).
#     Los registros (revisiones.log, recibos.sh, huella.sh) no desaparecen en ninguna fase.
for f in AGENTS.md README.md contexto/README.md docs/estado.md docs/encuadre.md \
         docs/plan.md docs/trazabilidad.md docs/decisiones.md docs/convenciones.md \
         docs/definicion-de-hecho.md docs/despliegue.md docs/MEMORIA.md docs/revisiones.log \
         scripts/check_docs.sh scripts/huella.sh scripts/recibos.sh scripts/trazabilidad.sh \
         .githooks/pre-commit .githooks/commit-msg \
         .claude/skills/dirigiendo-revisiones/SKILL.md .claude/skills/revision-funcional/SKILL.md \
         .claude/skills/revision-critica/SKILL.md .claude/skills/revision-seguridad/SKILL.md \
         .claude/skills/verificando-por-sabotaje/SKILL.md \
         .claude/agents/revisor-funcional.md .claude/agents/juez-codigo.md \
         .claude/agents/juez-conjunto.md .claude/agents/juez-seguridad.md; do
  has "$f" || err "falta $f (viene con la plantilla y el método lo necesita: los cuatro roles, sus rúbricas, el procedimiento del principal, los registros y los hooks)"
done
# Adaptador Codex (si se usa): los mismos cuatro roles.
if [ -d .codex/agents ]; then
  for r in revisor-funcional juez-codigo juez-conjunto juez-seguridad; do
    has ".codex/agents/$r.toml" || err "falta .codex/agents/$r.toml (el adaptador Codex declara los cuatro roles)"
  done
fi
# --- 0a) Contrato por fase: scripts/check.sh es salida del diseño, existe desde el cierre de F2.
if [ "$INICIADO" -eq 1 ]; then
  has scripts/check.sh || err "falta scripts/check.sh (lint+formato+tests; salida obligatoria del diseño, F2)"
fi

# --- 0b) Instalación: siempre que haya repo, en cualquier fase y modo (V01). En la
#     exportación del índice no hay .git y el propio hook ya demuestra que corre.
if git rev-parse --git-dir >/dev/null 2>&1; then
  [ "$(git config core.hooksPath 2>/dev/null)" = ".githooks" ] \
    || err "core.hooksPath no es .githooks: los hooks de la plantilla no están activos (git config core.hooksPath .githooks)"
  flags=$(git ls-files -v | grep -E '^[a-z]|^S' || true)
  [ -z "$flags" ] || err "hay archivos con assume-unchanged/skip-worktree ($(printf '%s' "$flags" | head -1 | cut -c3-)…): ocultan cambios a la huella y a los hooks; quítalos"
  for h in .githooks/pre-commit .githooks/commit-msg; do
    [ -x "$h" ] || err "$h no es ejecutable: git lo IGNORA en silencio (chmod +x $h && git update-index --chmod=+x $h)"
    git ls-files -s "$h" 2>/dev/null | grep -q '^100755' \
      || err "$h está versionado sin bit ejecutable (git update-index --chmod=+x $h): un clon nuevo lo recibiría ignorado"
  done
fi

# --- Trazabilidad: lector ÚNICO (scripts/trazabilidad.sh), el mismo del commit-msg y del replay.
#     Produce "TIPO ID INCR ESTADO"; aquí se juzgan las filas, no se vuelven a leer.
if has scripts/trazabilidad.sh; then
  FILAS=$(sh scripts/trazabilidad.sh docs/trazabilidad.md)
else
  err "falta scripts/trazabilidad.sh (viene con la plantilla): sin él no se puede leer docs/trazabilidad.md"; FILAS=""
fi

# Las TRES tablas deben existir con sus columnas; un encabezado renombrado ("Situación")
# no puede volver invisible un hallazgo.
if has docs/trazabilidad.md; then
  for want in "C:Criterio,Alias,Incremento(s),Estado,Nota" \
              "E:Vacío,Alias,Punto incumplido,Estado,Resuelto (cómo · AAAA-MM-DD HH:MM UTC)" \
              "R:Hallazgo,Alias,Incr.,Criterio,Descripción,Estado,Resuelto (AAAA-MM-DD HH:MM UTC · commit)"; do
    tipo=${want%%:*}; cols=${want#*:}; colsn=$(printf '%s' "$cols" | tr ' ' '_')
    nh=$(printf '%s\n' "$FILAS" | awk -v tp="$tipo" '$1=="HDR" && $2==tp' | grep -c .)
    [ "$nh" -gt 0 ] || { err "trazabilidad.md: falta la tabla de tipo $tipo (encabezado: | $(printf '%s' "$cols" | sed 's/,/ | /g') |)"; continue; }
    [ "$nh" -eq 1 ] || err "trazabilidad.md: hay $nh tablas de tipo $tipo; cada tabla existe una sola vez (una segunda tabla puede esconder filas)"
    for got in $(printf '%s\n' "$FILAS" | awk -v tp="$tipo" '$1=="HDR" && $2==tp {print $3}'); do
      [ "$got" = "$colsn" ] || err "trazabilidad.md: encabezado de la tabla $tipo alterado: '$(printf '%s' "$got" | tr '_' ' ')' (esperado '$cols'). Un estado no puede desaparecer por renombrar una columna."
    done
  done
  for id in $(printf '%s\n' "$FILAS" | awk '$1=="NOEST"{print $2}'); do
    err "trazabilidad.md: la fila $id está bajo un encabezado sin columna Estado: su estado es invisible"
  done
  for h in $(printf '%s\n' "$FILAS" | awk '$1=="H" && $4!="verificado" {print $2}'); do
    err "trazabilidad.md: $h está en el Histórico sin '· verificado': al Histórico solo llega lo verificado"
  done
fi
for bad in $(printf '%s\n' "$FILAS" | awk '$1=="X"{print $2}'); do
  err "trazabilidad.md: ID '$bad' fuera de la gramática (C<n> | R-E.<n> | R-I<i>.<n> | R-S<i>.<n> | R-F4.<n> | R-SF4.<n>); una fila que no se lee es un hallazgo invisible"
done
# Filas de ejemplo de la plantilla: toleradas solo hasta F1; con el proyecto iniciado se borran.
if [ "$INICIADO" -eq 1 ]; then
  for ej in $(printf '%s\n' "$FILAS" | awk '$1=="EJ"{print $2}'); do
    err "trazabilidad.md conserva la fila de ejemplo de la plantilla '$ej' con el proyecto iniciado: bórrala (el contrato de la fase lee solo filas reales)"
  done
fi
for bad in $(printf '%s\n' "$FILAS" | awk '$1=="T"{print $2}'); do
  err "trazabilidad.md: $bad está en la tabla equivocada (C# en Cobertura; R-E en Vacíos; R-I/R-S/R-F4/R-SF4 en el Registro del juez)"
done
for ln in $(printf '%s\n' "$FILAS" | awk '$1=="SANGRIA"{print $2}'); do
  err "trazabilidad.md línea $ln: fila o entrada del Histórico con sangría; se lee igual, pero empieza en la columna 1 (Markdown puede mostrarla como código y esconderla a la persona)"
done
printf '%s\n' "$FILAS" | awk '$1=="ARIDAD"' | while read -r _ id n ncol; do
  echo "  ✗ check_docs: trazabilidad.md: la fila $id tiene $n celdas y su encabezado $ncol: fila incompleta o desbordada (una celda que falta deja un estado sin leer)" >&2
done
printf '%s\n' "$FILAS" | awk '$1=="ARIDAD"{bad=1} END{exit bad?1:0}' || FAIL=1
printf '%s\n' "$FILAS" | awk '$1=="INCR"' | while read -r _ id incr want; do
  echo "  ✗ check_docs: trazabilidad.md: $id lleva Incr. '$incr' pero su ID dice $want: dos identidades para un hallazgo; corrige una de las dos" >&2
done
printf '%s\n' "$FILAS" | awk '$1=="INCR"{bad=1} END{exit bad?1:0}' || FAIL=1
# Estado fuera del enum de su tabla (un estado desconocido no es ni abierto ni resuelto).
printf '%s\n' "$FILAS" | awk '
  $1=="C" && $4 !~ /^(pendiente|cubierto|verificado)$/ { print $2, $4 }
  $1=="E" && $4 !~ /^(abierto|resuelto)$/ { print $2, $4 }
  $1=="R" && $4 !~ /^(abierto|resuelto|verificado)$/ { print $2, $4 }' | while read -r id est; do
  err "trazabilidad.md: $id tiene Estado '$est', fuera del enum de su tabla"
  FAIL=1
done
# (el while corre en subshell: repetir la detección en el shell principal)
printf '%s\n' "$FILAS" | awk '
  ($1=="C" && $4 !~ /^(pendiente|cubierto|verificado)$/) ||
  ($1=="E" && $4 !~ /^(abierto|resuelto)$/) ||
  ($1=="R" && $4 !~ /^(abierto|resuelto|verificado)$/) { bad=1 } END { exit bad ? 1 : 0 }' || FAIL=1

# Unicidad: un C# o un hallazgo con dos filas es un registro ambiguo (V04/V10).
for dup in $(printf '%s\n' "$FILAS" | awk 'NF && $1!="X" && $1!="T" && $1!="HDR" && $1!="NOEST" && $1!="EJ" && $1!="SANGRIA" && $1!="ARIDAD" && $1!="INCR" {print $2}' | sort | uniq -d); do
  err "trazabilidad.md tiene más de una fila para $dup (tablas o Histórico): un ID se registra una sola vez; una pasada nueva continúa la numeración desde el último, incluido el Histórico"
done

# --- 1) Criterios C#: únicos en encuadre.md y con fila en trazabilidad.md -------------
# Gramática publicada de un criterio: la línea EXACTA `- C<n>: enunciado`. Cualquier otra
# forma que parezca un criterio (negrita, otro marcador, sin dos puntos) es error explícito,
# nunca un criterio que se vuelve invisible.
CRIT=""
if has docs/encuadre.md; then
  CRIT=$(grep -oE '^- C[0-9]+:' docs/encuadre.md | grep -oE 'C[0-9]+' | sort -u)
  mal=$(awk '/^[[:space:]]*[-*+][[:space:]]+/ { t=$2; gsub(/[*_`]/,"",t); if (t ~ /^C[0-9]+:?$/ && $0 !~ /^- C[0-9]+:/) print }' docs/encuadre.md | head -2)
  [ -z "$mal" ] || err "encuadre.md: criterio escrito fuera de la gramática '- C<n>: enunciado' (no se inventaría): $(printf '%s' "$mal" | tr '\n' '|' | cut -c1-80)"
  dups=$(grep -oE '^- C[0-9]+:' docs/encuadre.md | grep -oE 'C[0-9]+' | sort | uniq -d)
  for c in $dups; do err "$c está definido más de una vez en encuadre.md"; done
  if [ "$INICIADO" -eq 1 ]; then
    vac=$(grep -E '^- C[0-9]+:[[:space:]]*$' docs/encuadre.md | grep -oE 'C[0-9]+' | tr '\n' ' ')
    [ -z "$vac" ] || err "encuadre.md: criterio(s) sin enunciado con el proyecto iniciado: $vac"
  fi
  # La cobertura se siembra con el plan (F2): desde ahí los dos conjuntos coinciden.
  if has docs/trazabilidad.md && [ "$INICIADO" -eq 1 ]; then
    for c in $CRIT; do
      printf '%s\n' "$FILAS" | awk -v c="$c" '$1=="C" && $2==c {f=1} END {exit f?0:1}' \
        || err "$c está en encuadre.md pero no tiene fila (legible) en la tabla de cobertura de trazabilidad.md"
    done
    # Y al revés: una fila de cobertura cuyo criterio no existe en el encuadre es huérfana.
    for c in $(printf '%s\n' "$FILAS" | awk '$1=="C"{print $2}'); do
      printf '%s\n' "$CRIT" | grep -qx "$c" || err "trazabilidad.md cubre $c, que no está definido en encuadre.md (criterio huérfano)"
    done
    # Un hallazgo cuya columna Criterio nombra un C<n> nombra uno que existe (otra cosa, p. ej.
    # una categoría OWASP/CWE en seguridad, se admite tal cual).
    for c in $(printf '%s\n' "$FILAS" | awk '$1=="R" && $5 ~ /^C[0-9]+$/ {print $2 ":" $5}'); do
      printf '%s\n' "$CRIT" | grep -qx "${c#*:}" || err "trazabilidad.md: ${c%%:*} dice proteger ${c#*:}, que no está definido en encuadre.md"
    done
    # Desde el plan aprobado (F2) todo criterio tiene incremento asignado: un C# sin I# es un
    # plan incompleto, no una decisión diferida (si se excluye, se saca del encuadre con ADR).
    for c in $(printf '%s\n' "$FILAS" | awk '$1=="C" && $3 !~ /I[0-9]+/ {print $2}'); do
      err "trazabilidad.md: $c no tiene incremento asignado (columna Incremento) con el plan aprobado; cada criterio se cubre con un I<n> o sale del encuadre por ADR"
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

# --- 3b) Presupuesto del canon: AGENTS.md ≤ 24 KB (lo lee cada sesión; Codex limita las
#     instrucciones combinadas a 32 KiB). Lo que crece va a una skill, no aquí.
if has AGENTS.md; then
  bytes=$(wc -c < AGENTS.md | tr -d ' ')
  [ "$bytes" -le 24576 ] || err "AGENTS.md pesa $bytes bytes (> 24576): mueve procedimiento a skills; el canon guarda invariantes (docs/convenciones.md §Contexto)"
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
  # Clave repetida: YAML no define cuál gana; aquí es error.
  dupk=$(printf '%s\n' "$FM" | grep -oE '^[a-z-]+:' | sort | uniq -d)
  [ -z "$dupk" ] || err "$f: clave repetida en el frontmatter: $(printf '%s' "$dupk" | tr '\n' ' ')"
  # Un escalar SIN comillas no puede contener ': ' (YAML lo lee como mapeo anidado → error).
  colon=$(printf '%s\n' "$FM" | grep -E '^[a-z-]+:[[:space:]]+[^"'"'"'\[[:space:]]' | sed -E 's/^[a-z-]+:[[:space:]]+//; s/[[:space:]]+#.*$//' | grep -E ': ')
  [ -z "$colon" ] || err "$f: valor sin comillas con ': ' dentro (YAML inválido; entrecomíllalo): $(printf '%s' "$colon" | head -1 | cut -c1-50)"
  # Escalares entre comillas: se recorre la cadena ENTERA carácter a carácter (no por sufijos),
  # como lo haría un parser. "…": \ escapa solo [0abtnvfre"/\N_LPxuU espacio], con \x \u \U
  # seguidos de 2/4/8 hex; una " sin escapar dentro es error; una \ justo antes de la " final
  # la escapa y deja el valor sin cerrar. '…': la única secuencia es ''. Bloques (>, |) y
  # colecciones ([…], {…}) no son texto: tampoco se aceptan como description.
  quoted=$(printf '%s\n' "$FM" | sed -n -E 's/^[a-z-]+:[[:space:]]+(["'"'"'].*)$/\1/p' | sed -E 's/[[:space:]]+#[^"'"'"']*$//' \
        | awk -v ok='0abtnvfre"/\\N_LPxuU ' '
    { q=substr($0,1,1); n=length($0); bad=""
      if (n<2 || substr($0,n,1)!=q) bad="sin cerrar"
      else if (q=="\"") {
        i=2
        while (i<n && bad=="") {
          c=substr($0,i,1)
          if (c=="\\") {
            e=substr($0,i+1,1)
            if (i+1>=n) { bad="la barra escapa la comilla de cierre: valor sin cerrar"; break }
            if (index(ok,e)==0) { bad="escape inválido \\" e; break }
            L=(e=="x")?2:(e=="u")?4:(e=="U")?8:0; h=substr($0,i+2,L)
            if (L && (length(h)<L || h ~ /[^0-9a-fA-F]/ || i+1+L>=n)) { bad="escape \\" e " incompleto o no hexadecimal"; break }
            i+=2+L
          } else if (c=="\"") { bad="comilla doble interior sin escapar"; break }
          else i++
        }
      } else {
        i=2
        while (i<n && bad=="") {
          c=substr($0,i,1)
          if (c=="\047") { if (i+1<n && substr($0,i+1,1)=="\047") i+=2; else { bad="comilla simple interior sin doblar"; break } }
          else i++
        }
      }
      if (bad!="") print bad ": " substr($0,1,50) }')
  [ -z "$quoted" ] || err "$f: valor entre comillas inválido en el frontmatter (YAML): $(printf '%s' "$quoted" | head -1)"
  for k in description name; do
    v=$(printf '%s\n' "$FM" | sed -n "s/^$k:[[:space:]]*//p" | head -1 | sed -E 's/[[:space:]]+#.*$//')
    case "$v" in
      \[*|\{*|\>*|\|*) err "$f: $k es una lista, un mapa o un bloque ($(printf '%s' "$v" | cut -c1-20)); tiene que ser texto en una línea" ;;
    esac
    # Sin comillas, YAML interpreta estos escalares como nulo, booleano o número, no como
    # texto: `description: null` es YAML válido cuyo valor NO es una cadena. Entre comillas
    # ("null", "true") sí son texto.
    if printf '%s' "$v" | grep -qE '^(~|null|Null|NULL|true|True|TRUE|false|False|FALSE|[-+]?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?|0x[0-9a-fA-F]+|0o[0-7]+|[-+]?\.(inf|Inf|INF)|\.(nan|NaN|NAN))$'; then
      err "$f: $k: '$v' sin comillas es un nulo, booleano o número en YAML, no texto; escribe el texto (o entrecomíllalo si de verdad es ese literal)"
    fi
  done
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
    adesc=$(printf '%s\n' "$afm" | sed -n 's/^description:[[:space:]]*//p' | head -1 | sed -e 's/[[:space:]]*#.*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
    [ -n "$adesc" ] || err "$f: description vacía o ausente (con ella Claude Code decide cuándo delegar; \"\" es YAML válido pero no dice nada)"
    askills=$( { printf '%s\n' "$afm" \
      | awk '/^skills:[[:space:]]*$/ {insk=1; next} insk && /^[^ ]/ {insk=0} insk {print}' \
      | sed -n 's/^[[:space:]]*-[[:space:]]*//p' ; \
      printf '%s\n' "$afm" | sed -n -E 's/^skills:[[:space:]]*\[(.*)\][[:space:]]*$/\1/p' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' ; } | grep -v '^$')
    printf '%s\n' "$afm" | grep -qE '^skills:[[:space:]]*[^[[:space:]]' \
      && err "$f: 'skills:' con un valor escalar; usa lista (bloque '- x' o inline '[x, y]')"
    # Lista inline: corchetes cerrados y cada ítem un identificador de skill, nada más.
    inl=$(printf '%s\n' "$afm" | grep -E '^skills:[[:space:]]*\[' || true)
    if [ -n "$inl" ]; then
      printf '%s' "$inl" | grep -qE '^skills:[[:space:]]*\[[^][]*\][[:space:]]*$' || err "$f: 'skills:' inline sin cerrar o con corchetes anidados: $inl"
      for s in $(printf '%s' "$inl" | sed -E 's/^skills:[[:space:]]*\[//; s/\].*$//' | tr ',' '\n'); do :; done
      bad_items=$(printf '%s' "$inl" | sed -E 's/^skills:[[:space:]]*\[//; s/\].*$//' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -vE '^[a-z0-9][a-z0-9-]*$' || true)
      [ -z "$bad_items" ] || err "$f: ítem de 'skills:' inline inválido (solo identificadores): '$bad_items'"
    fi
    for s in $askills; do
      has ".claude/skills/$s/SKILL.md" || err "$f precarga la skill '$s' pero .claude/skills/$s/SKILL.md no existe"
    done
  done
fi

# --- 7) Recibos de revisión: el parser ÚNICO (scripts/recibos.sh), el mismo del commit-msg --
if has docs/revisiones.log; then
  if has scripts/recibos.sh; then
    sh scripts/recibos.sh validar docs/revisiones.log || err "docs/revisiones.log tiene recibos inválidos (arriba); el commit-msg no aceptará ninguno hasta corregirlos"
  else
    err "falta scripts/recibos.sh (viene con la plantilla): sin él no se pueden validar los recibos"
  fi
fi

# --- Modo cierre (F4/F5): condiciones de salida del ciclo ----------------------------------
if [ "$MODE" = "cierre" ]; then
  if has docs/trazabilidad.md; then
    n_abiertos=$(printf '%s\n' "$FILAS" | awk '($1=="E"||$1=="R") && $4=="abierto"' | grep -c .)
    [ "$n_abiertos" -gt 0 ] && err "hay $n_abiertos hallazgo(s)/vacío(s) con Estado 'abierto' al cierre"
    n_resueltos=$(printf '%s\n' "$FILAS" | awk '$1=="R" && $4=="resuelto"' | grep -c .)
    [ "$n_resueltos" -gt 0 ] && err "hay $n_resueltos hallazgo(s) con Estado 'resuelto' que nunca pasaron a 'verificado' (condición de salida de las Fases 3 y 4)"
    # Un conjunto vacío de criterios no se "cumple": al cierre hay al menos uno, real.
    [ -n "$CRIT" ] || err "encuadre.md no define ningún criterio '- C<n>: …': no hay nada que validar ni cerrar"
    # Todo C# con incremento (columna Incremento) y Estado 'verificado' (columna Estado).
    for c in $CRIT; do
      row=$(printf '%s\n' "$FILAS" | awk -v c="$c" '$1=="C" && $2==c' | head -1)
      [ -n "$row" ] || { err "$c no tiene fila en trazabilidad.md al cierre"; continue; }
      printf '%s' "$row" | awk '{exit ($3 ~ /I[0-9]+/) ? 0 : 1}' \
        || err "$c no tiene incremento asignado (columna Incremento) en trazabilidad.md al cierre"
      printf '%s' "$row" | awk '{exit ($4=="verificado") ? 0 : 1}' \
        || err "$c no está en Estado 'verificado' al cierre (la columna Estado manda, no la Nota)"
    done
  fi
  # El plan y la cobertura no se contradicen al cierre: ningún incremento queda sin marcar.
  if has docs/plan.md; then
    for i in $(awk '/^## Incrementos/{s=1;next} /^## /{s=0} s && /^- \[ \] I[0-9]+ /{print $3}' docs/plan.md); do
      err "plan.md: $i sigue como '- [ ]' al cierre; márcalo [x] si se cerró o sácalo del plan (backlog/exclusión) con ADR"
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
