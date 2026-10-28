#!/bin/sh
# Instala el método en un proyecto que YA EXISTE sin tocar nada de lo que ya tiene.
# Guion: docs/arranque-existente.md (Paso 0). Se corre DESDE LA PLANTILLA.
#
#   sh scripts/adoptar.sh inspeccionar <destino>           solo lectura: estado del destino y bloqueos
#   sh scripts/adoptar.sh vista-previa <destino>           qué copiaría, qué colisiona, qué se excluye; no escribe
#   sh scripts/adoptar.sh copiar <destino> [motivo]        copia SOLO lo ausente; crea contexto/adopcion.md una vez;
#                                                          tras la instalación, anota cada adición en el log de actualizaciones
#   sh scripts/adoptar.sh gitignore <destino> [--aplicar]  entradas del método que faltan; con --aplicar las añade
#   sh scripts/adoptar.sh actualizar <destino> "<motivo>"   sustituye SOLO lo instalado que el proyecto no tocó
#                                                          y lo registra en contexto/adopcion-actualizaciones.md
#
# Garantías (regresión: scripts/pruebas/regresion-adopcion.sh):
# - Ningún archivo existente del destino cambia (salvo el log append-only de actualizaciones, que solo crece). Repetir `copiar` con la misma plantilla no escribe nada.
# - Conjunto distribuible CERRADO por nombre ($CONJUNTO); su contenido se enumera con git. Un archivo
#   nuevo en la raíz de la plantilla no entra solo. README.md, .gitignore y mejoras/ quedan fuera a
#   propósito: el README del proyecto manda, .gitignore tiene su modo, mejoras/ es local.
# - La PRIMERA copia exige un commit base y ningún cambio sin commitear (la instalación debe
#   distinguirse de lo previo); inspeccionar y vista-previa lo informan sin bloquear. Git se informa
#   por separado; del remoto, solo el nombre.
# - Antes de escribir se bloquea: un enlace simbólico en CUALQUIER componente de una ruta destino (se
#   escribiría fuera del repositorio) y una ruta que el destino ignora con la semántica de git.
# - El manifiesto registra lo instalado con su hash y no se modifica NUNCA (tampoco antes del commit
#   de instalación). Una actualización posterior va a contexto/adopcion-actualizaciones.md (append-only:
#   ruta · hash anterior → hash nuevo · plantilla · fecha · motivo), y la clasificación usa el último
#   hash registrado allí. Resumen: cada corrida clasifica
#   contra él (sin cambios, modificado en el destino, plantilla actualizada, idéntico sin registro,
#   colisión) y nunca sobreescribe.
# - `gitignore` evalúa el efecto del bloque candidato ANTES y DESPUÉS en un repositorio temporal con
#   todos los .gitignore del destino; si oculta un archivo versionado, `--aplicar` no aplica nada.
set -euf   # -f: sin comodines; las reglas de .gitignore (*.pyc) no se expanden

MODO="${1:-}"; DESTINO_ARG="${2:-}"; BANDERA="${3:-}"
PLANTILLA=$(cd "$(dirname "$0")/.." && pwd -P)
CONJUNTO='.claude .githooks .github/workflows/metodo.yml scripts docs contexto/README.md AGENTS.md CLAUDE.md .editorconfig'
EXCLUIDOS='README.md, .gitignore, mejoras/, scripts/adoptar.sh, scripts/pruebas/regresion-adopcion.sh (herramientas de la plantilla)'
MANIFIESTO='contexto/adopcion.md'
ACTUALIZACIONES='contexto/adopcion-actualizaciones.md'

