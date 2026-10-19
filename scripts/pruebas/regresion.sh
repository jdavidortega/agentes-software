#!/bin/sh
# Regresión de los HOOKS y SCRIPTS de la plantilla (viene con ella; README §Enforcement).
# Crea repositorios temporales a partir de los archivos versionados de esta plantilla y
# comprueba cada regla con su caso NEGATIVO (el hook rechaza) y su caso POSITIVO (acepta).
# Sin red, sin credenciales, sin clientes de IA: solo git, sh, awk y python3. Corre en
# segundos. Se ejecuta antes de tocar un hook o un script de la plantilla, y en CI.
#
#   sh scripts/pruebas/regresion.sh        → 0 si todos los casos pasan; 1 y la lista si no
#   sh scripts/pruebas/regresion.sh -v     → además imprime la salida de cada caso
#
# Cada caso vive en una copia fresca de una ETAPA (plantilla recién copiada; proyecto en
# F3 con I1 cerrado; proyecto listo para cerrar), así ningún caso contamina a otro.
VERBOSE=0; [ "${1:-}" = "-v" ] && VERBOSE=1
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
W=$(mktemp -d 2>/dev/null || mktemp -d -t regresion); trap 'rm -rf "$W"' EXIT INT TERM
export GIT_AUTHOR_NAME=regresion GIT_AUTHOR_EMAIL=regresion@local
export GIT_COMMITTER_NAME=regresion GIT_COMMITTER_EMAIL=regresion@local
export GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_CONFIG_SYSTEM=/dev/null   # sin config del usuario
: > "$W/gitconfig"; git config --file "$W/gitconfig" --add safe.directory "*"
unset FASE_PREVIA
TOTAL=0; MAL=0; FALLIDOS=""
SAB="$RAIZ/.claude/skills/verificando-por-sabotaje/scripts/sabotear.py"

# --- utilidades ------------------------------------------------------------------------
die() { echo "regresion: $1" >&2; exit 2; }
# espera <falla|pasa> <nombre> <patrón en la salida (regex ERE; vacío = cualquiera)> -- cmd...
espera() {
  modo=$1; nombre=$2; patron=$3; shift 4
  TOTAL=$((TOTAL+1)); out=$("$@" 2>&1); rc=$?
  if [ "$modo" = falla ]; then ok=$([ $rc -ne 0 ] && echo 1 || echo 0); else ok=$([ $rc -eq 0 ] && echo 1 || echo 0); fi
  if [ "$ok" = 1 ] && [ -n "$patron" ] && ! printf '%s' "$out" | grep -qE "$patron"; then ok=0; fi
  if [ "$ok" = 1 ]; then echo "  ok    $nombre"; else echo "  FALLO $nombre (esperaba $modo${patron:+ con «$patron»}; rc=$rc)"; MAL=$((MAL+1)); FALLIDOS="$FALLIDOS
    - $nombre"; fi
  [ "$VERBOSE" = 1 ] || [ "$ok" = 0 ] && printf '%s\n' "$out" | sed 's/^/        | /' | head -12
  return 0
}
# copia <etapa> <nombre> → crea $W/<nombre> desde $W/etapas/<etapa> y lo deja en $D
copia() { D="$W/$2"; rm -rf "$D"; cp -R "$W/etapas/$1" "$D"; }
# en <dir> cmd... : ejecuta en ese directorio
en() { d=$1; shift; ( cd "$d" && "$@" ); }
commitea() {  # commitea <dir> <mensaje con trailer>
  en "$1" git add -A && en "$1" git -c core.hooksPath=.githooks commit -q -m "$2"
}
huella_idx() { en "$1" git add -A >/dev/null 2>&1; en "$1" sh scripts/huella.sh indice; }
# recibo <dir> rol tipo alcance veredicto bloqueantes [campos extra...] → añade al log con la huella del índice
recibo() {
  d=$1; rol=$2; tipo=$3; alc=$4; ver=$5; blo=$6; shift 6
  h=$(huella_idx "$d")
  printf 'fecha=2026-10-19T10:00Z rol=%s tipo=%s alcance=%s veredicto=%s bloqueantes=%s huella=%s ejecutor=regresion %s\n' \
    "$rol" "$tipo" "$alc" "$ver" "$blo" "$h" "$*" >> "$d/docs/revisiones.log"
}
# recibo_fijo <dir> ... igual pero con la huella dada (último argumento)
fase() { sed -i.bak -E "s/^- \*\*Fase actual:\*\*.*/- **Fase actual:** $2 · incremento activo: ${3:-I_ «alias»}/" "$1/docs/estado.md" && rm -f "$1/docs/estado.md.bak"; }
# trazabilidad <dir> "<filas C>" "<filas E>" "<filas R>" "<histórico>": escribe el archivo entero
trazabilidad() {
  {
    cat <<'EOF'
# Trazabilidad

## IDs y cómo se enlazan

- Ver docs/convenciones.md.

## Cobertura de criterios

| Criterio | Alias | Incremento(s) | Estado | Nota |
|----------|-------|---------------|--------|------|
EOF
    [ -n "$2" ] && printf '%s\n' "$2"
    cat <<'EOF'

## Registro de vacíos del revisor funcional (arranque)

| Vacío | Alias | Punto incumplido | Estado | Resuelto (cómo · AAAA-MM-DD HH:MM UTC) |
|-------|-------|------------------|--------|----------------------------------------|
EOF
    [ -n "$3" ] && printf '%s\n' "$3"
    cat <<'EOF'

## Registro de revisiones del juez

| Hallazgo | Alias | Incr. | Criterio | Descripción | Estado | Resuelto (AAAA-MM-DD HH:MM UTC · commit) |
|----------|-------|-------|----------|-------------|--------|------------------------------------------|
EOF
    [ -n "$4" ] && printf '%s\n' "$4"
    printf '\n## Histórico (compactado)\n\n'
    [ -n "${5:-}" ] && printf '%s\n' "$5"
  } > "$1/docs/trazabilidad.md"
}
C1_PEND='| C1 | «suma» | I1 | pendiente | |'
C1_VERIF='| C1 | «suma» | I1 | verificado | |'

