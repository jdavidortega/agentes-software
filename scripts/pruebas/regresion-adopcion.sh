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
unset FASE_PREVIA FASE_HISTORICA REV SUITE_ID SUITE_REGISTRO SUITE_PLAZO SUITE_ENVUELTO SUITE_INFORME SUITE_PROPIA
# Todo check.sh, en cualquier fase, empieza por el bloque de la suite vigilada (check_docs lo exige y lo prueba).
BLOQUE=$(awk '/^# --- suite vigilada/{f=1} f{print} /^# --- fin suite vigilada/{exit}' "$RAIZ/docs/convenciones.md")
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
  printf '# Encuadre\n\n## Criterios de éxito\n\n- C1:\n\n## Set de oro (ejemplos de salida esperada)\n\n- Entrada: _…_ → Salida esperada: _…_\n' > "$P/docs/encuadre.md"
  printf '# Plan\n\n- [ ] I1 «…» — _…_ (satisface: C_)\n' > "$P/docs/plan.md"
  printf '# Trazabilidad\n\n## Cobertura de criterios\n\n| Criterio | Alias | Incremento(s) | Estado | Nota |\n|----------|-------|---------------|--------|------|\n| C1 | «…» | I_ | pendiente / cubierto / verificado | |\n\n## Registro de vacíos del revisor funcional (arranque)\n\n| Vacío | Alias | Punto incumplido | Estado | Resuelto (cómo · AAAA-MM-DD HH:MM UTC) |\n|-------|-------|------------------|--------|----------------------------------------|\n\n## Registro de revisiones del juez\n\n| Hallazgo | Alias | Incr. | Criterio | Descripción | Estado | Resuelto (AAAA-MM-DD HH:MM UTC · commit) |\n|----------|-------|-------|----------|-------------|--------|------------------------------------------|\n\n## Histórico (compactado)\n\n' > "$P/docs/trazabilidad.md"
  for f in decisiones convenciones definicion-de-hecho despliegue MEMORIA; do printf '# %s\n\n(sintético)\n' "$f" > "$P/docs/$f.md"; done
  printf '# Registro de recibos (sintético). Las líneas que empiezan por # se ignoran.\n# contrato-recibos: 2\n' > "$P/docs/revisiones.log"
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

echo "== adoptar.sh: git por separado y lo previo antes de la primera copia"
mkdir -p "$W/sin-commits"; en "$W/sin-commits" git init -q; printf 'print(1)\n' > "$W/sin-commits/app.py"
espera pasa "sin commits: inspeccionar sigue disponible y lo informa" "commit actual: +sin commits" -- adoptar "$P" inspeccionar "$W/sin-commits"
espera pasa "sin commits: la vista previa sigue disponible y dice qué falta antes de copiar" "Antes de la primera copia.*: 2" -- adoptar "$P" vista-previa "$W/sin-commits"
espera falla "sin commits: copiar se rechaza" "no se puede separar de la instalación" -- adoptar "$P" copiar "$W/sin-commits"
espera pasa "sin commits: el rechazo no escribe nada" "" -- sh -c "[ \"\$(ls -A '$W/sin-commits' | tr '\n' ' ')\" = '.git app.py ' ]"
espera pasa "sin remoto: el trabajo local sigue" "remoto: +ninguno \(el trabajo local sigue" -- adoptar "$P" inspeccionar "$W/sin-commits"
espera pasa "publicar se informa como decisión, no como dato" "publicar: +decisión de la persona" -- adoptar "$P" inspeccionar "$W/sin-commits"
copia existente g1; printf 'cambio local\n' >> "$D/app.py"
espera falla "cambios sin commitear: copiar se rechaza" "cambio\(s\) sin commitear" -- adoptar "$P" copiar "$D"
espera pasa "cambios sin commitear: la inspección no cuenta un bloqueo" "Bloqueos: 0" -- adoptar "$P" inspeccionar "$D"
copia existente g2; en "$D" git remote add origin "https://usuario:secreto@ejemplo.invalid/r.git"
espera pasa "remoto: se informa solo el nombre" "remoto: +origin$" -- adoptar "$P" inspeccionar "$D"
espera pasa "remoto: la URL con credenciales no se imprime" "" -- sh -c "! sh '$P/scripts/adoptar.sh' inspeccionar '$D' | grep -q secreto"

echo "== adoptar.sh: inventario de ramas (solo lectura)"
# Ronda 12 (T6): hechos de git contra el destino de integración que declara la persona; sin fetch,
# sin escribir; squash no se detecta y lo dice; la antigüedad no decide.
RM="$W/ramas"; mkdir -p "$RM"; git init -q -b main "$RM/d"; git init -q --bare "$RM/remoto.git"
( cd "$RM/d" && g() { git -c user.name=a -c user.email=a@b -c core.hooksPath=/dev/null "$@"; }
  echo a > a; git add a; g commit -qm base
  git checkout -qb fusionada; echo f > f; git add f; g commit -qm f; git checkout -q main; g merge -q --no-ff -m m fusionada
  git checkout -qb propia; echo p > p; git add p; g commit -qm p; git checkout -q main
  git checkout -qb aplastada; echo s1 > s; git add s; g commit -qm s1; echo s2 >> s; g commit -qam s2
  git checkout -q main; g merge -q --squash aplastada >/dev/null; g commit -qm squash
  git checkout -qb rebasada; echo r > r; git add r; g commit -qm r; git checkout -q main; echo m2 > m2; git add m2; g commit -qm m2; g cherry-pick rebasada >/dev/null
  git checkout -qb remota-sola; echo x > x; git add x; g commit -qm x
  git checkout -q main; git checkout -qb lado; echo l > l; git add l; g commit -qm l; git checkout -q main
  git checkout -qb con-merge; echo k > k; git add k; g commit -qm k; g merge -q --no-ff --no-commit lado; echo propio > propio; git add propio; g commit -qm "merge con contenido propio"
  git checkout -q main; echo m3 > m3; git add m3; g commit -qm m3; g cherry-pick con-merge~1 >/dev/null; g cherry-pick lado >/dev/null
  git checkout -qb rota; echo contenido-perdido > z; git add z; g commit -qm z; git checkout -q main; echo otro > z; git add z; g commit -qm z-main  # misma ruta: cherry debe leer el contenido
  git remote add origin ../remoto.git; git push -q origin remota-sola main 2>/dev/null; git checkout -q main; git branch -qD remota-sola; git fetch -q origin
  b=$(git rev-parse rota:z); rm -f ".git/objects/$(echo "$b" | cut -c1-2)/$(echo "$b" | cut -c3-)" ) || die "no pude preparar las ramas"
espera pasa "ramas: destino no declarado se dice y no se deduce de main" "integración: +NO DECLARADO.*no se deduce de main" -- adoptar "$P" inspeccionar "$RM/d"
espera pasa "ramas: sin destino no se calcula incorporación (ninguna fila la afirma)" "" -- sh -c "sh '$P/scripts/adoptar.sh' inspeccionar '$RM/d' | grep ' · ' | grep -v 'incorporación no calculada' | { ! grep -q .; }"
espera pasa "ramas: destino inexistente se dice y no se calcula incorporación" "«develop» NO EXISTE" -- adoptar "$P" inspeccionar "$RM/d" develop
espera pasa "ramas: con destino inexistente ninguna fila se da por incorporada" "" -- sh -c "! sh '$P/scripts/adoptar.sh' inspeccionar '$RM/d' develop | grep -q 'incorporada ('"
espera pasa "ramas: fusionada con merge sale incorporada" "local +fusionada · último commit .* · incorporada \\(sin commits fuera de main\\)" -- adoptar "$P" inspeccionar "$RM/d" main
espera pasa "ramas: con commits propios dice cuántos" "local +propia · último commit .* · 1 commit\\(s\\) fuera de main \\(si se integró por squash" -- adoptar "$P" inspeccionar "$RM/d" main
espera pasa "ramas: integrada por squash no sale incorporada y pide contrastar PR/MR" "local +aplastada · último commit .* · 2 commit\\(s\\) fuera de main \\(si se integró por squash, git no lo ve: contrastar PR/MR\\)" -- adoptar "$P" inspeccionar "$RM/d" main
espera pasa "ramas: integrada por cherry-pick o rebase sale equivalente por parche" "local +rebasada · último commit .* · 1 commit\\(s\\) fuera de main, equivalentes por parche" -- adoptar "$P" inspeccionar "$RM/d" main
espera pasa "ramas: un merge con contenido propio fuera del destino no se da por equivalente (git cherry no evalúa merges)" "local +con-merge · último commit .* · 3 commit\\(s\\) fuera de main, 1 de ellos merge .*comparación incompleta; investigar" -- adoptar "$P" inspeccionar "$RM/d" main
espera pasa "ramas: si la comparación por parche falla, no se da por equivalente" "local +rota · último commit .* · 1 commit\\(s\\) fuera de main; comparación incompleta; investigar \\(falló" -- adoptar "$P" inspeccionar "$RM/d" main
espera pasa "ramas: una rama solo remota se inventaría" "remota origin/remota-sola · último commit .* · 1 commit\\(s\\) fuera de main" -- adoptar "$P" inspeccionar "$RM/d" main
espera pasa "ramas: el destino puede ser una referencia remota" "integración: +origin/main$" -- adoptar "$P" inspeccionar "$RM/d" origin/main
espera pasa "ramas: avisa que las remotas dependen del último fetch, que PR/MR no se comprobó y que la antigüedad no decide" "según el último fetch.*desactualizadas.*no comprobado.*antigüedad sola no justifica eliminar" -- sh -c "sh '$P/scripts/adoptar.sh' inspeccionar '$RM/d' main | tr '\\n' ' '"
python3 -c 'import time; time.sleep(1.05)'; touch "$W/ramas-marca"; python3 -c 'import time; time.sleep(1.05)'
G0=$(cd "$RM/d" && find .git -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done | cksum)
for d in "" main develop origin/main; do adoptar "$P" inspeccionar "$RM/d" $d >/dev/null 2>&1 || true; done
espera pasa "ramas: el inventario no escribe en .git (sin fetch, sin configuración, sin ramas)" "" -- sh -c "[ '$G0' = \"\$(cd '$RM/d' && find .git -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\\n' \"\$f\" \"\$(cksum < \"\$f\")\"; done | cksum)\" ] && [ -z \"\$(find '$RM/d/.git' -newer '$W/ramas-marca' | head -1)\" ]"

