#!/bin/sh
# Instala el método en un proyecto que YA EXISTE sin tocar nada de lo que ya tiene.
# Guion: docs/arranque-existente.md (Paso 0). Se corre DESDE LA PLANTILLA.
#
#   sh scripts/adoptar.sh inspeccionar <destino>           solo lectura: estado del destino y bloqueos
#   sh scripts/adoptar.sh vista-previa <destino>           qué copiaría, qué colisiona, qué se excluye; no escribe
#   sh scripts/adoptar.sh copiar <destino>                 copia SOLO lo ausente; crea contexto/adopcion.md una vez
#   sh scripts/adoptar.sh gitignore <destino> [--aplicar]  entradas del método que faltan; con --aplicar las añade
#
# Garantías (regresión: scripts/pruebas/regresion-adopcion.sh):
# - Ningún archivo existente del destino cambia. Repetir `copiar` con la misma plantilla no escribe nada.
# - Conjunto distribuible CERRADO por nombre ($CONJUNTO); su contenido se enumera con git. Un archivo
#   nuevo en la raíz de la plantilla no entra solo. README.md, .gitignore y mejoras/ quedan fuera a
#   propósito: el README del proyecto manda, .gitignore tiene su modo, mejoras/ es local.
# - Antes de escribir se bloquea: un enlace simbólico en CUALQUIER componente de una ruta destino (se
#   escribiría fuera del repositorio) y una ruta que el destino ignora con la semántica de git.
# - El manifiesto registra lo instalado con su hash y no se modifica después: cada corrida clasifica
#   contra él (sin cambios, modificado en el destino, plantilla actualizada, idéntico sin registro,
#   colisión) y nunca sobreescribe.
# - `gitignore` evalúa el efecto del bloque candidato ANTES y DESPUÉS en un repositorio temporal con
#   todos los .gitignore del destino; si oculta un archivo versionado, `--aplicar` no aplica nada.
set -euf   # -f: sin comodines; las reglas de .gitignore (*.pyc) no se expanden

MODO="${1:-}"; DESTINO_ARG="${2:-}"; BANDERA="${3:-}"
PLANTILLA=$(cd "$(dirname "$0")/.." && pwd -P)
CONJUNTO='.claude .githooks .github/workflows/metodo.yml scripts docs contexto/README.md AGENTS.md CLAUDE.md .editorconfig'
EXCLUIDOS='README.md, .gitignore, mejoras/'
MANIFIESTO='contexto/adopcion.md'

uso() { sed -n '2,9p' "$0" >&2; exit 2; }
fallo() { echo "adoptar: $1" >&2; exit 1; }
case "$MODO" in inspeccionar|vista-previa|copiar|gitignore) ;; *) uso ;; esac
[ -n "$DESTINO_ARG" ] || uso
[ -d "$DESTINO_ARG" ] || fallo "el destino no existe o no es un directorio: $DESTINO_ARG"
DESTINO=$(cd "$DESTINO_ARG" && pwd -P)
git -C "$PLANTILLA" rev-parse --show-toplevel >/dev/null 2>&1 || fallo "la plantilla no es un repositorio git: $PLANTILLA"
raiz=$(git -C "$DESTINO" rev-parse --show-toplevel 2>/dev/null) || fallo "el destino no es un repositorio git: $DESTINO"
raiz=$(cd "$raiz" && pwd -P)
[ "$raiz" = "$DESTINO" ] || fallo "el destino no es la RAÍZ de su repositorio (la raíz es $raiz)"
[ "$DESTINO" != "$PLANTILLA" ] || fallo "el destino es la propia plantilla"

# shellcheck disable=SC2086
ARCHIVOS=$(git -C "$PLANTILLA" ls-files -- $CONJUNTO)
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
# Hash registrado en el manifiesto para una ruta (sección «Añadidos»: «- <ruta> · <hash>»).
registrado() {
  [ -f "$DESTINO/$MANIFIESTO" ] || return 0
  awk -v r="$1" '
    /^## /{ sec = ($0 ~ /^## Añadidos/) }
    sec && $1=="-" && $2==r && $3=="·" { print $4; exit }' "$DESTINO/$MANIFIESTO"
}

# --- clasificación de cada archivo del conjunto ----------------------------------------
COPIAR=""; AUTO=""; SIN_CAMBIOS=""; MODIFICADO=""; ACTUALIZADA=""; IDENTICO=""; COLISION=""
BLOQ_ENLACE=""; BLOQ_IGNORADO=""
IGN=$(printf '%s\n%s\n' "$ARCHIVOS" "$MANIFIESTO" | git -C "$DESTINO" check-ignore --stdin 2>/dev/null || true)
for f in $ARCHIVOS $MANIFIESTO; do
  if e=$(enlace_en_ruta "$f"); then BLOQ_ENLACE="$BLOQ_ENLACE
$f (enlace simbólico en «${e}»)"; continue; fi
  if printf '%s\n' "$IGN" | grep -qxF -- "$f"; then BLOQ_IGNORADO="$BLOQ_IGNORADO
$f"; continue; fi
  [ "$f" = "$MANIFIESTO" ] && continue
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