# --- etapas ----------------------------------------------------------------------------
mkdir -p "$W/etapas"
# E0: plantilla recién copiada, hooks activos, primer commit (Ref: F1) hecho.
B="$W/etapas/plantilla"; mkdir -p "$B"
if git -C "$RAIZ" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$RAIZ" ls-files -z -co --exclude-standard | ( cd "$RAIZ" && xargs -0 -I{} sh -c 'mkdir -p "$0/$(dirname "{}")" && cp "{}" "$0/{}"' "$B" )
else
  ( cd "$RAIZ" && find . -path ./.git -prune -o -path ./mejoras -prune -o -type f -print | while read -r f; do mkdir -p "$B/$(dirname "$f")"; cp "$f" "$B/$f"; done )
fi
rm -rf "$B/mejoras"
en "$B" git init -q && en "$B" git config core.hooksPath .githooks
chmod +x "$B"/.githooks/* "$B"/scripts/*.sh "$B"/scripts/pruebas/*.sh
en "$B" git add -A >/dev/null
for x in .githooks/pre-commit .githooks/commit-msg scripts/check_docs.sh scripts/huella.sh scripts/recibos.sh scripts/pruebas/regresion.sh; do
  en "$B" git update-index --chmod=+x "$x"
done
echo "== etapa: plantilla recién copiada"
espera pasa "arranque nuevo: primer commit Ref: F1 sobre la plantilla" "" -- commitea "$B" "Encuadre inicial

Ref: F1"

# E1: proyecto en F2 cerrado (encuadre + plan + trazabilidad sembrada + check.sh), listo para I1.
P="$W/etapas/f2"; cp -R "$B" "$P"
sed -i.bak -e 's/_\[nombre\]_/Demo/' -e 's/_\[qué problema resuelve, en una frase\]_/sumar dos números/' "$P/AGENTS.md"; rm -f "$P/AGENTS.md.bak"
grep -q '_\[' "$P/AGENTS.md" && sed -i.bak -E 's/_\[[^]]+\]_/x/g' "$P/AGENTS.md"; rm -f "$P/AGENTS.md.bak"
sed -i.bak 's/^- C1:.*/- C1: la función suma devuelve a+b para enteros./' "$P/docs/encuadre.md"; rm -f "$P/docs/encuadre.md.bak"
python3 - "$P/docs/plan.md" <<'EOF'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'^- \[ \] I1 .*$', '- [ ] I1 «suma» — función suma (satisface: C1)', s, flags=re.M)
s=re.sub(r'^- \[ \] I2 .*$', '- [ ] I2 «resta» — función resta (satisface: C1)\n- [ ] I3 «multiplica» — (satisface: C1)\n- [ ] I4 «divide» — (satisface: C1)\n- [ ] I5 «potencia» — (satisface: C1)', s, flags=re.M)
open(p,'w').write(s)
EOF
trazabilidad "$P" "$C1_PEND" "" ""
printf '#!/bin/sh\n# suite del proyecto demo\n[ -f app.py ] && python3 -I app.py\nexit 0\n' > "$P/scripts/check.sh"
fase "$P" F2 "I1 «suma»"
recibo "$P" revisor-funcional encuadre F2 PASA 0
echo "== etapa: plan aprobado (F2)"
espera pasa "cierre del plan: Ref: F2 con recibo del revisor funcional vigente" "" -- commitea "$P" "Plan

