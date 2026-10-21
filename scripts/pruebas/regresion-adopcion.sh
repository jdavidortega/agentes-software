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
espera pasa "vista previa no escribe nada" "" -- sh -c "[ -z \"\$(git -C '$E' status --porcelain)\" ]"

echo "== adoptar.sh: copia"
copia existente c1
espera pasa "copiar: crea el manifiesto" "Manifiesto creado" -- adoptar "$P" copiar "$D"
espera pasa "copiar: README del proyecto idéntico byte a byte" "" -- cmp "$W/readme.orig" "$D/README.md"
espera pasa "copiar: runbook propio idéntico byte a byte" "" -- cmp "$W/runbook.orig" "$D/docs/despliegue.md"
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
espera pasa "añadido posterior: se reconoce como idéntico sin registro, no como colisión" "sin instalación registrada: 1" -- adoptar "$P2" vista-previa "$D"
espera pasa "añadido posterior: el manifiesto original no lo registra (inmutable)" "" -- sh -c "! grep -q 'nuevo-del-metodo' '$D/contexto/adopcion.md'"
copia existente c3; adoptar "$P" copiar "$D" >/dev/null
printf '\nnota del proyecto\n' >> "$D/docs/MEMORIA.md"; cp "$D/docs/MEMORIA.md" "$W/memoria.mod"
printf '\n(nota a mano)\n' >> "$D/contexto/adopcion.md"; cp "$D/contexto/adopcion.md" "$W/manif.mod"
espera pasa "destino modificado: se reporta y no se sobreescribe" "desde la instalación \(no se toca\): 1" -- adoptar "$P" copiar "$D"
espera pasa "destino modificado: contenido y manifiesto editado se conservan" "" -- sh -c "cmp -s '$W/memoria.mod' '$D/docs/MEMORIA.md' && cmp -s '$W/manif.mod' '$D/contexto/adopcion.md'"

echo "== adoptar.sh: bloqueos (enlaces simbólicos y rutas ignoradas)"
copia existente c4; mkdir -p "$W/fuera"; mv "$D/docs" "$W/fuera/docs"; ln -s "$W/fuera/docs" "$D/docs"; sin_hooks "$D" "docs enlazado"
espera falla "enlace simbólico en docs/: la inspección bloquea" "enlace simbólico" -- adoptar "$P" inspeccionar "$D"
espera falla "enlace simbólico en docs/: copiar rehúsa" "bloqueo" -- adoptar "$P" copiar "$D"
espera pasa "enlace simbólico en docs/: nada se escribió fuera del repositorio" "" -- sh -c "[ \"\$(ls '$W/fuera/docs')\" = despliegue.md ] && [ ! -e '$D/AGENTS.md' ]"
copia existente c5; mkdir -p "$W/fuera2"; ln -s "$W/fuera2" "$D/contexto"; sin_hooks "$D" "contexto enlazado"
espera falla "enlace simbólico en contexto/: bloquea también el manifiesto" "contexto/adopcion\.md" -- adoptar "$P" inspeccionar "$D"
copia existente c6; printf 'scripts/\n' >> "$D/.gitignore"; sin_hooks "$D" "ignora scripts"
espera falla "ruta ignorada por el destino: bloquea" "ignorado por el destino" -- adoptar "$P" inspeccionar "$D"

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

echo
echo "regresion-adopcion: $((TOTAL-MAL))/$TOTAL casos en verde"
if [ "$MAL" -gt 0 ]; then echo "FALLARON:$FALLIDOS"; exit 1; fi
exit 0