uso() { sed -n '2,11p' "$0" >&2; exit 2; }
fallo() { echo "adoptar: $1" >&2; exit 1; }
case "$MODO" in inspeccionar|vista-previa|copiar|gitignore|actualizar) ;; *) uso ;; esac
[ -n "$DESTINO_ARG" ] || uso
[ -d "$DESTINO_ARG" ] || fallo "el destino no existe o no es un directorio: $DESTINO_ARG"
DESTINO=$(cd "$DESTINO_ARG" && pwd -P)
git -C "$PLANTILLA" rev-parse --show-toplevel >/dev/null 2>&1 || fallo "la plantilla no es un repositorio git: $PLANTILLA"
raiz=$(git -C "$DESTINO" rev-parse --show-toplevel 2>/dev/null) || fallo "el destino no es un repositorio git: $DESTINO"
raiz=$(cd "$raiz" && pwd -P)
[ "$raiz" = "$DESTINO" ] || fallo "el destino no es la RAÍZ de su repositorio (la raíz es $raiz)"
[ "$DESTINO" != "$PLANTILLA" ] || fallo "el destino es la propia plantilla"

# shellcheck disable=SC2086
# Herramientas que solo tienen sentido en la plantilla (se corren desde ella; dentro de un proyecto
# confunden): no se distribuyen.
SOLO_PLANTILLA='scripts/adoptar.sh scripts/pruebas/regresion-adopcion.sh'
ARCHIVOS=$(git -C "$PLANTILLA" ls-files -- $CONJUNTO | grep -vxF "$(printf '%s\n' $SOLO_PLANTILLA)")
[ -n "$ARCHIVOS" ] || fallo "la plantilla no tiene archivos versionados en el conjunto distribuible"
printf '%s\n' "$ARCHIVOS" | grep -q '[[:space:]]' && fallo "una ruta del conjunto tiene espacios; no se admite"
PLANTILLA_COMMIT=$(git -C "$PLANTILLA" rev-parse HEAD 2>/dev/null || echo "sin-commits")
# shellcheck disable=SC2086
PLANTILLA_LIMPIA=$([ -z "$(git -C "$PLANTILLA" status --porcelain -- $CONJUNTO)" ] && echo sí || echo no)

lista() { printf '%s\n' "$1" | sed '/^$/d'; }
cuenta() { lista "$1" | grep -c . || true; }
hash_de() { git hash-object -- "$1"; }

# enlace_en_ruta <ruta> → imprime el primer componente que es un enlace simbólico (rc 0), o rc 1
enlace_en_ruta() {
  p=""
  for comp in $(printf '%s' "$1" | tr '/' ' '); do
    p="${p:+$p/}$comp"
    if [ -L "$DESTINO/$p" ]; then printf '%s' "$p"; return 0; fi
  done
  return 1
}
# negables <lista> → de las rutas del método que el destino ignora, imprime las que una negación
# precisa al final del .gitignore raíz («!/<ruta>») vuelve a incluir. Si lo excluido es una carpeta
# padre, git no permite re-incluir el archivo: esa ruta no sale y sigue siendo bloqueo.
copia_gitignores() {  # copia_gitignores <dir> → todos los .gitignore del destino en sus rutas
  ( cd "$DESTINO" && find . -name .gitignore -not -path './.git/*' -type f ) | while IFS= read -r g; do
    mkdir -p "$1/$(dirname "$g")"; cp "$DESTINO/$g" "$1/$g"
  done
}
negables() {
  [ -n "$(lista "$1")" ] || return 0
  Tn=$(mktemp -d 2>/dev/null || mktemp -d -t adoptar-neg); git init -q "$Tn"; copia_gitignores "$Tn"
  { [ -f "$Tn/.gitignore" ] && [ -n "$(tail -c1 "$Tn/.gitignore")" ] && echo; lista "$1" | sed 's|^|!/|'; } >> "$Tn/.gitignore"
  aun=$(lista "$1" | git -C "$Tn" check-ignore --no-index --stdin 2>/dev/null || true)
  rm -rf "$Tn"
  lista "$1" | while IFS= read -r p; do printf '%s\n' "$aun" | grep -qxF -- "$p" || printf '%s\n' "$p"; done
}