Ref: F2"

# E2: I1 cerrado en F3 (app.py revisado por el juez), listo para más incrementos.
Q="$W/etapas/f3"; cp -R "$P" "$Q"
fase "$Q" F3 "I1 «suma»"
printf 'def suma(a, b):\n    return a + b\n\nassert suma(1, 2) == 3\n' > "$Q/app.py"
recibo "$Q" juez-codigo incremento I1 PASA 0 seguridad=no-aplica
echo "== etapa: F3 con I1 cerrado"
espera pasa "I1: Ref: I1 con recibo del juez PASA sobre esta huella" "" -- commitea "$Q" "I1 «suma»: función suma

Ref: I1"

# ======================================================================================
echo "== A01 · fase ilegible / registros en F1"
copia f3 a01; fase "$D" "F_"
espera falla "fase F_ con proyecto iniciado se rechaza" "no declara una fase legible" -- commitea "$D" "docs

Ref: I1"
copia f3 a01b; sed -i.bak '/Fase actual/d' "$D/docs/estado.md"; rm -f "$D/docs/estado.md.bak"
espera falla "fase ausente con proyecto iniciado se rechaza" "no declara una fase legible" -- commitea "$D" "docs

Ref: I1"
copia plantilla a01c
espera falla "F1: eliminar docs/revisiones.log se rechaza" "elimina|append-only|falta docs/revisiones.log" -- sh -c 'cd "$1" && git rm -q docs/revisiones.log && git -c core.hooksPath=.githooks commit -q -m "limpia

Ref: F1"' sh "$D"
copia plantilla a01d; fase "$D" "F_"; echo "- nota" >> "$D/docs/MEMORIA.md"
espera pasa "plantilla sin iniciar: F_ sigue siendo modo plantilla" "" -- commitea "$D" "docs

Ref: F1"
copia plantilla a01e; fase "$D" "F1"
espera falla "F1: borrar scripts/recibos.sh se rechaza" "falta scripts/recibos.sh" -- sh -c 'cd "$1" && git add -A && git rm -q scripts/recibos.sh && git -c core.hooksPath=.githooks commit -q -m "x

Ref: F1"' sh "$D"

echo "== A02 · código sin Ref: I<n>"
copia f3 a02; printf 'def resta(a, b):\n    return a - b\n' >> "$D/app.py"
trazabilidad "$D" "$C1_PEND" "" '| R-I1.1 | «sin-prueba» | I1 | C1 | falta prueba | resuelto | 2026-10-19 10:00 · abc1234 |'
espera falla "Cierra: solo con código se rechaza" "sin 'Ref: I<n>'" -- commitea "$D" "corrige

Cierra: R-I1.1"
copia f3 a02b; printf 'def resta(a, b):\n    return a - b\n' >> "$D/app.py"
espera falla "Ref: F1 con código se rechaza" "sin 'Ref: I<n>'" -- commitea "$D" "encuadre

Ref: F1"
copia f3 a02c; printf 'def resta(a, b):\n    return a - b\n' >> "$D/app.py"
trazabilidad "$D" "$C1_PEND" "" '| R-I1.1 | «sin-prueba» | I1 | C1 | falta prueba | resuelto | 2026-10-19 10:00 · abc1234 |'
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "Ref: I2 + Cierra: con recibo vigente se acepta" "" -- commitea "$D" "I2 «resta»

Ref: I2
Cierra: R-I1.1"
copia f3 a02d; echo "- nota" >> "$D/docs/MEMORIA.md"
espera pasa "solo rastro (docs/) con Ref: F1 se acepta" "" -- commitea "$D" "memoria

Ref: F1"