echo "== adoptar.sh: copia"
copia existente c1
espera pasa "copiar: crea el manifiesto" "Manifiesto creado" -- adoptar "$P" copiar "$D"
espera pasa "copiar: README del proyecto idéntico byte a byte" "" -- cmp "$W/readme.orig" "$D/README.md"
espera pasa "copiar: runbook propio idéntico byte a byte" "" -- cmp "$W/runbook.orig" "$D/docs/despliegue.md"
espera pasa "copiar: adoptar.sh y su regresión no se distribuyen" "" -- sh -c "[ ! -e '$D/scripts/adoptar.sh' ] && [ ! -e '$D/scripts/pruebas/regresion-adopcion.sh' ]"
espera pasa "copiar: los hooks quedan ejecutables" "" -- sh -c "[ -x '$D/.githooks/pre-commit' ] && [ -x '$D/.githooks/pre-merge-commit' ] && [ -x '$D/.githooks/commit-msg' ]"
espera pasa "copiar: el lector del contrato (scripts/contrato.py) se distribuye idéntico" "" -- cmp "$P/scripts/contrato.py" "$D/scripts/contrato.py"
espera pasa "copiar: manifiesto registra hash por archivo y la colisión" "" -- sh -c "grep -qE '^- AGENTS\.md · [0-9a-f]{40}$' '$D/contexto/adopcion.md' && grep -qx -- '- docs/despliegue.md' '$D/contexto/adopcion.md'"
huella_arbol "$D" > "$W/h1"; cp "$D/contexto/adopcion.md" "$W/m1"
espera pasa "repetir: todo instalado sin cambios" "Instalado sin cambios: [1-9]" -- adoptar "$P" copiar "$D"
espera pasa "repetir: la colisión ya registrada no cuenta como diferencia" "Sin diferencias respecto de la instalación registrada" -- adoptar "$P" copiar "$D"
huella_arbol "$D" > "$W/h2"
espera pasa "repetir: cero escrituras (árbol idéntico) y manifiesto idéntico" "" -- sh -c "cmp -s '$W/h1' '$W/h2' && cmp -s '$W/m1' '$D/contexto/adopcion.md'"
espera pasa "repetir: nada se clasifica como idéntico sin registro" "sin instalación registrada: 0" -- adoptar "$P" vista-previa "$D"

espera pasa "copiar: el aviso de inicio se distribuye con su configuración (SessionStart), idénticos" "" -- sh -c "cmp '$P/.claude/hooks/inicio-sesion.py' '$D/.claude/hooks/inicio-sesion.py' && cmp '$P/.claude/settings.json' '$D/.claude/settings.json' && [ -x '$D/.claude/hooks/inicio-sesion.py' ]"
copia existente c1s; mkdir -p "$D/.claude"; printf '{\n  "permissions": {"allow": ["Bash(make:*)"]}\n}\n' > "$D/.claude/settings.json"; cp "$D/.claude/settings.json" "$W/settings-adaptado.json"
sin_hooks "$D" "configuración propia de Claude Code" || die "no pude preparar c1s"
espera pasa "copiar: una .claude/settings.json propia se conserva como colisión, no se sobrescribe" "" -- sh -c "sh '$P/scripts/adoptar.sh' copiar '$D' >/dev/null && cmp '$W/settings-adaptado.json' '$D/.claude/settings.json' && grep -qx -- '- .claude/settings.json' '$D/contexto/adopcion.md'"
espera pasa "copiar: ... y el script del aviso se instala igual (su entrada en esa configuración la integra la persona)" "" -- test -x "$D/.claude/hooks/inicio-sesion.py"

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
echo "== adoptar.sh: un hook nuevo del método llega a un proyecto ya adoptado (pre-merge-commit)"
# La entrega anterior: sin el hook y con el doctor que no lo exigía. actualizar trae el doctor nuevo, que señala la
# instalación parcial; copiar añade el hook (ejecutable, registrado en el log) y el doctor deja de señalarlo.
cp -R "$P" "$W/plantilla5"; P5="$W/plantilla5"; en "$P5" git rm -q .githooks/pre-merge-commit
sed -e '/^# contrato-merges: 1$/d' -e '/^# contrato-check: 1$/d' "$P5/scripts/check_docs.sh" > "$W/cd5" && cat "$W/cd5" > "$P5/scripts/check_docs.sh"
grep -qx '# contrato-merges: 1' "$P5/scripts/check_docs.sh" && die "no pude preparar la entrega anterior"
sin_hooks "$P5" "entrega anterior: sin pre-merge-commit" || die "no pude versionar la entrega anterior"
copia existente c15; adoptar "$P5" copiar "$D" >/dev/null; sin_hooks "$D" "instala el método (entrega anterior)" || die "c15"
adoptar "$P" actualizar "$D" "trae el doctor nuevo" >/dev/null; sin_hooks "$D" "actualiza" || die "c15 actualizar"
espera falla "hook nuevo: con el doctor nuevo y sin el hook, el doctor señala la instalación parcial" "falta \.githooks/pre-merge-commit" -- en "$D" sh scripts/check_docs.sh
espera pasa "hook nuevo: copiar lo añade ejecutable y lo registra en el log" "" -- sh -c "sh '$P/scripts/adoptar.sh' copiar '$D' >/dev/null && [ -x '$D/.githooks/pre-merge-commit' ] && grep -qE '^- \.githooks/pre-merge-commit · \(ausente\) → [0-9a-f]{40} · plantilla ' '$D/contexto/adopcion-actualizaciones.md'"
sin_hooks "$D" "añade el hook" || die "c15 copiar"
espera pasa "hook nuevo: versionado con bit ejecutable y el doctor ya no lo señala" "" -- sh -c "cd '$D' && git ls-files -s .githooks/pre-merge-commit | grep -q '^100755' && ! sh scripts/check_docs.sh 2>&1 | grep -q 'pre-merge-commit'"
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

echo "== suite vigilada desde el Paso 0 (el check.sh nace en el paso G con el bloque)"
copia existente vg0; adoptar "$P" copiar "$D" >/dev/null; en "$D" git rm -q --cached config/.env.prod
adoptar "$P" gitignore "$D" --aplicar >/dev/null; en "$D" git config core.hooksPath .githooks; VG0=$(en "$D" git rev-parse HEAD)
printf '#!/bin/sh\necho "id=${SUITE_ID:-}" > "%s"\n' "$W/cuerpo-vg0" > "$D/scripts/check.sh"
espera falla "Paso 0 (paso G): check.sh sin el bloque, check_docs falla" "no EMPIEZA por el bloque" -- sh -c 'cd "$1" && git add -A && sh scripts/check_docs.sh' _ "$D"
base_decl "$D" "- **Base del método:** $VG0"; fase "$D" F1
espera falla "commit de instalación con check.sh sin el bloque: se rechaza" "no EMPIEZA por el bloque" -- commitea "$D" "Instalación del método (adopción)

Ref: F1"
espera falla "... y su cuerpo no llegó a correr" "" -- test -e "$W/cuerpo-vg0"
{ printf '#!/bin/sh\n%s\n' "$BLOQUE"; tail -n +2 "$D/scripts/check.sh"; } > "$D/c.tmp" && mv "$D/c.tmp" "$D/scripts/check.sh"
espera pasa "control: con el bloque antepuesto, el commit de instalación se acepta" "" -- commitea "$D" "Instalación del método (adopción)

Ref: F1"
espera pasa "... y el cuerpo corrió vigilado (con identificador de la suite)" "" -- grep -qE '^id=[0-9]{8}T' "$W/cuerpo-vg0"
espera pasa "... primera adopción: el cuerpo de check.sh entró sin Ref: I<n> con el contrato de check.sh instalado y antes de cualquier Ref: F2" "" -- sh -c 'cd "$1" && grep -qx "# contrato-check: 1" scripts/check_docs.sh && git diff --name-only HEAD~1 HEAD | grep -qx scripts/check.sh && ! git log --format=%B | grep -qx "Ref: F2"' _ "$D"

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