# Hash registrado en el manifiesto para una ruta (sección «Añadidos»: «- <ruta> · <hash>»).
registrado() {  # el último hash registrado: el de la actualización más reciente, o el de la instalación
  [ -f "$DESTINO/$MANIFIESTO" ] || return 0
  if [ -f "$DESTINO/$ACTUALIZACIONES" ]; then
    u=$(awk -v r="$1" '$1=="-" && $2==r && $3=="·" && $5=="→" { h=$6 } END { print h }' "$DESTINO/$ACTUALIZACIONES")
    [ -z "$u" ] || { printf '%s\n' "$u"; return 0; }
  fi
  awk -v r="$1" '
    /^## /{ sec = ($0 ~ /^## Añadidos/) }
    sec && $1=="-" && $2==r && $3=="·" { print $4; exit }' "$DESTINO/$MANIFIESTO"
}

# --- clasificación de cada archivo del conjunto ----------------------------------------
COPIAR=""; AUTO=""; SIN_CAMBIOS=""; MODIFICADO=""; ACTUALIZADA=""; IDENTICO=""; COLISION=""
BLOQ_ENLACE=""; BLOQ_IGNORADO=""
IGN=$(printf '%s\n%s\n%s\n' "$ARCHIVOS" "$MANIFIESTO" "$ACTUALIZACIONES" | git -C "$DESTINO" check-ignore --stdin 2>/dev/null || true)
for f in $ARCHIVOS $MANIFIESTO $ACTUALIZACIONES; do
  if e=$(enlace_en_ruta "$f"); then BLOQ_ENLACE="$BLOQ_ENLACE
$f (enlace simbólico en «${e}»)"; continue; fi
  if printf '%s\n' "$IGN" | grep -qxF -- "$f"; then BLOQ_IGNORADO="$BLOQ_IGNORADO
$f"; continue; fi
  [ "$f" = "$MANIFIESTO" ] || [ "$f" = "$ACTUALIZACIONES" ] && continue
  if [ ! -e "$DESTINO/$f" ]; then
    COPIAR="$COPIAR
$f"
    printf '%s' "$f" | grep -qE '^(\.claude/|CLAUDE\.md$|AGENTS\.md$)' && AUTO="$AUTO
$f"
    continue
  fi
  hd=$(hash_de "$DESTINO/$f"); hp=$(hash_de "$PLANTILLA/$f"); reg=$(registrado "$f")
  if [ -n "$reg" ]; then
    if [ "$hd" != "$reg" ]; then MODIFICADO="$MODIFICADO
$f"
    elif [ "$hp" != "$reg" ]; then ACTUALIZADA="$ACTUALIZADA
$f"
    else SIN_CAMBIOS="$SIN_CAMBIOS
$f"; fi
  elif [ "$hd" = "$hp" ]; then IDENTICO="$IDENTICO
$f"
  else COLISION="$COLISION
$f"; fi
done
BLOQUEOS=$(( $(cuenta "$BLOQ_ENLACE") + $(cuenta "$BLOQ_IGNORADO") ))

# Instalados que la plantilla ya no distribuye: se informan y se conservan (retirarlos exige
# revisar modificaciones e integraciones locales; no se hace en automático).
RETIRADOS=""
if [ -f "$DESTINO/$MANIFIESTO" ]; then
  instalados=$( { awk '/^## /{ sec = ($0 ~ /^## Añadidos/) } sec && $1=="-" && $3=="·" { print $2 }' "$DESTINO/$MANIFIESTO"
                  [ -f "$DESTINO/$ACTUALIZACIONES" ] && awk '$1=="-" && $3=="·" && $5=="→" && $6 !~ /^\(retirado/ { print $2 }' "$DESTINO/$ACTUALIZACIONES"
                } | sort -u)
  retirados_ya=""
  [ ! -f "$DESTINO/$ACTUALIZACIONES" ] || retirados_ya=$(awk '$1=="-" && $3=="·" && $5=="→" && $6 ~ /^\(retirado/ { print $2 }' "$DESTINO/$ACTUALIZACIONES" | sort -u)
  for f in $instalados; do
    printf '%s\n' "$ARCHIVOS" | grep -qxF -- "$f" && continue
    printf '%s\n' "$retirados_ya" | grep -qxF -- "$f" && continue
    [ -e "$DESTINO/$f" ] || continue
    RETIRADOS="$RETIRADOS