HOOKS_PATH=$(git -C "$DESTINO" config core.hooksPath 2>/dev/null || echo "sin configurar")
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
  echo "commit actual:        $(git -C "$DESTINO" rev-parse --short HEAD 2>/dev/null || echo 'sin commits')"
  echo "cambios pendientes:   $(git -C "$DESTINO" status --porcelain | grep -c . || true)"
  echo "core.hooksPath:       $HOOKS_PATH"
  echo "hooks en .git/hooks:  ${HOOKS_PROPIOS:-ninguno}"
  for f in README.md CLAUDE.md AGENTS.md .claude .githooks scripts docs contexto .github .editorconfig; do
    printf '%-22s%s\n' "$f:" "$([ -e "$DESTINO/$f" ] && echo existe || echo ausente)"
  done
  echo "manifiesto:           $([ -f "$DESTINO/$MANIFIESTO" ] && echo "existe ($MANIFIESTO)" || echo ausente)"
  echo "plantilla:            $PLANTILLA_COMMIT (árbol del conjunto limpio: $PLANTILLA_LIMPIA)"
  echo "== Bloqueos: $BLOQUEOS"
  [ -z "$BLOQ_ENLACE" ] || seccion "enlace simbólico en la ruta (se escribiría fuera del repositorio)" "$BLOQ_ENLACE"
  [ -z "$BLOQ_IGNORADO" ] || seccion "ignorado por el destino (entraría al disco, no al repositorio)" "$BLOQ_IGNORADO"
  [ "$BLOQUEOS" -eq 0 ]
}
informe() {
  seccion "Se copiaría (ausente en el destino)" "$COPIAR"
  seccion "Afecta autodescubrimiento del agente desde que se copia" "$AUTO"
  seccion "Instalado sin cambios" "$SIN_CAMBIOS"
  seccion "Modificado en el destino desde la instalación (no se toca)" "$MODIFICADO"
  seccion "Plantilla actualizada desde la instalación (no se toca; actualización pendiente)" "$ACTUALIZADA"
  seccion "Existente e idéntico a la plantilla, sin instalación registrada" "$IDENTICO"
  seccion "Colisión: existe y difiere de la plantilla (se conserva el del proyecto)" "$COLISION"
  echo "-- Excluido deliberadamente: $EXCLUIDOS"
  seccion "Bloqueado" "$BLOQ_ENLACE$BLOQ_IGNORADO"
}
vista_previa() {
  echo "== Vista previa de adopción en $DESTINO (no escribe nada)"
  informe
  echo "-- Pendiente de integración a mano (Paso D):"; printf '%s\n' "$PENDIENTES" | sed 's/^/   /'
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
copiar() {
  [ "$BLOQUEOS" -eq 0 ] || { inspeccionar >&2 || true; fallo "hay $BLOQUEOS bloqueo(s): resuélvelos antes de copiar"; }
  n=0
  for f in $(lista "$COPIAR"); do
    [ -e "$DESTINO/$f" ] && continue   # defensa: nunca sobre un existente
    mkdir -p "$DESTINO/$(dirname "$f")"
    cp -p "$PLANTILLA/$f" "$DESTINO/$f"
    n=$((n+1))
  done
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
  # Bloque candidato: reglas de la plantilla ausentes (línea exacta) en el .gitignore raíz, en su orden.
  bloque=""
  for r in $(grep -vE '^[[:space:]]*(#|$)' "$PLANTILLA/.gitignore"); do
    [ -f "$gi" ] && grep -qxF -- "$r" "$gi" && continue
    bloque="$bloque
$r"
  done
  echo "== .gitignore de $DESTINO"
  if [ -z "$(lista "$bloque")" ]; then echo "-- Nada que añadir: todas las entradas del método ya están."; return 0; fi
  # Efecto ANTES y DESPUÉS en un repositorio temporal con todos los .gitignore del destino en sus rutas.
  T=$(mktemp -d 2>/dev/null || mktemp -d -t adoptar-gi)
  git init -q "$T"
  ( cd "$DESTINO" && find . -name .gitignore -not -path './.git/*' -type f ) | while IFS= read -r g; do
    mkdir -p "$T/$(dirname "$g")"; cp "$DESTINO/$g" "$T/$g"
  done
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
  seccion "Versionados que el bloque OCULTARÍA (exclusión nueva)" "$explica"
  seccion "Versionados que el destino YA ignoraba (preexistente; hallazgo, no causado por el bloque)" "$antes"
  if [ "$BANDERA" = "--aplicar" ]; then
    [ -z "$(lista "$nuevas")" ] || fallo "no se aplica nada: el bloque ocultaría archivos versionados. Decide primero qué hacer con ellos (p. ej. retirar del índice un secreto) y repite."
    { [ -f "$gi" ] && [ -n "$(tail -c1 "$gi")" ] && echo; echo "# Método (adopción): añadido por scripts/adoptar.sh"; lista "$bloque"; } >> "$gi"
    echo "-- Aplicado: $(cuenta "$bloque") entrada(s) añadida(s) al final de .gitignore"
  fi
}

case "$MODO" in
  inspeccionar) inspeccionar ;;
  vista-previa) vista_previa ;;
  copiar) copiar ;;
  gitignore) gitignore_modo ;;
esac