echo "== base del método: proyecto con workflows y pruebas propias"
# Lo previo a la adopción no se juzga ni se reescribe; la instalación de la instrumentación pasa
# con Ref: F1; después, sus workflows y pruebas propias son producto y sus documentos, rastro.
copia existente pp; PP="$D"
mkdir -p "$PP/.github/workflows" "$PP/scripts/pruebas"
printf 'name: ci\non: push\n' > "$PP/.github/workflows/ci.yml"
printf '# Cómo contribuir\n' > "$PP/.github/README.md"
printf '#!/bin/sh\npython3 app.py\n' > "$PP/scripts/pruebas/prueba_propia.sh"
# Un archivo propio con el nombre de uno del método: la instalación lo conserva (colisión). Que después
# sea producto (P(B)) lo prueba la sección «procedencia en un adoptado (PR-3)».
printf '#!/bin/sh\necho suite propia\n' > "$PP/scripts/pruebas/regresion-suite.sh"; cp "$PP/scripts/pruebas/regresion-suite.sh" "$W/suite-propia.orig"
# Un hook previo local (.git/hooks) dejaría de correr con core.hooksPath=.githooks: se integra en un
# commit del proyecto previo a la base, que no se juzga.
printf '#!/bin/sh\necho x >> "$(git rev-parse --git-dir)/pre-push.marca"\n' > "$PP/.git/hooks/pre-push"; chmod +x "$PP/.git/hooks/pre-push"
mkdir -p "$PP/.githooks"; cp "$PP/.git/hooks/pre-push" "$PP/.githooks/pre-push"
sin_hooks "$PP" "ci, guía, pruebas y hook propios"
PREVIO_PP=$(en "$PP" git rev-parse HEAD)
adoptar "$P" copiar "$PP" >/dev/null
en "$PP" git rm -q --cached config/.env.prod
adoptar "$P" gitignore "$PP" --aplicar >/dev/null
base_decl "$PP" "- **Base del método:** $PREVIO_PP"
fase "$PP" F1
en "$PP" git config core.hooksPath .githooks
espera pasa "propios previos: commit de instalación aceptado (Ref: F1)" "" -- commitea "$PP" "Instalación del método (adopción)

Ref: F1"
espera pasa "propios previos: la instalación conserva intactos el workflow, la guía y la prueba propios" "" -- en "$PP" git diff --quiet "$PREVIO_PP" HEAD -- .github/workflows/ci.yml .github/README.md scripts/pruebas/prueba_propia.sh
espera pasa "propios previos: ... e instala a su lado el workflow y la regresión del método" "" -- sh -c 'cd "$1" && git cat-file -e HEAD:.github/workflows/metodo.yml && git cat-file -e HEAD:scripts/pruebas/regresion.sh' sh "$PP"
espera pasa "propios previos: el replay no juzga lo previo a la base" "1/1 commits cumplen" -- replay "$PP" HEAD
rm -rf "$W/etapas/propios"; cp -R "$PP" "$W/etapas/propios"
copia propios pp1; printf '  # paso nuevo\n' >> "$D/.github/workflows/ci.yml"
espera falla "propios previos: cambiar su workflow con Ref: F1 se rechaza" "código fuera del rastro" -- commitea "$D" "ci

Ref: F1"
copia propios pp2; printf 'echo listo\n' >> "$D/scripts/pruebas/prueba_propia.sh"
espera falla "propios previos: cambiar su prueba propia con Ref: F1 se rechaza" "código fuera del rastro" -- commitea "$D" "prueba

Ref: F1"
copia propios pp3; printf '\nMás detalle.\n' >> "$D/.github/README.md"
espera pasa "propios previos: cambiar su guía de .github/ con Ref: F1 se acepta" "" -- commitea "$D" "guía

Ref: F1"
espera pasa "propios previos: la colisión de nombre queda registrada en el manifiesto" "" -- grep -qx -- '- scripts/pruebas/regresion-suite.sh' "$PP/contexto/adopcion.md"
espera pasa "propios previos: el archivo propio colisionado no se sobrescribe" "" -- cmp -s "$W/suite-propia.orig" "$PP/scripts/pruebas/regresion-suite.sh"
copia propios pp5; printf '\n# nota\n' >> "$D/scripts/pruebas/regresion.sh"
espera pasa "propios previos: cambiar un archivo del método instalado con Ref: F1 se acepta" "" -- commitea "$D" "actualiza el método

Ref: F1"
copia propios pp7; printf 'echo cambio\n' >> "$D/.githooks/pre-push"
espera falla "propios previos: cambiar el hook previo integrado con Ref: F1 se rechaza" "pre-push" -- commitea "$D" "hook