$f"
  done
fi

HOOKS_PATH=$(git -C "$DESTINO" config core.hooksPath 2>/dev/null || echo "sin configurar")
# Git por separado: cada dato se informa solo; se pregunta lo que falte. Del remoto, solo el nombre
# (una URL puede llevar credenciales). Publicar es una decisión de la persona, no un dato.
NOMBRE=$(git -C "$DESTINO" config user.name 2>/dev/null || true); CORREO=$(git -C "$DESTINO" config user.email 2>/dev/null || true)
if [ -n "$NOMBRE" ] && [ -n "$CORREO" ]; then IDENTIDAD="$NOMBRE <$CORREO>"; else IDENTIDAD="FALTA (git config user.name y user.email)"; fi
RAMA=$(git -C "$DESTINO" symbolic-ref --short -q HEAD 2>/dev/null || echo "HEAD separado (sin rama)")
REMOTOS=$(git -C "$DESTINO" remote 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
[ -n "$REMOTOS" ] || REMOTOS="ninguno (el trabajo local sigue; publicar no aplica mientras no haya uno)"
BASE_SHA=$(git -C "$DESTINO" rev-parse --short --verify -q HEAD 2>/dev/null || true)
CAMBIOS=$(git -C "$DESTINO" status --porcelain 2>/dev/null | grep -c . || true)
# Antes de la PRIMERA copia, lo previo tiene que poder separarse de la instalación: un commit base y
# ningún cambio sin commitear. No es un bloqueo de la inspección: inspeccionar y vista-previa siguen.
PREVIAS=""
if [ ! -f "$DESTINO/$MANIFIESTO" ]; then
  [ -n "$BASE_SHA" ] || PREVIAS="sin commits: haz un commit con el estado actual del proyecto (será la Base del método)"
  [ "$CAMBIOS" -eq 0 ] || PREVIAS="$PREVIAS
$CAMBIOS cambio(s) sin commitear: commitéalos o apártalos (git stash -u) para que no se mezclen con la instalación"
fi
HOOKS_PROPIOS=$(ls "$DESTINO/.git/hooks" 2>/dev/null | grep -v '\.sample$' | tr '\n' ' ' || true)
PENDIENTES="README.md: se conserva el del proyecto; se verifica contra el código en la Fase 1
.gitignore: entradas del método con «sh scripts/adoptar.sh gitignore <destino> --aplicar»"
for f in CLAUDE.md AGENTS.md; do
  if printf '%s\n' "$COLISION" | grep -qx "$f"; then PENDIENTES="$PENDIENTES
$f: existe en el proyecto; se integra por referencia y con aprobación, sin renombrar"; fi
done
[ "$HOOKS_PATH" != "sin configurar" ] && [ "$HOOKS_PATH" != ".githooks" ] && PENDIENTES="$PENDIENTES
hooks: core.hooksPath apunta a «${HOOKS_PATH}»; decidir cómo conviven antes de activar .githooks"
[ -n "$HOOKS_PROPIOS" ] && PENDIENTES="$PENDIENTES
hooks: .git/hooks tiene hooks propios ($HOOKS_PROPIOS); decidir cómo conviven antes de activar .githooks"
if [ -d "$DESTINO/.github" ] && printf '%s\n' "$COPIAR" | grep -qx '.github/workflows/metodo.yml'; then PENDIENTES="$PENDIENTES
.github/: el proyecto ya tiene; revisar el efecto de metodo.yml sobre su CI"; fi
for f in $(lista "$RETIRADOS"); do PENDIENTES="$PENDIENTES
$f: la plantilla ya no lo distribuye; se conserva; decidir a mano si se retira (y registrarlo)"; done
for f in $(lista "$COLISION"); do
  case "$f" in CLAUDE.md|AGENTS.md) continue ;; esac
  PENDIENTES="$PENDIENTES
