#!/bin/sh
# Regresión de la ADOPCIÓN de un proyecto existente (viene con la plantilla; docs/arranque-existente.md).
# Prueba las dos piezas propias de esa ruta: scripts/adoptar.sh (copia sin sobreescribir, manifiesto,
# bloqueos, .gitignore por efecto) y el recorte por «Base del método» de validar_historial.sh, con su
# caso NEGATIVO y su control POSITIVO. Sin red ni credenciales: git, sh, awk y python3.
#
#   sh scripts/pruebas/regresion-adopcion.sh        → 0 si todos los casos pasan; 1 y la lista si no
#   sh scripts/pruebas/regresion-adopcion.sh -v     → además imprime la salida de cada caso
#
# AUTOCONTENIDA: del repositorio donde corre toma SOLO la instrumentación del método (.githooks/,
# scripts/, .claude/, .github/); los documentos de la «plantilla» de prueba son los de este repositorio
# si es la plantilla sin iniciar (estado.md con F_), o sintéticos si no. El proyecto destino es
# sintético: README propio, código, un runbook propio en docs/despliegue.md, un .env versionado y tres
# commits previos sin trailers (lo que el método nunca juzgó).
VERBOSE=0; [ "${1:-}" = "-v" ] && VERBOSE=1
RAIZ=$(cd "$(dirname "$0")/../.." && pwd -P)
W=$(mktemp -d 2>/dev/null || mktemp -d -t regadop); W=$(cd "$W" && pwd -P); trap 'rm -rf "$W"' EXIT INT TERM
export GIT_AUTHOR_NAME=regresion GIT_AUTHOR_EMAIL=regresion@local
export GIT_COMMITTER_NAME=regresion GIT_COMMITTER_EMAIL=regresion@local
export GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_CONFIG_SYSTEM=/dev/null
: > "$W/gitconfig"; git config --file "$W/gitconfig" --add safe.directory "*"
git config --file "$W/gitconfig" init.defaultBranch main
unset FASE_PREVIA FASE_HISTORICA REV
TOTAL=0; MAL=0; FALLIDOS=""