Ref: F1"
copia propios pp8; en "$D" git init -q --bare "$W/pp8-remoto.git"; rm -f "$D/.git/pre-push.marca"
en "$D" git push -q "$W/pp8-remoto.git" HEAD:refs/heads/main >/dev/null 2>&1 || die "no pude empujar al remoto local de prueba"
espera pasa "propios previos: el hook previo integrado sigue corriendo con los hooks del método activos" "" -- test -s "$D/.git/pre-push.marca"

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
    "$rol" "$tipo" "$alc" "$ver" "$blo" "$h" "${MODALIDAD-modalidad=lectura filtro=comprobado aislamiento=ninguno} $*" >> "$d/docs/revisiones.log"
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
  criterios_estado "$1" "$2"
}
# criterios_estado <dir> "<filas C>": regenera la tabla «## Criterios» de estado.md desde las filas de
# cobertura (como el agente al regenerar estado.md): mismo C#, alias y celda de estado. Así el proyecto del
# fixture es coherente desde F2 (check_docs §1b); los casos que prueban una contradicción la escriben aparte.
criterios_estado() {
  python3 -I - "$1/docs/estado.md" "$2" <<'PY'
import sys
p, filas = sys.argv[1], sys.argv[2]
try: s = open(p).read()
except OSError: sys.exit(0)
rows = []
for l in filas.split("\n"):
    c = [x.strip() for x in l.strip().strip("|").split("|")]
    if len(c) >= 4 and c[0]: rows.append("| %s | %s | %s |" % (c[0], c[1], c[3]))
sec = "## Criterios\n\n| C# | Alias | Estado |\n|----|-------|--------|\n" + "".join(r + "\n" for r in rows) + "\n"
i = s.find("\n## Criterios\n")
if i < 0: s = s.rstrip("\n") + "\n\n" + sec
else:
    j = s.find("\n## ", i + 1)
    s = s[:i + 1] + sec + (s[j + 1:] if j >= 0 else "")
open(p, "w").write(s)
PY
}
C1A='| C1 | «arranca» | I1 | pendiente | |'
siembra_f2() {  # documentos mínimos de un plan aprobado sobre el proyecto adoptado
  printf '# AGENTS.md\n\nProyecto adoptado (regresión). Ver docs/.\n' > "$1/AGENTS.md"
  printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: app.py termina sin error (comportamiento que se conserva).\n\n## Set de oro\n\n- ejecutar app.py: sin salida, código 0\n' > "$1/docs/encuadre.md"
  printf '# Plan\n\n## Incrementos\n\n- [ ] I1 «caracteriza» — prueba de caracterización (satisface: C1)\n- [ ] I2 «protege» — (satisface: C1)\n' > "$1/docs/plan.md"
  printf '# Decisiones\n\n(ninguna todavía)\n' > "$1/docs/decisiones.md"
  trazabilidad "$1" "$C1A" "" ""
  printf '#!/bin/sh\n%s\npython3 -I app.py || exit 1\nexit 0\n' "$BLOQUE" > "$1/scripts/check.sh"
  grep -q 'Plazo de la suite' "$1/docs/convenciones.md" 2>/dev/null || printf -- '- **Plazo de la suite:** 60 s\n' >> "$1/docs/convenciones.md"
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

echo "== adoptado: ruta de trabajo elegido (un criterio que se conserva, uno nuevo, el resto fuera)"
# El doctor exige al cierre solo los C# del encuadre: lo declarado fuera del alcance del ciclo no
# bloquea, y un C# del ciclo sin verificar sí. Sin hooks nuevos: es el contrato actual.
copia instalado tr; T="$D"; siembra_f2 "$T"
printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: [conserva] app.py termina sin error.\n- C2: [nuevo] nuevo.py imprime «hola».\n\n## Set de oro\n\n- ejecutar app.py: sin salida, código 0\n- ejecutar nuevo.py: imprime «hola» (salida esperada acordada)\n\n## Fuera del alcance de este ciclo\n\n- El runbook docs/despliegue.md: sin verificar (no lo toca el trabajo elegido).\n' > "$T/docs/encuadre.md"
printf '# Plan\n\n## Incrementos\n\n- [ ] I1 «protege-app» — protección (satisface: C1)\n- [ ] I2 «construye-hola» — construcción (satisface: C2)\n' > "$T/docs/plan.md"
trazabilidad "$T" '| C1 | «arranca» | I1 | pendiente | |
| C2 | «hola» | I2 | pendiente | |' "" ""
fase "$T" F2; recibo "$T" revisor-funcional encuadre F2 PASA 0
commitea "$T" "Plan: trabajo elegido

Ref: F2" || die "no pude preparar el plan de trabajo elegido"
fase "$T" F3; printf 'assert 2 + 2 == 4\n' >> "$T/app.py"; recibo "$T" juez-codigo incremento I1 PASA 0 seguridad=no-aplica
commitea "$T" "I1

Ref: I1" || die "no pude cerrar I1 de trabajo elegido"
printf 'print("hola")\n' > "$T/nuevo.py"; recibo "$T" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
commitea "$T" "I2

Ref: I2" || die "no pude cerrar I2 de trabajo elegido"
rm -rf "$W/etapas/elegido-f3"; cp -R "$T" "$W/etapas/elegido-f3"
trazabilidad "$T" '| C1 | «arranca» | I1 | verificado | |
| C2 | «hola» | I2 | verificado | |' "" ""
fase "$T" F4; recibo "$T" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera pasa "trabajo elegido: F4 cierra con sus dos C# verificados y lo demás declarado fuera" "" -- commitea "$T" "validación

Ref: F4"
fase "$T" F5
espera pasa "trabajo elegido: F5 cierra el ciclo" "" -- commitea "$T" "cierre

Ref: F5"
copia elegido-f3 tr2
trazabilidad "$D" '| C1 | «arranca» | I1 | verificado | |
| C2 | «hola» | I2 | cubierto | |' "" ""
fase "$D" F4; recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "trabajo elegido: el C# nuevo sin verificar bloquea F4" "C2 no está en Estado 'verificado'" -- commitea "$D" "validación

Ref: F4"

echo "== adoptado: contrato de recibos y evidencia tras la instalación"
espera pasa "la instalación trae el marcador una sola vez en docs/revisiones.log" "" -- sh -c "[ \"\$(grep -c '^# contrato-recibos: 2' '$W/etapas/instalado/docs/revisiones.log')\" -eq 1 ]"
incompleto() { MODALIDAD=""; recibo "$@"; unset MODALIDAD; }
copia adoptado-f3 ar1
grep -v '^# contrato-recibos: 2' "$D/docs/revisiones.log" | sed -E 's/ modalidad=[^ ]+ filtro=[^ ]+ aislamiento=[^ ]+//' > "$D/l"; mv "$D/l" "$D/docs/revisiones.log"
sin_hooks "$D" "registro con una versión anterior de la plantilla (preparación)" || die "no pude preparar el registro anterior adoptado"
printf -- '- nota\n' >> "$D/docs/MEMORIA.md"
espera falla "adoptado: al actualizar la plantilla, el registro anterior se bloquea con la instrucción de migrar" "añade al FINAL del registro" -- commitea "$D" "nota

Ref: F1"
printf '# contrato-recibos: 2\n' >> "$D/docs/revisiones.log"
espera pasa "adoptado: con el marcador al final se acepta" "" -- commitea "$D" "migra el registro

Ref: F1"
printf 'assert 3 + 3 == 6\n' >> "$D/app.py"; incompleto "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "adoptado: un recibo nuevo incompleto se rechaza" "sin modalidad=" -- commitea "$D" "I2

Ref: I2"
copia adoptado-f3 ar1b
grep -v '^# contrato-recibos: 2' "$D/docs/revisiones.log" | sed -E 's/ modalidad=[^ ]+ filtro=[^ ]+ aislamiento=[^ ]+//' > "$D/l"; mv "$D/l" "$D/docs/revisiones.log"
sin_hooks "$D" "registro anterior (preparación)" || die "no pude preparar el registro anterior adoptado (ar1b)"
printf 'assert 3 + 3 == 6\n' >> "$D/app.py"; incompleto "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica; printf '# contrato-recibos: 2\n' >> "$D/docs/revisiones.log"
espera falla "adoptado: al migrar, un recibo nuevo incompleto colocado ANTES del marcador se rechaza" "aunque quede antes del marcador" -- commitea "$D" "I2 y migración

Ref: I2"
espera falla "adoptado: con RECIBOS_CONTRATO_PREVIO=1 heredado, el recibo incompleto antes del marcador sigue rechazado" "aunque quede antes del marcador" -- sh -c 'export RECIBOS_CONTRATO_PREVIO=1; cd "$1" && git add -A && git -c core.hooksPath=.githooks commit -q -m "I2 y migración

Ref: I2"' sh "$D"
copia adoptado-f3 ar2; printf 'assert 3 + 3 == 6\n' >> "$D/app.py"
mkdir -p "$W/evsrc-ad"; printf 'salida\n' > "$W/evsrc-ad/salida.txt"; h=$(en "$D" sh scripts/huella.sh evidencia "$W/evsrc-ad")
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica evidencia=docs/revisiones/I2-ad@$h
mkdir -p "$D/docs/revisiones"; cp -R "$W/evsrc-ad" "$D/docs/revisiones/I2-ad"
espera pasa "adoptado: guardar evidencia tras el PASA permite cerrar Ref: I2" "" -- commitea "$D" "I2

Ref: I2"
printf 'retocada\n' >> "$D/docs/revisiones/I2-ad/salida.txt"; sin_hooks "$D" "retoca evidencia colada

Ref: F1"
espera falla "adoptado: el replay detecta la evidencia modificada" "cambió después de registrarse" -- replay "$D" HEAD~1..HEAD

echo "== adoptado: separadores, carpetas ocultas y migración con adoptar.sh actualizar"
copia adoptado-f3 at1; printf 'assert 3 + 3 == 6\n' >> "$D/app.py"; cierra_inc "$D" I2
printf '%s\n' "$(printf 'fecha=2026-10-22T10:00Z rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica huella=%s ejecutor=x modalidad=lectura filtro=comprobado aislamiento=ninguno\tevidencia=docs/revisiones/no-existe@0123456789ab' "$(huella_idx "$D")")" >> "$D/docs/revisiones.log"
espera falla "adoptado: un tabulador entre campos: el parser lo rechaza" "separador no admitido" -- en "$D" sh scripts/recibos.sh validar docs/revisiones.log
espera falla "adoptado: un tabulador entre campos se rechaza" "separador no admitido|no existe en lo que se guarda" -- commitea "$D" "I2

Ref: I2"
copia adoptado-f3 at2; mkdir -p "$D/docs/revisiones/.huerfana"; printf 'x\n' > "$D/docs/revisiones/.huerfana/salida.txt"
espera falla "adoptado: una carpeta oculta en docs/revisiones/ se rechaza" "entrada oculta" -- commitea "$D" "oculta

Ref: F1"
sin_hooks "$D" "oculta colada

Ref: F1"
espera falla "adoptado: el replay rechaza la carpeta oculta colada" "entrada oculta" -- replay "$D" HEAD~1..HEAD
# Plantilla ANTERIOR: recibos.sh que no conoce el marcador y registro sin él. Se adopta con ella
# (commits con sus hooks: aquí, sin hooks) y luego se actualiza con la actual.
PA="$W/plantilla-anterior"; rm -rf "$PA"; cp -R "$P" "$PA"
sed -e 's/contrato-recibos: 2/contrato-recibos-anterior/g' -e 's/if (nm==0 \&\& marca \&\& !previo) ok=bad(/if (0) ok=bad(/' -e 's/if (nm==0 \&\& !hm \&\& !previo) ok=bad(/if (0) ok=bad(/' "$PA/scripts/recibos.sh" > "$PA/r" && mv "$PA/r" "$PA/scripts/recibos.sh"
grep -v '^# contrato-recibos: 2' "$PA/docs/revisiones.log" > "$PA/l" && mv "$PA/l" "$PA/docs/revisiones.log"
sin_hooks "$PA" "versión anterior de la plantilla" || die "no pude preparar la plantilla anterior"
copia existente am; PREVIO_AM=$(en "$D" git rev-parse HEAD)
adoptar "$PA" copiar "$D" >/dev/null; en "$D" git rm -q --cached config/.env.prod; adoptar "$PA" gitignore "$D" --aplicar >/dev/null
base_decl "$D" "- **Base del método:** $PREVIO_AM"; fase "$D" F1; en "$D" git config core.hooksPath .githooks
sin_hooks "$D" "Instalación del método (versión anterior)

Ref: F1" || die "no pude instalar la versión anterior"
siembra_f2 "$D"; fase "$D" F2; incompleto "$D" revisor-funcional encuadre F2 PASA 0
sin_hooks "$D" "Plan

Ref: F2" || die "no pude preparar el plan con la versión anterior"
fase "$D" F3; printf 'assert 2 + 2 == 4\n' >> "$D/app.py"; incompleto "$D" juez-codigo incremento I1 PASA 0 seguridad=no-aplica
sin_hooks "$D" "I1

Ref: I1" || die "no pude cerrar I1 con la versión anterior"
espera pasa "adoptado con la versión anterior: el replay acepta su historial" "3/3 commits cumplen" -- replay "$D" HEAD
adoptar "$P" actualizar "$D" "T3: contrato de recibos" >/dev/null || die "adoptar.sh actualizar falló"
espera pasa "adoptar.sh actualizar sustituye recibos.sh (no lo había tocado el proyecto)" "" -- grep -q 'contrato-recibos: 2' "$D/scripts/recibos.sh"
printf -- '- nota\n' >> "$D/docs/MEMORIA.md"
espera falla "adoptado y actualizado: sin el marcador se bloquea con la instrucción de migrar" "añade al FINAL del registro" -- commitea "$D" "actualización

Ref: F1"
printf '# contrato-recibos: 2\n' >> "$D/docs/revisiones.log"
espera pasa "adoptado y actualizado: con el marcador al final se acepta" "" -- commitea "$D" "actualiza la plantilla y migra el registro

Ref: F1"
espera pasa "adoptado y migrado: el replay del historial completo sigue aceptándolo" "4/4 commits cumplen" -- replay "$D" HEAD
# Merge de una rama con la versión anterior (desde el commit previo a la migración) sobre lo migrado.
RAMA0=$(en "$D" git rev-parse --abbrev-ref HEAD); rm -rf "$W/etapas/adop-migrado"; cp -R "$D" "$W/etapas/adop-migrado"
copia adop-migrado amf1; en "$D" git checkout -q -b antigua HEAD~1; printf -- '- nota\n' >> "$D/docs/MEMORIA.md"
sin_hooks "$D" "nota en la rama antigua

Ref: F1" || die "no pude commitear en la rama antigua adoptada"
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-commit "$RAMA0" >/dev/null 2>&1; en "$D" git checkout -q HEAD -- scripts/recibos.sh
espera falla "adoptado: merge sobre la rama antigua que conserva su recibos.sh se rechaza" "no retrocede" -- en "$D" git -c core.hooksPath=.githooks commit -q -m "integra conservando el parser anterior

Ref: F1"
en "$D" git -c core.hooksPath=/dev/null commit -q --no-verify -m "integra colado

Ref: F1" || die "no pude colar el merge adoptado"
incompleto "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica; sin_hooks "$D" "recibo incompleto colado

Ref: F1"
espera falla "adoptado: el replay rechaza el merge que retrocede (y lo que sigue)" "no retrocede" -- replay "$D" HEAD~2..HEAD
copia adop-migrado amf2; en "$D" git checkout -q -b antigua HEAD~1; printf -- '- nota\n' >> "$D/docs/MEMORIA.md"
sin_hooks "$D" "nota en la rama antigua

Ref: F1" || die "no pude commitear en la rama antigua adoptada (2)"
espera pasa "adoptado: merge limpio que conserva la versión migrada se acepta" "" -- en "$D" git -c core.hooksPath=.githooks merge -q --no-ff --no-edit "$RAMA0"
copia adop-migrado amv; printf -- '- nota\n' >> "$D/docs/MEMORIA.md"; incompleto "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "adoptado: con RECIBOS_CONTRATO_PREVIO=1 heredado, el commit local sigue rechazando" "sin modalidad=" -- sh -c 'export RECIBOS_CONTRATO_PREVIO=1; cd "$1" && git add -A && git -c core.hooksPath=.githooks commit -q -m "x

Ref: F1"' sh "$D"
copia adop-migrado amc
incompleto "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica; sin_hooks "$D" "recibo incompleto colado

Ref: F1"
espera falla "adoptado y migrado: un recibo incompleto colado lo rechaza el replay" "sin modalidad=" -- replay "$D" HEAD~1..HEAD

echo "== adoptado: el filtro de revisores instalado juzga cada escritura por su destino"
GI="$W/etapas/instalado"; GA="$W/filtro-aut"; GF="$W/filtro-fuera"; mkdir -p "$GA" "$GF"
grA() {  # grA <modalidad|''> <comando>: el hook que trae la instalación, como revisor
  if [ -n "$1" ]; then printf '%s\n' "$1" > "$GI/.git/revision-modalidad"; else rm -f "$GI/.git/revision-modalidad"; fi
  python3 -c 'import json,sys; print(json.dumps({"agent_type":"juez-codigo","tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$2" "$GI" \
    | CLAUDE_PROJECT_DIR="$GI" python3 "$GI/.claude/hooks/guarda-revisor.py"
}
espera falla "adoptado: experimentos: git -C <fuera> add se rechaza" "git → $GF" -- grA "experimentos $GA" "git -C $GF add x"
espera falla "adoptado: experimentos: touch con destino entre comillas fuera se rechaza" "touch → $GF/x" -- grA "experimentos $GA" "touch \"$GF/x\""
espera pasa "adoptado: experimentos (control): touch entre comillas dentro del autorizado pasa" "" -- grA "experimentos $GA" "touch \"$GA/ok\""
espera falla "adoptado: lectura: git -c clave=valor commit se rechaza" "git" -- grA "" "git -c user.name=x commit -m y"
espera pasa "adoptado: lectura (control): git -C <otro> log pasa" "" -- grA "" "git -C $GF log --oneline -1"
espera falla "adoptado: git -C <D> init <fuera>/repo se rechaza" "git → $GF/repo" -- grA "experimentos $GA" "git -C $GA init $GF/repo"
espera falla "adoptado: una escritura permitida no oculta otra indeterminable" "touch → (destino desconocido|$GF/x)" -- grA "experimentos $GA" "touch $GA/ok; env -u V touch $GF/x"
espera falla "adoptado: cd en una tubería no cambia el directorio de fuera" "touch → $GI/x" -- grA "experimentos $GA" "cd $GA | cat; touch x"
espera falla "adoptado: cd a un inexistente con ; deja el directorio incierto" "destino desconocido" -- grA "experimentos $GA" "cd $GA/inexistente; touch x"
espera pasa "adoptado (control): cd <D>; touch relativo pasa" "" -- grA "experimentos $GA" "cd $GA; touch z"
espera falla "adoptado: git clone --branch consume el valor y ve el destino de fuera" "git → $GF/clon" -- grA "experimentos $GA" "git -C $GA clone -q --branch main $GA/origen $GF/clon"
espera falla "adoptado: git worktree add -b consume el valor y ve el destino de fuera" "git → $GF/arbol" -- grA "experimentos $GA" "git -C $GA/origen worktree add -b rama $GF/arbol"
espera pasa "adoptado (control): git clone --branch dentro pasa" "" -- grA "experimentos $GA" "git -C $GA clone -q --branch main $GA/origen $GA/clon"
espera falla "adoptado: cd <inexistente> && …; escritura se rechaza" "destino desconocido" -- grA "experimentos $GA" "cd $GA/no-existe && true; touch x"
espera falla "adoptado: cd <inexistente> && … || escritura se rechaza" "destino desconocido" -- grA "experimentos $GA" "cd $GA/no-existe && true || touch x"
espera pasa "adoptado (control): cd <D> && touch relativo pasa" "" -- grA "experimentos $GA" "cd $GA && touch z"
espera falla "adoptado: git init --shared no consume el destino de fuera" "git → $GF/repo2" -- grA "experimentos $GA" "git -C $GA init --shared $GF/repo2"
espera falla "adoptado: (cd <D> && …); escritura relativa se juzga fuera" "touch → $GI/externo" -- grA "experimentos $GA" "(cd $GA && touch interno); touch externo"
espera pasa "adoptado (control): (cd <D> && touch interno); touch <D>/x pasa" "" -- grA "experimentos $GA" "(cd $GA && touch interno); touch $GA/x"
rm -f "$GI/.git/revision-modalidad"

echo "== adoptado: la suite corre sobre una instantánea de lo que se commitea"
suite_es() { printf '#!/bin/sh\n%s\n%s\n' "$BLOQUE" "$2" > "$1/scripts/check.sh"; sin_hooks "$1" "suite (preparación)

Ref: F1" || die "no pude preparar la suite adoptada"; }
nota_f1() { printf -- '- nota %s\n' "$2" >> "$1/docs/MEMORIA.md"; commitea "$1" "nota

Ref: F1"; }
copia adoptado-f3 as1; suite_es "$D" 'python3 app.py || exit 1'
printf 'local_dep.py\n' >> "$D/.gitignore"; printf 'VALOR = 3\n' > "$D/local_dep.py"; printf 'from local_dep import VALOR\nassert VALOR == 3\n' >> "$D/app.py"
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "adoptado: un archivo ignorado que no se commitea no sostiene la suite" "sobre la instantánea" -- commitea "$D" "I2

Ref: I2"
copia adoptado-f3 as2; suite_es "$D" 'PYTHONPATH=deps python3 app.py || exit 1'
mkdir -p "$D/deps"; printf 'VALOR = 3\n' > "$D/deps/local_dep.py"; printf 'deps/\n' >> "$D/.gitignore"
printf '\n| Ruta | Propósito | Cómo se reproduce |\n|---|---|---|\n| deps | dependencias locales | copia manual |\n' >> "$D/docs/convenciones.md"
printf 'from local_dep import VALOR\nassert VALOR == 3\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "adoptado: la entrada externa declarada sostiene la suite" "" -- commitea "$D" "I2

Ref: I2"
copia adoptado-f3 as3; suite_es "$D" 'printf x >> README.md; touch -r app.py README.md'
espera falla "adoptado: una suite que reescribe un versionado (fecha restaurada) se rechaza" "README.md \(contenido\)" -- nota_f1 "$D" 3
copia adoptado-f3 as4; suite_es "$D" 'git tag suite-t && git config user.name intruso-suite'
espera pasa "adoptado: etiqueta y config en la suite solo tocan el repositorio temporal" "" -- nota_f1 "$D" 4
espera falla "adoptado: ... la etiqueta no aparece en el original" "" -- en "$D" git rev-parse -q --verify refs/tags/suite-t

copia adoptado-f3 aw1; suite_es "$D" 'git tag suite-wt && git config user.name intruso-wt'
ANTES_AW="$(en "$D" git rev-parse HEAD) $(en "$D" git config user.name || echo -) $(en "$D" git tag | tr '\n' ',')"
en "$D" git worktree add -q --detach "$W/aw1-arbol" || die "no pude crear el worktree adoptado"
printf -- '- nota\n' >> "$W/aw1-arbol/docs/MEMORIA.md"
espera pasa "adoptado: commit desde un worktree enlazado con una suite que etiqueta y configura" "" -- commitea "$W/aw1-arbol" "nota

Ref: F1"
espera pasa "adoptado: ... el repositorio original queda intacto" "" -- sh -c "[ \"\$1\" = \"\$(cd \"\$2\" && echo \"\$(git rev-parse HEAD) \$(git config user.name || echo -) \$(git tag | tr '\\n' ',')\")\" ]" sh "$ANTES_AW" "$D"
copia adoptado-f3 au1; printf 'x\n' > "$D/docs/año.txt"
espera pasa "adoptado: un nombre Unicode no produce un falso rechazo" "" -- nota_f1 "$D" au1
copia adoptado-f3 at1; suite_es "$D" 'cp README.md c && rm README.md && ln -s c README.md'
espera falla "adoptado: sustituir un archivo regular por un enlace se rechaza" "README.md \(tipo" -- nota_f1 "$D" at1

echo "== fallos previos: un ADR retrospectivo no decide una prueba (decisiones.md «Aceptación»)"
# Fixtures del focal H1–M01: la misma prueba declarada y un ADR aceptado que la nombra; solo cambia su Aprobación.
FPP=tests.test_calc.TestCalc.test_redondeo
fp_adr() {  # fp_adr <dir> <aprobación>: docs/decisiones.md con ADR-001 aceptado que nombra la prueba
  mkdir -p "$1/docs"; printf '# Decisiones\n\n## ADR-001 — Tratamiento de la prueba\n\n- **Estado:** aceptada\n- **Aprobación:** %s\n- **Contexto:** la prueba `%s` falla en la línea base.\n' "$2" "$FPP" > "$1/docs/decisiones.md"; }
fp_retirada() {  # fp_retirada <aprobación>: la guarda (coherencia) con una retirada que cita ADR-001
  d="$W/fp-ret-$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; fp_adr "$d" "$1"
  python3 -I - "$RAIZ/scripts/fallos_previos.py" "$d/docs/decisiones.md" "$FPP" <<'PY2'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("fp", sys.argv[1]); fp = importlib.util.module_from_spec(spec); spec.loader.exec_module(fp)
e = fp.coherencia({sys.argv[3]: ("falla", "fallo · AssertionError · 000000000000")}, {}, {sys.argv[3]: "ADR-001"}, open(sys.argv[2]).read())
print("\n".join(e)); sys.exit(1 if e else 0)
PY2
}
fp_destino() {  # fp_destino <aprobación>: check_docs desde F2 (fallos_previos.py destinos) con destino ADR-001
  d="$W/fp-dest-$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; fp_adr "$d" "$1"; mkdir -p "$d/scripts"
  cp "$RAIZ/scripts/fallos_previos.py" "$RAIZ/scripts/decisiones.py" "$RAIZ/scripts/check_docs.sh" "$d/scripts/"
  printf '# Plan\n\n## Incrementos\n\n- [ ] I1 «x» · C1\n' > "$d/docs/plan.md"
  printf '# Fallos previos\n\n## Fallos previos declarados\n\n| Prueba | Firma | Destino |\n|---|---|---|\n| `%s` | fallo · AssertionError · 000000000000 | ADR-001 |\n\n## Retiradas del inventario\n\n| Prueba | Motivo | ADR |\n|---|---|---|\n' "$FPP" > "$d/docs/fallos-previos.md"
  ( cd "$d" && python3 -I scripts/fallos_previos.py destinos ); }
NUEVA='«sí, retírala» (chat 2026-11-04, sobre ADR-001)'; RETRO='`retrospectivo: evidencia (tests/test_calc.py)`'
espera pasa "decisión nueva aceptada y pertinente: vale para retirar la prueba" "" -- fp_retirada "$NUEVA"
espera pasa "... y como destino del fallo declarado" "" -- fp_destino "$NUEVA"
espera falla "ADR retrospectivo como retirada: rechazado" "registro retrospectivo" -- fp_retirada "$RETRO"
espera falla "ADR retrospectivo como destino: rechazado" "registro retrospectivo" -- fp_destino "$RETRO"

echo "== replay anclado en un adoptado con fallos previos declarados (M01 con T05)"
# La orden de entrada, literal de docs/convenciones.md (como en regresion.sh).
ENTRADA=$(awk '/^ *```sh$/ { b = ""; f = 1; next }
  f && /^ *```$/ { if (b ~ /replay_anclado\.sh/) { printf "%s", b; exit } f = 0; next }
  f { sub(/^      /, ""); b = b $0 "\n" }' "$RAIZ/docs/convenciones.md" | grep -vE '^(ancla|inicio|fin)=')
[ -n "$ENTRADA" ] || die "no encontré la orden de entrada del replay anclado en docs/convenciones.md"
TA="$W/tmp-anclado"; mkdir -p "$TA"
anclado_t() { out=$( cd "$1" && TMPDIR="$TA" ancla="$2" inicio="$3" fin="$4" sh -c "$ENTRADA" 2>&1 ); rc=$?; printf '%s' "$out" | tr '\n' ' '; return $rc; }
# Proyecto con dos pruebas en rojo desde antes de adoptar; la instalación captura la línea base y es la primera ancla.
X="$W/etapas/fp-anclado"; mkdir -p "$X/tests"; en "$X" git init -q
printf '# Proyecto con pruebas\n' > "$X/README.md"; printf '__pycache__/\n' > "$X/.gitignore"; : > "$X/tests/__init__.py"
printf 'def suma(a, b):\n    return a + b\n\ndef redondea(x):\n    return int(x)\n' > "$X/app.py"
printf 'import unittest\nfrom app import suma, redondea\n\n\nclass T(unittest.TestCase):\n    def test_suma(self):\n        self.assertEqual(suma(1, 2), 3)\n\n    def test_redondeo(self):\n        self.assertEqual(redondea(2.6), 3)\n\n    def test_falla(self):\n        self.fail("roto desde antes")\n' > "$X/tests/test_app.py"
sin_hooks "$X" "código y pruebas (dos rojas desde siempre)"
PREVIO_FP=$(en "$X" git rev-parse HEAD)
adoptar "$P" copiar "$X" >/dev/null || die "no pude instalar en fp-anclado"
base_decl "$X" "- **Base del método:** $PREVIO_FP"; fase "$X" F1
printf '#!/bin/sh\n%s\npython3 -I scripts/fallos_previos.py comprobar --adaptador unittest --inicio tests || exit $?\nexit 0\n' "$BLOQUE" > "$X/scripts/check.sh"
en "$X" git config core.hooksPath .githooks
en "$X" python3 -I scripts/fallos_previos.py capturar --adaptador unittest --inicio tests >/dev/null || die "no pude capturar la línea base de fp-anclado"
commitea "$X" "Instalación del método (adopción) con fallos previos

Ref: F1" || die "no pude commitear la instalación de fp-anclado"
ANC_FP=$(en "$X" git rev-parse HEAD)
printf '# AGENTS.md\n\nProyecto adoptado con fallos previos (regresión). Ver docs/.\n' > "$X/AGENTS.md"
printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: suma devuelve a+b (comportamiento que se conserva).\n\n## Set de oro\n\n- suma(1, 2) → 3\n' > "$X/docs/encuadre.md"
printf '# Plan\n\n## Incrementos\n\n- [ ] I1 «caracteriza» — prueba de caracterización (satisface: C1)\n- [ ] I2 «redondeo» — corrige los fallos previos (satisface: C1)\n' > "$X/docs/plan.md"
printf '# Decisiones\n\n(ninguna todavía)\n' > "$X/docs/decisiones.md"
trazabilidad "$X" "$C1A" "" ""
sed -i.bak 's/_pendiente: I<n> que la corrige o ADR_/I2/' "$X/docs/fallos-previos.md" && rm -f "$X/docs/fallos-previos.md.bak"
grep -q 'Plazo de la suite' "$X/docs/convenciones.md" || printf -- '- **Plazo de la suite:** 60 s\n' >> "$X/docs/convenciones.md"
fase "$X" F2; recibo "$X" revisor-funcional encuadre F2 PASA 0
commitea "$X" "Plan de adopción

Ref: F2" || die "no pude commitear el plan de fp-anclado"
fase "$X" F3; printf '\ndef resta(a, b):\n    return a - b\n' >> "$X/app.py"; recibo "$X" juez-codigo incremento I1 PASA 0 seguridad=no-aplica
commitea "$X" "I1

Ref: I1" || die "no pude cerrar I1 en fp-anclado"
espera pasa "fallos previos + replay anclado en la instalación (primera ancla): el plan e I1 pasan" "2/2 commits cumplen.*resultado PASA" -- anclado_t "$X" "$ANC_FP" "$ANC_FP" HEAD
espera pasa "... sin presentar la suite como aprobada: check.sh lo dice y CHECK_ESTRICTO=1 termina en 2" "" -- sh -c 'cd "$1" && sh scripts/check.sh 2>&1 | grep -q "no es una suite aprobada" && { CHECK_ESTRICTO=1 sh scripts/check.sh >/dev/null 2>&1; [ $? -eq 2 ]; }' _ "$X"
copia fp-anclado fpa1; printf '<!-- retoque -->\n' >> "$D/contexto/exploracion/linea-base-pruebas.xml"
sin_hooks "$D" "línea base modificada

Ref: F1"
espera falla "fallos previos + replay anclado: modificar la línea base se rechaza" "fallos previos declarados no se sostienen.*resultado FALLA" -- anclado_t "$D" "$ANC_FP" "$ANC_FP" HEAD
copia fp-anclado fpa2
printf '# Plan\n\n## Incrementos\n\n- [x] I1 «caracteriza» — prueba de caracterización (satisface: C1)\n- [ ] I2 «redondeo» — corrige los fallos previos (satisface: C1)\n' > "$D/docs/plan.md"
trazabilidad "$D" '| C1 | «arranca» | I1 | verificado | |' "" ""
fase "$D" F4 "— «ninguno»"; recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
sin_hooks "$D" "validación con fallos previos pendientes

Ref: F4"
espera falla "fallos previos + replay anclado: el cierre (Ref: F4) no pasa mientras queden fallos declarados" "sigue declarada como fallo previo al cierre.*resultado FALLA" -- anclado_t "$D" "$ANC_FP" "$ANC_FP" HEAD
espera falla "... y la causa es esa: los destinos al cierre rechazan los fallos que quedan" "" -- en "$D" python3 -I scripts/fallos_previos.py destinos --cierre
espera pasa "la orden de entrada no dejó carpetas en su TMPDIR" "" -- sh -c '[ -z "$(ls -A "$1")" ]' _ "$TA"

# M01 con cierre acotado: excluir el criterio al que apuntan los fallos previos no elude su bloqueo.
copia fp-anclado fpc1; fase "$D" F5 "— «ninguno»"; sin_hooks "$D" "cierre de un ciclo anterior (colado: simula un ciclo cerrado)

Ref: F5"
python3 -I - "$D/docs/encuadre.md" <<'EOF'
import sys; p = sys.argv[1]; s = open(p).read(); a = "- C1: suma devuelve a+b (comportamiento que se conserva).\n"
assert s.count(a) == 1; open(p, "w").write(s.replace(a, a + "- C2: resta devuelve a-b.\n"))
EOF
trazabilidad "$D" "$C1A
| C2 | «resta» | I1 | verificado | |" "" ""; fase "$D" F2; recibo "$D" revisor-funcional encuadre F2 PASA 0
commitea "$D" "apertura de un ciclo posterior

Ref: F2" || die "no pude abrir el ciclo posterior en fpc1"
fase "$D" F4; recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica cubre=C2 excluye=C1
espera falla "M01 + cierre acotado: con C1 excluido como pendiente histórico, los fallos previos siguen bloqueando F4" "sigue declarada como fallo previo al cierre" -- commitea "$D" "validación

Ref: F4"

# M01 con una retirada (PR-4): retirar un requisito (por decisión de alcance) no levanta el bloqueo de los fallos previos.
copia fp-anclado fpr1
printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: suma devuelve a+b (comportamiento que se conserva).\n- C2: la división redondea a dos decimales.\n\n## Set de oro\n\n- suma(1, 2) → 3\n' > "$D/docs/encuadre.md"
printf '# Plan\n\n## Incrementos\n\n- [x] I1 «caracteriza» — prueba de caracterización (satisface: C1)\n- [ ] I2 «redondeo» — corrige los fallos previos (satisface: C1, C2)\n' > "$D/docs/plan.md"
trazabilidad "$D" '| C1 | «arranca» | I1, I2 | verificado | |
| C2 | «redondeo» | I2 | pendiente | |' "" ""; fase "$D" F2; recibo "$D" revisor-funcional encuadre F2 PASA 0
commitea "$D" "C2 en el contrato

Ref: F2" || die "no pude preparar fpr1"
printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: suma devuelve a+b (comportamiento que se conserva).\n- C2: [retirado: ADR-001] la división redondea a dos decimales.\n\n## Set de oro\n\n- suma(1, 2) → 3\n' > "$D/docs/encuadre.md"
printf '# Decisiones\n\n## ADR-001 — Alcance\n\n- **Estado:** aceptada\n- **Aprobación:** «la división ya no es del producto» (chat 2026-11-09)\n- **Decisión:** retirar C2 por decisión de alcance; no repara los fallos previos.\n' > "$D/docs/decisiones.md"
trazabilidad "$D" '| C1 | «arranca» | I1, I2 | verificado | |
| C2 | «redondeo» | I2 | pendiente | (histórico; retirado por ADR-001) |' "" ""
sed -i.bak 's/^| C2 | «redondeo» | pendiente |$/| C2 | «redondeo» | pendiente (histórico; retirado por ADR-001) |/' "$D/docs/estado.md" && rm -f "$D/docs/estado.md.bak"
recibo "$D" revisor-funcional encuadre reentrada:C2 PASA 0
espera pasa "M01 + retirada: retirar un criterio con fallos previos declarados se permite (decisión de alcance)" "" -- commitea "$D" "retira C2

Ref: F2"
fase "$D" F4 "— «ninguno»"; recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "... pero el cierre sigue bloqueado mientras queden fallos previos declarados" "sigue declarada como fallo previo al cierre" -- commitea "$D" "validación

Ref: F4"
espera pasa "... y el replay anclado acepta la retirada" "1/1 commits cumplen.*resultado PASA" -- anclado_t "$D" "$(en "$D" git rev-parse HEAD~1)" "$(en "$D" git rev-parse HEAD~1)" HEAD

echo "== procedencia en un adoptado (PR-3): base que nace y no cambia, colisiones y R-S.1"
# Un solo tipo de comprobación por caso, con hooks activos; los colados (--no-verify) los juzgan el replay actual
# y el anclado (ancla: la instalación, con los validadores de esta entrega).
replay_1l() { out=$(replay "$1" "$2" 2>&1); rc=$?; printf '%s' "$out" | tr '\n' ' '; return $rc; }
rev_cm() { ( cd "$1" && REV=HEAD sh .githooks/commit-msg /dev/null ); }
INST_PP=$(en "$W/etapas/propios" git rev-parse HEAD)
# P(B): el archivo propio que colisionó (scripts/pruebas/regresion-suite.sh) es producto.
copia propios pb1; printf 'echo otra cosa\n' >> "$D/scripts/pruebas/regresion-suite.sh"
espera falla "P(B): cambiar con Ref: F1 el archivo propio que colisionó se rechaza" "código fuera del rastro \(scripts/pruebas/regresion-suite\.sh" -- commitea "$D" "suite

Ref: F1"
sin_hooks "$D" "suite colada

Ref: F1"
espera falla "P(B): el replay actual rechaza el cambio colado" "código fuera del rastro \(scripts/pruebas/regresion-suite\.sh" -- replay "$D" HEAD
espera falla "P(B): y el anclado" "regresion-suite\.sh.*resultado FALLA" -- anclado_t "$D" "$INST_PP" "$INST_PP" HEAD
copia propios pb2; RAMA0=$(en "$D" git rev-parse --abbrev-ref HEAD); en "$D" git checkout -q -b lateral
printf 'echo lateral\n' >> "$D/scripts/pruebas/regresion-suite.sh"; sin_hooks "$D" "suite en la rama lateral

Ref: F1"
en "$D" git checkout -q "$RAMA0"; printf '\nnota\n' >> "$D/docs/MEMORIA.md"; commitea "$D" "nota

Ref: F1" || die "no pude preparar la principal en pb2"
en "$D" git -c core.hooksPath=.githooks merge -q --no-ff -m "integra la rama lateral" lateral || die "no pude integrar la rama lateral en pb2"
espera falla "P(B): el cambio en una rama lateral integrada con un merge limpio lo rechaza el replay actual" "código fuera del rastro \(scripts/pruebas/regresion-suite\.sh" -- replay "$D" HEAD
espera falla "P(B): y el anclado" "regresion-suite\.sh.*resultado FALLA" -- anclado_t "$D" "$INST_PP" "$INST_PP" HEAD
copia propios pb3; grep -vx -- '- scripts/pruebas/regresion-suite.sh' "$D/contexto/adopcion.md" > "$D/m.t" && mv "$D/m.t" "$D/contexto/adopcion.md"
commitea "$D" "el manifiesto deja de registrar la colisión

Ref: F1" || die "no pude editar el manifiesto en pb3"
printf 'echo otra cosa\n' >> "$D/scripts/pruebas/regresion-suite.sh"
espera falla "P(B): sin la colisión en el manifiesto, el archivo sigue siendo producto (se lee del árbol de la base)" "regresion-suite\.sh" -- commitea "$D" "suite

Ref: F1"
copia propios pb4; cp "$P/scripts/pruebas/regresion-suite.sh" "$D/scripts/pruebas/regresion-suite.sh"
espera falla "P(B): sustituirlo por la versión del método también es un cambio de código" "regresion-suite\.sh" -- commitea "$D" "adopta la suite del método

Ref: F1"
PN="$W/plantilla-pr3"; rm -rf "$PN"; cp -R "$P" "$PN"; printf '# nota de la entrega nueva\n' >> "$PN/scripts/huella.sh"; sin_hooks "$PN" "la plantilla cambia huella.sh"
copia propios pb5; adoptar "$PN" actualizar "$D" "entrega nueva" >/dev/null || die "no pude actualizar en pb5"
espera pasa "control: actualizar un archivo instalado (adoptar.sh actualizar) con Ref: F1 se acepta" "" -- commitea "$D" "actualiza el método

Ref: F1"
espera pasa "control: el replay actual lo acepta" "2/2 commits cumplen" -- replay "$D" HEAD
espera pasa "control: y el anclado" "resultado PASA" -- anclado_t "$D" "$INST_PP" "$INST_PP" HEAD

# La base no cambia ni desaparece.
copia instalado bm1; base_decl "$D" "- **Base del método:** $INST"
espera falla "base: cambiarla se rechaza" "no cambia ni desaparece" -- commitea "$D" "mueve la base

Ref: F1"
copia instalado bm2; base_decl "$D" ""
espera falla "base: borrarla se rechaza" "no cambia ni desaparece.*no declara ninguna" -- commitea "$D" "quita la base

Ref: F1"
copia instalado bm3; printf -- '- **Base del método:** %s\n' "$PREVIO" >> "$D/docs/convenciones.md"
espera falla "base: duplicarla se rechaza" "más de una declaración" -- commitea "$D" "duplica la base

Ref: F1"
copia instalado bm4; base_decl "$D" "- **Base del método:** zzz"
espera falla "base: una declaración malformada se rechaza (no equivale a sin base)" "malformada" -- commitea "$D" "estropea la base

Ref: F1"
copia instalado bm5; base_decl "$D" "- **Base del método:** $INST"; sin_hooks "$D" "mueve la base (colado)

Ref: F1"
base_decl "$D" "- **Base del método:** $PREVIO"; sin_hooks "$D" "la devuelve (colado)

Ref: F1"
espera falla "base: el replay actual rechaza un cambio colado y devuelto" "1/3 commits cumplen" -- replay "$D" HEAD
espera falla "base: y el anclado" "no cambia ni desaparece.*resultado FALLA" -- anclado_t "$D" "$INST" "$INST" HEAD
copia instalado bm6; base_decl "$D" "- **Base del método:** $INST"; sin_hooks "$D" "mueve la base (colado)

Ref: F1"
espera falla "base: replay anclado con la base del final distinta de la del ancla se detiene" "se lee del ancla" -- anclado_t "$D" "$INST" "$INST" HEAD
copia instalado bm7; printf '\nnota\n' >> "$D/docs/MEMORIA.md"; commitea "$D" "nota

Ref: F1" || die "no pude preparar bm7"
espera pasa "control: replay anclado cuya base nació antes del ancla" "1/1 commits cumplen.*resultado PASA" -- anclado_t "$D" "$INST" "$INST" HEAD

# Nacimiento: en un commit ordinario, igual a su padre.
copia existente bn1; adoptar "$P" copiar "$D" >/dev/null; en "$D" git rm -q --cached config/.env.prod; adoptar "$P" gitignore "$D" --aplicar >/dev/null
base_decl "$D" "- **Base del método:** $(en "$D" git rev-parse HEAD~1)"; fase "$D" F1; en "$D" git config core.hooksPath .githooks
espera falla "nacimiento: una base distinta del padre se rechaza" "nace distinta de su padre" -- commitea "$D" "Instalación del método (adopción)

Ref: F1"
copia existente bn2; RAMA0=$(en "$D" git rev-parse --abbrev-ref HEAD); en "$D" git checkout -q -b lado
printf '\nlado\n' >> "$D/README.md"; sin_hooks "$D" "cambio en otra rama"; en "$D" git checkout -q "$RAMA0"
BN2=$(en "$D" git rev-parse HEAD); adoptar "$P" copiar "$D" >/dev/null || die "no pude copiar en bn2"
en "$D" git merge -q --no-ff --no-commit lado || die "no pude preparar el merge de bn2"; en "$D" git rm -q --cached config/.env.prod; adoptar "$P" gitignore "$D" --aplicar >/dev/null
base_decl "$D" "- **Base del método:** $BN2"; fase "$D" F1; en "$D" git config core.hooksPath .githooks
espera falla "nacimiento: la base no nace en un merge" "nace en un merge" -- commitea "$D" "Instalación del método (adopción) en un merge

Ref: F1"
copia existente bn3; adoptar "$P" copiar "$D" >/dev/null; en "$D" git rm -q --cached config/.env.prod; adoptar "$P" gitignore "$D" --aplicar >/dev/null
fase "$D" F1; sin_hooks "$D" "Instalación sin base (colada)

Ref: F1"
BN3=$(en "$D" git rev-parse HEAD); base_decl "$D" "- **Base del método:** $BN3"; sin_hooks "$D" "base declarada después del ancla

Ref: F1"
espera falla "nacimiento: una base que el ancla no declaraba detiene el replay anclado" "se lee del ancla" -- anclado_t "$D" "$BN3" "$BN3" HEAD

# Merges.
copia instalado mg1; RAMA0=$(en "$D" git rev-parse --abbrev-ref HEAD); en "$D" git checkout -q -b otra
base_decl "$D" "- **Base del método:** $INST"; sin_hooks "$D" "otra base (colada)

Ref: F1"
en "$D" git checkout -q "$RAMA0"; printf '\nnota\n' >> "$D/docs/MEMORIA.md"; commitea "$D" "nota

Ref: F1" || die "no pude preparar mg1"
espera falla "merges: padres con bases distintas se rechazan" "Bases del método distintas" -- en "$D" git -c core.hooksPath=.githooks merge -q --no-ff -m "integra otra" otra
copia instalado mg2; RAMA0=$(en "$D" git rev-parse --abbrev-ref HEAD); en "$D" git checkout -q -b vieja; en "$D" git checkout -q "$RAMA0"
printf '\nnota\n' >> "$D/docs/MEMORIA.md"; commitea "$D" "nota en la principal

Ref: F1" || die "no pude preparar mg2"
en "$D" git checkout -q vieja; printf '\notra\n' >> "$D/docs/decisiones.md"; commitea "$D" "nota en la rama vieja

Ref: F1" || die "no pude preparar mg2 (rama vieja)"
espera pasa "control: merge de la principal en una rama vieja (misma base)" "" -- en "$D" git -c core.hooksPath=.githooks merge -q --no-ff -m "trae la principal" "$RAMA0"
espera pasa "control: el replay actual lo acepta" "4/4 commits cumplen" -- replay "$D" HEAD
espera pasa "control: y el anclado" "resultado PASA" -- anclado_t "$D" "$INST" "$INST" HEAD

# R-S.1, por transición: sin el marcador (una instalación anterior, que todavía traía adoptar.sh y la regresión de
# adopción), la regla anterior; con él, son producto en el adoptado aunque los trajera la instalación.
copia existente rs; RS="$D"; adoptar "$P" copiar "$RS" >/dev/null; en "$RS" git rm -q --cached config/.env.prod; adoptar "$P" gitignore "$RS" --aplicar >/dev/null
grep -vx '# contrato-procedencia: 1' "$RS/scripts/check_docs.sh" > "$RS/c.t" && cat "$RS/c.t" > "$RS/scripts/check_docs.sh" && rm "$RS/c.t"
cp "$P/scripts/adoptar.sh" "$RS/scripts/adoptar.sh"; cp "$P/scripts/pruebas/regresion-adopcion.sh" "$RS/scripts/pruebas/regresion-adopcion.sh"
base_decl "$RS" "- **Base del método:** $(en "$RS" git rev-parse HEAD)"; fase "$RS" F1; en "$RS" git config core.hooksPath .githooks
commitea "$RS" "Instalación del método (adopción, entrega anterior)

Ref: F1" || die "no pude instalar la entrega anterior en rs"
RS_INST=$(en "$RS" git rev-parse HEAD)
printf '# retoque\n' >> "$RS/scripts/adoptar.sh"
espera pasa "R-S.1 sin marcador: cambiar adoptar.sh con Ref: F1 conserva la interpretación anterior" "" -- commitea "$RS" "retoca adoptar.sh

Ref: F1"
cp "$P/scripts/check_docs.sh" "$RS/scripts/check_docs.sh"
espera pasa "R-S.1: activar el marcador (actualizar check_docs.sh) con Ref: F1 se acepta" "" -- commitea "$RS" "activa el contrato de procedencia

Ref: F1"
RS_MARCA=$(en "$RS" git rev-parse HEAD)
rm -rf "$W/etapas/rs-marcado"; cp -R "$RS" "$W/etapas/rs-marcado"
copia rs-marcado rs1; printf '# otro retoque\n' >> "$D/scripts/adoptar.sh"
espera falla "R-S.1 con marcador: cambiar adoptar.sh con Ref: F1 se rechaza aunque lo trajera la instalación" "código fuera del rastro \(scripts/adoptar\.sh" -- commitea "$D" "retoca adoptar.sh

Ref: F1"
copia rs-marcado rs2; printf '# retoque\n' >> "$D/scripts/pruebas/regresion-adopcion.sh"
espera falla "R-S.1 con marcador: lo mismo con la regresión de adopción" "código fuera del rastro \(scripts/pruebas/regresion-adopcion\.sh" -- commitea "$D" "retoca la regresión

Ref: F1"
copia rs-marcado rs3; grep -vx '# contrato-procedencia: 1' "$D/scripts/check_docs.sh" > "$D/c.t" && cat "$D/c.t" > "$D/scripts/check_docs.sh" && rm "$D/c.t"
espera falla "R-S.1: retirar el marcador se rechaza (guardas 8d)" "deja de declarar «# contrato-procedencia: 1»" -- commitea "$D" "retira el marcador

Ref: F1"
copia rs-marcado rs4; printf '# otro retoque\n' >> "$D/scripts/adoptar.sh"; sin_hooks "$D" "retoca adoptar.sh (colado)

Ref: F1"
espera falla "R-S.1: el replay actual acepta lo anterior al marcador y rechaza solo lo posterior" "  ok    [0-9a-f]+ retoca adoptar\.sh .*  ok    [0-9a-f]+ activa el contrato .*FALLO [0-9a-f]+ retoca adoptar\.sh \(colado\).*3/4 commits cumplen" -- replay_1l "$D" HEAD
espera pasa "R-S.1: el anclado acepta el tramo hasta la activación (interpretación histórica)" "2/2 commits cumplen.*resultado PASA" -- anclado_t "$D" "$RS_INST" "$RS_INST" "$RS_MARCA"
espera falla "R-S.1: y rechaza el cambio posterior" "adoptar\.sh.*2/3 commits cumplen.*resultado FALLA" -- anclado_t "$D" "$RS_INST" "$RS_INST" HEAD

# Errores de lectura: nunca equivalen a «sin base», «sin colisiones» ni «sin marcador».
quita_obj() { o=$(en "$1" git rev-parse "$2"); rm -f "$1/.git/objects/$(printf '%s' "$o" | cut -c1-2)/$(printf '%s' "$o" | cut -c3-)"; ! en "$1" git cat-file -e "$o" 2>/dev/null || die "no pude retirar el objeto $2 en $1"; }
copia propios er1; printf '\nnota\n' >> "$D/docs/MEMORIA.md"; sin_hooks "$D" "nota

Ref: F1"; quita_obj "$D" "$PREVIO_PP^{tree}"
espera falla "errores: si el árbol de la base no se puede leer, se rechaza (no equivale a sin colisiones)" "no pude leer el árbol de la Base del método" -- rev_cm "$D"
copia instalado er2; printf '\n<!-- nota -->\n' >> "$D/docs/convenciones.md"; sin_hooks "$D" "nota en convenciones

Ref: F1"; quita_obj "$D" "$INST:docs/convenciones.md"
espera falla "errores: si la base del padre no se puede leer, se rechaza (no equivale a sin base)" "no pude determinar la Base del método de un padre" -- rev_cm "$D"
copia rs-marcado er3; grep -vx '# contrato-procedencia: 1' "$D/scripts/check_docs.sh" > "$D/c.t" && cat "$D/c.t" > "$D/scripts/check_docs.sh" && rm "$D/c.t"
printf '# retoque\n' >> "$D/scripts/adoptar.sh"; sin_hooks "$D" "retoca adoptar.sh y retira el marcador (colado)

Ref: F1"; quita_obj "$D" "$RS_MARCA:scripts/check_docs.sh"
espera falla "errores: si el marcador del padre no se puede leer, cambiar adoptar.sh se rechaza (no equivale a sin marcador)" "no pude leer scripts/check_docs.sh .*contrato-procedencia" -- rev_cm "$D"

echo
echo "regresion-adopcion: $((TOTAL-MAL))/$TOTAL casos en verde"
if [ "$MAL" -gt 0 ]; then echo "FALLARON:$FALLIDOS"; exit 1; fi
exit 0