$f: colisión; se conserva el del proyecto y su contenido se integra en la Fase 1"
done

seccion() {  # seccion <título> <lista>
  echo "-- $1: $(cuenta "$2")"; lista "$2" | sed 's/^/   /'
}

inspeccionar() {
  echo "== Inspección de $DESTINO"
  echo "-- Git (cada punto por separado; se pregunta solo lo que falte)"
  echo "identidad:            $IDENTIDAD"
  echo "rama:                 $RAMA"
  echo "remoto:               $REMOTOS"
  echo "publicar:             decisión de la persona, en su momento; no se deduce de la configuración"
  echo "commit actual:        ${BASE_SHA:-sin commits}"
  echo "cambios pendientes:   $CAMBIOS"
  echo "core.hooksPath:       $HOOKS_PATH"
  echo "hooks en .git/hooks:  ${HOOKS_PROPIOS:-ninguno}"
  for f in README.md CLAUDE.md AGENTS.md .claude .githooks scripts docs contexto .github .editorconfig; do
    printf '%-22s%s\n' "$f:" "$([ -e "$DESTINO/$f" ] && echo existe || echo ausente)"
  done
  echo "manifiesto:           $([ -f "$DESTINO/$MANIFIESTO" ] && echo "existe ($MANIFIESTO)" || echo ausente)"
  [ ! -L "$DESTINO/.gitignore" ] || echo ".gitignore:           ENLACE SIMBÓLICO (el modo gitignore lo rechaza: escribiría fuera del repositorio)"
  echo "plantilla:            $PLANTILLA_COMMIT (árbol del conjunto limpio: $PLANTILLA_LIMPIA)"
  echo "== Bloqueos: $BLOQUEOS"
  [ -z "$BLOQ_ENLACE" ] || seccion "enlace simbólico en la ruta (se escribiría fuera del repositorio)" "$BLOQ_ENLACE"
  if [ -n "$BLOQ_IGNORADO" ]; then
    seccion "ignorado por el destino (entraría al disco, no al repositorio)" "$BLOQ_IGNORADO"
    neg=$(negables "$BLOQ_IGNORADO")
    [ -z "$(lista "$neg")" ] || seccion "de ellos, resolubles con una negación precisa (la propone y la aplica, con --aplicar, «sh scripts/adoptar.sh gitignore <destino>»)" "$neg"
    duro=$(lista "$BLOQ_IGNORADO" | while IFS= read -r p; do printf '%s\n' "$neg" | grep -qxF -- "$p" || printf '%s\n' "$p"; done)
    [ -z "$(lista "$duro")" ] || seccion "de ellos, con una carpeta padre excluida (una negación no los rescata; se resuelve con la persona)" "$duro"
  fi
  antes_de_copiar
  [ "$BLOQUEOS" -eq 0 ]
}
antes_de_copiar() {
  [ -n "$(lista "$PREVIAS")" ] || return 0
  seccion "Antes de la primera copia (copiar lo exige; inspeccionar y vista-previa no)" "$PREVIAS"
}
informe() {
  seccion "Se copiaría (ausente en el destino)" "$COPIAR"
  seccion "Afecta autodescubrimiento del agente desde que se copia" "$AUTO"
  seccion "Instalado sin cambios" "$SIN_CAMBIOS"
  seccion "Modificado en el destino desde la instalación (no se toca)" "$MODIFICADO"
  seccion "Plantilla actualizada desde la instalación (no se toca; actualización pendiente)" "$ACTUALIZADA"
  seccion "Existente e idéntico a la plantilla, sin instalación registrada" "$IDENTICO"
  seccion "Colisión: existe y difiere de la plantilla (se conserva el del proyecto)" "$COLISION"
  seccion "Retirado de la distribución (instalado; se conserva; decidir a mano)" "$RETIRADOS"
  echo "-- Excluido deliberadamente: $EXCLUIDOS"
  seccion "Bloqueado" "$BLOQ_ENLACE$BLOQ_IGNORADO"
}
vista_previa() {
  echo "== Vista previa de adopción en $DESTINO (no escribe nada)"
  informe
  echo "-- Pendiente de integración a mano (Paso D):"; printf '%s\n' "$PENDIENTES" | sed 's/^/   /'
  antes_de_copiar
}
manifiesto() {
  echo "# Adopción del método — manifiesto de instalación"
  echo
  echo "> Lo escribe \`scripts/adoptar.sh copiar\` en la PRIMERA copia y no se modifica después: las"
  echo "> corridas siguientes clasifican contra él e informan. Lo lee el agente en el Paso 0 de"
  echo "> \`docs/arranque-existente.md\`. Es un registro, no un plan."
  echo
  echo "- Fecha (UTC): $(date -u +'%Y-%m-%d %H:%M')"
  echo "- Plantilla de origen: commit $PLANTILLA_COMMIT (árbol del conjunto limpio: $PLANTILLA_LIMPIA)"
  echo
  echo "## Añadidos (ruta · hash del contenido instalado)"
  echo
  for f in $(lista "$COPIAR"); do echo "- $f · $(hash_de "$DESTINO/$f")"; done
  echo
  echo "## Omitidos por colisión (se conserva el archivo del proyecto)"
  echo
  if [ -n "$(lista "$COLISION")" ]; then lista "$COLISION" | sed 's/^/- /'; else echo "- ninguno"; fi
  echo
  echo "## Existentes e idénticos a la plantilla (no se copiaron)"
  echo
  if [ -n "$(lista "$IDENTICO")" ]; then lista "$IDENTICO" | sed 's/^/- /'; else echo "- ninguno"; fi
  echo
  echo "## Excluidos deliberadamente"
  echo
  echo "- $EXCLUIDOS"
  echo
  echo "## Pendientes de integración a mano (Paso D)"
  echo
  printf '%s\n' "$PENDIENTES" | sed 's/^/- /'
}
# Log append-only de cambios tras la instalación (el manifiesto no se toca nunca). Lo escriben
# `actualizar` (sustituciones) y `copiar` (adiciones de archivos nuevos de la plantilla).
log_actualizaciones() {
  log="$DESTINO/$ACTUALIZACIONES"
  [ ! -f "$log" ] || return 0
  { echo "# Adopción del método — actualizaciones de archivos instalados"
    echo
    echo "> Append-only. Lo escriben \`scripts/adoptar.sh actualizar\` (sustituye solo archivos que el proyecto"
    echo "> no modificó desde su último registro) y \`copiar\` (añade archivos nuevos de la plantilla tras la"
    echo "> instalación; hash anterior «(ausente)»). El manifiesto (\`$MANIFIESTO\`) no se toca nunca."
    echo "> Formato: ruta · hash anterior → hash nuevo · plantilla · fecha UTC · motivo."
    echo; } > "$log"
}