echo "== Recibos · caducado, FALLA, seguridad"
copia f3 r1; printf 'def resta(a, b):\n    return a - b\n' >> "$D/app.py"
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
printf '\n# cambio después del PASA\n' >> "$D/app.py"
espera falla "recibo caducado (huella distinta) se rechaza" "el contenido cambió después" -- commitea "$D" "I2

Ref: I2"
copia f3 r2; printf 'x = 1\n' >> "$D/app.py"
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
recibo "$D" juez-codigo incremento I2 FALLA 1 seguridad=no-aplica
espera falla "último veredicto FALLA se rechaza" "fue FALLA, no PASA" -- commitea "$D" "I2

Ref: I2"
copia f3 r3; printf 'x = 1\n' >> "$D/app.py"
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=requerida
espera falla "seguridad=requerida sin recibo del juez de seguridad se rechaza" "juez-seguridad" -- commitea "$D" "I2

Ref: I2"
copia f3 r3b; printf 'x = 1\n' >> "$D/app.py"
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=requerida
recibo "$D" juez-seguridad incremento I2 PASA 0
espera pasa "seguridad=requerida con recibo de seguridad se acepta" "" -- commitea "$D" "I2

Ref: I2"
copia f3 r4; sed -i.bak '/rol=juez-codigo/d' "$D/docs/revisiones.log"; rm -f "$D/docs/revisiones.log.bak"; echo "- nota" >> "$D/docs/MEMORIA.md"
espera falla "log reescrito (recibo borrado) se rechaza" "append-only" -- commitea "$D" "memoria

Ref: F1"
copia f3 r5
espera falla "log eliminado en F3 se rechaza" "elimina|falta docs/revisiones.log" -- sh -c 'cd "$1" && git rm -q docs/revisiones.log && git -c core.hooksPath=.githooks commit -q -m "x

Ref: F1"' sh "$D"
echo "== P09/P10 · fecha y bloqueantes"
copia f3 p9; printf 'fecha=ayer rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica huella=%s ejecutor=x\n' "$(huella_idx "$D")" >> "$D/docs/revisiones.log"
espera falla "fecha=ayer es inválida" "fecha debe ser ISO" -- en "$D" sh scripts/recibos.sh validar docs/revisiones.log
copia f3 p9b; printf 'fecha=2026-02-30 rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica huella=%s ejecutor=x\n' "$(huella_idx "$D")" >> "$D/docs/revisiones.log"
espera falla "fecha=2026-02-30 es inválida" "fecha debe ser ISO" -- en "$D" sh scripts/recibos.sh validar docs/revisiones.log
copia f3 p10; printf 'fecha=2026-10-19 rol=juez-codigo tipo=incremento alcance=I2 veredicto=FALLA bloqueantes=00 seguridad=no-aplica huella=%s ejecutor=x\n' "$(huella_idx "$D")" >> "$D/docs/revisiones.log"
espera falla "bloqueantes=00 es inválido" "bloqueantes debe ser" -- en "$D" sh scripts/recibos.sh validar docs/revisiones.log
copia f3 p10b; printf 'fecha=2026-10-19T23:59:59Z rol=juez-codigo tipo=incremento alcance=I2 veredicto=FALLA bloqueantes=12 seguridad=no-aplica huella=%s ejecutor=x\n' "$(huella_idx "$D")" >> "$D/docs/revisiones.log"
espera pasa "fecha ISO completa y bloqueantes=12 son válidos" "" -- en "$D" sh scripts/recibos.sh validar docs/revisiones.log

echo "== A04 · hallazgos abiertos del incremento"
copia f3 a04; printf 'x = 1\n' >> "$D/app.py"
trazabilidad "$D" "$C1_PEND" "" '| R-I2.1 | «sin-prueba» | I2 | C1 | falta prueba | abierto | — |'
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "Ref: I2 con R-I2.1 abierto se rechaza" "R-I2.1" -- commitea "$D" "I2

Ref: I2"
copia f3 a04b; printf 'x = 1\n' >> "$D/app.py"
trazabilidad "$D" "$C1_PEND" "" '| R-S2.1 | «inyeccion» | I2 | C1 | entrada sin validar | abierto | — |'
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "Ref: I2 con R-S2.1 abierto se rechaza" "R-S2.1" -- commitea "$D" "I2

Ref: I2"
copia f3 a04c; printf 'x = 1\n' >> "$D/app.py"
trazabilidad "$D" "$C1_PEND" "" '| R-I2.1 | «sin-prueba» | I2 | C1 | falta prueba | resuelto | 2026-10-19 10:00 · abc1234 |
| R-I3.1 | «otro» | I3 | C1 | de otro incremento | abierto | — |'
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "Ref: I2 con R-I2.1 resuelto y R-I3.1 (ajeno) abierto se acepta" "" -- commitea "$D" "I2