# --- utilidades (mismo contrato que regresion.sh) ----------------------------------------
# espera <falla|pasa> <nombre> <patrón ERE en la salida; vacío = cualquiera> -- cmd...
espera() {
  modo=$1; nombre=$2; patron=$3; shift 4
  TOTAL=$((TOTAL+1)); out=$("$@" 2>&1); rc=$?
  if [ "$modo" = falla ]; then ok=$([ $rc -ne 0 ] && echo 1 || echo 0); else ok=$([ $rc -eq 0 ] && echo 1 || echo 0); fi
  if [ "$ok" = 1 ] && [ -n "$patron" ] && ! printf '%s' "$out" | grep -qE -- "$patron"; then ok=0; fi
  if [ "$ok" = 1 ]; then echo "  ok    $nombre"; else echo "  FALLO $nombre (esperaba $modo${patron:+ con «${patron}»}; rc=$rc)"; MAL=$((MAL+1)); FALLIDOS="$FALLIDOS
    - $nombre"; fi
  { [ "$VERBOSE" = 1 ] || [ "$ok" = 0 ]; } && printf '%s\n' "$out" | sed 's/^/        | /' | head -20
  return 0
}
die() { echo "regresion-adopcion: $1" >&2; exit 2; }   # una preparación fallida aborta: nunca sigue en silencio
en() { d=$1; shift; ( cd "$d" && "$@" ); }
sin_hooks() { en "$1" git add -A && en "$1" git -c core.hooksPath=/dev/null commit -q --no-verify -m "$2"; }
commitea() { en "$1" git add -A && en "$1" git -c core.hooksPath=.githooks commit -q -m "$2"; }
copia() { D="$W/$2"; rm -rf "$D"; cp -R "$W/etapas/$1" "$D"; }
adoptar() { pl=$1; shift; sh "$pl/scripts/adoptar.sh" "$@"; }
huella_arbol() { ( cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(git hash-object "$f")"; done ); }
fase() {  # fase <dir> <F?>
  python3 - "$1/docs/estado.md" "$2" <<'EOF'
import re,sys
p,f=sys.argv[1:]; s=open(p).read()
s=re.sub(r'^- \*\*Fase actual:\*\*.*$', f'- **Fase actual:** {f} · en curso: instalación del método (adopción)', s, count=1, flags=re.M)
open(p,'w').write(s)
EOF
}
base_decl() {  # base_decl <dir> <línea completa o vacío>: reemplaza toda declaración de base
  grep -vE '^- \*\*Base del método:\*\*' "$1/docs/convenciones.md" > "$1/docs/convenciones.md.t"
  [ -n "$2" ] && printf '%s\n' "$2" >> "$1/docs/convenciones.md.t"
  mv "$1/docs/convenciones.md.t" "$1/docs/convenciones.md"
}
replay() { en "$1" sh scripts/pruebas/validar_historial.sh "$2"; }

# --- etapa: plantilla de prueba (repositorio con el conjunto distribuible versionado) -------
mkdir -p "$W/etapas"
P="$W/etapas/plantilla"; mkdir -p "$P"
for d in .githooks scripts .claude .github; do [ -d "$RAIZ/$d" ] && { mkdir -p "$P/$d"; cp -R "$RAIZ/$d/." "$P/$d/"; }; done
find "$P" -name __pycache__ -type d -prune -exec rm -rf {} +
rm -f "$P/scripts/check.sh"
PRISTINA=0; grep -q 'Fase actual:\*\* F_' "$RAIZ/docs/estado.md" 2>/dev/null && PRISTINA=1
if [ "$PRISTINA" -eq 1 ]; then
  for f in AGENTS.md CLAUDE.md README.md .gitignore .editorconfig; do [ -f "$RAIZ/$f" ] && cp "$RAIZ/$f" "$P/$f"; done
  mkdir -p "$P/docs" "$P/contexto"; cp -R "$RAIZ/docs/." "$P/docs/"; cp "$RAIZ/contexto/README.md" "$P/contexto/README.md"
else
  mkdir -p "$P/docs" "$P/contexto"
  printf '# AGENTS.md\n\nPlantilla sintética de la regresión de adopción.\n' > "$P/AGENTS.md"
  printf '# CLAUDE.md\n\n@AGENTS.md\n' > "$P/CLAUDE.md"
  printf '# Plantilla\n\nREADME del método (no se copia).\n' > "$P/README.md"
  cp "$RAIZ/.gitignore" "$P/.gitignore" 2>/dev/null || printf '.env\n.env.*\n!.env.example\n__pycache__/\nmejoras/\n' > "$P/.gitignore"
  printf 'root = true\n' > "$P/.editorconfig"
  printf '# Contexto\n\nEntradas del proyecto.\n' > "$P/contexto/README.md"
  printf '# Estado del proyecto\n\n- **Fase actual:** F_ · incremento activo: I_ «alias»\n- **Próximo paso:** _…_\n' > "$P/docs/estado.md"
  printf '# Encuadre\n\n## Criterios de éxito\n\n- C1:\n' > "$P/docs/encuadre.md"
  printf '# Plan\n\n- [ ] I1 «…» — _…_ (satisface: C_)\n' > "$P/docs/plan.md"
  printf '# Trazabilidad\n\n## Cobertura de criterios\n\n| Criterio | Alias | Incremento(s) | Estado | Nota |\n|----------|-------|---------------|--------|------|\n| C1 | «…» | I_ | pendiente / cubierto / verificado | |\n\n## Registro de vacíos del revisor funcional (arranque)\n\n| Vacío | Alias | Punto incumplido | Estado | Resuelto (cómo · AAAA-MM-DD HH:MM UTC) |\n|-------|-------|------------------|--------|----------------------------------------|\n\n## Registro de revisiones del juez\n\n| Hallazgo | Alias | Incr. | Criterio | Descripción | Estado | Resuelto (AAAA-MM-DD HH:MM UTC · commit) |\n|----------|-------|-------|----------|-------------|--------|------------------------------------------|\n\n## Histórico (compactado)\n\n' > "$P/docs/trazabilidad.md"
  for f in decisiones convenciones definicion-de-hecho despliegue MEMORIA; do printf '# %s\n\n(sintético)\n' "$f" > "$P/docs/$f.md"; done
  printf '# Registro de recibos (sintético). Las líneas que empiezan por # se ignoran.\n' > "$P/docs/revisiones.log"
fi
base_decl "$P" ""
chmod +x "$P"/.githooks/* "$P"/scripts/*.sh "$P"/scripts/pruebas/*.sh 2>/dev/null
en "$P" git init -q && sin_hooks "$P" "plantilla de prueba"

# --- etapa: proyecto existente (tres commits sin trailers) ------------------------------------
E="$W/etapas/existente"; mkdir -p "$E/docs" "$E/config"
en "$E" git init -q
printf '# Proyecto existente\n\nYa funciona.\n' > "$E/README.md"
printf '__pycache__/\n' > "$E/.gitignore"
printf 'assert 1 + 1 == 2\n' > "$E/app.py"
sin_hooks "$E" "inicio"
printf '# Runbook propio\n\nCómo se despliega hoy.\n' > "$E/docs/despliegue.md"
sin_hooks "$E" "runbook"
printf 'API_URL=http://interno\n' > "$E/config/.env.prod"
sin_hooks "$E" "config de producción"
cp "$E/README.md" "$W/readme.orig"; cp "$E/docs/despliegue.md" "$W/runbook.orig"

echo "== adoptar.sh: inspección y vista previa"
espera pasa "inspeccionar la raíz registra la configuración previa (hooks sin configurar)" "core\.hooksPath: +sin configurar" -- adoptar "$P" inspeccionar "$E"
espera falla "inspeccionar un subdirectorio se rechaza (se exige la raíz)" "RAÍZ" -- adoptar "$P" inspeccionar "$E/docs"
mkdir -p "$W/sin-repo"
espera falla "un directorio sin repositorio se rechaza" "no es un repositorio" -- adoptar "$P" inspeccionar "$W/sin-repo"
espera pasa "vista previa: README excluido deliberadamente" "Excluido deliberadamente: README\.md" -- adoptar "$P" vista-previa "$E"
espera pasa "vista previa: docs/despliegue.md propio es colisión" "Colisión: existe y difiere de la plantilla \(se conserva el del proyecto\): 1" -- adoptar "$P" vista-previa "$E"
espera pasa "vista previa: CLAUDE.md marcado como autodescubrimiento" "autodescubrimiento[^:]*: [1-9]" -- adoptar "$P" vista-previa "$E"
espera pasa "vista previa: las herramientas de la plantilla se excluyen deliberadamente" "Excluido deliberadamente: .*scripts/adoptar\\.sh" -- adoptar "$P" vista-previa "$E"
espera pasa "vista previa no escribe nada" "" -- sh -c "[ -z \"\$(git -C '$E' status --porcelain)\" ]"

echo "== adoptar.sh: copia"
copia existente c1
espera pasa "copiar: crea el manifiesto" "Manifiesto creado" -- adoptar "$P" copiar "$D"
espera pasa "copiar: README del proyecto idéntico byte a byte" "" -- cmp "$W/readme.orig" "$D/README.md"
espera pasa "copiar: runbook propio idéntico byte a byte" "" -- cmp "$W/runbook.orig" "$D/docs/despliegue.md"
espera pasa "copiar: adoptar.sh y su regresión no se distribuyen" "" -- sh -c "[ ! -e '$D/scripts/adoptar.sh' ] && [ ! -e '$D/scripts/pruebas/regresion-adopcion.sh' ]"
espera pasa "copiar: los hooks quedan ejecutables" "" -- sh -c "[ -x '$D/.githooks/pre-commit' ] && [ -x '$D/.githooks/commit-msg' ]"
espera pasa "copiar: manifiesto registra hash por archivo y la colisión" "" -- sh -c "grep -qE '^- AGENTS\.md · [0-9a-f]{40}$' '$D/contexto/adopcion.md' && grep -qx -- '- docs/despliegue.md' '$D/contexto/adopcion.md'"
huella_arbol "$D" > "$W/h1"; cp "$D/contexto/adopcion.md" "$W/m1"
espera pasa "repetir: todo instalado sin cambios" "Instalado sin cambios: [1-9]" -- adoptar "$P" copiar "$D"
espera pasa "repetir: la colisión ya registrada no cuenta como diferencia" "Sin diferencias respecto de la instalación registrada" -- adoptar "$P" copiar "$D"
huella_arbol "$D" > "$W/h2"
espera pasa "repetir: cero escrituras (árbol idéntico) y manifiesto idéntico" "" -- sh -c "cmp -s '$W/h1' '$W/h2' && cmp -s '$W/m1' '$D/contexto/adopcion.md'"
espera pasa "repetir: nada se clasifica como idéntico sin registro" "sin instalación registrada: 0" -- adoptar "$P" vista-previa "$D"

echo "== adoptar.sh: plantilla actualizada, destino modificado, añadidos posteriores"
cp -R "$P" "$W/plantilla2"; P2="$W/plantilla2"
printf '\nlínea nueva de la plantilla\n' >> "$P2/docs/MEMORIA.md"
printf '# Nuevo\n' > "$P2/docs/nuevo-del-metodo.md"
sin_hooks "$P2" "plantilla crece"
copia existente c2; adoptar "$P" copiar "$D" >/dev/null; cp "$D/docs/MEMORIA.md" "$W/memoria.inst"
espera pasa "plantilla actualizada: el archivo nuevo de la plantilla se copia" "1 archivo\(s\) copiado" -- adoptar "$P2" copiar "$D"
espera pasa "plantilla actualizada: el cambiado se reporta y el destino conserva lo instalado" "actualización pendiente\): 1" -- sh -c "cmp -s '$W/memoria.inst' '$D/docs/MEMORIA.md' && sh '$P2/scripts/adoptar.sh' vista-previa '$D'"
espera pasa "añadido posterior: queda registrado en el log y figura como instalado, no como colisión" "Instalado sin cambios" -- sh -c "sh '$P2/scripts/adoptar.sh' vista-previa '$D' | awk '/^-- /{s=\$0} /docs\/nuevo-del-metodo\.md/{print s}'"
espera pasa "añadido posterior: el manifiesto original no lo registra (inmutable)" "" -- sh -c "! grep -q 'nuevo-del-metodo' '$D/contexto/adopcion.md'"
copia existente c3; adoptar "$P" copiar "$D" >/dev/null
printf '\nnota del proyecto\n' >> "$D/docs/MEMORIA.md"; cp "$D/docs/MEMORIA.md" "$W/memoria.mod"
printf '\n(nota a mano)\n' >> "$D/contexto/adopcion.md"; cp "$D/contexto/adopcion.md" "$W/manif.mod"
espera pasa "destino modificado: se reporta y no se sobreescribe" "desde la instalación \(no se toca\): 1" -- adoptar "$P" copiar "$D"
espera pasa "destino modificado: contenido y manifiesto editado se conservan" "" -- sh -c "cmp -s '$W/memoria.mod' '$D/docs/MEMORIA.md' && cmp -s '$W/manif.mod' '$D/contexto/adopcion.md'"

echo "== adoptar.sh: actualizar (registro aparte; el manifiesto no se toca)"
copia existente c11; adoptar "$P" copiar "$D" >/dev/null; cp "$D/contexto/adopcion.md" "$W/m11"; H1=$(git hash-object "$D/docs/MEMORIA.md")
espera falla "actualizar sin motivo se rechaza" "falta el motivo" -- adoptar "$P2" actualizar "$D"
espera pasa "actualizar sustituye lo instalado que la plantilla cambió" "1 archivo\(s\) sustituido" -- adoptar "$P2" actualizar "$D" "prueba de regresión"
espera pasa "actualizar: el archivo queda como el de la plantilla nueva y el manifiesto intacto" "" -- sh -c "cmp -s '$P2/docs/MEMORIA.md' '$D/docs/MEMORIA.md' && cmp -s '$W/m11' '$D/contexto/adopcion.md'"
espera pasa "actualizar: registro con hash anterior y nuevo" "" -- sh -c "grep -qE '^- docs/MEMORIA\.md · $H1 → [0-9a-f]{40} · plantilla ' '$D/contexto/adopcion-actualizaciones.md'"
espera pasa "tras actualizar: no queda pendiente ni se ve como modificado" "actualización pendiente\): 0" -- sh -c "sh '$P2/scripts/adoptar.sh' vista-previa '$D' | grep -q 'desde la instalación (no se toca): 0' && sh '$P2/scripts/adoptar.sh' vista-previa '$D'"
espera pasa "actualizar repetido: nada que sustituir y el registro no crece" "0 archivo\(s\) sustituido" -- sh -c "n=\$(wc -l < '$D/contexto/adopcion-actualizaciones.md'); sh '$P2/scripts/adoptar.sh' actualizar '$D' 'otra vez' && [ \$(wc -l < '$D/contexto/adopcion-actualizaciones.md') -eq \$n ]"
copia existente c12; adoptar "$P" copiar "$D" >/dev/null; printf '\nnota del proyecto\n' >> "$D/docs/MEMORIA.md"; cp "$D/docs/MEMORIA.md" "$W/memoria12"
espera pasa "actualizar no sustituye lo que el proyecto modificó (integración manual)" "integración manual\): 1" -- adoptar "$P2" actualizar "$D" "prueba"
espera pasa "actualizar: lo modificado por el proyecto queda intacto" "" -- cmp -s "$W/memoria12" "$D/docs/MEMORIA.md"
echo "== adoptar.sh: archivos que la plantilla deja de distribuir"
cp -R "$P" "$W/plantilla3"; P3="$W/plantilla3"; en "$P3" git rm -q docs/MEMORIA.md; sin_hooks "$P3" "la plantilla deja de distribuir MEMORIA"
copia existente c13; adoptar "$P" copiar "$D" >/dev/null; cp "$D/docs/MEMORIA.md" "$W/memoria13"
espera pasa "retirado de la distribución: se informa" "Retirado de la distribución[^:]*: 1" -- adoptar "$P3" vista-previa "$D"
espera pasa "retirado de la distribución: copiar lo conserva intacto" "" -- sh -c "sh '$P3/scripts/adoptar.sh' copiar '$D' >/dev/null && cmp -s '$W/memoria13' '$D/docs/MEMORIA.md'"
echo "== adoptar.sh: adiciones tras la instalación (log de actualizaciones, manifiesto intacto)"
cp -R "$P" "$W/plantilla4"; P4="$W/plantilla4"; printf '#!/bin/sh\necho nuevo\n' > "$P4/scripts/nuevo.sh"; sin_hooks "$P4" "la plantilla añade un archivo"
copia existente c14; adoptar "$P" copiar "$D" >/dev/null
espera pasa "instalación nueva: no crea el log de actualizaciones" "" -- test ! -e "$D/contexto/adopcion-actualizaciones.md"
cp "$D/contexto/adopcion.md" "$W/manifiesto14"
espera pasa "copiar tras la instalación: anuncia la adición registrada" "Adiciones registradas[^:]*: 1" -- adoptar "$P4" copiar "$D"
espera pasa "copiar tras la instalación: la adición queda en el log con hash anterior ausente" "" -- sh -c "grep -qE '^- scripts/nuevo\.sh · \(ausente\) → [0-9a-f]{40} · plantilla ' '$D/contexto/adopcion-actualizaciones.md'"
espera pasa "copiar tras la instalación: el manifiesto inicial no cambia" "" -- cmp -s "$W/manifiesto14" "$D/contexto/adopcion.md"
espera pasa "copiar tras la instalación: el archivo añadido figura como instalado sin cambios" "Instalado sin cambios" -- sh -c "sh '$P4/scripts/adoptar.sh' vista-previa '$D' | awk '/^-- /{s=\$0} /scripts\/nuevo\.sh/{print s}'"
adoptar "$P4" copiar "$D" >/dev/null
espera pasa "copiar repetido: no duplica la adición" "" -- sh -c "[ \"\$(grep -c 'scripts/nuevo.sh' '$D/contexto/adopcion-actualizaciones.md')\" -eq 1 ]"
echo "== adoptar.sh: bloqueos (enlaces simbólicos y rutas ignoradas)"
copia existente c4; mkdir -p "$W/fuera"; mv "$D/docs" "$W/fuera/docs"; ln -s "$W/fuera/docs" "$D/docs"; sin_hooks "$D" "docs enlazado"
espera falla "enlace simbólico en docs/: la inspección bloquea" "enlace simbólico" -- adoptar "$P" inspeccionar "$D"
espera falla "enlace simbólico en docs/: copiar rehúsa" "bloqueo" -- adoptar "$P" copiar "$D"
espera pasa "enlace simbólico en docs/: nada se escribió fuera del repositorio" "" -- sh -c "[ \"\$(ls '$W/fuera/docs')\" = despliegue.md ] && [ ! -e '$D/AGENTS.md' ]"
copia existente c5; mkdir -p "$W/fuera2"; ln -s "$W/fuera2" "$D/contexto"; sin_hooks "$D" "contexto enlazado"
espera falla "enlace simbólico en contexto/: bloquea también el manifiesto" "contexto/adopcion\.md" -- adoptar "$P" inspeccionar "$D"
copia existente c6; printf 'scripts/\n' >> "$D/.gitignore"; sin_hooks "$D" "ignora scripts"
espera falla "ruta ignorada por el destino: bloquea" "ignorado por el destino" -- adoptar "$P" inspeccionar "$D"
espera falla "carpeta excluida: la negación no la rescata y sigue bloqueando" "carpeta padre excluida[^:]*: [1-9]" -- adoptar "$P" inspeccionar "$D"
espera pasa "carpeta excluida: gitignore no propone negaciones para ella" "" -- sh -c "! sh '$P/scripts/adoptar.sh' gitignore '$D' | grep -q '^ *!/scripts/'"
copia existente c6b; en "$D" git rm -q config/.env.prod; printf '*.log\n' >> "$D/.gitignore"; sin_hooks "$D" "ignora *.log"
espera falla "*.log tapa el registro: bloquea y señala la negación" "resolubles con una negación precisa[^:]*: 1" -- adoptar "$P" inspeccionar "$D"
espera pasa "*.log: gitignore propone la negación precisa y su efecto" "!/docs/revisiones\.log" -- adoptar "$P" gitignore "$D"
espera pasa "*.log: sin --aplicar no se escribe" "" -- sh -c "! grep -qxF '!/docs/revisiones.log' '$D/.gitignore'"
espera pasa "*.log: --aplicar añade la negación" "Aplicado" -- adoptar "$P" gitignore "$D" --aplicar
espera pasa "*.log: tras la negación el registro ya no está ignorado y no hay bloqueos" "Bloqueos: 0" -- adoptar "$P" inspeccionar "$D"
espera pasa "*.log: la negación no rescata otros .log del proyecto" "" -- sh -c "cd '$D' && git check-ignore -q otro.log"

echo "== adoptar.sh: .gitignore por efecto (antes y después)"
copia existente c7
espera falla "gitignore --aplicar rehúsa si el bloque ocultaría un versionado" "config/\.env\.prod +\(regla «\.env\.\*»\)" -- adoptar "$P" gitignore "$D" --aplicar
espera pasa "gitignore rehusado: no se escribió nada" "" -- cmp -s "$E/.gitignore" "$D/.gitignore"
en "$D" git rm -q --cached config/.env.prod; en "$D" git -c core.hooksPath=/dev/null commit -q --no-verify -m "retira secreto (queda en disco, fuera del índice)"
espera pasa "gitignore --aplicar aplica tras retirar el secreto" "Aplicado" -- adoptar "$P" gitignore "$D" --aplicar
espera pasa "gitignore repetido: nada que añadir" "Nada que añadir" -- adoptar "$P" gitignore "$D" --aplicar
espera pasa "gitignore: sin entradas duplicadas" "" -- sh -c "[ \"\$(grep -cxF '.env.*' '$D/.gitignore')\" -eq 1 ]"
copia existente c8; en "$D" git rm -q config/.env.prod
printf '*.log\n' >> "$D/.gitignore"; printf 'x\n' > "$D/keep.log"; mkdir -p "$D/sub"; printf '!keep.log\n' > "$D/sub/.gitignore"; printf 'y\n' > "$D/sub/keep.log"
en "$D" git add -f keep.log; sin_hooks "$D" "logs"
espera pasa "preexistente: un versionado que el destino ya ignoraba se informa aparte" "YA ignoraba \(preexistente; hallazgo, no causado por el bloque\): 1" -- adoptar "$P" gitignore "$D"
espera pasa "preexistente: la negación del .gitignore de subdirectorio se respeta" "" -- sh -c "! sh '$P/scripts/adoptar.sh' gitignore '$D' | grep -qE '^   sub/keep\.log'"
espera pasa "preexistente: no bloquea --aplicar" "Aplicado" -- adoptar "$P" gitignore "$D" --aplicar
copia existente c9; en "$D" git rm -q config/.env.prod
printf 'notas/*\n!notas/mejoras/\n' >> "$D/.gitignore"; mkdir -p "$D/notas/mejoras"; printf 'z\n' > "$D/notas/mejoras/idea.md"; sin_hooks "$D" "notas"
espera falla "negación del destino anulada por una regla posterior del bloque: se detecta por su efecto" "notas/mejoras/idea\.md +\(regla «mejoras/»\)" -- adoptar "$P" gitignore "$D" --aplicar
copia existente c10; mkdir -p "$W/fuera3"; mv "$D/.gitignore" "$W/fuera3/gi"; ln -s "$W/fuera3/gi" "$D/.gitignore"; sin_hooks "$D" "gitignore enlazado"; cp "$W/fuera3/gi" "$W/gi.orig"
espera falla ".gitignore enlace simbólico: --aplicar rehúsa" "enlace simbólico" -- adoptar "$P" gitignore "$D" --aplicar
espera pasa ".gitignore enlace simbólico: el archivo externo queda intacto" "" -- cmp -s "$W/gi.orig" "$W/fuera3/gi"
espera pasa ".gitignore enlace simbólico: la inspección lo reporta" "ENLACE SIMBÓLICO" -- adoptar "$P" inspeccionar "$D"

echo "== base del método: commit de instalación con los hooks reales"
copia existente inst; I="$D"
PREVIO=$(en "$I" git rev-parse HEAD)
adoptar "$P" copiar "$I" >/dev/null
en "$I" git rm -q --cached config/.env.prod
adoptar "$P" gitignore "$I" --aplicar >/dev/null
base_decl "$I" "- **Base del método:** $PREVIO"
fase "$I" F1
en "$I" git config core.hooksPath .githooks
espera pasa "commit de instalación aceptado (Ref: F1, fase en curso, base declarada)" "" -- commitea "$I" "Instalación del método (adopción)

Ref: F1"
mkdir -p "$W/etapas"; rm -rf "$W/etapas/instalado"; cp -R "$I" "$W/etapas/instalado"
INST=$(en "$I" git rev-parse HEAD)

echo "== base del método: replay"
espera pasa "con base: el historial previo no se juzga y la instalación sí" "1/1 commits cumplen" -- replay "$I" HEAD
copia instalado r1; base_decl "$D" ""
espera falla "sin base: los commits previos sin trailers fallan como hoy" "FALLO" -- replay "$D" HEAD
espera pasa "sin base: un rango con ... que git acepta funciona como hoy" "1/1 commits cumplen" -- replay "$D" "HEAD~1...HEAD"
copia instalado r2
espera falla "con base: un rango con ... se rechaza (no se puede fijar el extremo)" "debe ser <rev> o <a>\.\.<b>" -- replay "$D" "HEAD~1...HEAD"
copia instalado r3; HUERFANO=$(en "$D" git commit-tree "$(en "$D" git hash-object -t tree /dev/null)" -m huerfano)
base_decl "$D" "- **Base del método:** $HUERFANO"
espera falla "base ajena a la historia del extremo final" "no es ancestro" -- replay "$D" HEAD
copia instalado r4; base_decl "$D" "- **Base del método:** zzz-no-es-sha"
espera falla "declaración malformada falla (no equivale a sin base)" "malformada" -- replay "$D" HEAD
copia instalado r5; printf -- '- **Base del método:** %s\n' "$PREVIO" >> "$D/docs/convenciones.md"
espera falla "declaración duplicada falla" "más de una" -- replay "$D" HEAD
copia instalado r6; base_decl "$D" "- **Base del método:** $INST"
espera falla "base movida al commit de instalación (ya tiene fase) falla" "commit con fase" -- replay "$D" HEAD
copia instalado r7; printf '\nnota\n' >> "$D/docs/MEMORIA.md"; commitea "$D" "nota

Ref: F1"
espera pasa "rango con inicio posterior a la base: se conserva el inicio" "1/1 commits cumplen" -- replay "$D" "$INST..HEAD"
espera pasa "rango sin inicio explícito: excluye lo previo a la base" "2/2 commits cumplen" -- replay "$D" HEAD

echo "== base del método: lo posterior a la base sigue sujeto al contrato"
copia instalado r8; printf '\nx\n' >> "$D/docs/MEMORIA.md"; sin_hooks "$D" "sin trailer"
espera falla "commit posterior sin trailer: rechazado por el replay" "falta el trailer" -- replay "$D" HEAD
copia instalado r9; printf 'assert 2 + 2 == 4\n' >> "$D/app.py"; sin_hooks "$D" "cambio de código

Ref: F1"
espera falla "commit posterior que toca código sin Ref: I<n>: rechazado por el replay" "código fuera del rastro" -- replay "$D" HEAD

echo "== etapa: adoptado en F3 (encuadre revisado, plan aprobado, I1 cerrado)"
# Los controles comunes se prueban también DESPUÉS de la instalación: mismas utilidades que regresion.sh.
huella_idx() { en "$1" git add -A >/dev/null 2>&1; en "$1" sh scripts/huella.sh indice; }
cierra_inc() {  # casilla [x] y una línea en estado.md; idempotente
  grep -q "^- \[ \] $2 " "$1/docs/plan.md" 2>/dev/null || return 0
  sed -i.bak "s/^- \[ \] $2 /- [x] $2 /" "$1/docs/plan.md" && rm -f "$1/docs/plan.md.bak"
  printf -- '- Cerrado %s.\n' "$2" >> "$1/docs/estado.md"
}
recibo() {  # recibo <dir> rol tipo alcance veredicto bloqueantes [extra...] → al log con la huella del índice
  d=$1; rol=$2; tipo=$3; alc=$4; ver=$5; blo=$6; shift 6
  [ "$rol $tipo" = "juez-codigo incremento" ] && cierra_inc "$d" "$alc"
  h=$(huella_idx "$d")
  printf 'fecha=2026-10-22T10:00Z rol=%s tipo=%s alcance=%s veredicto=%s bloqueantes=%s huella=%s ejecutor=regresion %s\n' \
    "$rol" "$tipo" "$alc" "$ver" "$blo" "$h" "$*" >> "$d/docs/revisiones.log"
}
trazabilidad() {  # trazabilidad <dir> "<filas C>" "<filas E>" "<filas R>" ["<histórico>"]
  {
    printf '# Trazabilidad\n\n## Cobertura de criterios\n\n| Criterio | Alias | Incremento(s) | Estado | Nota |\n|----------|-------|---------------|--------|------|\n'
    [ -n "$2" ] && printf '%s\n' "$2"
    printf '\n## Registro de vacíos del revisor funcional (arranque)\n\n| Vacío | Alias | Punto incumplido | Estado | Resuelto (cómo · AAAA-MM-DD HH:MM UTC) |\n|-------|-------|------------------|--------|----------------------------------------|\n'
    [ -n "$3" ] && printf '%s\n' "$3"
    printf '\n## Registro de revisiones del juez\n\n| Hallazgo | Alias | Incr. | Criterio | Descripción | Estado | Resuelto (AAAA-MM-DD HH:MM UTC · commit) |\n|----------|-------|-------|----------|-------------|--------|------------------------------------------|\n'
    [ -n "$4" ] && printf '%s\n' "$4"
    printf '\n## Histórico (compactado)\n\n'
    [ -n "${5:-}" ] && printf '%s\n' "$5"
  } > "$1/docs/trazabilidad.md"
}
C1A='| C1 | «arranca» | I1 | pendiente | |'
siembra_f2() {  # documentos mínimos de un plan aprobado sobre el proyecto adoptado
  printf '# AGENTS.md\n\nProyecto adoptado (regresión). Ver docs/.\n' > "$1/AGENTS.md"
  printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: app.py termina sin error (comportamiento que se conserva).\n\n## Set de oro\n\n- ejecutar app.py: sin salida, código 0\n' > "$1/docs/encuadre.md"
  printf '# Plan\n\n## Incrementos\n\n- [ ] I1 «caracteriza» — prueba de caracterización (satisface: C1)\n- [ ] I2 «protege» — (satisface: C1)\n' > "$1/docs/plan.md"
  printf '# Decisiones\n\n(ninguna todavía)\n' > "$1/docs/decisiones.md"
  trazabilidad "$1" "$C1A" "" ""
  printf '#!/bin/sh\npython3 -I app.py || exit 1\nexit 0\n' > "$1/scripts/check.sh"
}
copia instalado af; A="$D"; siembra_f2 "$A"; fase "$A" F2; recibo "$A" revisor-funcional encuadre F2 PASA 0
commitea "$A" "Plan de adopción

Ref: F2" || die "no pude preparar el plan del proyecto adoptado"
fase "$A" F3; printf 'assert 2 + 2 == 4\n' >> "$A/app.py"; recibo "$A" juez-codigo incremento I1 PASA 0 seguridad=no-aplica
commitea "$A" "I1

Ref: I1" || die "no pude cerrar I1 en el proyecto adoptado"
rm -rf "$W/etapas/adoptado-f3"; cp -R "$A" "$W/etapas/adoptado-f3"
espera pasa "adoptado en F3: el replay desde la base valida instalación, plan e I1" "3/3 commits cumplen" -- replay "$A" HEAD

echo "== contrato revisado tras la adopción"
reescribe_c1() { sed -i.bak 's/^- C1: .*/- C1: app.py hace lo que sea./' "$1/docs/encuadre.md" && rm -f "$1/docs/encuadre.md.bak"; }
copia adoptado-f3 ac1; reescribe_c1 "$D"; printf 'assert 3 + 3 == 6\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "adoptado: reescribir C1 dentro de Ref: I2 se rechaza" "contrato revisado" -- commitea "$D" "I2

Ref: I2"
copia adoptado-f3 ac2; fase "$D" F1; reescribe_c1 "$D"
commitea "$D" "reencuadre

Ref: F1" || die "no pude preparar el reencuadre adoptado"
printf 'assert 3 + 3 == 6\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "adoptado: F3→F1, reescribir C1 y cerrar Ref: I2 quedándose en F1 se rechaza" "contrato revisado" -- commitea "$D" "I2

Ref: I2"
copia adoptado-f3 ac3; fase "$D" F1; reescribe_c1 "$D"
commitea "$D" "reencuadre

Ref: F1" || die "no pude preparar el reencuadre completo adoptado"
fase "$D" F2; recibo "$D" revisor-funcional encuadre reentrada:C1 PASA 0
espera pasa "adoptado: reencuadre completo con Ref: F2 y recibo reentrada:C1 se acepta" "" -- commitea "$D" "reentrada

Ref: F2"
fase "$D" F3; printf 'assert 3 + 3 == 6\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "adoptado: Ref: I2 tras el contrato nuevo se acepta" "" -- commitea "$D" "I2

Ref: I2"
copia adoptado-f3 ac4; trazabilidad "$D" "$C1A" "" '| R-I2.1 | «bug» | I2 | C1 | falta prueba | abierto | — |'; sin_hooks "$D" "hallazgo abierto"
trazabilidad "$D" "$C1A" "" ""; printf 'assert 3 + 3 == 6\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "adoptado: un hallazgo abierto que desaparece se rechaza" "desaparece" -- commitea "$D" "I2

Ref: I2"
sin_hooks "$D" "I2 colado

Ref: I2"
espera falla "adoptado: el replay detecta la desaparición colada" "desaparece" -- replay "$D" HEAD~1..HEAD
copia adoptado-f3 ac5; trazabilidad "$D" "$C1A" "" '| R-I2.1 | «bug» | I2 | C1 | falta prueba | resuelto | 2026-10-22 10:00 |'; printf 'assert 3 + 3 == 6\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "adoptado: resuelto con solo una fecha se rechaza" "referencia que resuelva" -- commitea "$D" "I2

Ref: I2"
copia adoptado-f3 ac6; trazabilidad "$D" "$C1A" "" '| R-I2.1 | «bug» | I2 | C1 | falta prueba | resuelto | 2026-10-22 10:00 · app.py:2 |'; printf 'assert 3 + 3 == 6\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "adoptado: resuelto con una ruta del índice se acepta" "" -- commitea "$D" "I2

Ref: I2"
copia adoptado-f3 ac7; fase "$D" F5
espera falla "adoptado: estado.md pasa a F5 con Ref: F1 se rechaza" "entrar a la Fase 5" -- commitea "$D" "cierre fingido

Ref: F1"
# Un `Ref: F2` del historial PREVIO a la adopción no acredita contrato: se busca tras la base del método.
copia existente ab; printf '\nnota antigua\n' >> "$D/README.md"; sin_hooks "$D" "commit antiguo con trailer

Ref: F2"
PREVIO_AB=$(en "$D" git rev-parse HEAD)
adoptar "$P" copiar "$D" >/dev/null; en "$D" git rm -q --cached config/.env.prod; adoptar "$P" gitignore "$D" --aplicar >/dev/null
base_decl "$D" "- **Base del método:** $PREVIO_AB"; fase "$D" F1; en "$D" git config core.hooksPath .githooks
commitea "$D" "Instalación del método (adopción)

Ref: F1" || die "no pude instalar sobre el historial con trailer antiguo"
siembra_f2 "$D"; fase "$D" F3; printf 'assert 2 + 2 == 4\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I1 PASA 0 seguridad=no-aplica
espera falla "adoptado: un Ref: F2 anterior a la Base del método no acredita contrato revisado" "posterior a la Base del método" -- commitea "$D" "I1

Ref: I1"

echo "== adoptado: criterio en una línea y merge limpio que integra un cierre"
copia adoptado-f3 ad1; printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: app.py termina sin error (comportamiento que se conserva).\n  Y además lo que sea.\n\n## Set de oro\n\n- ejecutar app.py: sin salida, código 0\n' > "$D/docs/encuadre.md"
espera falla "adoptado: el doctor rechaza un criterio con continuación" "continuación" -- en "$D" sh scripts/check_docs.sh
copia adoptado-f3 ad1b; printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: app.py termina sin error (comportamiento que se conserva).\n\n  Y además lo que sea.\n\n## Set de oro\n\n- ejecutar app.py: sin salida, código 0\n' > "$D/docs/encuadre.md"
espera falla "adoptado: el pre-commit rechaza un párrafo sangrado tras blanco en un criterio" "continuación" -- commitea "$D" "criterio con párrafo

Ref: F1"
sin_hooks "$D" "criterio con párrafo colado

Ref: F1"
espera falla "adoptado: el replay rechaza ese criterio colado" "continuación" -- replay "$D" HEAD~1..HEAD
# Cierre legítimo del ciclo de adopción en una rama; la principal cambia el README; el merge entra a F5.
copia adoptado-f3 ad2; RAMA0=$(en "$D" git rev-parse --abbrev-ref HEAD); en "$D" git checkout -q -b cierre-rama
printf '# Plan\n\n## Incrementos\n\n- [x] I1 «caracteriza» — prueba de caracterización (satisface: C1)\n\n## Fuera de alcance / backlog\n\n- I2 «protege» — siguiente ciclo\n' > "$D/docs/plan.md"
trazabilidad "$D" '| C1 | «arranca» | I1 | verificado | |' "" ""
fase "$D" F4; recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
commitea "$D" "validación

Ref: F4" || die "no pude validar el ciclo adoptado"
fase "$D" F5
commitea "$D" "cierre

Ref: F5" || die "no pude cerrar el ciclo adoptado"
en "$D" git checkout -q "$RAMA0"; printf '\nnota\n' >> "$D/README.md"; commitea "$D" "readme

Ref: F1" || die "no pude cambiar la principal adoptada"
espera falla "adoptado: merge limpio que lleva estado.md a F5 sin Ref: F5 se rechaza" "entrar a la Fase 5" -- en "$D" git -c core.hooksPath=.githooks merge -q --no-ff --no-edit cierre-rama
en "$D" git merge --abort >/dev/null 2>&1 || true
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-commit cierre-rama >/dev/null 2>&1 || die "no pude preparar el merge adoptado con recibo"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica; en "$D" git add -A
espera pasa "adoptado: merge que integra el cierre con Ref: F5 y recibo sobre el árbol integrado se acepta" "" -- en "$D" git -c core.hooksPath=.githooks commit -q -m "integra el cierre

Ref: F5"

echo
echo "regresion-adopcion: $((TOTAL-MAL))/$TOTAL casos en verde"
if [ "$MAL" -gt 0 ]; then echo "FALLARON:$FALLIDOS"; exit 1; fi
exit 0