copiar() {
  [ "$BLOQUEOS" -eq 0 ] || { inspeccionar >&2 || true; fallo "hay $BLOQUEOS bloqueo(s): resuélvelos antes de copiar"; }
  instalado=0; [ ! -f "$DESTINO/$MANIFIESTO" ] || instalado=1
  [ -z "$(lista "$PREVIAS")" ] || { antes_de_copiar >&2; fallo "lo previo del proyecto no se puede separar de la instalación: resuélvelo antes de la primera copia"; }
  n=0; fecha=$(date -u +'%Y-%m-%d %H:%M')
  for f in $(lista "$COPIAR"); do
    [ -e "$DESTINO/$f" ] && continue   # defensa: nunca sobre un existente
    mkdir -p "$DESTINO/$(dirname "$f")"
    cp -p "$PLANTILLA/$f" "$DESTINO/$f"
    if [ "$instalado" -eq 1 ]; then   # adición tras la instalación: al log, no al manifiesto
      log_actualizaciones
      printf -- '- %s · (ausente) → %s · plantilla %s · %s · %s\n' "$f" "$(hash_de "$DESTINO/$f")" "$PLANTILLA_COMMIT" "$fecha" "${BANDERA:-adición tras la instalación (copiar)}" >> "$log"
    fi
    n=$((n+1))
  done
  [ "$instalado" -eq 0 ] || [ "$n" -eq 0 ] || echo "-- Adiciones registradas en $ACTUALIZACIONES: $n"

  echo "== Copia en $DESTINO: $n archivo(s) copiado(s)"
  informe
  if [ -f "$DESTINO/$MANIFIESTO" ]; then
    echo "-- Manifiesto: existe y NO se modifica ($MANIFIESTO)."
    # Una colisión ya registrada en la instalación no es una diferencia; una nueva, sí.
    nuevas_col=""
    for f in $(lista "$COLISION"); do
      awk -v r="$f" '/^## /{ sec = ($0 ~ /^## Omitidos por colisión/) } sec && $1=="-" && $2==r { e=1 } END { exit !e }' \
        "$DESTINO/$MANIFIESTO" || nuevas_col="$nuevas_col $f"
    done
    if [ "$n" -eq 0 ] && [ -z "$MODIFICADO$ACTUALIZADA$nuevas_col" ]; then
      echo "   Sin diferencias respecto de la instalación registrada."
    else
      echo "   Diferencias respecto de la instalación registrada: las listas de arriba distintas de «sin cambios»."
    fi
  else
    mkdir -p "$DESTINO/contexto"
    manifiesto > "$DESTINO/$MANIFIESTO"
    echo "-- Manifiesto creado: $MANIFIESTO"
  fi
}