Ref: I2"

echo "== A03 · contador de hitos"
# Cierra I2 e I3 de verdad (commits), luego intenta I4 en distintas condiciones.
H="$W/etapas/f3-tres"; cp -R "$Q" "$H"
for i in 2 3; do
  printf 'y%s = %s\n' "$i" "$i" >> "$H/app.py"; recibo "$H" juez-codigo incremento I$i PASA 0 seguridad=no-aplica
  commitea "$H" "I$i

Ref: I$i" || die "no pude preparar la etapa de tres incrementos"
done
copia f3-tres h1; printf 'z = 4\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I4 PASA 0 seguridad=no-aplica
espera falla "cuarto incremento sin hito se rechaza" "hito" -- commitea "$D" "I4

Ref: I4"
copia f3-tres h2
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
espera pasa "commit del hito: Ref: hito:I1-I3 con recibo vigente" "" -- commitea "$D" "hito I1-I3

Ref: hito:I1-I3"
printf 'z = 4\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I4 PASA 0 seguridad=no-aplica
espera pasa "cuarto incremento tras hito válido (huella de un commit real) se acepta" "" -- commitea "$D" "I4

Ref: I4"
copia f3-tres h3
printf 'fecha=2026-10-19 rol=juez-conjunto tipo=hito alcance=hito:I1-I3 veredicto=PASA bloqueantes=0 seguridad=no-aplica huella=000000000000 ejecutor=x cubre=C1 excluye=ninguno componentes=app\n' >> "$D/docs/revisiones.log"
printf 'z = 4\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I4 PASA 0 seguridad=no-aplica
espera falla "hito con huella inventada no reinicia el contador" "no es la de ningún commit" -- commitea "$D" "I4

Ref: I4"
copia f3-tres h4
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=requerida cubre=C1 excluye=ninguno componentes=app
printf 'z = 4\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I4 PASA 0 seguridad=no-aplica
espera falla "hito con seguridad=requerida sin recibo de seguridad no cuenta" "hito" -- commitea "$D" "I4

Ref: I4"
copia f3-tres h5
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
recibo "$D" juez-conjunto hito hito:I1-I3 FALLA 2 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
printf 'z = 4\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I4 PASA 0 seguridad=no-aplica
espera falla "hito PASA seguido de FALLA no cuenta" "hito" -- commitea "$D" "I4

Ref: I4"
copia f3-tres h6; echo "- nota" >> "$D/docs/MEMORIA.md"
espera falla "Ref: hito sin recibo de hito se rechaza" "no hay recibo válido de juez-conjunto" -- commitea "$D" "hito

Ref: hito:I1-I3"

echo "== A05 · cierre: criterios, IDs"
# Etapa de cierre válida: C1 verificado, hallazgo verificado, ADR-000 fuera, F4 con conjunto.
Z="$W/etapas/cierre"; cp -R "$Q" "$Z"
trazabilidad "$Z" "$C1_VERIF" "" '| R-I1.1 | «sin-prueba» | I1 | C1 | falta prueba | verificado | 2026-10-19 10:00 · abc1234 |'
python3 - "$Z/docs/decisiones.md" <<'EOF'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'\n## ADR-000.*', '\n', s, flags=re.S); open(p,'w').write(s)
EOF
fase "$Z" F4 "— «ninguno»"
recibo "$Z" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
echo "== etapa: cierre"
espera pasa "cierre válido: Ref: F4 con todo verificado y conjunto PASA" "" -- commitea "$Z" "validación

Ref: F4"
copia cierre z1; sed -i.bak 's/^- C1:.*/- Objetivo: sumar/' "$D/docs/encuadre.md"; rm -f "$D/docs/encuadre.md.bak"
trazabilidad "$D" "" "" ""
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "cierre sin ningún criterio se rechaza" "ningún criterio" -- commitea "$D" "cierre

Ref: F5"
copia cierre z2; trazabilidad "$D" "$C1_VERIF
| C999 | «fantasma» | I1 | verificado | |" "" ""
espera falla "criterio huérfano C999 en trazabilidad se rechaza" "huérfano" -- commitea "$D" "docs