gitignore_modo() {
  [ -f "$PLANTILLA/.gitignore" ] || fallo "la plantilla no tiene .gitignore"
  gi="$DESTINO/.gitignore"
  # El .gitignore raíz es la única ruta que este modo escribe: si es un enlace simbólico (o un
  # directorio), escribir en él saldría del repositorio. Se rechaza antes de leer o escribir nada.
  [ ! -L "$gi" ] || fallo ".gitignore es un enlace simbólico (apunta a $(readlink "$gi")): escribir en él modificaría un archivo fuera del repositorio. Reemplázalo por un archivo real y repite."
  [ ! -e "$gi" ] || [ -f "$gi" ] || fallo ".gitignore existe pero no es un archivo regular"
  # Bloque candidato: reglas de la plantilla ausentes (línea exacta) en el .gitignore raíz, en su orden.
  bloque=""
  for r in $(grep -vE '^[[:space:]]*(#|$)' "$PLANTILLA/.gitignore"); do
    [ -f "$gi" ] && grep -qxF -- "$r" "$gi" && continue
    bloque="$bloque
$r"
  done
  # Negaciones precisas para archivos del método que el destino ignora y que una negación rescata.
  negaciones=$(negables "$BLOQ_IGNORADO" | sed 's|^|!/|')
  bloque="$bloque
$negaciones"
  echo "== .gitignore de $DESTINO"
  if [ -z "$(lista "$bloque")" ]; then echo "-- Nada que añadir: todas las entradas del método ya están."; return 0; fi
  # Efecto ANTES y DESPUÉS en un repositorio temporal con todos los .gitignore del destino en sus rutas.
  T=$(mktemp -d 2>/dev/null || mktemp -d -t adoptar-gi)
  git init -q "$T"; copia_gitignores "$T"
  versionados=$(git -C "$DESTINO" ls-files)
  antes=$(printf '%s\n' "$versionados" | git -C "$T" check-ignore --no-index --stdin 2>/dev/null || true)
  { [ -f "$T/.gitignore" ] && [ -n "$(tail -c1 "$T/.gitignore")" ] && echo; lista "$bloque"; } >> "$T/.gitignore"
  despues=$(printf '%s\n' "$versionados" | git -C "$T" check-ignore --no-index --stdin 2>/dev/null || true)
  nuevas=$(printf '%s\n' "$despues" | sed '/^$/d' | while IFS= read -r p; do
    printf '%s\n' "$antes" | grep -qxF -- "$p" || printf '%s\n' "$p"
  done)
  explica=""
  [ -z "$nuevas" ] || explica=$(printf '%s\n' "$nuevas" | git -C "$T" check-ignore --no-index -v --stdin 2>/dev/null | awk -F'\t' '{ n=split($1,a,":"); printf "%s  (regla «%s»)\n", $2, a[n] }')
  rm -rf "$T"
  seccion "Entradas del método que faltan (bloque candidato, en orden)" "$bloque"
  seccion "Archivos del método que el destino ignora y que la negación vuelve a incluir" "$(printf '%s\n' "$negaciones" | sed 's|^!/||')"
  seccion "Versionados que el bloque OCULTARÍA (exclusión nueva)" "$explica"
  seccion "Versionados que el destino YA ignoraba (preexistente; hallazgo, no causado por el bloque)" "$antes"
  if [ "$BANDERA" = "--aplicar" ]; then
    [ -z "$(lista "$nuevas")" ] || fallo "no se aplica nada: el bloque ocultaría archivos versionados. Decide primero qué hacer con ellos (p. ej. retirar del índice un secreto) y repite."
    { [ -f "$gi" ] && [ -n "$(tail -c1 "$gi")" ] && echo; echo "# Método (adopción): añadido por scripts/adoptar.sh"; lista "$bloque"; } >> "$gi"
    echo "-- Aplicado: $(cuenta "$bloque") entrada(s) añadida(s) al final de .gitignore"
  fi
}

actualizar() {
  [ -f "$DESTINO/$MANIFIESTO" ] || fallo "no hay manifiesto de instalación ($MANIFIESTO): primero 'copiar'"
  [ "$BLOQUEOS" -eq 0 ] || { inspeccionar >&2 || true; fallo "hay $BLOQUEOS bloqueo(s): resuélvelos antes de actualizar"; }
  [ -n "$BANDERA" ] || fallo "falta el motivo: sh scripts/adoptar.sh actualizar <destino> \"<motivo>\""
  log_actualizaciones
  n=0; fecha=$(date -u +'%Y-%m-%d %H:%M')
  for f in $(lista "$ACTUALIZADA"); do
    ant=$(registrado "$f")
    # ACTUALIZADA ya exige destino == último hash registrado: lo modificado por el proyecto no llega aquí.
    cp -p "$PLANTILLA/$f" "$DESTINO/$f"
    printf -- '- %s · %s → %s · plantilla %s · %s · %s\n' "$f" "$ant" "$(hash_de "$DESTINO/$f")" "$PLANTILLA_COMMIT" "$fecha" "$BANDERA" >> "$log"
    n=$((n+1))
  done
  echo "== Actualización en $DESTINO: $n archivo(s) sustituido(s) y registrado(s) en $ACTUALIZACIONES"
  seccion "No se actualiza: modificado en el destino (integración manual)" "$MODIFICADO"
  seccion "Ausente en el destino (usa 'copiar')" "$COPIAR"
}

case "$MODO" in
  actualizar) actualizar ;;
  inspeccionar) inspeccionar ;;
  vista-previa) vista_previa ;;
  copiar) copiar ;;
  gitignore) gitignore_modo ;;
esac