Ref: F1"
copia cierre z3; sed -i.bak 's/^- C1:/- **C1**:/' "$D/docs/encuadre.md"; rm -f "$D/docs/encuadre.md.bak"
espera falla "criterio en negrita (**C1**) se rechaza como formato no admitido" "fuera de la gramática" -- commitea "$D" "docs

Ref: F1"
copia cierre z4; trazabilidad "$D" "$C1_VERIF" "" '| R-I1_1 | «raro» | I1 | C1 | abierto escondido | abierto | — |'
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "ID con guion bajo (R-I1_1) se rechaza, no se omite" "fuera de la gramática" -- commitea "$D" "cierre

Ref: F5"
copia f2 z5
espera falla "fila de ejemplo de la plantilla con proyecto iniciado se rechaza" "fila de ejemplo" -- sh -c 'cd "$1" && printf "| R-I_._ | «…» | I_ | C_ | _…_ | abierto | — |\n" >> docs/trazabilidad.md && git add -A && git -c core.hooksPath=.githooks commit -q -m "x

Ref: F1"' sh "$D"
copia cierre z6; sed -i.bak 's/^- C1:.*/- C1:/' "$D/docs/encuadre.md"; rm -f "$D/docs/encuadre.md.bak"
espera falla "criterio sin enunciado con proyecto iniciado se rechaza" "sin enunciado" -- commitea "$D" "docs

Ref: F1"

echo "== A06 · roles y procedimiento obligatorios"
copia f3 a06; rm "$D/.claude/agents/juez-seguridad.md"
espera falla "quitar juez-seguridad.md se rechaza" "falta .claude/agents/juez-seguridad.md" -- commitea "$D" "docs

Ref: F1"
copia f3 a06b; rm -r "$D/.claude/skills/dirigiendo-revisiones"
espera falla "quitar dirigiendo-revisiones/ se rechaza" "falta .claude/skills/dirigiendo-revisiones" -- commitea "$D" "docs

Ref: F1"

echo "== A07 · YAML"
copia f3 a07; sed -i.bak 's/^description: .*/description: "Texto \\q raro"/' "$D/.claude/agents/juez-codigo.md"; rm -f "$D/.claude/agents/juez-codigo.md.bak"
espera falla "escape \\q en el frontmatter se rechaza" "escape inválido" -- commitea "$D" "docs

Ref: F1"
copia f3 a07b; sed -i.bak 's/^description: .*/description: "Dice \\"hola\\" y sigue"/' "$D/.claude/agents/juez-codigo.md"; rm -f "$D/.claude/agents/juez-codigo.md.bak"
espera pasa "comillas escapadas válidas se aceptan" "" -- commitea "$D" "docs

Ref: F1"

echo "== A08 · arnés de sabotaje"
S="$W/sab"; mkdir -p "$S/scripts"; en "$S" git init -q
printf '#!/bin/sh\nif [ -f gate.sh ]; then\n  exit 0\nfi\nexit 1\n' > "$S/gate.sh"; chmod +x "$S/gate.sh"
printf '#!/bin/sh\nsh ./gate.sh\n' > "$S/scripts/check.sh"
printf '[{"label":"sin-fi","file":"gate.sh","before":"fi\\n","after":"\\n"}]\n' > "$S/sin_fi.json"
printf '[{"label":"exit1","file":"gate.sh","before":"exit 0","after":"exit 1"}]\n' > "$S/exit1.json"
espera falla "mutante shell sin fi es INVALID (exit 2), no DIES" "INVALID" -- en "$S" python3 -I "$SAB" sin_fi.json
espera pasa "--suite ./gate.sh corre la copia mutada: DIES" "DIES" -- en "$S" python3 -I "$SAB" exit1.json --suite ./gate.sh

echo "== Recorrido F1→F5"
R="$W/recorrido"; cp -R "$Z" "$R"
fase "$R" F5 "— «ninguno»"
espera pasa "F5: Ref: F5 con el conjunto de F4 vigente" "" -- commitea "$R" "cierre

Ref: F5"
espera pasa "doctor en verde sobre el proyecto cerrado" "" -- en "$R" sh scripts/check_docs.sh
espera pasa "doctor en modo cierre sobre el proyecto cerrado" "" -- en "$R" sh scripts/check_docs.sh cierre

echo
echo "regresion: $((TOTAL-MAL))/$TOTAL casos en verde"
if [ "$MAL" -gt 0 ]; then echo "FALLARON:$FALLIDOS"; exit 1; fi
exit 0
