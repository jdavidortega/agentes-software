#!/bin/sh
# Regresión de los HOOKS y SCRIPTS de la plantilla (viene con ella; README §Enforcement).
# Crea repositorios temporales y comprueba cada regla con su caso NEGATIVO (el hook
# rechaza) y su caso POSITIVO (acepta). Sin red, sin credenciales, sin clientes de IA:
# solo git, sh, awk y python3. Corre en segundos. Se ejecuta antes de tocar un hook o un
# script de la plantilla, y en CI de cada proyecto.
#
#   sh scripts/pruebas/regresion.sh        → 0 si todos los casos pasan; 1 y la lista si no
#   sh scripts/pruebas/regresion.sh -v     → además imprime la salida de cada caso
#
# AUTOCONTENIDA: del repositorio donde corre toma SOLO la instrumentación del método
# (.githooks/, scripts/, .claude/, .codex/ si existe); los documentos del proyecto de prueba
# (docs/, encuadre, plan, trazabilidad, suite, código) los genera aquí. Así da el mismo
# resultado en la plantilla vacía y dentro de un proyecto con código, plan y hallazgos reales.
# Cada caso vive en una copia fresca de una ETAPA (plantilla; F2; F3 con I1; tres cerrados;
# cierre), así ningún caso contamina a otro.
VERBOSE=0; [ "${1:-}" = "-v" ] && VERBOSE=1
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
W=$(mktemp -d 2>/dev/null || mktemp -d -t regresion)
# Al salir, además de borrar $W, termina los PID que un caso dejó anotados en $W/pids (si falló).
trap 'find "$W/pids" -type f 2>/dev/null | while IFS= read -r f; do kill -9 "$(cat "$f")" 2>/dev/null; done; rm -rf "$W"' EXIT INT TERM
export GIT_AUTHOR_NAME=regresion GIT_AUTHOR_EMAIL=regresion@local
export GIT_COMMITTER_NAME=regresion GIT_COMMITTER_EMAIL=regresion@local
export GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_CONFIG_SYSTEM=/dev/null   # sin config del usuario
: > "$W/gitconfig"; git config --file "$W/gitconfig" --add safe.directory "*"
unset FASE_PREVIA REV SUITE_ID SUITE_REGISTRO SUITE_PLAZO SUITE_ENVUELTO SUITE_INFORME
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
  if [ "$ok" = 1 ]; then echo "  ok    $nombre"; else echo "  FALLO $nombre (esperaba $modo${patron:+ con «${patron}»}; rc=$rc)"; MAL=$((MAL+1)); FALLIDOS="$FALLIDOS
    - $nombre"; fi
  [ "$VERBOSE" = 1 ] || [ "$ok" = 0 ] && printf '%s\n' "$out" | sed 's/^/        | /' | head -12
  return 0
}
copia() { D="$W/$2"; rm -rf "$D"; cp -R "$W/etapas/$1" "$D"; }   # copia <etapa> <nombre> → $D
en() { d=$1; shift; ( cd "$d" && "$@" ); }                          # en <dir> cmd...
commitea() { en "$1" git add -A && en "$1" git -c core.hooksPath=.githooks commit -q -m "$2"; }
sin_hooks() { en "$1" git add -A && en "$1" git -c core.hooksPath=/dev/null commit -q --no-verify -m "$2"; }
huella_idx() { en "$1" git add -A >/dev/null 2>&1; en "$1" sh scripts/huella.sh indice; }
# recibo <dir> rol tipo alcance veredicto bloqueantes [campos extra...] → al log, con la huella del índice
# El recibo del juez de código sobre I<n> es el cierre del incremento: como haría el agente, deja
# la casilla en [x] y regenera estado.md ANTES de la huella (commit-msg los exige en Ref: I<n>).
recibo() {
  d=$1; rol=$2; tipo=$3; alc=$4; ver=$5; blo=$6; shift 6
  [ "$rol $tipo" = "juez-codigo incremento" ] && cierra_inc "$d" "$alc"
  h=$(huella_idx "$d")
  printf 'fecha=2026-10-19T10:00Z rol=%s tipo=%s alcance=%s veredicto=%s bloqueantes=%s huella=%s ejecutor=regresion %s\n' \
    "$rol" "$tipo" "$alc" "$ver" "$blo" "$h" "${MODALIDAD-modalidad=lectura filtro=comprobado aislamiento=ninguno} $*" >> "$d/docs/revisiones.log"
}
cierra_inc() {  # cierra_inc <dir> I<n> → casilla [x] y una línea en estado.md; idempotente
  grep -q "^- \[ \] $2 " "$1/docs/plan.md" 2>/dev/null || return 0
  sed -i.bak "s/^- \[ \] $2 /- [x] $2 /" "$1/docs/plan.md" && rm -f "$1/docs/plan.md.bak"
  printf -- '- Cerrado %s.\n' "$2" >> "$1/docs/estado.md"
}
# recibo_bruto <dir> <línea completa> → al log tal cual (huellas inventadas, etc.)
recibo_bruto() { printf '%s\n' "$2" >> "$1/docs/revisiones.log"; }
fase() {  # fase <dir> <F?> [incremento activo]
  python3 - "$1/docs/estado.md" "$2" "${3:-I_ «alias»}" <<'EOF'
import re,sys
p,f,i=sys.argv[1:]; s=open(p).read()
s=re.sub(r'^- \*\*Fase actual:\*\*.*$', f'- **Fase actual:** {f} · incremento activo: {i}', s, count=1, flags=re.M)
open(p,'w').write(s)
EOF
}
# trazabilidad <dir> "<filas C>" "<filas E>" "<filas R>" ["<histórico>"]: escribe el archivo entero
trazabilidad() {
  {
    printf '# Trazabilidad\n\n## IDs y cómo se enlazan\n\n- Ver docs/convenciones.md.\n\n## Cobertura de criterios\n\n'
    printf '| Criterio | Alias | Incremento(s) | Estado | Nota |\n|----------|-------|---------------|--------|------|\n'
    [ -n "$2" ] && printf '%s\n' "$2"
    printf '\n## Registro de vacíos del revisor funcional (arranque)\n\n'
    printf '| Vacío | Alias | Punto incumplido | Estado | Resuelto (cómo · AAAA-MM-DD HH:MM UTC) |\n|-------|-------|------------------|--------|----------------------------------------|\n'
    [ -n "$3" ] && printf '%s\n' "$3"
    printf '\n## Registro de revisiones del juez\n\n'
    printf '| Hallazgo | Alias | Incr. | Criterio | Descripción | Estado | Resuelto (AAAA-MM-DD HH:MM UTC · commit) |\n|----------|-------|-------|----------|-------------|--------|------------------------------------------|\n'
    [ -n "$4" ] && printf '%s\n' "$4"
    printf '\n## Histórico (compactado)\n\n'
    [ -n "${5:-}" ] && printf '%s\n' "$5"
  } > "$1/docs/trazabilidad.md"
}
C1_PEND='| C1 | «suma» | I1 | pendiente | |'
C1_VERIF='| C1 | «suma» | I1 | verificado | |'
SUITE='#!/bin/sh
# suite del proyecto demo: lo que diga app.py decide (un assert en rojo = commit rechazado)
if [ -f app.py ]; then python3 -I app.py || exit 1; fi
exit 0
'

# --- etapas ----------------------------------------------------------------------------
mkdir -p "$W/etapas"
B="$W/etapas/plantilla"; mkdir -p "$B"
# Instrumentación: SIEMPRE la de este repositorio (es lo que se prueba).
for d in .githooks scripts .claude .codex; do
  [ -d "$RAIZ/$d" ] && { mkdir -p "$B/$d" && cp -R "$RAIZ/$d/." "$B/$d/"; }
done
rm -rf "$B/scripts/__pycache__" "$B/scripts/check.sh"
# Documentos: los de la plantilla si este repositorio ES la plantilla sin iniciar (estado.md
# con F_), para probar también lo que viaja con ella; si no, un proyecto sintético mínimo.
PRISTINA=0; grep -q 'Fase actual:\*\* F_' "$RAIZ/docs/estado.md" 2>/dev/null && PRISTINA=1
if [ "$PRISTINA" -eq 1 ]; then
  for f in AGENTS.md CLAUDE.md README.md .gitignore .editorconfig; do [ -f "$RAIZ/$f" ] && cp "$RAIZ/$f" "$B/$f"; done
  mkdir -p "$B/docs" "$B/contexto"; cp -R "$RAIZ/docs/." "$B/docs/"; cp -R "$RAIZ/contexto/." "$B/contexto/"
else
  mkdir -p "$B/docs" "$B/contexto"
  printf '# AGENTS.md\n\nProyecto sintético de la regresión. Ver docs/.\n' > "$B/AGENTS.md"
  printf '# CLAUDE.md\n\n@AGENTS.md\n' > "$B/CLAUDE.md"
  printf '# Demo\n\nProyecto sintético de la regresión de la plantilla.\n' > "$B/README.md"
  printf '.env\n.env.*\n!.env.example\n__pycache__/\nmejoras/\n' > "$B/.gitignore"
  printf 'root = true\n' > "$B/.editorconfig"
  printf '# Contexto\n\nEntradas del proyecto (sintético).\n' > "$B/contexto/README.md"
  printf '# Estado del proyecto\n\n- **Fase actual:** F_ · incremento activo: I_ «alias»\n- **Próximo paso:** _…_\n' > "$B/docs/estado.md"
  printf '# Encuadre\n\n## Criterios de éxito\n\n- C1:\n' > "$B/docs/encuadre.md"
  printf '# Plan\n\n- [ ] I1 «…» — _…_ (satisface: C_)\n' > "$B/docs/plan.md"
  trazabilidad "$B" '| C1 | «…» | I_ | pendiente / cubierto / verificado | |' '| R-E._ | «…» | _…_ | abierto | — |' '| R-I_._ | «…» | I_ | C_ | _…_ | abierto | — |' '- _(ejemplo)_ `R-I_._ «alias» · verificado AAAA-MM-DD · commit abc1234`'
  for f in decisiones convenciones definicion-de-hecho despliegue MEMORIA; do printf '# %s\n\n(sintético)\n' "$f" > "$B/docs/$f.md"; done
  printf '# Registro de recibos (sintético). Las líneas que empiezan por # se ignoran.\n# contrato-recibos: 2\n' > "$B/docs/revisiones.log"
fi
rm -rf "$B/mejoras"
en "$B" git init -q && en "$B" git config core.hooksPath .githooks
chmod +x "$B"/.githooks/* "$B"/scripts/*.sh "$B"/scripts/pruebas/*.sh 2>/dev/null
en "$B" git add -A >/dev/null
for x in .githooks/pre-commit .githooks/commit-msg scripts/check_docs.sh scripts/huella.sh scripts/recibos.sh scripts/trazabilidad.sh scripts/guardas.sh; do
  en "$B" git update-index --chmod=+x "$x"
done
echo "== etapa: plantilla recién copiada ($([ "$PRISTINA" -eq 1 ] && echo 'documentos de la plantilla' || echo 'documentos sintéticos'))"
espera pasa "arranque nuevo: primer commit Ref: F1 sobre la plantilla" "" -- commitea "$B" "Encuadre inicial

Ref: F1"

# E1: F2 cerrado (encuadre + plan + trazabilidad sembrada + suite), listo para I1.
P="$W/etapas/f2"; cp -R "$B" "$P"
printf '# AGENTS.md\n\nProyecto Demo: sumar dos números. Ver docs/.\n' > "$P/AGENTS.md"
printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: la función suma devuelve a+b para enteros.\n' > "$P/docs/encuadre.md"
printf '# Plan\n\n- [ ] I1 «suma» — función suma (satisface: C1)\n- [ ] I2 «resta» — (satisface: C1)\n- [ ] I3 «multiplica» — (satisface: C1)\n- [ ] I4 «divide» — (satisface: C1)\n- [ ] I5 «potencia» — (satisface: C1)\n' > "$P/docs/plan.md"
printf '# Decisiones\n\n(ninguna todavía)\n' > "$P/docs/decisiones.md"
trazabilidad "$P" "$C1_PEND" "" ""
printf '%s' "$SUITE" > "$P/scripts/check.sh"
fase "$P" F2 "I1 «suma»"
recibo "$P" revisor-funcional encuadre F2 PASA 0
echo "== etapa: plan aprobado (F2)"
espera pasa "cierre del plan: Ref: F2 con recibo del revisor funcional vigente" "" -- commitea "$P" "Plan

Ref: F2"

# E2: I1 cerrado en F3 (app.py revisado por el juez).
Q="$W/etapas/f3"; cp -R "$P" "$Q"
fase "$Q" F3 "I1 «suma»"
printf 'def suma(a, b):\n    return a + b\n\nassert suma(1, 2) == 3\n' > "$Q/app.py"
recibo "$Q" juez-codigo incremento I1 PASA 0 seguridad=no-aplica
echo "== etapa: F3 con I1 cerrado"
espera pasa "I1: Ref: I1 con recibo del juez PASA sobre esta huella" "" -- commitea "$Q" "I1 «suma»: función suma

Ref: I1"

# E3: I1, I2, I3 cerrados (tres commits Ref: I), sin hito.
H="$W/etapas/f3-tres"; cp -R "$Q" "$H"
for i in 2 3; do
  printf 'y%s = %s\n' "$i" "$i" >> "$H/app.py"; recibo "$H" juez-codigo incremento I$i PASA 0 seguridad=no-aplica
  commitea "$H" "I$i

Ref: I$i" || die "no pude preparar la etapa de tres incrementos"
done

# E4: listo para cerrar: C1 verificado, hallazgo verificado, F4 con conjunto PASA.
Z="$W/etapas/cierre"; cp -R "$Q" "$Z"
printf '# Plan\n\n## Incrementos\n\n- [x] I1 «suma» — función suma (satisface: C1)\n\n## Fuera de alcance / backlog\n\n- resta, multiplica: fuera de este ciclo (ADR-001)\n' > "$Z/docs/plan.md"
printf '# Decisiones\n\n## ADR-001 — Alcance del primer ciclo\n\n- **Estado:** aceptada\n' > "$Z/docs/decisiones.md"
trazabilidad "$Z" "$C1_VERIF" "" '| R-I1.1 | «sin-prueba» | I1 | C1 | falta prueba | verificado | 2026-10-19 10:00 · app.py:1 |'
fase "$Z" F4 "— «ninguno»"
recibo "$Z" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
echo "== etapa: cierre"
espera pasa "cierre válido: Ref: F4 con todo verificado y conjunto PASA" "" -- commitea "$Z" "validación

Ref: F4"

# ======================================================================================
echo "== Suite del producto"
copia f3 s1; printf 'assert suma(2, 2) == 5\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "suite en rojo (assert falla) bloquea el commit aunque el recibo esté vigente" "check.sh falló" -- commitea "$D" "I2

Ref: I2"

echo "== Fase ilegible / registros / suite adquirida"
copia f3 a01; fase "$D" "F_"
espera falla "fase F_ con proyecto iniciado se rechaza" "no declara una fase legible" -- commitea "$D" "docs

Ref: I1"
copia f3 a01b; python3 - "$D/docs/estado.md" <<'EOF'
import sys; p=sys.argv[1]; open(p,'w').write(''.join(l for l in open(p) if 'Fase actual' not in l))
EOF
espera falla "fase ausente con proyecto iniciado se rechaza" "no declara una fase legible" -- commitea "$D" "docs

Ref: I1"
copia plantilla a01c
espera falla "F1: eliminar docs/revisiones.log se rechaza" "desaparece|append-only|falta docs/revisiones.log" -- sh -c 'cd "$1" && git rm -q docs/revisiones.log && git -c core.hooksPath=.githooks commit -q -m "limpia

Ref: F1"' sh "$D"
copia plantilla a01d; fase "$D" "F_"; echo "- nota" >> "$D/docs/MEMORIA.md"
espera pasa "plantilla sin iniciar: F_ sigue siendo modo plantilla" "" -- commitea "$D" "docs

Ref: F1"
copia plantilla a01e; fase "$D" "F1"
espera falla "F1: borrar scripts/recibos.sh se rechaza" "falta scripts/recibos.sh|no retrocede" -- sh -c 'cd "$1" && git add -A && git rm -q scripts/recibos.sh && git -c core.hooksPath=.githooks commit -q -m "x

Ref: F1"' sh "$D"
copia f3 a02; fase "$D" "F1"; echo "- reencuadre" >> "$D/docs/MEMORIA.md"
espera pasa "reencuadre: F3→F1 con la suite intacta se acepta" "" -- commitea "$D" "reencuadre

Ref: F1"
espera falla "tras el reencuadre, eliminar scripts/check.sh se rechaza (obligación adquirida)" "obligación adquirida" -- sh -c 'cd "$1" && git rm -q scripts/check.sh && git -c core.hooksPath=.githooks commit -q -m "sin suite

Ref: F1"' sh "$D"

echo "== Contrato revisado: el trabajo dependiente se ata al último Ref: F2, no a la fase"
reescribe_c1() { sed -i.bak 's/^- C1: .*/- C1: la función suma devuelve lo que sea./' "$1/docs/encuadre.md" && rm -f "$1/docs/encuadre.md.bak"; }
copia f3 cr1; printf -- '- C2: criterio colado.\n' >> "$D/docs/encuadre.md"; trazabilidad "$D" "$C1_PEND
| C2 | «colado» | I2 | pendiente | |" "" ""
espera pasa "borrador: añadir C2 con Ref: F1 se acepta (F1 edita el encuadre libremente)" "" -- commitea "$D" "C2

Ref: F1"
printf 'y2 = 2\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "Ref: I2 con un criterio que no está en el último contrato revisado se rechaza" "contrato revisado" -- commitea "$D" "I2

Ref: I2"
copia f3 cr2; reescribe_c1 "$D"; printf 'y2 = 2\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "reescribir C1 dentro del commit Ref: I2 se rechaza (el juez de código no juzga el encuadre)" "contrato revisado" -- commitea "$D" "I2

Ref: I2"
copia f3 cr3; fase "$D" F1 "I2 «resta»"; reescribe_c1 "$D"
commitea "$D" "reencuadre

Ref: F1" || die "no pude preparar el reencuadre"
printf 'y2 = 2\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "reencuadre F3→F1 que reescribe C1 y cierra Ref: I2 quedándose en F1 se rechaza" "contrato revisado" -- commitea "$D" "I2

Ref: I2"
copia f3 cr4; fase "$D" F1 "I2 «resta»"; reescribe_c1 "$D"
commitea "$D" "reencuadre

Ref: F1" || die "no pude preparar el reencuadre completo"
fase "$D" F2 "I2 «resta»"; recibo "$D" revisor-funcional encuadre reentrada:C1 PASA 0
espera pasa "reencuadre completo: Ref: F2 con recibo reentrada:C1 (solo cambió C1) se acepta" "" -- commitea "$D" "reentrada

Ref: F2"
fase "$D" F3 "I2 «resta»"; printf 'y2 = 2\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "tras el Ref: F2 nuevo, Ref: I2 con el contrato revisado se acepta" "" -- commitea "$D" "I2

Ref: I2"
copia f3 cr5; reescribe_c1 "$D"; printf -- '- C2: criterio nuevo.\n' >> "$D/docs/encuadre.md"; trazabilidad "$D" "$C1_PEND
| C2 | «nuevo» | I2 | pendiente | |" "" ""
recibo "$D" revisor-funcional encuadre reentrada:C1 PASA 0
espera falla "reentrada:C1 cuando también cambió C2 se rechaza (varios criterios ⇒ alcance F2)" "también cambió C2" -- commitea "$D" "reentrada parcial

Ref: F2"
copia f3 cr6; printf '\n## Set de oro\n\n- suma(1, 2) → 3\n' >> "$D/docs/encuadre.md"; printf 'y2 = 2\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "cambiar el set de oro dentro de Ref: I2 se rechaza" "contrato revisado" -- commitea "$D" "I2

Ref: I2"
copia f3 cr7; printf '\n## Set de oro\n\n- suma(1, 2) → 3\n' >> "$D/docs/encuadre.md"; recibo "$D" revisor-funcional encuadre reentrada:C1 PASA 0
espera pasa "reentrada:C1 con solo el set de oro cambiado se acepta" "" -- commitea "$D" "set de oro

Ref: F2"
copia f3 cr8; reescribe_c1 "$D"; printf 'y2 = 2\n' >> "$D/app.py"; cierra_inc "$D" I2
recibo "$D" revisor-funcional encuadre F2 PASA 0; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "Ref: F2 e I2 en el mismo commit, ambos recibos sobre el índice completo, se acepta" "" -- commitea "$D" "reentrada e I2

Ref: F2
Ref: I2"
copia f3 cr9; recibo "$D" revisor-funcional encuadre F2 PASA 0; reescribe_c1 "$D"; printf 'y2 = 2\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "Ref: F2 e I2 en el mismo commit con el recibo del revisor sobre una huella anterior se rechaza" "huella" -- commitea "$D" "reentrada e I2

Ref: F2
Ref: I2"
copia plantilla cr10; for f in AGENTS.md docs/encuadre.md docs/plan.md docs/trazabilidad.md docs/decisiones.md scripts/check.sh; do cp "$W/etapas/f2/$f" "$D/$f"; done
fase "$D" F3 "I1 «suma»"; printf 'def suma(a, b):\n    return a + b\n' > "$D/app.py"; recibo "$D" juez-codigo incremento I1 PASA 0 seguridad=no-aplica
espera falla "Ref: I1 sin ningún commit Ref: F2 en el historial se rechaza (sin plan aprobado no hay contrato)" "no hay ningún commit 'Ref: F2'" -- commitea "$D" "I1

Ref: I1"
copia f3 cr11; fase "$D" F5 "— «ninguno»"
espera falla "estado.md pasa a F5 con Ref: F1 (sin cierre) se rechaza" "entrar a la Fase 5" -- commitea "$D" "cierre fingido

Ref: F1"

echo "== Transiciones de trazabilidad: nada desaparece; resuelto|verificado con referencia que resuelve"
copia f3 hd1; trazabilidad "$D" "$C1_PEND" "" '| R-I2.1 | «bug» | I2 | C1 | falta prueba | abierto | — |'; sin_hooks "$D" "hallazgo abierto"
trazabilidad "$D" "$C1_PEND" "" ""; printf 'y2 = 2\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "un hallazgo abierto que desaparece de trazabilidad se rechaza" "desaparece" -- commitea "$D" "I2

Ref: I2"
sin_hooks "$D" "I2 colado

Ref: I2"
espera falla "validar_historial detecta la desaparición colada con --no-verify" "desaparece" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia f3 hd2; trazabilidad "$D" "$C1_PEND" "" '| R-I1.1 | «sin-prueba» | I1 | C1 | falta prueba | verificado | 2026-10-19 10:00 · app.py:1 |'; sin_hooks "$D" "verificado"
trazabilidad "$D" "$C1_PEND" "" "" "- \`R-I1.1 «sin-prueba» · verificado 2026-10-19 · commit $(en "$D" git rev-parse --short HEAD)\`"
espera pasa "un hallazgo verificado compactado al Histórico sigue existiendo: se acepta" "" -- commitea "$D" "compactación

Cierra: R-I1.1"
fila_res() { trazabilidad "$1" "$C1_PEND" "" "| R-I2.1 | «sin-prueba» | I2 | C1 | falta prueba | resuelto | $2 |"; printf 'y2 = 2\n' >> "$1/app.py"; recibo "$1" juez-codigo incremento I2 PASA 0 seguridad=no-aplica; }
copia f3 rf1; fila_res "$D" "2026-10-19 10:00"
espera falla "resuelto con solo una fecha (sin referencia) se rechaza" "referencia que resuelva" -- commitea "$D" "I2

Ref: I2"
copia f3 rf2; fila_res "$D" "2026-10-19 10:00 · app.py:3 (assert)"
espera pasa "resuelto con una ruta existente del índice (app.py:3) se acepta" "" -- commitea "$D" "I2

Ref: I2"
copia f3 rf3; fila_res "$D" "2026-10-19 10:00 · $(en "$D" git rev-parse --short HEAD)"
espera pasa "resuelto con un commit del historial se acepta" "" -- commitea "$D" "I2

Ref: I2"
copia f3 rf4; fila_res "$D" "2026-10-19 10:00 · abc1234"
espera falla "resuelto con un sha que no está en el historial se rechaza" "referencia que resuelva" -- commitea "$D" "I2

Ref: I2"
copia f3 rf5; fila_res "$D" "2026-10-19 10:00 · tests/no_existe.py:1"
espera falla "resuelto con una ruta que no está en el índice se rechaza" "referencia que resuelva" -- commitea "$D" "I2

Ref: I2"
copia f3 rf6; trazabilidad "$D" "$C1_PEND" "" '| R-I1.1 | «sin-prueba» | I1 | C1 | falta prueba | resuelto | 2026-10-19 10:00 |'; sin_hooks "$D" "resuelto sin referencia (histórico)"
printf 'y2 = 2\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "una fila ya resuelta en HEAD (sin transición) no se reevalúa" "" -- commitea "$D" "I2

Ref: I2"
copia f3 rf7; trazabilidad "$D" "$C1_PEND" "" '| R-I1.1 | «sin-prueba» | I1 | C1 | falta prueba | resuelto | — |'
espera falla "el doctor rechaza resuelto con la columna Resuelto vacía" "columna Resuelto vacía" -- en "$D" sh scripts/check_docs.sh

echo "== Criterio en una línea; merges limpios y las invariantes del resultado"
copia f3 cc1; printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: la función suma devuelve a+b para enteros.\n  Las entradas inválidas se rechazan.\n' > "$D/docs/encuadre.md"
espera falla "el doctor rechaza un criterio con texto de continuación (sangrado)" "continuación" -- en "$D" sh scripts/check_docs.sh
copia f3 cc1b; printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: la función suma devuelve a+b para enteros.\nLas entradas inválidas se rechazan.\n' > "$D/docs/encuadre.md"
espera falla "el doctor rechaza un criterio con continuación perezosa (sin sangría)" "continuación" -- en "$D" sh scripts/check_docs.sh
copia f3 cc2; printf '# Encuadre\n\n## Criterios de éxito\n\n<!-- nota -->\n- C1: la función suma devuelve a+b para enteros.\n- C2: resta devuelve a-b.\n\n## Set de oro\n\n- par\n' > "$D/docs/encuadre.md"; trazabilidad "$D" "$C1_PEND
| C2 | «resta» | I2 | pendiente | |" "" ""
espera pasa "criterios de una línea seguidos de otro ítem, blanco, comentario o encabezado pasan el doctor" "" -- en "$D" sh scripts/check_docs.sh
copia f3 cc3; printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: la función suma devuelve a+b para enteros.\n\n  Las entradas inválidas se rechazan.\n' > "$D/docs/encuadre.md"
espera falla "el doctor rechaza un párrafo sangrado tras una línea blanca (sigue siendo del criterio)" "continuación" -- en "$D" sh scripts/check_docs.sh
espera falla "el pre-commit rechaza ese criterio con párrafo tras blanco (Ref: F1)" "continuación" -- commitea "$D" "criterio con párrafo

Ref: F1"
sin_hooks "$D" "criterio con párrafo colado

Ref: F1"
espera falla "validar_historial rechaza el criterio con párrafo tras blanco colado con --no-verify" "continuación" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia f3 cc4; printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: la función suma devuelve a+b para enteros.\n\n- C2: resta devuelve a-b.\n\n\n## Set de oro\n\nTexto del set en la columna 1.\n' > "$D/docs/encuadre.md"; trazabilidad "$D" "$C1_PEND
| C2 | «resta» | I2 | pendiente | |" "" ""
espera pasa "blancos antes del siguiente criterio, del encabezado o de un párrafo en la columna 1 pasan el doctor" "" -- en "$D" sh scripts/check_docs.sh
rama_cierre() {  # rama_cierre <dir>: la rama cierra en F5; la principal cambia el README. Deja HEAD en la principal.
  RAMA0=$(en "$1" git rev-parse --abbrev-ref HEAD)
  en "$1" git checkout -q -b cierre-rama; fase "$1" F5 "— «ninguno»"
  commitea "$1" "cierre

Ref: F5" || die "no pude cerrar la rama en F5"
  en "$1" git checkout -q "$RAMA0"; printf '\nnota\n' >> "$1/README.md"
  commitea "$1" "readme

Ref: F1" || die "no pude cambiar la principal"
}
copia cierre mg1; rama_cierre "$D"
espera falla "merge limpio que lleva estado.md a F5 sin Ref: F5 se rechaza (el recibo del conjunto es de otro árbol)" "entrar a la Fase 5" -- en "$D" git -c core.hooksPath=.githooks merge -q --no-ff --no-edit cierre-rama
en "$D" git merge --abort >/dev/null 2>&1 || true
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-edit cierre-rama || die "no pude colar el merge del cierre"
espera falla "validar_historial rechaza ese merge colado con --no-verify" "entrar a la Fase 5" -- en "$D" sh scripts/pruebas/validar_historial.sh "HEAD~1..HEAD"
copia cierre mg2; rama_cierre "$D"
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-commit cierre-rama >/dev/null 2>&1 || die "no pude preparar el merge con recibo"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica; en "$D" git add -A
espera pasa "merge que integra el cierre con Ref: F5 y recibo del conjunto sobre el árbol integrado se acepta" "" -- en "$D" git -c core.hooksPath=.githooks commit -q -m "integra el cierre

Ref: F5"
copia cierre mg3; RAMA0=$(en "$D" git rev-parse --abbrev-ref HEAD); en "$D" git checkout -q -b notas; printf -- '- nota de la rama\n' >> "$D/docs/MEMORIA.md"
commitea "$D" "nota

Ref: F1" || die "no pude preparar la rama de notas"
en "$D" git checkout -q "$RAMA0"; printf '\nnota\n' >> "$D/README.md"; commitea "$D" "readme

Ref: F1" || die "no pude cambiar la principal (mg3)"
espera pasa "merge limpio que no entra a F5 ni pierde hallazgos sigue aceptándose sin trailer" "" -- en "$D" git -c core.hooksPath=.githooks merge -q --no-ff --no-edit notas

echo "== Contrato de recibos: modalidad declarada y marcador"
incompleto() { MODALIDAD=""; recibo "$@"; unset MODALIDAD; }   # recibo sin modalidad/filtro/aislamiento
sin_marcador() {  # sin_marcador <dir> [quitar-campos]: registro de una versión anterior (base sin marcador)
  grep -v '^# contrato-recibos: 2' "$1/docs/revisiones.log" > "$1/docs/revisiones.log.t"
  [ -n "${2:-}" ] && sed -i.bak -E 's/ modalidad=[^ ]+ filtro=[^ ]+ aislamiento=[^ ]+//' "$1/docs/revisiones.log.t" && rm -f "$1/docs/revisiones.log.t.bak"
  mv "$1/docs/revisiones.log.t" "$1/docs/revisiones.log"
  sin_hooks "$1" "registro de una versión anterior (preparación)" || die "no pude preparar el registro sin marcador"
}
nota() { printf -- '- nota %s\n' "$2" >> "$1/docs/MEMORIA.md"; }
copia f3 rc1; sin_marcador "$D"
printf 'y2 = 2\n' >> "$D/app.py"; incompleto "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "proyecto nuevo sin marcador: un recibo incompleto se rechaza" "sin modalidad=" -- commitea "$D" "I2

Ref: I2"
copia f3 rc2; sin_marcador "$D"
printf 'y2 = 2\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "proyecto nuevo sin marcador: un recibo completo se acepta" "" -- commitea "$D" "I2

Ref: I2"
copia f3 rc3; sin_marcador "$D" quitar; nota "$D" 1
espera falla "registro anterior (recibos sin campos, sin marcador): se bloquea y dice cómo migrar" "añade al FINAL del registro" -- commitea "$D" "nota

Ref: F1"
printf '# contrato-recibos: 2\n' >> "$D/docs/revisiones.log"
espera pasa "tras añadir el marcador al final, los recibos anteriores quedan históricos y se acepta" "" -- commitea "$D" "migra el registro de recibos

Ref: F1"
printf 'y2 = 2\n' >> "$D/app.py"; incompleto "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "después de migrar, un recibo nuevo incompleto se rechaza" "sin modalidad=" -- commitea "$D" "I2

Ref: I2"
copia f3 rc4; sin_marcador "$D" quitar
printf 'y2 = 2\n' >> "$D/app.py"; incompleto "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica; printf '# contrato-recibos: 2\n' >> "$D/docs/revisiones.log"
espera falla "un recibo nuevo incompleto ANTES del marcador añadido en el mismo commit se rechaza" "aunque quede antes del marcador" -- commitea "$D" "I2

Ref: I2"
copia f3 rc5; printf 'y2 = 2\n' >> "$D/app.py"; cierra_inc "$D" I2
recibo_bruto "$D" "fecha=2020-01-02 rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica huella=$(huella_idx "$D") ejecutor=x"
espera falla "un recibo nuevo incompleto con fecha antigua se rechaza" "sin modalidad=" -- commitea "$D" "I2

Ref: I2"
copia f3 rc5b; incompleto "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "el doctor de inicio de sesión rechaza un recibo sin campos posterior al marcador" "posterior al marcador" -- en "$D" sh scripts/check_docs.sh
copia f3 rc6; printf '# contrato-recibos: 2\n' >> "$D/docs/revisiones.log"; nota "$D" 6
espera falla "marcador duplicado se rechaza" "repetido" -- commitea "$D" "nota

Ref: F1"
copia f3 rc7; grep -v '^# contrato-recibos: 2' "$D/docs/revisiones.log" > "$D/l"; printf '# contrato-recibos: 2\n' >> "$D/l"; mv "$D/l" "$D/docs/revisiones.log"; nota "$D" 7
espera falla "marcador movido (al final) se rechaza" "append-only" -- commitea "$D" "nota

Ref: F1"
copia f3 rc8; grep -v '^# contrato-recibos: 2' "$D/docs/revisiones.log" > "$D/l"; mv "$D/l" "$D/docs/revisiones.log"; nota "$D" 8
espera falla "marcador eliminado se rechaza" "append-only" -- commitea "$D" "nota

Ref: F1"
copia f3 rc9; printf 'y2 = 2\n' >> "$D/app.py"; MODALIDAD="modalidad=otra filtro=comprobado aislamiento=ninguno"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica; unset MODALIDAD
espera falla "modalidad fuera del enum se rechaza" "modalidad debe ser" -- commitea "$D" "I2

Ref: I2"
copia f3 rc10; printf 'y2 = 2\n' >> "$D/app.py"; MODALIDAD="modalidad=lectura filtro=comprobado"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica; unset MODALIDAD
espera falla "solo dos de los tres campos: el parser lo rechaza" "van los tres juntos" -- en "$D" sh scripts/recibos.sh validar docs/revisiones.log
espera falla "solo dos de los tres campos: el commit lo rechaza" "sin modalidad=" -- commitea "$D" "I2

Ref: I2"

echo "== Evidencia de una revisión: guardarla permite cerrar; cambiarla después se detecta"
# Flujo real: el revisor calcula la huella sobre su directorio autorizado; el principal la copia
# a docs/revisiones/<id>/ DESPUÉS del recibo (fuera de la huella de vigencia).
evid() {  # evid <dir> <id> → deja la fuente en $W/evsrc-<id> e imprime su huella
  mkdir -p "$W/evsrc-$2"; printf 'salida del experimento %s\n' "$2" > "$W/evsrc-$2/salida.txt"
  en "$1" sh scripts/huella.sh evidencia "$W/evsrc-$2"
}
copia f3 ev1; printf 'y2 = 2\n' >> "$D/app.py"; h=$(evid "$D" I2-juez-codigo-1)
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica evidencia=docs/revisiones/I2-juez-codigo-1@$h
mkdir -p "$D/docs/revisiones"; cp -R "$W/evsrc-I2-juez-codigo-1" "$D/docs/revisiones/I2-juez-codigo-1"
espera pasa "evidencia copiada a docs/revisiones/ después del PASA: Ref: I2 se acepta (no caduca el recibo)" "" -- commitea "$D" "I2

Ref: I2"
rm -rf "$W/etapas/con-evidencia"; cp -R "$D" "$W/etapas/con-evidencia"
copia con-evidencia ev2; printf 'retocada\n' >> "$D/docs/revisiones/I2-juez-codigo-1/salida.txt"
espera falla "modificar la evidencia ya registrada se rechaza" "cambió después de registrarse" -- commitea "$D" "retoca evidencia

Ref: F1"
sin_hooks "$D" "retoca evidencia colada

Ref: F1"
espera falla "validar_historial rechaza la evidencia modificada colada con --no-verify" "cambió después de registrarse" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia con-evidencia ev3; rm -rf "$D/docs/revisiones/I2-juez-codigo-1"
espera falla "borrar la evidencia ya registrada se rechaza" "no existe en lo que se guarda" -- commitea "$D" "borra evidencia

Ref: F1"
copia con-evidencia ev3b; printf 'nuevo\n' > "$D/docs/revisiones/I2-juez-codigo-1/otro.txt"
espera falla "añadir un archivo a la evidencia ya registrada se rechaza" "cambió después de registrarse" -- commitea "$D" "añade a la evidencia

Ref: F1"
copia f3 ev4; printf 'y2 = 2\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
mkdir -p "$D/contexto/exploracion"; printf 'salida\n' > "$D/contexto/exploracion/evidencia-I2.txt"
espera falla "contraste: la misma evidencia en contexto/ después del PASA caduca el recibo" "el contenido cambió después de la revisión" -- commitea "$D" "I2

Ref: I2"
copia f3 ev5; printf 'y2 = 2\n' >> "$D/app.py"; h=$(evid "$D" I2-mal)
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica evidencia=docs/revisiones/I2-mal@000000000000
mkdir -p "$D/docs/revisiones"; cp -R "$W/evsrc-I2-mal" "$D/docs/revisiones/I2-mal"
espera falla "evidencia recién registrada con huella incorrecta se rechaza" "cambió después de registrarse" -- commitea "$D" "I2

Ref: I2"
copia f3 ev6; printf 'y2 = 2\n' >> "$D/app.py"; h=$(evid "$D" I2-falta)
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica evidencia=docs/revisiones/I2-falta@$h
espera falla "evidencia registrada que no se copió se rechaza" "no existe en lo que se guarda" -- commitea "$D" "I2

Ref: I2"
copia f3 ev7; mkdir -p "$D/docs/revisiones/huerfana"; printf 'x\n' > "$D/docs/revisiones/huerfana/a.txt"
espera falla "el doctor rechaza una carpeta de evidencia que ningún recibo registra" "no la registra ningún recibo" -- en "$D" sh scripts/check_docs.sh
copia f3 ev8; mkdir -p "$W/evsrc-enlace"; ln -s /etc/hosts "$W/evsrc-enlace/h"
espera falla "huella.sh evidencia rechaza enlaces simbólicos" "enlaces simbólicos" -- en "$D" sh scripts/huella.sh evidencia "$W/evsrc-enlace"

echo "== Separadores y carpetas ocultas en la evidencia"
copia f3 tb1; printf 'y2 = 2\n' >> "$D/app.py"; cierra_inc "$D" I2
recibo_bruto "$D" "$(printf 'fecha=2026-10-19T10:00Z rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica huella=%s ejecutor=x modalidad=lectura filtro=comprobado aislamiento=ninguno\tevidencia=docs/revisiones/no-existe@0123456789ab' "$(huella_idx "$D")")"
en "$D" git add -A
espera falla "un tabulador entre campos: la guarda de evidencia lee igual y la rechaza" "no existe en lo que se guarda" -- en "$D" sh scripts/guardas.sh HEAD INDICE
espera falla "un tabulador entre campos: el parser lo rechaza" "separador no admitido" -- en "$D" sh scripts/recibos.sh validar docs/revisiones.log
espera falla "un tabulador entre campos se rechaza (evidencia inexistente no se cuela)" "separador no admitido|no existe en lo que se guarda" -- commitea "$D" "I2

Ref: I2"
sin_hooks "$D" "I2 colado

Ref: I2"
espera falla "validar_historial rechaza el recibo con tabulador colado" "separador no admitido|no existe en lo que se guarda" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia f3 tb2; mkdir -p "$D/docs/revisiones/.huerfana"; printf 'x\n' > "$D/docs/revisiones/.huerfana/salida.txt"
espera falla "el doctor rechaza una carpeta oculta en docs/revisiones/" "entrada oculta" -- en "$D" sh scripts/check_docs.sh
espera falla "el commit rechaza la carpeta oculta" "entrada oculta" -- commitea "$D" "oculta

Ref: F1"
sin_hooks "$D" "oculta colada

Ref: F1"
espera falla "validar_historial rechaza la carpeta oculta colada" "entrada oculta" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia f3 tb3; printf 'y2 = 2\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica evidencia=docs/revisiones/.oculta@0123456789ab
espera falla "un id de evidencia que empieza por punto se rechaza" "empieza por letra o número" -- en "$D" sh scripts/recibos.sh validar docs/revisiones.log

echo "== Migración del registro: el historial hecho con la versión anterior sigue validando"
antigua() {  # simula el scripts/recibos.sh de una versión anterior: no conoce el marcador ni exige los campos
  sed -e 's/contrato-recibos: 2/contrato-recibos-anterior/g' -e 's/if (nm==0 \&\& marca \&\& !previo) ok=bad(/if (0) ok=bad(/' -e 's/if (nm==0 \&\& !hm \&\& !previo) ok=bad(/if (0) ok=bad(/' "$1/scripts/recibos.sh" > "$1/scripts/recibos.sh.t" && mv "$1/scripts/recibos.sh.t" "$1/scripts/recibos.sh"
}
registro_anterior() {  # sin marcador y sin los tres campos
  grep -v '^# contrato-recibos: 2' "$1/docs/revisiones.log" | sed -E 's/ modalidad=[^ ]+ filtro=[^ ]+ aislamiento=[^ ]+//' > "$1/l" && mv "$1/l" "$1/docs/revisiones.log"
}
M="$W/mig"; rm -rf "$M"; mkdir -p "$M"; ( cd "$W/etapas/f3" && tar cf - --exclude ./.git . ) | ( cd "$M" && tar xf - )
antigua "$M"; registro_anterior "$M"; en "$M" git init -q; en "$M" git config core.hooksPath .githooks
sin_hooks "$M" "Plan con la versión anterior

Ref: F2" || die "no pude preparar el proyecto con la versión anterior"
INI=$(en "$M" git rev-parse HEAD)
printf 'y2 = 2\n' >> "$M/app.py"; incompleto "$M" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
sin_hooks "$M" "I2 (hooks de la versión anterior)

Ref: I2" || die "no pude preparar I2 con la versión anterior"
espera pasa "antes de migrar: el replay acepta el historial hecho con la versión anterior" "1/1 commits cumplen" -- en "$M" sh scripts/pruebas/validar_historial.sh "$INI..HEAD"
cp "$W/etapas/f3/scripts/recibos.sh" "$M/scripts/recibos.sh"; printf '# contrato-recibos: 2\n' >> "$M/docs/revisiones.log"
espera pasa "migración: actualizar recibos.sh y añadir el marcador al final se acepta" "" -- commitea "$M" "actualiza la instrumentación y migra el registro

Ref: F1"
espera pasa "después de migrar: el replay del historial completo sigue aceptándolo" "2/2 commits cumplen" -- en "$M" sh scripts/pruebas/validar_historial.sh "$INI..HEAD"
rm -rf "$W/etapas/migrado"; cp -R "$M" "$W/etapas/migrado"
copia migrado mg4; incompleto "$D" juez-codigo incremento I3 PASA 0 seguridad=no-aplica; sin_hooks "$D" "recibo incompleto colado

Ref: F1"
espera falla "después de migrar: un recibo incompleto colado lo rechaza el replay" "sin modalidad=" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia migrado mg5; antigua "$D"; printf -- '- nota\n' >> "$D/docs/MEMORIA.md"
espera falla "la instrumentación del contrato de recibos no retrocede (commit)" "no retrocede" -- commitea "$D" "vuelve a la versión anterior

Ref: F1"
sin_hooks "$D" "retroceso colado

Ref: F1"
espera falla "la instrumentación no retrocede (replay)" "no retrocede" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD

echo "== La excepción histórica no sale del entorno ni de un padre antiguo"
con_previo() { ( export RECIBOS_CONTRATO_PREVIO=1; "$@" ); }
copia f3 vp1; printf 'y2 = 2\n' >> "$D/app.py"; incompleto "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "con RECIBOS_CONTRATO_PREVIO=1 heredado, el commit local sigue rechazando un recibo incompleto" "sin modalidad=" -- con_previo commitea "$D" "I2

Ref: I2"
espera falla "con la variable heredada, el doctor sigue rechazando el recibo incompleto" "posterior al marcador" -- con_previo en "$D" sh scripts/check_docs.sh
copia f3 vp2; sin_marcador "$D" quitar
printf 'y2 = 2\n' >> "$D/app.py"; incompleto "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica; printf '# contrato-recibos: 2\n' >> "$D/docs/revisiones.log"
espera falla "con la variable heredada, un recibo incompleto antes del marcador al migrar sigue rechazado (solo la guarda lo ve)" "aunque quede antes del marcador" -- con_previo commitea "$D" "I2 y migración

Ref: I2"
fusion_antigua() {  # fusion_antigua <dir>: rama 'antigua' desde el commit previo a la migración, con un commit propio
  RAMA0=$(en "$1" git rev-parse --abbrev-ref HEAD)
  en "$1" git checkout -q -b antigua HEAD~1 || die "no pude crear la rama antigua"
  printf -- '- nota de la rama antigua\n' >> "$1/docs/MEMORIA.md"
  sin_hooks "$1" "nota (rama con la versión anterior)

Ref: F1" || die "no pude commitear en la rama antigua"
}
copia migrado mf1; fusion_antigua "$D"
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-commit "$RAMA0" >/dev/null 2>&1; en "$D" git checkout -q HEAD -- scripts/recibos.sh
espera falla "merge sobre la rama antigua que conserva su recibos.sh (otro padre ya migró) se rechaza" "no retrocede" -- en "$D" git -c core.hooksPath=.githooks commit -q -m "integra la migración conservando el parser anterior

Ref: F1"
en "$D" git -c core.hooksPath=/dev/null commit -q --no-verify -m "integra colado

Ref: F1" || die "no pude colar el merge"
espera falla "validar_historial rechaza ese merge colado" "no retrocede" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia migrado mf2; fusion_antigua "$D"
espera pasa "merge limpio que conserva la versión migrada se acepta" "" -- en "$D" git -c core.hooksPath=.githooks merge -q --no-ff --no-edit "$RAMA0"
incompleto "$D" juez-codigo incremento I3 PASA 0 seguridad=no-aplica; sin_hooks "$D" "recibo incompleto colado tras la fusión

Ref: F1"
espera falla "tras ese merge, un recibo incompleto colado lo rechaza el replay" "sin modalidad=" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD

echo "== Suite sobre una instantánea de lo que se commitea (repositorio git temporal propio)"
suite_es() { printf '#!/bin/sh\n%s\n' "$2" > "$1/scripts/check.sh"; sin_hooks "$1" "suite (preparación)

Ref: F1" || die "no pude preparar la suite"; }
externa() { printf '\n| Ruta | Propósito | Cómo se reproduce |\n|------|-----------|-------------------|\n| %s | prueba | regresión |\n' "$2" >> "$1/docs/convenciones.md"; }
nota_f1() { printf -- '- nota %s\n' "$2" >> "$1/docs/MEMORIA.md"; commitea "$1" "nota

Ref: F1"; }
copia f3 su1; suite_es "$D" 'python3 app.py || exit 1'
printf 'local_dep.py\n' >> "$D/.gitignore"; printf 'VALOR = 3\n' > "$D/local_dep.py"; printf 'from local_dep import VALOR\nassert VALOR == 3\n' >> "$D/app.py"
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "la suite no se sostiene con un archivo ignorado que no se commitea (corre en la instantánea)" "sobre la instantánea" -- commitea "$D" "I2

Ref: I2"
copia f3 su2; suite_es "$D" 'PYTHONPATH=deps python3 app.py || exit 1'
mkdir -p "$D/deps"; printf 'VALOR = 3\n' > "$D/deps/local_dep.py"; printf 'deps/\n' >> "$D/.gitignore"; externa "$D" deps
printf 'from local_dep import VALOR\nassert VALOR == 3\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "una carpeta ignorada DECLARADA como entrada externa sostiene la suite" "" -- commitea "$D" "I2

Ref: I2"
copia f3 su3; printf 'local_dep.py\n' >> "$D/.gitignore"; printf 'VALOR = 3\n' > "$D/local_dep.py"; externa "$D" local_dep.py
espera falla "declarar un archivo suelto como entrada externa se rechaza" "no es una carpeta" -- nota_f1 "$D" 3
copia f3 su4; externa "$D" docs
espera falla "declarar una carpeta versionada como entrada externa se rechaza" "no está ignorada" -- nota_f1 "$D" 4
copia f3 su5; suite_es "$D" 'printf x >> README.md; touch -r docs/plan.md README.md'
espera falla "una suite que reescribe un archivo versionado (restaurando su fecha) se rechaza" "README.md \(contenido\)" -- nota_f1 "$D" 5
copia f3 su6; suite_es "$D" 'chmod +x README.md'
espera falla "una suite que cambia el modo de un archivo versionado se rechaza" "README.md \(modo\)" -- nota_f1 "$D" 6
copia f3 su7; suite_es "$D" 'rm -f README.md'
espera falla "una suite que borra un archivo versionado se rechaza" "README.md \(borrado\)" -- nota_f1 "$D" 7
copia f3 su8; suite_es "$D" 'mkdir -p __pycache__ && echo x > __pycache__/a.pyc && echo y > salida-suite.txt'
espera pasa "una suite que solo escribe archivos no versionados se acepta" "" -- nota_f1 "$D" 8
copia f3 su9; suite_es "$D" 'git tag suite-t && git config user.name intruso-suite'
espera pasa "una suite que crea una etiqueta y cambia la config de git se acepta (solo toca su repositorio)" "" -- nota_f1 "$D" 9
espera falla "... y la etiqueta no aparece en el repositorio original" "" -- en "$D" git rev-parse -q --verify refs/tags/suite-t
espera pasa "... y la configuración del original no cambia" "" -- sh -c "[ \"\$(git -C '$D' config user.name)\" != intruso-suite ]"
copia f3 su10; suite_es "$D" 'grep -q "cambio staged" README.md && git show HEAD:README.md | cmp -s - README.md && [ -z "$(git status --porcelain --untracked-files=no)" ]'
printf '\ncambio staged\n' >> "$D/README.md"
espera pasa "en la instantánea, HEAD, índice y archivos son el candidato (README cambiado y staged)" "" -- nota_f1 "$D" 10
copia f3 su11; mkdir -p "$D/deps"; printf '%s\n' "$(cd "$D" && pwd -P)" > "$D/deps/editable.pth"; printf 'deps/\n' >> "$D/.gitignore"; externa "$D" deps
espera falla "una entrada externa con una instalación editable hacia el repositorio se rechaza" "apunta al árbol original" -- nota_f1 "$D" 11
copia f3 su12; mkdir -p "$D/node_modules" "$D/docs/paq"; printf 'x\n' > "$D/docs/paq/i.md"; ln -s "$(cd "$D" && pwd -P)/docs/paq" "$D/node_modules/p"; printf 'node_modules/\n' >> "$D/.gitignore"; externa "$D" node_modules
espera falla "una entrada externa con un enlace hacia el repositorio se rechaza" "enlace hacia el árbol original" -- nota_f1 "$D" 12
# Segunda pasada de T2: worktree enlazado (variables locales de git), nombres especiales, cambio de tipo.
estado_original() { printf '%s %s %s\n' "$(en "$1" git rev-parse HEAD)" "$(en "$1" git config user.name || echo -)" "$(en "$1" git tag | tr '\n' ',')"; }
copia f3 wt1; suite_es "$D" 'git tag suite-wt && git config user.name intruso-wt'; ANTES_WT=$(estado_original "$D")
en "$D" git worktree add -q --detach "$W/wt1-arbol" || die "no pude crear el worktree"
printf -- '- nota\n' >> "$W/wt1-arbol/docs/MEMORIA.md"
espera pasa "worktree enlazado: el commit con una suite que etiqueta y configura se acepta" "" -- commitea "$W/wt1-arbol" "nota

Ref: F1"
espera pasa "... y HEAD, configuración y etiquetas del repositorio original no cambian" "" -- sh -c "[ \"\$1\" = \"\$(cd \"\$2\" && printf '%s %s %s\\n' \"\$(git rev-parse HEAD)\" \"\$(git config user.name || echo -)\" \"\$(git tag | tr '\\n' ',')\")\" ]" sh "$ANTES_WT" "$D"
copia f3 wt2; suite_es "$D" 'git tag suite-wt2; git config user.name intruso-wt2; exit 1'; ANTES_WT=$(estado_original "$D")
en "$D" git worktree add -q --detach "$W/wt2-arbol" || die "no pude crear el worktree (2)"
printf -- '- nota\n' >> "$W/wt2-arbol/docs/MEMORIA.md"
espera falla "worktree enlazado: una suite que falla rechaza el commit" "falló" -- commitea "$W/wt2-arbol" "nota

Ref: F1"
espera pasa "... y aun así el repositorio original queda intacto (HEAD, config, etiquetas)" "" -- sh -c "[ \"\$1\" = \"\$(cd \"\$2\" && printf '%s %s %s\\n' \"\$(git rev-parse HEAD)\" \"\$(git config user.name || echo -)\" \"\$(git tag | tr '\\n' ',')\")\" ]" sh "$ANTES_WT" "$D"
copia f3 un1; printf 'x\n' > "$D/docs/año.txt"; printf 'y\n' > "$D/docs/con espacio.md"
espera pasa "nombres Unicode y con espacios no producen falsos rechazos" "" -- nota_f1 "$D" un1
copia f3 un2; printf 'x\n' > "$D/docs/año.txt"; nota_f1 "$D" prep >/dev/null 2>&1 || die "no pude preparar el nombre Unicode"
suite_es "$D" 'printf z >> docs/año.txt'
espera falla "una suite que reescribe un archivo con nombre Unicode se rechaza" "año.txt \(contenido\)" -- nota_f1 "$D" un2
copia f3 ti1; suite_es "$D" 'cp README.md copia-readme && rm README.md && ln -s copia-readme README.md'
espera falla "una suite que sustituye un archivo regular por un enlace idéntico se rechaza" "README.md \(tipo" -- nota_f1 "$D" ti1
copia f3 ti2; ln -s plan.md "$D/docs/enlace.md"
espera pasa "un enlace versionado sin cambios no se rechaza" "" -- nota_f1 "$D" ti2
N="$W/primer"; rm -rf "$N"; mkdir -p "$N"; ( cd "$W/etapas/plantilla" && tar cf - --exclude ./.git . ) | ( cd "$N" && tar xf - )
printf '#!/bin/sh\ngit ls-files --error-unmatch README.md >/dev/null && [ -z "$(git status --porcelain --untracked-files=no)" ]\n' > "$N/scripts/check.sh"
en "$N" git init -q; en "$N" git config core.hooksPath .githooks; chmod +x "$N"/.githooks/*; en "$N" git add -A
for x in .githooks/pre-commit .githooks/commit-msg; do en "$N" git update-index --chmod=+x "$x"; done
espera pasa "primer commit del repositorio (sin HEAD): la suite corre en la instantánea" "" -- commitea "$N" "Encuadre inicial

Ref: F1"

echo "== Suite vigilada en el pre-commit (arranque protegido de check.sh sobre la instantánea)"
# El bloque, tal cual de docs/convenciones.md; los temporales de estos casos (instantánea, carpeta de
# la ejecución) van a $W/tmpd: TMPDIR explícito, que el pre-commit respeta con su plantilla de mktemp.
BLOQUE=$(awk '/^# --- suite vigilada/{f=1} f{print} /^# --- fin suite vigilada/{exit}' "$RAIZ/docs/convenciones.md")
mkdir -p "$W/tmpd" "$W/pids" "$W/bin"
cat > "$W/bin/ps" <<EOF
#!/bin/sh
$(command -v ps) "\$@"; rc=\$?
[ "\$1" = -A ] && [ -f "$W/fantasma" ] && echo "99999 \$(cat "$W/fantasma") S Thu Oct 29 10:00:00 2026 fantasma"
exit \$rc
EOF
chmod +x "$W/bin/ps"   # ps de prueba: con $W/fantasma lista un miembro que sobrevive a KILL (simulado)
vigilada() {  # vigilada <dir> <plazo> <cuerpo>: check.sh = bloque + cuerpo; plazo en convenciones
  { grep -v 'Plazo de la suite:' "$1/docs/convenciones.md"; printf '\n- **Plazo de la suite:** %s s\n' "$2"; } > "$1/conv.tmp" && mv "$1/conv.tmp" "$1/docs/convenciones.md"
  suite_es "$1" "$BLOQUE
$3"
}
con_tmp() { ( export TMPDIR="$W/tmpd" PATH="$W/bin:$PATH"; "$@" ); }
# acotado <seg> cmd...: si la garantía se rompe y el commit se cuelga, el caso FALLA (124) en vez de colgar.
acotado() { python3 -c '
import subprocess, sys
p = subprocess.Popen(sys.argv[2:], start_new_session=True)
try:
    sys.exit(p.wait(timeout=int(sys.argv[1])))
except subprocess.TimeoutExpired:
    import os, signal; os.killpg(p.pid, signal.SIGKILL); p.wait(); print("acotado: no terminó", file=sys.stderr); sys.exit(124)
' "$@"; }
registro_de() { python3 -c 'import json,glob,sys; r=sorted((json.load(open(p)) for p in glob.glob(sys.argv[1]+"/.git/suite-runs/*.json")), key=lambda x: x["inicio"]); print(r[-1]["estado"], r[-1]["dir"], r[-1].get("incompleta","")) if r else print("sin-registro")' "$1"; }
copia f3 sv1; vigilada "$D" 20 'echo "cuerpo en $(pwd -P)"; python3 app.py || exit 1'
espera pasa "check.sh con el bloque: el pre-commit lo corre vigilado y el commit pasa" "cuerpo en /.*/tmpd/precommit-snap\." -- con_tmp nota_f1 "$D" sv1
espera pasa "... registrado en el repositorio REAL (no en la instantánea), aprobado, sobre la instantánea" "^aprobada /.*/tmpd/precommit-snap\.[^/]*/r $" -- registro_de "$D"
espera pasa "... y el pre-commit no deja temporales propios (instantánea ni exportación)" "^0$" -- sh -c 'ls -d "$1"/precommit* 2>/dev/null | wc -l | tr -d " "' _ "$W/tmpd"
P="$W/pids/sv2"; mkdir -p "$P"
copia f3 sv2; vigilada "$D" 2 "sleep 300 & echo \$! > '$P/nieto'; echo \$\$ > '$P/lider'; trap '' TERM; echo arranco; while :; do sleep 1; done"
T0=$(date +%s)
espera falla "suite colgada en el pre-commit: el commit se rechaza al vencer el plazo, nombrando la causa" "EXCEDIÓ su plazo.*No es un fallo de pruebas" -- acotado 40 sh -c 'cd "$1" && export TMPDIR="$2" PATH="$3:$PATH" && printf -- "- nota sv2\n" >> docs/MEMORIA.md && git add -A && git -c core.hooksPath=.githooks commit -q -m "nota

Ref: F1"' _ "$D" "$W/tmpd" "$W/bin"
espera pasa "... en menos de 20 s" "" -- test $(( $(date +%s) - T0 )) -lt 20
espera falla "... sin el líder vivo" "" -- kill -0 "$(cat "$P/lider" 2>/dev/null)"
espera falla "... ni el nieto" "" -- kill -0 "$(cat "$P/nieto" 2>/dev/null)"
espera pasa "... el registro del repositorio real la da por excedida" "^excedida " -- registro_de "$D"
copia f3 sv3; vigilada "$D" 20 "[ -e '$W/sv3-hecho' ] || { : > '$W/sv3-hecho'; echo \$\$ > '$W/fantasma'; }; python3 app.py || exit 1"
espera falla "superviviente a KILL (simulado) en el pre-commit: rechaza por terminación incompleta" "quedaron procesos suyos vivos" -- con_tmp nota_f1 "$D" sv3a
espera pasa "... el registro sigue abierto e incompleto" "^abierta .* aprobada$" -- registro_de "$D"
espera pasa "... y su instantánea (directorio de trabajo de los procesos vivos) se conserva con sus archivos" "" -- test -f "$(registro_de "$D" | cut -d' ' -f2)/scripts/check.sh"
espera falla "... el siguiente commit se rechaza: hay otra ejecución abierta" "otra ejecución de la suite abierta" -- con_tmp nota_f1 "$D" sv3b
rm -f "$W/fantasma"
espera pasa "... ido el superviviente, el siguiente commit la recupera y pasa" "recupero la ejecución" -- con_tmp nota_f1 "$D" sv3c
# sv4: se interrumpe el hook (muere el lanzador) con el guardián aún activo: la instantánea no se borra.
P="$W/pids/sv4"; mkdir -p "$P"
copia f3 sv4; vigilada "$D" 60 "echo \$\$ > '$P/lider'; while :; do sleep 1; done"
acotado 40 sh -c 'cd "$1" && export TMPDIR="$2" PATH="$3:$PATH" && printf -- "- nota sv4\n" >> docs/MEMORIA.md && git add -A && git -c core.hooksPath=.githooks commit -q -m "nota

Ref: F1"' _ "$D" "$W/tmpd" "$W/bin" > "$P/salida" 2>&1 &
bg=$!
abierta_de() { python3 -c 'import json,glob,sys; r=[json.load(open(p)) for p in glob.glob(sys.argv[1]+"/.git/suite-runs/*.json")]; print(*next(([x["lanzador"], x["id"]] for x in r if x["estado"] == "abierta" and x.get("guardia")), []))' "$1"; }
n=0; until [ -s "$P/lider" ] && [ -n "$(abierta_de "$D")" ]; do n=$((n+1)); [ $n -lt 150 ] || break; sleep 0.2; done
ab=$(abierta_de "$D"); lz=${ab%% *}; sid=${ab#* }; kill -9 "${lz:-0}" 2>/dev/null; wait $bg
espera pasa "hook interrumpido con la ejecución activa: avisa que conserva la instantánea" "conservo la instantánea .*precommit-snap\..*${sid:-sin-id}" -- cat "$P/salida"
espera pasa "... el registro la sigue dando por abierta, vinculada a la instantánea" "^abierta /.*/tmpd/precommit-snap\.[^/]*/r $" -- registro_de "$D"
espera pasa "... y la instantánea sigue presente con sus archivos" "" -- test -f "$(registro_de "$D" | cut -d' ' -f2)/scripts/check.sh"
espera pasa "... terminarla después es posible y no deja vivo al líder" "" -- en "$D" python3 scripts/suite.py terminar "${sid:-sin-id}"
espera falla "... (líder muerto)" "" -- kill -0 "$(cat "$P/lider" 2>/dev/null)"
# sv5/sv6: la suite corre y se cierra, pero al salir el hook no puede leer el registro (dañado o sin
# permiso de lectura, provocado por el cuerpo al final): la ausencia de abiertas no está demostrada.
copia f3 sv5; vigilada "$D" 20 "python3 app.py || exit 1; echo '{roto' > '$D/.git/suite-runs/zz.json'"
espera pasa "registro dañado al salir: el commit pasa, pero la instantánea se conserva y se avisa" "conservo la instantánea .*registro ilegible" -- con_tmp nota_f1 "$D" sv5
copia f3 sv7; vigilada "$D" 20 "python3 app.py || exit 1; echo '{\"id\": \"x\", \"dir\": \"/x\", \"inicio\": 1}' > '$D/.git/suite-runs/zz.json'"
espera pasa "registro sin «estado» al salir: no autoriza el borrado; la instantánea se conserva y se avisa" "conservo la instantánea .*registro ilegible o dañado" -- con_tmp nota_f1 "$D" sv7
mkdir -p "$W/sin-lectura"; chmod 300 "$W/sin-lectura"
if ls "$W/sin-lectura" >/dev/null 2>&1; then
  echo "  (no aplica: este entorno lista carpetas sin permiso de lectura; registro inaccesible sin probar)"
else
  copia f3 sv6; vigilada "$D" 20 "python3 app.py || exit 1; chmod 300 '$D/.git/suite-runs'"
  espera pasa "registro que no se puede listar al salir: la instantánea se conserva y se avisa" "conservo la instantánea .*registro ilegible" -- con_tmp nota_f1 "$D" sv6
  chmod 700 "$D/.git/suite-runs"
fi
chmod 700 "$W/sin-lectura"

echo "== El avance queda a la vista: casilla del plan y estado.md en el commit Ref: I<n>"
# recibo_bruto con la huella del índice: un recibo vigente que NO pasa por cierra_inc.
copia f3 av1; printf '\ndef resta(a, b):\n    return a - b\n' >> "$D/app.py"; printf -- '- Cerrado I2.\n' >> "$D/docs/estado.md"
recibo_bruto "$D" "fecha=2026-10-19T10:00Z rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 huella=$(huella_idx "$D") ejecutor=regresion seguridad=no-aplica modalidad=lectura filtro=comprobado aislamiento=ninguno"
espera falla "Ref: I2 con su casilla aún en '- [ ]' se rechaza" "I2 sigue como" -- commitea "$D" "I2

Ref: I2"
copia f3 av2; printf '\ndef resta(a, b):\n    return a - b\n' >> "$D/app.py"; sed -i.bak 's/^- \[ \] I2 /- [x] I2 /' "$D/docs/plan.md"; rm -f "$D/docs/plan.md.bak"
recibo_bruto "$D" "fecha=2026-10-19T10:00Z rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 huella=$(huella_idx "$D") ejecutor=regresion seguridad=no-aplica modalidad=lectura filtro=comprobado aislamiento=ninguno"
espera falla "Ref: I2 sin regenerar docs/estado.md se rechaza" "sin regenerar docs/estado.md" -- commitea "$D" "I2

Ref: I2"

echo "== Código sin Ref: I<n>"
copia f3 b1; printf 'def resta(a, b):\n    return a - b\n' >> "$D/app.py"
trazabilidad "$D" "$C1_PEND" "" '| R-I1.1 | «sin-prueba» | I1 | C1 | falta prueba | resuelto | 2026-10-19 10:00 · app.py:1 |'
espera falla "Cierra: solo con código se rechaza" "sin 'Ref: I<n>'" -- commitea "$D" "corrige

Cierra: R-I1.1"
copia f3 b2; printf 'def resta(a, b):\n    return a - b\n' >> "$D/app.py"
espera falla "Ref: F1 con código se rechaza" "sin 'Ref: I<n>'" -- commitea "$D" "encuadre

Ref: F1"
copia f3 b3; printf 'def resta(a, b):\n    return a - b\n' >> "$D/app.py"
trazabilidad "$D" "$C1_PEND" "" '| R-I1.1 | «sin-prueba» | I1 | C1 | falta prueba | resuelto | 2026-10-19 10:00 · app.py:1 |'
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "Ref: I2 + Cierra: con recibo vigente se acepta" "" -- commitea "$D" "I2 «resta»

Ref: I2
Cierra: R-I1.1"
copia f3 b4; echo "- nota" >> "$D/docs/MEMORIA.md"
espera pasa "solo rastro (docs/) con Ref: F1 se acepta" "" -- commitea "$D" "memoria

Ref: F1"

echo "== Recibos: caducado, FALLA, seguridad, log"
copia f3 r1; printf 'x = 1\n' >> "$D/app.py"
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
copia f3 r4; python3 - "$D/docs/revisiones.log" <<'EOF'
import sys; p=sys.argv[1]; open(p,'w').write(''.join(l for l in open(p) if 'rol=juez-codigo' not in l))
EOF
echo "- nota" >> "$D/docs/MEMORIA.md"
espera falla "log reescrito (recibo borrado) se rechaza" "append-only" -- commitea "$D" "memoria

Ref: F1"
copia f3 r5
espera falla "log eliminado en F3 se rechaza" "desaparece|falta docs/revisiones.log" -- sh -c 'cd "$1" && git rm -q docs/revisiones.log && git -c core.hooksPath=.githooks commit -q -m "x

Ref: F1"' sh "$D"
copia f3 p9; recibo_bruto "$D" "fecha=ayer rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica huella=$(huella_idx "$D") ejecutor=x modalidad=lectura filtro=comprobado aislamiento=ninguno"
espera falla "fecha=ayer es inválida" "fecha debe ser ISO" -- en "$D" sh scripts/recibos.sh validar docs/revisiones.log
copia f3 p9b; recibo_bruto "$D" "fecha=2026-02-30 rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica huella=$(huella_idx "$D") ejecutor=x modalidad=lectura filtro=comprobado aislamiento=ninguno"
espera falla "fecha=2026-02-30 es inválida" "fecha debe ser ISO" -- en "$D" sh scripts/recibos.sh validar docs/revisiones.log
copia f3 p10; recibo_bruto "$D" "fecha=2026-10-19 rol=juez-codigo tipo=incremento alcance=I2 veredicto=FALLA bloqueantes=00 seguridad=no-aplica huella=$(huella_idx "$D") ejecutor=x modalidad=lectura filtro=comprobado aislamiento=ninguno"
espera falla "bloqueantes=00 es inválido" "bloqueantes debe ser" -- en "$D" sh scripts/recibos.sh validar docs/revisiones.log
copia f3 p10b; recibo_bruto "$D" "fecha=2026-10-19T23:59:59Z rol=juez-codigo tipo=incremento alcance=I2 veredicto=FALLA bloqueantes=12 seguridad=no-aplica huella=$(huella_idx "$D") ejecutor=x modalidad=lectura filtro=comprobado aislamiento=ninguno"
espera pasa "fecha ISO completa y bloqueantes=12 son válidos" "" -- en "$D" sh scripts/recibos.sh validar docs/revisiones.log

echo "== Hallazgos del incremento y Cierra:"
copia f3 c1; printf 'x = 1\n' >> "$D/app.py"
trazabilidad "$D" "$C1_PEND" "" '| R-I2.1 | «sin-prueba» | I2 | C1 | falta prueba | abierto | — |'
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "Ref: I2 con R-I2.1 abierto se rechaza" "R-I2.1" -- commitea "$D" "I2

Ref: I2"
copia f3 c2; printf 'x = 1\n' >> "$D/app.py"
trazabilidad "$D" "$C1_PEND" "" '| R-S2.1 | «inyeccion» | I2 | C1 | entrada sin validar | abierto | — |'
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "Ref: I2 con R-S2.1 abierto se rechaza" "R-S2.1" -- commitea "$D" "I2

Ref: I2"
copia f3 c3; printf 'x = 1\n' >> "$D/app.py"
trazabilidad "$D" "$C1_PEND" "" '| R-I2.1 | «sin-prueba» | I2 | C1 | falta prueba | resuelto | 2026-10-19 10:00 · app.py:1 |
| R-I3.1 | «otro» | I3 | C1 | de otro incremento | abierto | — |'
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "Ref: I2 con R-I2.1 resuelto y R-I3.1 (ajeno) abierto se acepta" "" -- commitea "$D" "I2

Ref: I2"
copia f3 c4; printf 'x = 1\n' >> "$D/app.py"
trazabilidad "$D" "$C1_PEND" "" "" "- \`R-I2.1 «sin-prueba» · verificado 2026-10-19 · commit $(en "$D" git rev-parse --short HEAD)\`"
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "Cierra: sobre un hallazgo ya compactado al Histórico (verificado) se acepta" "" -- commitea "$D" "I2

Ref: I2
Cierra: R-I2.1"
copia f3 c5; echo "- nota" >> "$D/docs/MEMORIA.md"
espera falla "Cierra: sobre un ID sin fila ni Histórico se rechaza" "no tiene fila" -- commitea "$D" "x

Cierra: R-I9.9"
copia f3 c6; printf 'x = 1\n' >> "$D/app.py"
trazabilidad "$D" "$C1_PEND" "" '  | R-I2.1 | «sin-prueba» | I2 | C1 | falta prueba | abierto | — |'
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "fila con sangría no se vuelve invisible: Ref: I2 con R-I2.1 abierto (sangrado) se rechaza" "sangría|R-I2.1" -- commitea "$D" "I2

Ref: I2"
copia f3 c7
trazabilidad "$D" "$C1_PEND" "" '| R-I99.1 | «cruzado» | I2 | C1 | ID e Incr. discordantes | abierto | — |'
espera falla "ID R-I99.1 con Incr. I2 (dos identidades) se rechaza" "dos identidades" -- commitea "$D" "docs

Ref: F1"
copia f3 c8
trazabilidad "$D" "$C1_PEND" "" '| R-I1.1 | «corta» | I1 | C1 | fila sin la última celda | verificado |'
espera falla "fila con menos celdas que el encabezado se rechaza" "celdas" -- commitea "$D" "docs

Ref: F1"

copia f3 pc1; printf '<!--\n- [ ] I99 «oculto» — no se ve en el plan renderizado\n-->\n' >> "$D/docs/plan.md"
printf 'w = 99\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I99 PASA 0 seguridad=no-aplica
espera falla "Ref: I99 cuyo incremento solo existe dentro de un comentario HTML se rechaza" "I99 no existe como incremento" -- commitea "$D" "I99

Ref: I99"

n=0
for cerco in '~~~text|```|~~~' '````|```|````'; do
  n=$((n+1)); a=${cerco%%|*}; r=${cerco#*|}; m=${r%%|*}; c=${r#*|}
  copia f3 pc$((n+1)); printf '\n%s\n%s\n- [ ] I99 «ejemplo» — dentro del cerco\n%s\n' "$a" "$m" "$c" >> "$D/docs/plan.md"
  printf 'w = 99\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I99 PASA 0 seguridad=no-aplica
  espera falla "Ref: I99 solo dentro de un cerco $a con un $m interior (no lo cierra) se rechaza" "I99 no existe como incremento" -- commitea "$D" "I99

Ref: I99"
done
copia f3 pc4; printf '\n````\n```\n- [ ] I98 «ejemplo» — dentro\n````\n- [ ] I99 «real» — después del cerco\n' >> "$D/docs/plan.md"
printf 'w = 99\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I99 PASA 0 seguridad=no-aplica
espera pasa "un incremento activo después de un cerco bien cerrado sigue visible (Ref: I99 se acepta)" "" -- commitea "$D" "I99

Ref: I99"

echo "== Fase perdida no es plantilla (R9-A01)"
espera falla "plantilla nunca iniciada: 'check_docs.sh iniciado' dice que no (la CI la omite)" "" -- en "$B" sh scripts/check_docs.sh iniciado
copia f3 a1; fase "$D" F_
sin_hooks "$D" "pierde la fase

Ref: F1" || die "no pude colar la fase perdida"
espera pasa "proyecto que perdió la fase sigue 'iniciado' (la CI valida su contrato)" "" -- en "$D" sh scripts/check_docs.sh iniciado
espera falla "validar_historial rechaza el commit que borró la fase" "última fase legible del historial: F3" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
echo "- nota" >> "$D/docs/MEMORIA.md"
espera falla "con la fase ya perdida en HEAD, el siguiente commit tampoco pasa como plantilla" "última fase legible del historial: F3" -- commitea "$D" "memoria

Ref: F1"

echo "== Hito: contador por commits, rango, cobertura, seguridad"
copia f3-tres h1; printf 'z = 4\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I4 PASA 0 seguridad=no-aplica
espera falla "cuarto incremento sin commit de hito se rechaza" "hito" -- commitea "$D" "I4

Ref: I4"
copia f3-tres h2
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
espera pasa "commit del hito: Ref: hito:I1-I3 con recibo vigente y los tres cierres en el historial" "" -- commitea "$D" "hito I1-I3

Ref: hito:I1-I3"
printf 'z = 4\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I4 PASA 0 seguridad=no-aplica
espera pasa "cuarto incremento tras el commit del hito se acepta" "" -- commitea "$D" "I4

Ref: I4"
copia f3-tres h3
recibo_bruto "$D" "fecha=2026-10-19 rol=juez-conjunto tipo=hito alcance=hito:I1-I3 veredicto=PASA bloqueantes=0 seguridad=no-aplica huella=000000000000 ejecutor=x cubre=C1 excluye=ninguno componentes=app modalidad=lectura filtro=comprobado aislamiento=ninguno"
printf 'z = 4\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I4 PASA 0 seguridad=no-aplica
espera falla "un recibo de hito suelto (sin su commit Ref: hito) no cuenta como hito" "hito" -- commitea "$D" "I4

Ref: I4"
copia f3-tres h4
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=requerida cubre=C1 excluye=ninguno componentes=app
recibo_bruto "$D" "fecha=2026-10-19 rol=juez-seguridad tipo=hito alcance=hito:I1-I3 veredicto=PASA bloqueantes=0 huella=000000000000 ejecutor=x cubre=C1 excluye=ninguno componentes=app modalidad=lectura filtro=comprobado aislamiento=ninguno"
espera falla "hito con seguridad=requerida cuyo recibo de seguridad tiene otra huella se rechaza" "juez-seguridad .hito hito:I1-I3. tiene huella 000000000000" -- commitea "$D" "hito

Ref: hito:I1-I3"
copia f3-tres h5
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
recibo "$D" juez-conjunto hito hito:I1-I3 FALLA 2 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
espera falla "hito PASA seguido de FALLA se rechaza" "fue FALLA" -- commitea "$D" "hito

Ref: hito:I1-I3"
copia f3-tres h6; echo "- nota" >> "$D/docs/MEMORIA.md"
espera falla "Ref: hito sin recibo de hito se rechaza" "no hay recibo válido de juez-conjunto" -- commitea "$D" "hito

Ref: hito:I1-I3"
copia f3-tres h7
recibo "$D" juez-conjunto hito hito:I99-I99 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
espera falla "hito sobre un rango inexistente (I99) se rechaza" "no existe" -- commitea "$D" "hito

Ref: hito:I99-I99"
copia f3 h8
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
espera falla "hito I1-I3 cuando solo I1 está cerrado se rechaza (revisa lo construido, no lo prometido)" "no tiene commit" -- commitea "$D" "hito

Ref: hito:I1-I3"
copia f2 h9; fase "$D" F3 "I1 «suma»"; printf 'def suma(a, b):\n    return a + b\n' > "$D/app.py"
for i in 1 2 3 4; do cierra_inc "$D" I$i; done   # antes de los recibos: ninguno cambia la huella del anterior
for i in 1 2 3 4; do recibo "$D" juez-codigo incremento I$i PASA 0 seguridad=no-aplica; done
espera pasa "recibos preparados para I1..I4 no bloquean el cierre de I1: el contador son commits cerrados" "" -- commitea "$D" "I1

Ref: I1"

copia f3-tres h10
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C999 excluye=C1 componentes=app
espera falla "hito con cubre=C999 (criterio inexistente) se rechaza" "C999, que no está definido" -- commitea "$D" "hito

Ref: hito:I1-I3"
copia f3-tres h11
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=C1 componentes=app
espera falla "hito con C1 a la vez en cubre= y excluye= se rechaza" "a la vez en cubre" -- commitea "$D" "hito

Ref: hito:I1-I3"
# Ronda 12 (C1): corrección de código pedida por un hito. Ruta documentada: reabrir un
# incremento del rango (Ref: I<k>) y pedir el hito al final, en commits separados o en uno.
hito_falla() {  # deja registrado el FALLA del hito con su bloqueante R-F4.1 abierto
  trazabilidad "$1" "$C1_PEND" "" '| R-F4.1 | «hito» | F4 | C1 | interacción sin prueba | abierto | — |'
  recibo "$1" juez-conjunto hito hito:I1-I3 FALLA 1 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
  sin_hooks "$1" "registra el FALLA del hito"
}
corrige_hito() {  # código corregido, fila resuelta con su referencia y estado.md regenerado
  printf 'assert suma(2, 3) == 5\n' >> "$1/app.py"; printf -- '- Corrección del hito (R-F4.1) en I3.\n' >> "$1/docs/estado.md"
  trazabilidad "$1" "$C1_PEND" "" '| R-F4.1 | «hito» | F4 | C1 | interacción sin prueba | resuelto | app.py:5 |'
}
copia f3-tres hc1; hito_falla "$D"; corrige_hito "$D"; recibo "$D" juez-codigo incremento I4 PASA 0 seguridad=no-aplica
espera falla "corrección de hito como incremento nuevo: sería el cuarto sin hito" "obligatorio antes de cerrar el cuarto" -- commitea "$D" "I4 corrige el hito

Ref: I4
Cierra: R-F4.1"
copia f3-tres hc2; hito_falla "$D"; corrige_hito "$D"; recibo "$D" juez-codigo incremento I3 PASA 0 seguridad=no-aplica
espera pasa "corrección de hito: reabrir I3 con juez de código y Cierra" "" -- commitea "$D" "I3 corrige el hito

Ref: I3
Cierra: R-F4.1"
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
espera pasa "corrección de hito: después, el hito sobre el contenido definitivo" "" -- commitea "$D" "hito I1-I3

Ref: hito:I1-I3"
copia f3-tres hc3; hito_falla "$D"; corrige_hito "$D"
recibo "$D" juez-codigo incremento I3 PASA 0 seguridad=no-aplica; recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
espera pasa "corrección de hito: reapertura y hito en un mismo commit" "" -- commitea "$D" "I3 y hito

Ref: I3
Ref: hito:I1-I3
Cierra: R-F4.1"
copia f3-tres hc4; hito_falla "$D"; corrige_hito "$D"
recibo "$D" juez-codigo incremento I3 PASA 0 seguridad=no-aplica; recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
printf 'assert suma(1, 1) == 2\n' >> "$D/app.py"
espera falla "corrección de hito: un cambio revisable tras el PASA caduca los recibos" "huella" -- commitea "$D" "I3 y hito

Ref: I3
Ref: hito:I1-I3
Cierra: R-F4.1"

# Ronda 12 (C3): el revisor GENERA su recibo; la herramienta pone fecha y huella, valida y no escribe.
copia f3 rl; G="modalidad=lectura filtro=comprobado aislamiento=ninguno"
linea() { en "$D" sh scripts/recibos.sh linea "$@"; }
L0=$(wc -c < "$D/docs/revisiones.log")
espera pasa "recibos linea: genera una línea válida con fecha de emisión y la huella de vigencia" "^fecha=20[0-9-]+T[0-9:]+Z rol=juez-codigo .* huella=$(en "$D" sh scripts/huella.sh)$" -- linea rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica ejecutor=juez-codigo $G
espera pasa "recibos linea: no escribe el registro" "" -- sh -c "[ \$(wc -c < '$D/docs/revisiones.log') -eq $L0 ]"
espera falla "recibos linea: sin ejecutor= no inventa autoría" "falta ejecutor=" -- linea rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica $G
espera falla "recibos linea: sin veredicto= no inventa el veredicto" "falta veredicto=" -- linea rol=juez-codigo tipo=incremento alcance=I2 bloqueantes=0 seguridad=no-aplica ejecutor=x $G
espera falla "recibos linea: fecha= declarada se rechaza (la pone la herramienta)" "lo calcula la herramienta" -- linea fecha=2026-01-01 rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica ejecutor=x $G
espera falla "recibos linea: huella= declarada se rechaza" "lo calcula la herramienta" -- linea huella=000000000000 rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica ejecutor=x $G
espera falla "recibos linea: valida con la gramática (tipo inventado)" "tipo desconocido" -- linea rol=revisor-funcional tipo=funcional alcance=F2 veredicto=PASA bloqueantes=0 ejecutor=x $G
espera falla "recibos linea: valida con la gramática (PASA con bloqueantes)" "PASA exige bloqueantes=0" -- linea rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=1 seguridad=no-aplica ejecutor=x $G
printf 'y2 = 2\n' >> "$D/app.py"; cierra_inc "$D" I2
espera pasa "recibos linea: la línea generada, registrada tal cual, cierra el incremento" "" -- sh -c "cd '$D' && git add -A && sh scripts/recibos.sh linea rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica ejecutor=juez-codigo $G >> docs/revisiones.log && git add -A && git -c core.hooksPath=.githooks commit -q -m 'I2

Ref: I2'"

# Ronda 12 (C3, revisión del evaluador): la huella del árbol de trabajo (vigencia e integridad) se
# calcula SIN ESCRIBIR (ni temporales, ni índice, ni objetos en .git) y coincide con el cálculo
# por índice temporal + write-tree que sustituye. Lo usa recibos.sh linea en modalidad lectura.
huella_vieja() {  # huella_vieja <dir> [integridad]: el cálculo anterior (escribe objetos en .git)
  ( cd "$1" && t=$(mktemp) && cp "$(git rev-parse --git-path index)" "$t" 2>/dev/null
    GIT_INDEX_FILE="$t" git add -A >/dev/null 2>&1; tr=$(GIT_INDEX_FILE="$t" git write-tree); rm -f "$t"
    ex='	docs/((revisiones\.log|trazabilidad\.md|estado\.md|MEMORIA\.md)$|revisiones/)'; [ "${2:-}" = integridad ] && ex='^$'
    git ls-tree -r "$tr" | grep -vE "$ex" | git hash-object --stdin | cut -c1-12 )
}
HV="$W/huella-eq"; mkdir -p "$HV/docs" "$HV/sub" "$HV/scripts"; en "$HV" git init -q
cp "$RAIZ/scripts/huella.sh" "$RAIZ/scripts/recibos.sh" "$HV/scripts/"
printf 'a\n' > "$HV/a.txt"; printf 'b\n' > "$HV/b.txt"; printf 'x\n' > "$HV/docs/estado.md"; printf '*.log\n' > "$HV/.gitignore"
printf 'crlf.txt text eol=crlf\n' > "$HV/.gitattributes"; printf 'l1\nl2\n' > "$HV/crlf.txt"
en "$HV" git add -A && en "$HV" git -c core.hooksPath=/dev/null commit -q -m base || die "no pude preparar la huella"
printf 'a2\n' > "$HV/a.txt"; rm "$HV/b.txt"; printf 'n\n' > "$HV/año nuevo.md"; printf 'q\n' > "$HV/con \"comillas\".txt"
printf 'c\n' > "$HV/\"inicio.txt"; printf 'm\n' > "$HV/ñ\"mezcla\\é.txt"; printf 'l\n' > "$HV/$(printf 'salto\nlinea.txt')"  # comilla inicial (--stdin-paths la desentrecomilla), no ASCII + comilla + barra, salto de línea
printf '#!/bin/sh\n' > "$HV/sub/run.sh"; chmod +x "$HV/sub/run.sh"; ln -s a.txt "$HV/enlace"; printf 'i\n' > "$HV/x.log"; printf 'y2\n' > "$HV/docs/estado.md"; printf 'r1\nr2 de otro tamaño\n' > "$HV/crlf.txt"  # estado.md y crlf.txt cambian de tamaño: con igual tamaño en el mismo segundo el cálculo ANTERIOR reusa el blob viejo (racy git)
espera pasa "huella sin escrituras = cálculo anterior (modificado, borrado, nuevo, ñ, comillas, comilla inicial, salto de línea, ejecutable, enlace, ignorado, registro, filtro)" "" -- sh -c "[ \"\$(cd '$HV' && sh scripts/huella.sh)\" = '$(huella_vieja "$HV")' ]"
espera pasa "huella de integridad sin escrituras = cálculo anterior" "" -- sh -c "[ \"\$(cd '$HV' && sh scripts/huella.sh integridad)\" = '$(huella_vieja "$HV" integridad)' ]"
espera pasa "huella sin escrituras con core.quotePath=false = cálculo anterior" "" -- sh -c "[ \"\$(cd '$HV' && GIT_CONFIG_PARAMETERS=\"'core.quotePath'='false'\" sh scripts/huella.sh)\" = '$(GIT_CONFIG_PARAMETERS="'core.quotePath'='false'" huella_vieja "$HV")' ]"
en "$HV" git config core.fileMode false; chmod -x "$HV/sub/run.sh"
espera pasa "huella sin escrituras con core.fileMode=false = cálculo anterior" "" -- sh -c "[ \"\$(cd '$HV' && sh scripts/huella.sh)\" = '$(huella_vieja "$HV")' ]"
en "$HV" git config core.fileMode true; chmod +x "$HV/sub/run.sh"
foto_git() { ( cd "$1" && find .git -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done | cksum ); }
HT="$W/huella-tmp"; mkdir -p "$HT"; G0=$(foto_git "$HV")
python3 -c 'import time; time.sleep(1.05)'; touch "$W/huella-marca"; python3 -c 'import time; time.sleep(1.05)'
( cd "$HV" && TMPDIR="$HT" sh scripts/recibos.sh linea rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica ejecutor=x modalidad=lectura filtro=comprobado aislamiento=ninguno >/dev/null \
  && TMPDIR="$HT" sh scripts/huella.sh >/dev/null && TMPDIR="$HT" sh scripts/huella.sh integridad >/dev/null ) || die "no pude correr el generador sobre la huella"
espera pasa "generador y huella: .git idéntico (índice y objetos) tras correrlos" "" -- sh -c "[ '$G0' = '$(foto_git "$HV")' ] && [ -z \"\$(find '$HV/.git' -newer '$W/huella-marca' | head -1)\" ]"
espera pasa "generador y huella: ningún temporal en TMPDIR" "" -- sh -c "[ -z \"\$(ls -A '$HT')\" ]"
huella_vieja "$HV" >/dev/null
espera falla "control: el cálculo anterior SÍ escribe objetos en .git (la prueba lo detecta)" "" -- sh -c "[ -z \"\$(find '$HV/.git/objects' -type f -newer '$W/huella-marca' | head -1)\" ]"
espera pasa "huella sin filtros de git configurados: sin aviso" "" -- sh -c "[ -z \"\$(cd '$HV' && sh scripts/huella.sh 2>&1 >/dev/null)\" ]"
en "$HV" git config filter.propio.clean cat
espera pasa "huella con un filtro clean configurado: avisa que no certifica lectura estricta" "no certifica lectura estricta" -- sh -c "cd '$HV' && sh scripts/huella.sh 2>&1 >/dev/null"
en "$HV" git config --unset filter.propio.clean

tres_criterios() {  # tres_criterios <dir>: C1..C3 construidos (I1, I2, I3) y C4 futuro (I4, sin commit)
  printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: suma devuelve a+b.\n- C2: resta devuelve a-b.\n- C3: multiplica devuelve a*b.\n- C4: divide devuelve a/b.\n' > "$1/docs/encuadre.md"
  trazabilidad "$1" "$C1_PEND
| C2 | «resta» | I2 | pendiente | |
| C3 | «multiplica» | I3 | pendiente | |
| C4 | «divide» | I4 | pendiente | |" "" ""
  # Criterios nuevos ⇒ contrato revisado nuevo: recibo del revisor funcional y commit Ref: F2.
  recibo "$1" revisor-funcional encuadre F2 PASA 0
  commitea "$1" "criterios C2..C4

Ref: F2" || die "no pude revisar los criterios de tres_criterios"
}
copia f3-tres h12; tres_criterios "$D"
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1,C2,C3 excluye=C4 componentes=app
espera pasa "hito parcial legítimo (cubre=C1,C2,C3 excluye=C4, futuro) se acepta" "" -- commitea "$D" "hito

Ref: hito:I1-I3"
copia f3-tres h13; tres_criterios "$D"
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1,C2 excluye=C2,C3 componentes=app
espera falla "hito con listas solapadas (cubre=C1,C2 excluye=C2,C3) se rechaza por C2" "C2 aparece a la vez" -- commitea "$D" "hito

Ref: hito:I1-I3"
copia f3-tres h15; tres_criterios "$D"
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1,C1 excluye=C3 componentes=app
espera falla "hito con un criterio repetido en la lista (cubre=C1,C1) se rechaza" "cubre= del recibo del hito repite C1" -- commitea "$D" "hito

Ref: hito:I1-I3"
copia f3-tres h16; tres_criterios "$D"
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=C2,C3,C2 componentes=app
espera falla "hito con un criterio repetido NO contiguo en excluye (C2,C3,C2) se rechaza" "excluye= del recibo del hito repite C2" -- commitea "$D" "hito

Ref: hito:I1-I3"
copia f3-tres h17; tres_criterios "$D"
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1,C1 excluye=C2,C3 componentes=app
sin_hooks "$D" "hito colado

Ref: hito:I1-I3" || die "no pude colar el hito con repetición"
espera falla "validar_historial rechaza un hito con cubre repetido colado con --no-verify" "cubre= del recibo del hito repite C1" -- en "$D" sh scripts/pruebas/validar_historial.sh "HEAD~1..HEAD"
copia f3-tres h14; tres_criterios "$D"
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1,C999 excluye=C3 componentes=app
espera falla "hito con una lista que incluye C999 se rechaza por C999" "C999, que no está definido" -- commitea "$D" "hito

Ref: hito:I1-I3"

echo "== Hito: cobertura completa (R9-A04)"
copia f3-tres h18; tres_criterios "$D"
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=ninguno excluye=C1,C2,C3,C4 componentes=app
espera falla "hito con cubre=ninguno se rechaza" "cubre= del recibo del hito no nombra ningún criterio" -- commitea "$D" "hito

Ref: hito:I1-I3"
copia f3-tres h19; tres_criterios "$D"
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1,C2 excluye=C3,C4 componentes=app
espera falla "hito que excluye un criterio ya construido (C3, I3 con commit) se rechaza" "C3 está en excluye= pero ya está construido" -- commitea "$D" "hito

Ref: hito:I1-I3"
copia f3-tres h20; tres_criterios "$D"
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1,C2,C3 excluye=ninguno componentes=app
espera falla "hito que no nombra un criterio del encuadre (C4) se rechaza" "C4 no está ni en cubre= ni en excluye=" -- commitea "$D" "hito

Ref: hito:I1-I3"
copia f3-tres h21
recibo "$D" juez-conjunto hito hito:I1-I1 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
espera falla "hito parcial (I1-I1) con I2 e I3 cerrados se rechaza: no reinicia el contador" "I2 se cerró después del último hito y queda fuera del rango" -- commitea "$D" "hito

Ref: hito:I1-I1"
copia f3-tres h22
recibo "$D" juez-conjunto hito hito:I1-I1 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
sin_hooks "$D" "hito colado

Ref: hito:I1-I1" || die "no pude colar el hito parcial"
espera falla "validar_historial rechaza un hito parcial colado con --no-verify" "queda fuera del rango" -- en "$D" sh scripts/pruebas/validar_historial.sh "HEAD~1..HEAD"
copia f3-tres h23
recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
commitea "$D" "hito

Ref: hito:I1-I3" || die "no pude preparar el primer hito"
echo "- nota" >> "$D/docs/MEMORIA.md"; recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
espera falla "hito vacío (sin incrementos nuevos desde el anterior) se rechaza" "no hay incrementos cerrados desde el último" -- commitea "$D" "hito otra vez

Ref: hito:I1-I3"
printf 'z = 4\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I4 PASA 0 seguridad=no-aplica
commitea "$D" "I4

Ref: I4" || die "no pude cerrar I4 tras el hito"
recibo "$D" juez-conjunto hito hito:I4-I4 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
espera pasa "segundo hito (I4-I4) sobre lo cerrado desde el anterior se acepta" "" -- commitea "$D" "hito I4

Ref: hito:I4-I4"

echo "== Hito: forma cerrada de cubre=/excluye= (verificación R9-P02)"
n=0
for par in "cubre=ninguno,C1,C2,C3 excluye=C4|cubre=" "cubre=C1,C2,C3, excluye=C4|cubre=" "cubre=C1,,C2,C3 excluye=C4|cubre=" "cubre=C1,C2,C3 excluye=ninguno,C4|excluye=" "cubre=C1,C2,C3 excluye=C4,|excluye="; do
  n=$((n+1)); campos=${par%|*}; pat=${par#*|}
  copia f3-tres hl$n; tres_criterios "$D"
  recibo "$D" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica $campos componentes=app
  espera falla "hito con lista mal formada ($campos) se rechaza por su forma" "$pat'[^']*' del recibo del hito no" -- commitea "$D" "hito

Ref: hito:I1-I3"
done

echo "== Familias de conjunto e Histórico"
copia f3 f1; trazabilidad "$D" "$C1_PEND" "" '| R-SF4.1 | «composicion» | F4 | C1 | fuga entre módulos | abierto | — |
| R-F4.1 | «ensamblado» | F4 | C1 | orden de arranque | resuelto | 2026-10-19 10:00 · app.py:1 |'
espera pasa "R-SF4.1 y R-F4.1 con Incr. F4 son filas válidas para el doctor" "" -- commitea "$D" "registra hallazgos del conjunto

Ref: F1"
trazabilidad "$D" "$C1_VERIF" "" '| R-SF4.1 | «composicion» | F4 | C1 | fuga entre módulos | abierto | — |
| R-F4.1 | «ensamblado» | F4 | C1 | orden de arranque | resuelto | 2026-10-19 10:00 · app.py:1 |'
fase "$D" F4 "— «ninguno»"; printf '# Plan\n\n## Incrementos\n\n- [x] I1 «suma» — (satisface: C1)\n' > "$D/docs/plan.md"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "R-SF4.1 abierto bloquea el cierre (Ref: F4)" "abierto" -- commitea "$D" "validación

Ref: F4"
copia cierre f2; printf '  - `R-I2.1 «sin-prueba» · abierto`\n' >> "$D/docs/trazabilidad.md"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "entrada del Histórico con sangría y sin verificado no se vuelve invisible: cierre rechazado" "Histórico sin|sangría" -- commitea "$D" "cierre

Ref: F5"
copia f3 f3; trazabilidad "$D" "$C1_PEND" "" '| R-I1.1 | «fantasma» | I1 | C999 | protege un criterio que no existe | resuelto | 2026-10-19 10:00 · app.py:1 |'
espera falla "hallazgo cuya columna Criterio nombra C999 (inexistente) se rechaza" "C999, que no está definido" -- commitea "$D" "docs

Ref: F1"
copia f3 f4; trazabilidad "$D" "$C1_PEND" "" '| R-S1.1 | «inyeccion» | I1 | CWE-89 | categoría, no un C<n> | resuelto | 2026-10-19 10:00 · app.py:1 |'
espera pasa "hallazgo de seguridad con categoría CWE en Criterio se acepta" "" -- commitea "$D" "docs

Ref: F1"

echo "== Cierre: criterios, IDs, alcance funcional"
copia cierre z1; printf '# Encuadre\n\n- Objetivo: sumar\n' > "$D/docs/encuadre.md"
trazabilidad "$D" "" "" '| R-I1.1 | «sin-prueba» | I1 | general | falta prueba | verificado | 2026-10-19 10:00 · app.py:1 |'
recibo "$D" revisor-funcional encuadre F2 PASA 0
commitea "$D" "encuadre sin criterios

Ref: F2" || die "no pude preparar el encuadre sin criterios"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "cierre sin ningún criterio se rechaza" "ningún criterio" -- commitea "$D" "cierre

Ref: F5"
copia cierre z10; printf '# Plan\n\n## Incrementos\n\n- [x] I1 «suma» — (satisface: C1)\n- [ ] I2 «resta» — (satisface: C1)\n\n## Fuera de alcance / backlog\n\n- nada\n' > "$D/docs/plan.md"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "cierre con un incremento del plan sin marcar (- [ ] I2) se rechaza" "sigue como" -- commitea "$D" "cierre

Ref: F5"
copia cierre z11; printf '# Plan\n\n## Incrementos\n\n- [x] I1 «suma» — (satisface: C1)\n\n## Pendientes\n\n- [ ] I2 «resta» — (satisface: C1)\n\n## Fuera de alcance / backlog\n\n- nada\n' > "$D/docs/plan.md"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "cierre con un incremento pendiente bajo otro encabezado (## Pendientes) se rechaza" "I2 sigue como" -- commitea "$D" "cierre

Ref: F5"
copia cierre z12; printf '# Plan\n\n## Incrementos\n\n- [x] I1 «suma» — (satisface: C1)\n* [ ] I2 «resta» — (satisface: C1)\n\n## Fuera de alcance / backlog\n\n- nada\n' > "$D/docs/plan.md"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "cierre con un incremento en formato no canónico (* [ ] I2) se rechaza con diagnóstico" "parece un incremento pero no tiene la forma" -- commitea "$D" "cierre

Ref: F5"
copia cierre z13; printf '# Plan\n\n## Incrementos\n\n- [x] I1 «suma» — (satisface: C1)\n\n## Fuera de alcance / backlog\n\n- [ ] I9 «potencia» — siguiente ciclo (ADR-001)\n' > "$D/docs/plan.md"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera pasa "cierre con un incremento futuro en el backlog (- [ ] I9) se acepta" "" -- commitea "$D" "cierre

Ref: F5"
copia cierre z14; printf '# Plan\n\n## Incrementos\n\n<!-- ejemplo de formato:\n- [ ] I99 «ejemplo» — no es plan\n-->\n- [x] I1 «suma» — (satisface: C1) <!-- nota -->\n<!-- - [ ] I98 «otro» — tampoco -->\n\n```\n- [ ] I97 «cercado» — ejemplo\n```\n\n## Fuera de alcance / backlog\n\n- nada\n' > "$D/docs/plan.md"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera pasa "cierre con incrementos de ejemplo en comentarios (una y varias líneas) y en un bloque cercado se acepta" "" -- commitea "$D" "cierre

Ref: F5"
copia cierre z15; printf '# Plan\n\n## Incrementos\n\n- [x] I1 «suma» — (satisface: C1)\n<!-- --> - [ ] I2 «resta» — (satisface: C1)\n\n## Fuera de alcance / backlog\n\n- nada\n' > "$D/docs/plan.md"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "un incremento activo tras un comentario vacío no se esconde: forma no canónica" "parece un incremento" -- commitea "$D" "cierre

Ref: F5"
copia cierre z2; trazabilidad "$D" "$C1_VERIF
| C999 | «fantasma» | I1 | verificado | |" "" ""
espera falla "criterio huérfano C999 en trazabilidad se rechaza" "huérfano" -- commitea "$D" "docs

Ref: F1"
copia cierre z3; printf '# Encuadre\n\n- **C1**: la función suma devuelve a+b.\n' > "$D/docs/encuadre.md"
espera falla "criterio en negrita (**C1**) se rechaza como formato no admitido" "fuera de la gramática" -- commitea "$D" "docs

Ref: F1"
copia cierre z4; trazabilidad "$D" "$C1_VERIF" "" '| R-I1_1 | «raro» | I1 | C1 | abierto escondido | abierto | — |'
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "ID con guion bajo (R-I1_1) se rechaza, no se omite" "fuera de la gramática" -- commitea "$D" "cierre

Ref: F5"
copia f2 z5
espera falla "fila de ejemplo de la plantilla con proyecto iniciado se rechaza" "fila de ejemplo" -- sh -c 'cd "$1" && printf "| R-I_._ | «…» | I_ | C_ | _…_ | abierto | — |\n" >> docs/trazabilidad.md && git add -A && git -c core.hooksPath=.githooks commit -q -m "x

Ref: F1"' sh "$D"
copia cierre z6; printf '# Encuadre\n\n- C1:\n' > "$D/docs/encuadre.md"
espera falla "criterio sin enunciado con proyecto iniciado se rechaza" "sin enunciado" -- commitea "$D" "docs

Ref: F1"
copia f2 z7; trazabilidad "$D" '| C1 | «suma» | - | pendiente | |' "" ""
espera falla "F2 con un criterio sin incremento asignado se rechaza" "no tiene incremento asignado" -- commitea "$D" "plan

Ref: F1"
copia plantilla z8; cp -R "$W/etapas/f2/docs" "$D/"; cp "$W/etapas/f2/AGENTS.md" "$D/AGENTS.md"; cp "$W/etapas/f2/scripts/check.sh" "$D/scripts/check.sh"
recibo "$D" revisor-funcional encuadre reentrada:C999 PASA 0
espera falla "F2 con recibo de reentrada:C999 (criterio inexistente) se rechaza" "C999 no está definido" -- commitea "$D" "reentrada

Ref: F2"
copia f3 z9; printf -- '- nota\n' >> "$D/docs/MEMORIA.md"
recibo "$D" revisor-funcional encuadre reentrada:C1 PASA 0
espera pasa "F2 con recibo de reentrada:C1 (criterio existente) se acepta" "" -- commitea "$D" "reentrada

Ref: F2"

echo "== Roles, YAML"
copia f3 a06; rm "$D/.claude/agents/juez-seguridad.md"
espera falla "quitar juez-seguridad.md se rechaza" "falta .claude/agents/juez-seguridad.md" -- commitea "$D" "docs

Ref: F1"
copia f3 a06b; rm -r "$D/.claude/skills/dirigiendo-revisiones"
espera falla "quitar dirigiendo-revisiones/ se rechaza" "falta .claude/skills/dirigiendo-revisiones" -- commitea "$D" "docs

Ref: F1"
yaml_desc() {  # yaml_desc <dir> <valor literal de description>
  python3 - "$1/.claude/agents/juez-codigo.md" "$2" <<'EOF'
import re,sys
p,v=sys.argv[1:]; s=open(p).read()
s=re.sub(r'^description: .*$', 'description: '+v.replace('\\','\\\\'), s, count=1, flags=re.M); open(p,'w').write(s)
EOF
}
copia f3 y1; yaml_desc "$D" '"Texto \q raro"'
espera falla "escape \\q en el frontmatter se rechaza" "escape inválido" -- commitea "$D" "docs

Ref: F1"
copia f3 y2; yaml_desc "$D" '"Texto \u12 corto"'
espera falla "escape \\u12 (unicode incompleto) se rechaza" "escape .u incompleto" -- commitea "$D" "docs

Ref: F1"
copia f3 y3; yaml_desc "$D" '"Texto \xGG"'
espera falla "escape \\xGG (hexadecimal ilegal) se rechaza" "escape .x incompleto o no hexadecimal" -- commitea "$D" "docs

Ref: F1"
copia f3 y4; yaml_desc "$D" '""'
espera falla "description vacía (\"\") se rechaza" "description vacía" -- commitea "$D" "docs

Ref: F1"
copia f3 y6; yaml_desc "$D" '"Texto "malo" y \n"'
espera falla "comilla interior sin escapar ANTES de un escape se rechaza (lectura completa)" "comilla doble interior" -- commitea "$D" "docs

Ref: F1"
copia f3 y7; yaml_desc "$D" '"abc\"'
espera falla "barra que escapa la comilla de cierre se rechaza" "sin cerrar" -- commitea "$D" "docs

Ref: F1"
copia f3 y8; yaml_desc "$D" '[]'
espera falla "description como lista ([]) se rechaza: tiene que ser texto" "lista, un mapa o un bloque" -- commitea "$D" "docs

Ref: F1"
copia f3 y9; yaml_desc "$D" 'null'
espera falla "description: null (nulo YAML, no texto) se rechaza" "nulo, booleano o número" -- commitea "$D" "docs

Ref: F1"
copia f3 y10; yaml_desc "$D" '~'
espera falla "description: ~ (nulo YAML) se rechaza" "nulo, booleano o número" -- commitea "$D" "docs

Ref: F1"
copia f3 y11; yaml_desc "$D" '"null"'
espera pasa "description: \"null\" entre comillas es texto y se acepta" "" -- commitea "$D" "docs

Ref: F1"
skill_desc() {  # skill_desc <dir> <valor literal>: description de una skill (mismo contrato que agentes)
  python3 - "$1/.claude/skills/revision-critica/SKILL.md" "$2" <<'EOF'
import re,sys
p,v=sys.argv[1:]; s=open(p).read()
s=re.sub(r'^description: .*$', lambda m: 'description: '+v, s, count=1, flags=re.M); open(p,'w').write(s)
EOF
}
copia f3 y12; skill_desc "$D" '# solo un comentario'
espera falla "description de skill que es solo un comentario (nulo en YAML) se rechaza" "revision-critica/SKILL.md: description vacía, en blanco, solo comentario" -- commitea "$D" "docs

Ref: F1"
copia f3 y13; skill_desc "$D" '"   "'
espera falla "description de skill en blanco (comillas con espacios) se rechaza" "revision-critica/SKILL.md: description vacía, en blanco" -- commitea "$D" "docs

Ref: F1"
copia f3 y14; yaml_desc "$D" "'   '"
espera falla "description de agente en blanco se rechaza (mismo contrato que skills)" "juez-codigo.md: description vacía, en blanco" -- commitea "$D" "docs

Ref: F1"
copia f3 y15; skill_desc "$D" '"Rúbrica del juez; el # dentro de comillas es texto" # y esto, comentario'
espera pasa "description de skill con # entre comillas y comentario al final se acepta" "" -- commitea "$D" "docs

Ref: F1"
copia f3 y16; skill_desc "$D" '"\u0020"'
espera falla "description de skill cuyo escape decodifica a un espacio (u0020) se rechaza" "revision-critica/SKILL.md: description vacía, en blanco" -- commitea "$D" "docs

Ref: F1"
copia f3 y17; yaml_desc "$D" '"\t"'
espera falla "description de agente cuyo escape decodifica a un tabulador se rechaza" "juez-codigo.md: description vacía, en blanco" -- commitea "$D" "docs

Ref: F1"
skill_clave() {  # skill_clave <dir> <l\u00ednea>: a\u00f1ade una l\u00ednea al frontmatter de una skill (tras description)
  python3 - "$1/.claude/skills/revision-critica/SKILL.md" "$2" <<'EOF'
import re,sys
p,l=sys.argv[1:]; s=open(p).read()
s=re.sub(r'^(description: .*)$', lambda m: m.group(1)+'\n'+l, s, count=1, flags=re.M); open(p,'w').write(s)
EOF
}
copia f3 y19; skill_clave "$D" 'disable-model-invocation: true'; skill_clave "$D" 'argument-hint: "[--update (default) | --create]"'
espera pasa "skill con disable-model-invocation y argument-hint (claves de Claude Code) se acepta" "" -- commitea "$D" "docs

Ref: F1"
copia f3 y20; skill_clave "$D" 'clave-inventada: x'
espera falla "skill con una clave de frontmatter desconocida se rechaza" "claves desconocidas: clave-inventada" -- commitea "$D" "docs

Ref: F1"
copia f3 y18; skill_desc "$D" '"Revisa \"todo\" con \u00e9nfasis\tantes del commit"'
espera pasa "description con palabras y escapes válidos se acepta" "" -- commitea "$D" "docs

Ref: F1"
copia f3 y5; yaml_desc "$D" '"Dice \"hola\", \u00e9 y \x41 \\ y sigue"'
espera pasa "comillas y escapes válidos se aceptan" "" -- commitea "$D" "docs

Ref: F1"

echo "== Arnés de sabotaje"
S="$W/sab"; mkdir -p "$S/scripts" "$S/docs"; en "$S" git init -q
cp "$RAIZ/scripts/suite.py" "$S/scripts/"; printf -- '- **Plazo de la suite:** 60 s\n' > "$S/docs/convenciones.md"
printf '#!/bin/sh\nif [ -f gate.sh ]; then\n  exit 0\nfi\necho "FAIL: gate"\nexit 1\n' > "$S/gate.sh"; chmod +x "$S/gate.sh"
printf '#!/bin/sh\nsh ./gate.sh\n' > "$S/scripts/check.sh"
printf '[{"label":"sin-fi","file":"gate.sh","before":"fi\\n","after":"\\n"}]\n' > "$S/sin_fi.json"
printf '[{"label":"gate-roto","file":"gate.sh","before":"-f gate.sh","after":"-f nope"}]\n' > "$S/gate.json"
printf '[{"label":"silencio","file":"gate.sh","before":"exit 0","after":"exit 1"}]\n' > "$S/silencio.json"
espera falla "mutante shell sin fi es INVALID (exit 2), no DIES" "INVALID" -- en "$S" python3 -I "$SAB" sin_fi.json
espera pasa "--suite ./gate.sh corre la copia mutada y el aserto (FAIL) acredita: DIES" "DIES" -- en "$S" python3 -I "$SAB" gate.json --suite ./gate.sh
espera falla "rojo sin firma de aserto (exit 1 mudo) es UNVERIFIED, no DIES" "UNVERIFIED" -- en "$S" python3 -I "$SAB" silencio.json --suite ./gate.sh
espera pasa "--trust-exit-code acepta el rojo mudo y lo declara en el resumen" "DIES.*|trust-exit-code" -- en "$S" python3 -I "$SAB" silencio.json --suite ./gate.sh --trust-exit-code
printf 'VALUE = 1\n' > "$S/cfg.py"; printf 'import cfg\nif cfg.VALUE != 1:\n    raise RuntimeError("helper fixture unavailable")\n' > "$S/app.py"
printf '#!/bin/sh\npython3 app.py || exit 1\nexit 0\n' > "$S/scripts/check.sh"
printf '[{"label":"helper","file":"cfg.py","before":"VALUE = 1","after":"VALUE = 2"}]\n' > "$S/helper.json"
espera falla "RuntimeError de un helper (sin aserto) no acredita: UNVERIFIED" "UNVERIFIED" -- en "$S" python3 -I "$SAB" helper.json
printf 'import cfg\nassert cfg.VALUE == 1, "VALUE cambió"\n' > "$S/app.py"
espera pasa "el mismo mutante con un aserto real sí muere: DIES" "DIES" -- en "$S" python3 -I "$SAB" helper.json
printf 'SELECT 1;\n' > "$S/query.sql"
printf '#!/bin/sh\npython3 -c "import sqlite3;sqlite3.connect(\\":memory:\\").executescript(open(\\"query.sql\\").read())" || exit 1\nexit 0\n' > "$S/scripts/check.sh"
printf '[{"label":"selec","file":"query.sql","before":"SELECT","after":"SELEC"}]\n' > "$S/sql.json"
espera falla "mutante SQL inválido (SELEC) no cuenta como garantía: INVALID/UNVERIFIED, exit 2" "INVALID|UNVERIFIED" -- en "$S" python3 -I "$SAB" sql.json
# R9-A02: el traceback CITA `assert helper()`, pero la causa terminal es el RuntimeError del helper.
printf 'import cfg\ndef helper():\n    if cfg.VALUE != 1:\n        raise RuntimeError("helper roto")\n    return True\nassert helper()\n' > "$S/app.py"
printf '#!/bin/sh\npython3 app.py || exit 1\nexit 0\n' > "$S/scripts/check.sh"
espera falla "helper que explota dentro de 'assert helper()' no acredita: UNVERIFIED, exit 2" "UNVERIFIED" -- en "$S" python3 -I "$SAB" helper.json
# Verificación R9-P01: AssertionError INTERMEDIO (envuelto con raise … from) no es la causa terminal.
printf 'import cfg\ndef helper():\n    try:\n        assert cfg.VALUE == 1\n    except AssertionError as exc:\n        raise RuntimeError("fixture setup unavailable") from exc\nhelper()\n' > "$S/app.py"
espera falla "AssertionError envuelto en RuntimeError (raise from) no acredita: la causa terminal manda, UNVERIFIED" "UNVERIFIED" -- en "$S" python3 -I "$SAB" helper.json
# Segunda pasada: la línea de la excepción se reconoce por POSICIÓN, no por sufijo del nombre.
for exc in Exception Indisponible; do
  printf 'import cfg\nclass Indisponible(Exception):\n    pass\ndef helper():\n    try:\n        assert cfg.VALUE == 1\n    except AssertionError as exc:\n        raise %s("fixture setup unavailable") from exc\nhelper()\n' "$exc" > "$S/app.py"
  espera falla "AssertionError envuelto en $exc (raise from) no acredita: UNVERIFIED" "UNVERIFIED" -- en "$S" python3 -I "$SAB" helper.json
done
printf 'import cfg\ntry:\n    if cfg.VALUE != 1:\n        raise RuntimeError("x")\nexcept RuntimeError:\n    assert False, "la aserción es la causa terminal"\n' > "$S/app.py"
espera pasa "AssertionError como causa TERMINAL (tras manejar un RuntimeError) sí acredita: DIES" "DIES" -- en "$S" python3 -I "$SAB" helper.json
# Piloto R9: el bytecode de la corrida base (python3 -I ignora PYTHONDONTWRITEBYTECODE) viajaba
# a la copia del mutante; una mutación del mismo tamaño escrita en el mismo segundo leía el .pyc
# viejo y «sobrevivía» sin correr. Se fuerza la condición: mtime al inicio de un segundo nuevo.
printf 'import sys; sys.path.insert(0, ".")\nimport cfg\nassert cfg.VALUE == 1, "VALUE cambió"\n' > "$S/app.py"; rm -rf "$S/__pycache__"
printf '#!/bin/sh\npython3 -I app.py || exit 1\nexit 0\n' > "$S/scripts/check.sh"
python3 -c 'import time; t=time.time(); time.sleep(1.02-(t%1))'; touch "$S/cfg.py" "$S/app.py"
espera pasa "mutación del mismo tamaño en el mismo segundo que la corrida base (suite con python3 -I, que escribe .pyc) no sobrevive por bytecode viejo: DIES" "DIES" -- en "$S" python3 -I "$SAB" helper.json
printf '#!/bin/sh\npython3 app.py || exit 1\nexit 0\n' > "$S/scripts/check.sh"
# R9-A03: --commit es un dato, nunca shell.
printf 'import cfg\nassert cfg.VALUE == 1, "VALUE cambió"\n' > "$S/app.py"
en "$S" git add -A >/dev/null && en "$S" git -c core.hooksPath=/dev/null commit -q -m base || die "no pude commitear el arnés"
espera falla "--commit con ';' se rechaza antes de ejecutar nada" "does not name a valid commit" -- en "$S" python3 -I "$SAB" helper.json --commit "HEAD; touch audit_marker.txt"
espera falla "... y no deja el marcador (nada se ejecutó)" "" -- test -e "$S/audit_marker.txt"
espera falla "--commit que empieza por '-' (opción de git) se rechaza" "does not name a valid commit" -- en "$S" python3 -I "$SAB" helper.json "--commit=--output=x"
espera pasa "--commit HEAD sigue funcionando: copia del commit y el aserto real muere (DIES)" "copy from commit HEAD" -- en "$S" python3 -I "$SAB" helper.json --commit HEAD
# Ronda 12 (C4): firmas de pytest sin depender de pytest (salida sintética), comillas en --suite,
# etiquetas del resumen y entradas externas declaradas con ejecución real (python3).
S2="$W/sab2"; mkdir -p "$S2/scripts" "$S2/docs"; en "$S2" git init -q; cp "$RAIZ/scripts/suite.py" "$S2/scripts/"
printf -- '- **Plazo de la suite:** 60 s\n' > "$S2/docs/convenciones.md"
printf 'VALUE = 1\n' > "$S2/cfg.py"
printf '[{"label":"cfg","file":"cfg.py","before":"VALUE = 1","after":"VALUE = 2"}]\n' > "$S2/m.json"
printf '[{"label":"perdida","file":"cfg.py","before":"NO ESTA","after":"x"}]\n' > "$S2/perdida.json"
pytest_falso() {  # pytest_falso <líneas de salida tras el rojo>: suite que imprime eso si cfg cambió
  { printf '#!/bin/sh\npython3 -c "import cfg,sys; sys.exit(cfg.VALUE != 1)" && exit 0\n'; printf "printf '%%s\\\\n' %s\nexit 1\n" "$1"; } > "$S2/scripts/check.sh"
}
pytest_falso "'_____ test_raise _____' 'E       Failed: DID NOT RAISE <class ValueError>' 'FAILED tests/test_x.py::test_raise - Failed: DID NOT RAISE <class ValueError>'"
espera pasa "pytest: «Failed: DID NOT RAISE» en el resumen es un aserto fallido: DIES" "DIES" -- en "$S2" python3 -I "$SAB" m.json
pytest_falso "'_____ test_raise _____' 'E       Failed: DID NOT RAISE <class ValueError>' 'FAILED tests/test_x.py::test_raise'"
espera pasa "pytest: resumen truncado sin causa, la línea E «DID NOT RAISE» acredita: DIES" "DIES" -- en "$S2" python3 -I "$SAB" m.json
pytest_falso "'_____ test_x _____' 'E       Failed: fixture no disponible' 'FAILED tests/test_x.py::test_x - Failed: fixture no disponible'"
espera falla "pytest: otro «Failed:» (pytest.fail) no se generaliza: UNVERIFIED" "UNVERIFIED" -- en "$S2" python3 -I "$SAB" m.json
pytest_falso "'ERROR tests/test_x.py - ModuleNotFoundError: No module named x' 'E   ModuleNotFoundError: No module named x'"
espera falla "pytest: error de colección/importación no acredita: INVALID o UNVERIFIED" "INVALID|UNVERIFIED" -- en "$S2" python3 -I "$SAB" m.json
espera falla "resumen: lo no verificado figura como aplicado sin veredicto válido (exit 2)" "applied, no valid verdict" -- en "$S2" python3 -I "$SAB" m.json
espera falla "resumen: un ancla perdida figura como no aplicada (exit 2)" "not applied \(stale or unsafe spec" -- en "$S2" python3 -I "$SAB" perdida.json
printf 'import sys, cfg\nassert sys.argv[1:] == ["dos palabras"], sys.argv\nassert cfg.VALUE == 1, "VALUE cambió"\n' > "$S2/args.py"
espera pasa "--suite con argumento entrecomillado llega entero (ejecución real): DIES" "DIES" -- en "$S2" python3 -I "$SAB" m.json --suite 'python3 args.py "dos palabras"'
espera falla "--suite con comillas sin cerrar se rechaza sin ejecutar" "cannot be split" -- en "$S2" python3 -I "$SAB" m.json --suite 'python3 args.py "dos'
mkdir -p "$S2/.venv/bin"; printf '#!/bin/sh\nexec python3 "$@"\n' > "$S2/.venv/bin/py"; chmod +x "$S2/.venv/bin/py"
printf '.venv/\n__pycache__/\n' > "$S2/.gitignore"
printf '# Convenciones\n\n- **Plazo de la suite:** 60 s\n\n| Ruta | Propósito | Cómo se reproduce |\n|------|-----------|-------------------|\n| .venv/ | intérprete | envoltorio |\n' > "$S2/docs/convenciones.md"
printf 'import cfg\nassert cfg.VALUE == 1, "VALUE cambió"\n' > "$S2/app.py"
printf '#!/bin/sh\n.venv/bin/py app.py\n' > "$S2/scripts/check.sh"
espera pasa "entrada externa declarada (.venv, excluido de la copia): se enlaza y el intérprete externo corre el código MUTADO: DIES" "DIES" -- en "$S2" python3 -I "$SAB" m.json
mkdir -p "$S2/.venv/lib"; printf '%s\n' "$(cd "$S2" && pwd -P)" > "$S2/.venv/lib/__editable__.app.pth"
espera falla "entrada externa con instalación editable hacia el original se rechaza" "points at the original tree" -- en "$S2" python3 -I "$SAB" m.json
rm "$S2/.venv/lib/__editable__.app.pth"; printf '__pycache__/\n' > "$S2/.gitignore"
espera falla "entrada externa declarada que git no ignora se rechaza" "is not ignored by git" -- en "$S2" python3 -I "$SAB" m.json

echo "== Sabotaje vigilado: cada corrida bajo scripts/suite.py del repositorio real (plazo, una a la vez)"
# $W/bin/ps es el ps de prueba de la sección del pre-commit: con $W/fantasma lista un miembro que
# sobrevive a KILL (SIMULADO). Las copias del sabotaje van a $W/tmpd-sab para ver qué conserva.
SV="$W/sabv"; mkdir -p "$SV/scripts" "$SV/docs" "$W/tmpd-sab" "$W/pids/sabv"; en "$SV" git init -q
cp "$RAIZ/scripts/suite.py" "$SV/scripts/"; printf -- '- **Plazo de la suite:** 20 s\n' > "$SV/docs/convenciones.md"
printf 'VALUE = 1\n' > "$SV/cfg.py"; printf '#!/bin/sh\npython3 app.py || exit 1\n' > "$SV/scripts/check.sh"
printf '[{"label":"cfg","file":"cfg.py","before":"VALUE = 1","after":"VALUE = 2"}]\n' > "$SV/m.json"
printf '[{"label":"uno","file":"cfg.py","before":"VALUE = 1","after":"VALUE = 2"},{"label":"dos","file":"cfg.py","before":"VALUE = 1","after":"VALUE = 3"}]\n' > "$SV/m2.json"
app_sv() { printf 'import cfg, glob, json, os, signal, subprocess, time\nREG = "%s"\nif cfg.VALUE != 1:\n%s\nassert cfg.VALUE == 1, "VALUE cambió"\n' "$SV/.git/suite-runs" "$1" > "$SV/app.py"; }
abierta_sv='    x = [json.load(open(p)) for p in glob.glob(REG + "/*.json")]; x = [r for r in x if r["estado"] == "abierta"][0]'
sabv() { ( cd "$SV" && export TMPDIR="$W/tmpd-sab" PATH="$W/bin:$PATH"; python3 -I "$SAB" "$@" ); }
ultimo_sv() { python3 -c 'import json,glob,sys; r=sorted((json.load(open(p)) for p in glob.glob(sys.argv[1]+"/*.json")), key=lambda x: x["inicio"]); print(r[-1]["estado"], r[-1]["plazo"], r[-1].get("incompleta",""), r[-1]["comando"][-1]) if r else print("sin-registro")' "$SV/.git/suite-runs"; }
copias_sv() { ls -d "$W/tmpd-sab"/sabotaje-* 2>/dev/null | wc -l | tr -d ' '; }
app_sv '    pass'
espera pasa "sabotaje normal: la corrida va vigilada y el aserto acredita (DIES)" "DIES" -- sabv m.json
espera pasa "... registrada en el repositorio real con el plazo común de convenciones (20 s)" "^fallida 20 " -- ultimo_sv
espera pasa "... y no deja copias" "^0$" -- copias_sv
sabv m.json --timeout 7 > /dev/null 2>&1
espera pasa "--timeout sobrescribe el plazo común" "^fallida 7 " -- ultimo_sv
P="$W/pids/sabv"
app_sv "    open('$P/nieto', 'w').write(str(subprocess.Popen(['sleep', '300']).pid)); open('$P/lider', 'w').write(str(os.getpid())); signal.signal(signal.SIGTERM, signal.SIG_IGN)
    while True: time.sleep(1)"
T0=$(date +%s)
espera falla "mutante que cuelga la suite: TIMEOUT, nunca DIES (exit 2)" "TIMEOUT .*exceeded its deadline" -- sabv m.json --timeout 3
espera pasa "... en menos de 20 s" "" -- test $(( $(date +%s) - T0 )) -lt 20
espera falla "... sin el líder vivo" "" -- kill -0 "$(cat "$P/lider" 2>/dev/null)"
espera falla "... ni su hijo" "" -- kill -0 "$(cat "$P/nieto" 2>/dev/null)"
espera pasa "... el registro la da por excedida" "^excedida 3 " -- ultimo_sv
espera pasa "... y no deja copias" "^0$" -- copias_sv
app_sv "    [ os.path.exists('$W/sabv-hecho') or open('$W/sabv-hecho', 'w') and open('$W/fantasma', 'w').write(str(os.getpgid(0))) ]"
espera falla "superviviente a KILL (simulado): el sabotaje entero se detiene, sin empezar el siguiente mutante" "STOPPED, no further mutant started: during uno: run .* ended as incompleta" -- sabv m2.json
espera pasa "... el registro sigue abierto e incompleto (bloquea)" "^abierta 20 fallida " -- ultimo_sv
espera pasa "... y la copia se conserva (es su directorio de trabajo)" "^1$" -- copias_sv
espera falla "... otro sabotaje no lanza nada: hay una abierta" "the suite did not start: another run is open" -- sabv m.json
espera pasa "... (sin dejar otra copia)" "^1$" -- copias_sv
rm -f "$W/fantasma"
espera pasa "... ido el superviviente, el siguiente la recupera y sigue (DIES)" "DIES" -- sabv m.json
rm -rf "$W/tmpd-sab"/sabotaje-*   # la copia conservada: su ejecución ya está cerrada (limpieza automática: bloque 3)
app_sv '    pass'
anidado() { ( export SUITE_ID=x; sabv "$@" ); }
espera falla "sabotaje lanzado desde dentro de otra ejecución: se detiene sin lanzar nada" "the suite did not start: called from inside another suite run" -- anidado m.json
grep -v 'Plazo de la suite' "$SV/docs/convenciones.md" > "$SV/c.tmp"; mv "$SV/c.tmp" "$SV/docs/convenciones.md"
espera falla "sin plazo común ni --timeout: se detiene explicando qué falta" "falta el plazo" -- sabv m.json
espera pasa "... y como no lanzó nada (sin registro suyo), no conserva copias" "^0$" -- copias_sv
printf -- '- **Plazo de la suite:** 20 s\n' > "$SV/docs/convenciones.md"
# Respaldo: el guardián no cierra a tiempo (congelado con SIGSTOP). SABOTAJE_RESPALDO acorta sus márgenes.
app_sv "$abierta_sv
    open('$P/guardia', 'w').write(str(x['guardia'])); os.kill(x['guardia'], signal.SIGSTOP); time.sleep(300)"
# acotado: si el respaldo faltara, el caso FALLA en vez de colgar la suite. Márgenes 3 s tras el
# plazo, 8 s de espera única para terminar + lanzador, 4 s para identificar la ejecución.
respaldo() { acotado 90 sh -c 'cd "$1" && export TMPDIR="$2" PATH="$3:$PATH" SABOTAJE_RESPALDO=3,8,4 && shift 3 && python3 -I "$0" "$@"' "$SAB" "$SV" "$W/tmpd-sab" "$W/bin" "$@"; }
T0=$(date +%s)
espera falla "respaldo: el guardián no cerró a tiempo y terminar no lo logra: el sabotaje se detiene y conserva" "STOPPED.*still open, incomplete or unverifiable after the backup" -- respaldo m2.json --timeout 2
# plazo 2 + 3 + UNA espera de 8 = 13 s más el arranque; dos esperas consecutivas llegarían a 21.
espera pasa "... con una sola espera acotada para terminar y lanzador (menos de 18 s)" "" -- test $(( $(date +%s) - T0 )) -lt 18
espera pasa "... la copia se conserva" "^1$" -- copias_sv
kill -CONT "$(cat "$P/guardia" 2>/dev/null)" 2>/dev/null
n=0; until [ "$(ultimo_sv | cut -d' ' -f1)" != abierta ] || [ $n -ge 60 ]; do n=$((n+1)); sleep 0.5; done
espera pasa "... (al reanudarse, el guardián la cierra)" "^terminada " -- ultimo_sv
rm -rf "$W/tmpd-sab"/sabotaje-*
app_sv "$abierta_sv
    os.kill(x['lanzador'], signal.SIGSTOP); os.kill(x['guardia'], signal.SIGKILL); open('$P/lider2', 'w').write(str(os.getpid())); time.sleep(300)"
espera falla "respaldo: sin guardián ni lanzador que respondan, terminar cierra la ejecución: TIMEOUT, no DIES" "TIMEOUT .*backup: run .* ended past its deadline" -- respaldo m.json --timeout 2
espera falla "... sin el líder vivo" "" -- kill -0 "$(cat "$P/lider2" 2>/dev/null)"
espera pasa "... y sin copias" "^0$" -- copias_sv
# Lanzador vivo que no registra su ejecución (atascado antes del registro): no hay identidad, así que
# no se señala nada; el sabotaje se detiene al vencer el margen de identificación y conserva la copia.
cp "$SV/scripts/suite.py" "$SV/suite.orig"
python3 - "$SV/scripts/suite.py" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
t = t.replace("def run(args) -> int:\n", "def run(args) -> int:\n    open(os.environ['SV_LANZADOR'], 'w').write(str(os.getpid())); time.sleep(300)\n", 1)
open(p, "w").write(t)
PY
export SV_LANZADOR="$P/lanzador"
T0=$(date +%s)
espera falla "lanzador sin registro: el sabotaje se detiene al vencer el margen de identificación" "STOPPED.*launcher [0-9]* still alive 4s after starting and it registered no run; nothing was signalled" -- respaldo m.json
espera pasa "... acotado (menos de 15 s)" "" -- test $(( $(date +%s) - T0 )) -lt 15
espera pasa "... no señala al lanzador (sigue vivo)" "" -- kill -0 "$(cat "$P/lanzador" 2>/dev/null)"
espera pasa "... y conserva la copia (el lanzador aún podría usarla)" "^1$" -- copias_sv
kill "$(cat "$P/lanzador" 2>/dev/null)" 2>/dev/null; rm -rf "$W/tmpd-sab"/sabotaje-*
echo '{roto' > "$SV/.git/suite-runs/zz.json"
espera falla "lanzador vivo con el registro no comprobable: se detiene sin señalar nada" "STOPPED.*launcher [0-9]* still alive 4s after starting and the registry could not be checked; nothing was signalled" -- respaldo m.json
espera pasa "... no señala al lanzador (sigue vivo)" "" -- kill -0 "$(cat "$P/lanzador" 2>/dev/null)"
espera pasa "... y conserva la copia" "^1$" -- copias_sv
kill "$(cat "$P/lanzador" 2>/dev/null)" 2>/dev/null; rm -rf "$W/tmpd-sab"/sabotaje-* "$SV/.git/suite-runs/zz.json"
unset SV_LANZADOR; mv "$SV/suite.orig" "$SV/scripts/suite.py"
# El vigilante es el scripts/suite.py del repositorio real: mutar el de la copia no lo desarma.
printf '[{"label":"vigilante","file":"scripts/suite.py","before":"deadline = deadline_of(args.plazo, workdir)","after":"deadline = 10 ** 6  # SABOTEADO"}]\n' > "$SV/vig.json"
app_sv "    pass" ; printf 'import time\nif "SABOTEADO" in open("scripts/suite.py").read():\n    while True: time.sleep(1)\n' > "$SV/app.py"
vig() { acotado 60 sh -c 'cd "$1" && TMPDIR="$2" PATH="$3:$PATH" python3 -I "$4" vig.json --timeout 3' _ "$SV" "$W/tmpd-sab" "$W/bin" "$SAB"; }
espera falla "mutar el suite.py de la copia no desarma el plazo: TIMEOUT a los 3 s" "TIMEOUT  vigilante" -- vig
SN="$W/sab-sin"; mkdir -p "$SN/scripts"; en "$SN" git init -q; printf 'VALUE = 1\n' > "$SN/cfg.py"; cp "$SV/m.json" "$SN/"
espera falla "proyecto sin scripts/suite.py: el sabotaje no corre sin vigilante" "scripts/suite.py is missing" -- en "$SN" python3 -I "$SAB" m.json

echo "== Recorrido F1→F5 y validación del historial"
R="$W/recorrido"; cp -R "$Z" "$R"
fase "$R" F5 "— «ninguno»"
espera pasa "F5: Ref: F5 con el conjunto de F4 vigente" "" -- commitea "$R" "cierre

Ref: F5"
espera pasa "doctor en verde sobre el proyecto cerrado" "" -- en "$R" sh scripts/check_docs.sh
espera pasa "doctor en modo cierre sobre el proyecto cerrado" "" -- en "$R" sh scripts/check_docs.sh cierre
espera pasa "validar_historial: todo el historial del recorrido cumple el contrato" "commits cumplen" -- en "$R" sh scripts/pruebas/validar_historial.sh HEAD
copia f3-tres v1; printf 'w = 1\n' >> "$D/app.py"
sin_hooks "$D" "colado sin trailer ni recibo" || die "no pude preparar el commit colado"
espera falla "validar_historial detecta el commit colado con --no-verify (sin trailer, código sin recibo)" "FALLO.*colado|falta el trailer" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD
espera pasa "validar_historial sobre el historial previo al colado sigue en verde" "commits cumplen" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1
copia f3-tres v2; printf 'SECRETO=x\n' > "$D/.env"; en "$D" git add -f .env; echo "- nota" >> "$D/docs/MEMORIA.md"
sin_hooks "$D" "cuela un .env

Ref: F1" || die "no pude preparar el commit con .env"
espera falla "validar_historial rechaza el .env colado con --no-verify (misma guarda que el pre-commit)" "guardas: .*\.env" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia f3-tres v3; printf -- '-----BEGIN RSA PRIVATE K''EY-----\nAAAA\n-----END RSA PRIVATE K''EY-----\n' > "$D/id_rsa.txt"; printf 'w = 1\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I4 PASA 0 seguridad=no-aplica
sin_hooks "$D" "cuela una llave

Ref: I4" || die "no pude preparar el commit con llave"
espera falla "validar_historial rechaza una llave privada colada con --no-verify" "llave privada" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia f3-tres v4; printf 'SECRETO=x\n' > "$D/.env"; en "$D" git add -f .env; echo "- nota" >> "$D/docs/MEMORIA.md"
espera falla "el pre-commit rechaza el mismo .env (misma guarda)" "\.env" -- commitea "$D" "memoria

Ref: F1"
copia f3-tres v6; printf 'SECRETO=x\n' > "$D/.env"; en "$D" git add -f .env
sin_hooks "$D" "cuela un .env

Ref: F1" || die "no pude preparar el .env versionado"
rm "$D/.env"
espera pasa "quitar un .env ya versionado se acepta (es la corrección)" "" -- commitea "$D" "quita el .env

Ref: F1"
espera pasa "validar_historial acepta el commit que quita el .env" "commits cumplen" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia f3-tres v7; printf 'SECRETO=x\n' > "$D/.env"; en "$D" git add -f .env
sin_hooks "$D" "cuela un .env

Ref: F1" || die "no pude preparar el .env versionado"
printf 'SECRETO=y\n' > "$D/.env"; echo "- nota" >> "$D/docs/MEMORIA.md"
espera falla "cambiar un .env ya versionado sigue rechazado" "guardas: .*\.env" -- commitea "$D" "memoria

Ref: F1"
copia f3-tres v8; mkdir -p "$D/sub"; printf 'API_URL=<api_url>\n' > "$D/sub/.env.example"
espera pasa "un .env.example en una subcarpeta entra sin Ref: I<n> (configuración, como en guardas.sh)" "" -- commitea "$D" "plantilla de configuración

Ref: F1"
copia f3-tres v9; mkdir -p "$D/sub"; printf 'x\n' > "$D/sub/x.env.example"
espera falla "un archivo que solo termina en .env.example sigue siendo código" "código fuera del rastro" -- commitea "$D" "no es plantilla

Ref: F1"
# Ramas: "rama" trae el hito y el I4 revisados; la principal avanza con un commit de rastro.
R2="$W/etapas/ramas"; cp -R "$W/etapas/f3-tres" "$R2"
en "$R2" git checkout -q -b rama && recibo "$R2" juez-conjunto hito hito:I1-I3 PASA 0 seguridad=no-aplica cubre=C1 excluye=ninguno componentes=app
commitea "$R2" "hito

Ref: hito:I1-I3" || die "no pude preparar la rama (hito)"
printf 'w = 1\n' >> "$R2/app.py"; recibo "$R2" juez-codigo incremento I4 PASA 0 seguridad=no-aplica
commitea "$R2" "I4

Ref: I4" || die "no pude preparar la rama (I4)"
en "$R2" git checkout -q master 2>/dev/null || en "$R2" git checkout -q main; echo "- nota" >> "$R2/docs/MEMORIA.md"; commitea "$R2" "memoria

Ref: F1" || die "no pude avanzar la rama principal"
echo "== Merges: limpio frente a contenido añadido al fusionar"
copia ramas v5
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-edit rama || die "no pude hacer el merge"
espera pasa "validar_historial acepta un merge limpio (árbol = fusión automática) sin trailer y valida los commits de la rama" "ok .*\(merge\)" -- en "$D" sh scripts/pruebas/validar_historial.sh "HEAD~4..HEAD"
copia ramas m1
espera pasa "con hooks activos, un merge limpio sin trailer se acepta localmente" "" -- en "$D" git -c core.hooksPath=.githooks merge -q --no-ff --no-edit rama
copia ramas m2
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-commit rama >/dev/null 2>&1; printf 'def nuevo():\n    return 1\n' > "$D/merge_only.py"; en "$D" git add merge_only.py
espera falla "con hooks activos, un merge que añade código al fusionar (merge_only.py) se rechaza" "cambia contenido respecto de la fusión" -- en "$D" git -c core.hooksPath=.githooks commit -q --no-edit
copia ramas m3
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-commit rama >/dev/null 2>&1; printf 'def nuevo():\n    return 1\n' > "$D/merge_only.py"; en "$D" git add merge_only.py
en "$D" git -c core.hooksPath=/dev/null commit -q --no-verify --no-edit || die "no pude colar el merge"
espera falla "validar_historial rechaza el merge con código añadido al fusionar, colado con --no-verify" "cambia contenido respecto de la fusión" -- en "$D" sh scripts/pruebas/validar_historial.sh "HEAD~1..HEAD"
copia ramas m5
python3 - "$D/app.py" <<'EOF'
import sys; p=sys.argv[1]; t=open(p).read(); open(p,'w').write('# cabecera de la principal\n'+t)
EOF
en "$D" git add -A && en "$D" git -c core.hooksPath=/dev/null commit -q --no-verify -m "principal toca app.py arriba" || die "no pude preparar el lado principal"
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-edit rama >/dev/null 2>&1 || die "git no fusionó app.py solo"
espera pasa "merge con fusión de contenido automática (ambos lados tocan app.py, sin conflicto) cuenta como limpio" "ok .*\(merge\)" -- en "$D" sh scripts/pruebas/validar_historial.sh "HEAD~1..HEAD"
copia ramas m4
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-commit rama >/dev/null 2>&1; printf '# Nota de la fusión\n' > "$D/docs/fusion.md"; en "$D" git add docs/fusion.md
espera pasa "un merge que solo añade rastro (docs/) con su trailer se acepta" "" -- en "$D" git -c core.hooksPath=.githooks commit -q -m "Merge rama con nota

Ref: F1"

# --- Filtro preventivo de revisores (.claude/hooks/guarda-revisor.py): NO es frontera; se prueba
#     que rechaza patrones evidentes, permite lecturas y respeta la modalidad «experimentos».
echo "== filtro preventivo de revisores"
GR="$RAIZ/.claude/hooks/guarda-revisor.py"; GW="$W/guarda"; mkdir -p "$GW/.git"
gr() {  # gr <agente> <comando>: corre el hook con la entrada JSON del evento PreToolUse
  python3 -c 'import json,sys; print(json.dumps({"agent_type":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]},"cwd":sys.argv[3]}))' "$1" "$2" "$GW" \
    | CLAUDE_PROJECT_DIR="$GW" python3 "$GR"
}
espera falla "revisor en lectura: rm se rechaza" "filtro preventivo" -- gr revisor-funcional 'rm -rf docs'
espera falla "revisor en lectura: redirección a un archivo se rechaza" "filtro preventivo" -- gr juez-codigo 'echo x > /tmp/salida.txt'
espera falla "revisor en lectura: git commit se rechaza" "filtro preventivo" -- gr juez-conjunto 'git commit -m x'
espera pasa "revisor en lectura: generar su recibo (recibos.sh linea, no escribe) se permite" "" -- gr juez-codigo 'sh scripts/recibos.sh linea rol=juez-codigo tipo=incremento alcance=I2 veredicto=PASA bloqueantes=0 seguridad=no-aplica ejecutor=juez-codigo modalidad=lectura filtro=comprobado aislamiento=ninguno'
espera falla "revisor en lectura: sed -i se rechaza" "filtro preventivo" -- gr juez-seguridad "sed -i '' s/a/b/ f"
espera pasa "revisor en lectura: la suite y las lecturas pasan" "" -- gr revisor-funcional 'sh scripts/check.sh 2>&1 | tail -3 && git log --oneline -3 > /dev/null'
espera pasa "revisor en lectura: un patrón entre comillas es una lectura" "" -- gr revisor-funcional 'grep -rn "a > b; rm -rf x" docs'
espera pasa "un agente que no es revisor no se filtra" "" -- gr general-purpose 'rm -rf docs'
espera pasa "revisor en lectura: consultar git config pasa" "" -- gr juez-codigo 'git config core.hooksPath && git config --get user.name && git config --list > /dev/null'
espera falla "revisor en lectura: escribir git config se rechaza" "git config \\(escritura\\)" -- gr juez-codigo 'git config user.name intruso'
espera falla "revisor en lectura: git config --unset se rechaza" "git config \\(escritura\\)" -- gr juez-codigo 'git config --unset core.hooksPath'
printf 'experimentos %s/aut\n' "$GW" > "$GW/.git/revision-modalidad"
espera pasa "revisor en experimentos: escribir en el directorio autorizado pasa" "" -- gr juez-conjunto "python3 x.py > $GW/aut/out.txt"
espera falla "revisor en experimentos: escribir fuera del directorio autorizado se rechaza" "solo en $GW/aut" -- gr juez-conjunto 'cp a /tmp/b'
# Cada escritura se juzga por su destino: nombrar el directorio autorizado en OTRO tramo no autoriza
# (caso reproducido en la medición: prueba de bloqueo en la misma línea que el doctor con TMPDIR=<autorizado>).
espera falla "experimentos: prueba de bloqueo sola se rechaza" "touch → $GW/.git/prueba-de-bloqueo" -- gr revisor-funcional "touch $GW/.git/prueba-de-bloqueo"
espera falla "experimentos: prueba de bloqueo seguida del doctor con TMPDIR autorizado se rechaza" "touch → $GW/.git/prueba-de-bloqueo" -- gr revisor-funcional "touch $GW/.git/prueba-de-bloqueo; echo rc=\$?; TMPDIR=$GW/aut sh scripts/check_docs.sh"
espera falla "experimentos: doctor con TMPDIR autorizado seguido de la prueba de bloqueo se rechaza" "touch → $GW/.git/prueba-de-bloqueo" -- gr revisor-funcional "TMPDIR=$GW/aut sh scripts/check_docs.sh && touch $GW/.git/prueba-de-bloqueo"
espera pasa "experimentos: el doctor con TMPDIR autorizado pasa" "" -- gr revisor-funcional "TMPDIR=$GW/aut sh scripts/check_docs.sh"
espera pasa "experimentos: cd al autorizado y escrituras relativas pasan" "" -- gr juez-conjunto "cd $GW/aut && mkdir -p d && touch d/f && git init -q"
espera falla "experimentos: cd fuera y escritura relativa se rechaza" "touch → $GW/f" -- gr juez-conjunto "cd $GW && touch f"
espera falla "experimentos: salir del autorizado con .. se rechaza" "rm → $GW/x" -- gr juez-conjunto "rm -rf $GW/aut/../x"
espera falla "experimentos: destino con variable no se da por permitido" "destino desconocido" -- gr juez-conjunto 'touch $HOME/x'
espera falla "experimentos: escritura dentro de \$( ) no se interpreta y se rechaza" "no interpreta" -- gr juez-conjunto "echo \$(touch $GW/aut/f)"
espera falla "experimentos: git commit en el proyecto se rechaza aunque otro tramo nombre el autorizado" "git → $GW" -- gr juez-conjunto "git commit -m x; ls $GW/aut"

# T4 (ronda 11): destinos entre comillas, opciones globales de git, mv con origen, destino indeterminable.
F="$W/fuera4"; mkdir -p "$F"
espera falla "experimentos: touch con destino entre comillas fuera del autorizado se rechaza" "touch → $F/archivo" -- gr juez-codigo "touch \"$F/archivo\""
espera falla "experimentos: cp con origen y destino entre comillas simples se rechaza" "cp → $F/b" -- gr juez-codigo "cp '$F/a' '$F/b'"
espera falla "experimentos: mv de un origen externo al autorizado se rechaza (el origen se modifica)" "mv → $F/origen" -- gr juez-codigo "mv $F/origen $GW/aut/destino"
espera falla "experimentos: git -C <fuera> add se rechaza" "git → $F" -- gr juez-codigo "git -C $F add archivo"
espera falla "experimentos: git -c clave=valor commit en el proyecto se rechaza" "git → $GW" -- gr juez-codigo "git -c user.name=x commit -m y"
espera falla "experimentos: git --git-dir con un subcomando que escribe es destino desconocido" "destino desconocido" -- gr juez-codigo "git --git-dir=$GW/aut/.git --work-tree=$GW/aut add x"
espera falla "experimentos: destino \$( ) entre comillas no se da por permitido" "no interpreta|destino desconocido" -- gr juez-codigo "touch \"\$(echo $F)/x\""
espera falla "experimentos: env rm (envoltorio) se juzga por su destino" "rm → $F/x" -- gr juez-codigo "env LC_ALL=C rm $F/x"
espera falla "experimentos: cd dentro de ( ) no cambia el directorio de fuera" "touch → $GW/x" -- gr juez-codigo "(cd $GW/aut && touch a) ; touch x"
espera falla "experimentos: una línea nueva separa tramos (cd y escritura)" "touch → $GW/y" -- gr juez-codigo "cd $GW
touch y"
espera falla "experimentos: una palabra de escritura sin destino ubicable se rechaza" "destino indeterminable|destino desconocido" -- gr juez-codigo "echo rm x"
espera pasa "experimentos (control): touch con destino entre comillas dentro del autorizado pasa" "" -- gr juez-codigo "touch \"$GW/aut/ok\""
espera pasa "experimentos (control): mv dentro del autorizado pasa" "" -- gr juez-codigo "mv $GW/aut/a $GW/aut/b"
espera pasa "experimentos (control): git -C <autorizado> init pasa" "" -- gr juez-codigo "git -C $GW/aut init -q"
espera pasa "experimentos (control): leer con git -C fuera (log) pasa" "" -- gr juez-codigo "git -C $F log --oneline -3"
espera pasa "experimentos (control): grep de 'rm -rf' entre comillas es lectura" "" -- gr juez-codigo 'grep -rn "rm -rf" docs'
espera pasa "experimentos (control): redirección 2>&1 y > /dev/null no son escrituras" "" -- gr juez-codigo 'sh scripts/check.sh 2>&1 | tail -3 > /dev/null'
# Segunda pasada de T4: destinos explícitos de git, incertidumbre por tramo, cd según operador.
mkdir -p "$GW/aut"
espera falla "experimentos: git -C <D> init <fuera>/repo se rechaza" "git → $F/repo" -- gr juez-codigo "git -C $GW/aut init $F/repo"
espera falla "experimentos: git -C <D> config --file <fuera> se rechaza" "git → $F/config" -- gr juez-codigo "git -C $GW/aut config --file $F/config a.b c"
espera falla "experimentos: git config --global es destino desconocido" "destino desconocido" -- gr juez-codigo "git -C $GW/aut config --global a.b c"
espera falla "experimentos: git archive -o <fuera> se rechaza" "git → $F/x.tar" -- gr juez-codigo "git -C $GW/aut archive -o $F/x.tar HEAD"
espera pasa "experimentos (control): git -C <D> init <D>/sub pasa" "" -- gr juez-codigo "git -C $GW/aut init -q $GW/aut/sub"
espera falla "experimentos: una escritura permitida no oculta otra indeterminable en otro tramo" "touch → (destino desconocido|$F/x)" -- gr juez-codigo "touch $GW/aut/ok; env -u VARIABLE touch $F/x"
espera falla "experimentos: tras un envoltorio desconocido (flock), la escritura de ese tramo es desconocida aunque otro tramo esté permitido" "touch → destino desconocido" -- gr juez-codigo "touch $GW/aut/ok; flock $F/lock touch $F/x"
espera pasa "experimentos (control): env -u VAR touch <D> pasa (la opción consume su argumento)" "" -- gr juez-codigo "env -u VARIABLE touch $GW/aut/ok"
espera falla "experimentos: env -C cambia el directorio: escritura relativa con destino desconocido" "destino desconocido" -- gr juez-codigo "env -C $F touch x"
espera falla "experimentos: cd en una tubería no cambia el directorio de fuera" "touch → $GW/x" -- gr juez-codigo "cd $GW/aut | cat; touch x"
espera falla "experimentos: cd a un directorio inexistente con ; deja el directorio incierto" "destino desconocido" -- gr juez-codigo "cd $GW/aut/inexistente; touch x"
espera falla "experimentos: cd X || escritura: corre si el cd falló, directorio incierto" "destino desconocido" -- gr juez-codigo "cd $GW/aut || touch x"
espera pasa "experimentos (control): cd <D existente>; touch relativo pasa" "" -- gr juez-codigo "cd $GW/aut; touch z"
espera pasa "experimentos (control): cd <D> && touch relativo pasa aunque <D>/nuevo aún no exista" "" -- gr juez-codigo "mkdir -p $GW/aut/nuevo && cd $GW/aut/nuevo && touch z"
# Tercera pasada de T4: opciones de git con su aridad; el camino de fallo de un cd encadenado con &&.
espera falla "experimentos: git clone --branch <rama> consume el valor y ve el destino de fuera" "git → $F/clon" -- gr juez-codigo "git -C $GW/aut clone -q --branch main $GW/aut/origen $F/clon"
espera falla "experimentos: git worktree add -b <rama> consume el valor y ve el destino de fuera" "git → $F/arbol" -- gr juez-codigo "git -C $GW/aut/origen worktree add -b rama $F/arbol"
espera falla "experimentos: git clone con una opción desconocida deja el destino desconocido" "destino desconocido" -- gr juez-codigo "git -C $GW/aut clone --opcion-rara x $GW/aut/o $GW/aut/c"
espera pasa "experimentos (control): git clone --branch dentro del autorizado pasa" "" -- gr juez-codigo "git -C $GW/aut clone -q --branch main $GW/aut/origen $GW/aut/clon"
espera pasa "experimentos (control): git worktree add -b dentro del autorizado pasa" "" -- gr juez-codigo "git -C $GW/aut/origen worktree add -b rama $GW/aut/arbol"
espera falla "experimentos: cd <inexistente> && …; escritura: si el cd falla, lo de después corre fuera" "destino desconocido" -- gr juez-codigo "cd $GW/aut/no-existe && true; touch x"
espera falla "experimentos: cd <inexistente> && … || escritura: el camino de fallo corre fuera" "destino desconocido" -- gr juez-codigo "cd $GW/aut/no-existe && true || touch x"
espera pasa "experimentos (control): cd <D existente> && …; escritura relativa pasa" "" -- gr juez-codigo "cd $GW/aut && true; touch z"
# Cuarta pasada de T4: opción de valor opcional (--shared) y operadores contiguos (`);`).
espera falla "experimentos: git init --shared no consume el destino de fuera" "git → $F/repo2" -- gr juez-codigo "git -C $GW/aut init --shared $F/repo2"
espera pasa "experimentos (control): git init --shared=group dentro pasa" "" -- gr juez-codigo "git -C $GW/aut init --shared=group $GW/aut/r"
espera falla "experimentos: (cd <D> && …); escritura relativa: el ) pegado al ; restaura el directorio" "touch → $GW/externo" -- gr juez-codigo "(cd $GW/aut && touch interno); touch externo"
espera falla "experimentos: (cd <D>)&&escritura relativa: el ) pegado al && restaura el directorio" "touch → $GW/y" -- gr juez-codigo "(cd $GW/aut)&&touch y"
espera pasa "experimentos (control): (cd <D> && touch interno); touch <D>/x pasa" "" -- gr juez-codigo "(cd $GW/aut && touch interno); touch $GW/aut/x"
rm -f "$GW/.git/revision-modalidad"
espera falla "lectura: git -C <otro> commit se rechaza" "git" -- gr juez-codigo "git -C $F commit -m x"
espera falla "lectura: git -c clave=valor commit se rechaza" "git" -- gr juez-codigo "git -c user.name=x commit -m y"
espera falla "lectura: touch con destino entre comillas se rechaza" "touch" -- gr juez-codigo "touch \"$F/x\""
espera falla "lectura: sh -c con una escritura en su texto se rechaza" "no interpreta" -- gr juez-codigo "sh -c 'touch $F/x'"
espera pasa "lectura (control): git -C <otro> log pasa" "" -- gr juez-codigo "git -C $F log --oneline -3"
espera pasa "lectura (control): grep con palabras de escritura entre comillas pasa" "" -- gr juez-codigo 'grep -rn "git commit; rm -rf x > y" docs'
espera pasa "lectura (límite declarado): python3 -c que abre un archivo no se ve" "" -- gr juez-codigo "python3 -c 'print(1)'"

# --- Captura de búsquedas (scripts/buscar.sh): lee con git grep contra un commit y escribe
# evidencia append-only; nunca guarda contenido ni toca archivos sensibles.
echo "== captura de búsquedas (buscar.sh)"
BW="$W/buscar"; mkdir -p "$BW/src" "$BW/docs" "$BW/otro"; BR="$BW/docs/busquedas.md"
( cd "$BW" && git init -q && printf 'uno firma\ndos\nfirma tres\n' > src/a.rs && printf 'nada\n' > src/b.rs \
  && printf 'TOKEN=firma\n' > .env && printf 'firma\n' > otro/c.md && git add -A && git commit -q -m base )
bus() { ( cd "$BW" && sh "$RAIZ/scripts/buscar.sh" "$@" ); }
reg_tiene() { grep -qF -- "$1" "$BR"; }
espera pasa "buscar: coincidencias registradas como archivo:línea" "B-1 registrada.*coincidencias" -- bus registrar --registro "$BR" -e firma --control otro/c.md -- src
espera pasa "buscar: el registro guarda la ubicación, no el contenido" "" -- sh -c "grep -qF 'coincidencias: src/a.rs:1, src/a.rs:3' '$BR' && ! grep -qF 'uno firma' '$BR'"
espera pasa "buscar: el control positivo queda registrado" "" -- reg_tiene "control: \`otro/c.md\` → líneas coincidentes: 1"
espera pasa "buscar: el .env no se busca ni se registra" "" -- sh -c "cd '$BW' && sh '$RAIZ/scripts/buscar.sh' registrar --registro '$BR' -e TOKEN -- . | grep -q 'sin coincidencias' && ! grep -q '\.env:' '$BR'"
espera pasa "buscar: sin coincidencias es resultado del alcance, no error" "sin coincidencias en el alcance" -- bus registrar --registro "$BR" -e zzz -- src
espera falla "buscar: una ruta sin archivos es error y se registra" "no tiene archivos de texto" -- bus registrar --registro "$BR" -e firma -- a.rs
espera pasa "buscar: la búsqueda fallida queda en el registro como no ejecutada" "" -- sh -c "tail -6 '$BR' | grep -q 'código de salida: no ejecutada'"
espera falla "buscar: un patrón inválido es error con su código" "parentheses|paréntesis|Unmatched|balanced" -- bus registrar --registro "$BR" -e 'a(' -- src
espera pasa "buscar: el patrón inválido se registra con código 128" "" -- sh -c "tail -6 '$BR' | grep -q 'código de salida: 128'"
espera pasa "buscar: -F trata el patrón como literal" "sin coincidencias" -- bus registrar --registro "$BR" -F -e 'a(' -- src
espera falla "buscar: un commit que no existe es error" "no se resuelve el commit" -- bus registrar --registro "$BR" --commit no-existe -e firma -- src
n_antes=$(wc -c < "$BR")
espera falla "buscar: un patrón con cabecera de llave se rechaza" "usa .*nombre llaves-privadas" -- bus registrar --registro "$BR" -e 'BEGIN RSA PRIVATE K''EY' -- .
espera falla "buscar: un patrón con un token largo se rechaza" "valores secretos" -- bus registrar --registro "$BR" -e 'abcdefghijklmnopqrstuvwxyz0123456789' -- .
espera pasa "buscar: los rechazos no escriben en el registro" "" -- test "$(wc -c < "$BR")" = "$n_antes"
espera pasa "buscar: la búsqueda con nombre no deja el patrón en el registro" "" -- sh -c "cd '$BW' && sh '$RAIZ/scripts/buscar.sh' registrar --registro '$BR' --nombre llaves-privadas -- . >/dev/null && grep -q 'nombre: llaves-privadas' '$BR' && ! grep -q 'PRIVATE' '$BR'"
espera falla "buscar: sin --registro no busca" "falta --registro" -- bus registrar -e firma -- src
ln -s "$BW/docs/fuera.md" "$BW/docs/enlace.md"
espera falla "buscar: un registro enlace simbólico se rechaza" "enlace simbólico" -- bus registrar --registro "$BW/docs/enlace.md" -e firma -- src
cp "$BR" "$W/buscar-previo.md"
espera pasa "buscar: append-only con identificador siguiente" "" -- sh -c "cd '$BW' && sh '$RAIZ/scripts/buscar.sh' registrar --registro '$BR' -e dos -- src | grep -q '^B-9 ' && head -c $(wc -c < "$W/buscar-previo.md") '$BR' | cmp -s - '$W/buscar-previo.md'"
h_antes=$(cksum < "$BR")
espera pasa "buscar: repetir reproduce una entrada" "B-1 reproduce" -- bus repetir --registro "$BR" B-1
espera pasa "buscar: repetir no escribe" "" -- test "$(cksum < "$BR")" = "$h_antes"
espera falla "buscar: repetir de una entrada con error se rechaza" "no hay resultado que reproducir" -- bus repetir --registro "$BR" B-4
sed 's/^- coincidencias: src\/a.rs:1, src\/a.rs:3$/- coincidencias: src\/a.rs:1/; s/^- líneas coincidentes: 2 (archivos: 1)$/- líneas coincidentes: 1 (archivos: 1)/' "$BR" > "$W/buscar-alterado.md"
espera falla "buscar: repetir detecta un resultado que no reproduce" "B-1 NO reproduce" -- bus repetir --registro "$W/buscar-alterado.md" B-1

echo "== Consumo: atribución por origen (transcripts sintéticos)"
# Ronda 12 (C6): principal y subagentes solo cuando la estructura lo permite; lo ambiguo queda sin
# atribuir; un mensaje repetido cuenta una vez; la suma es un subtotal medido, no un total.
msg() {  # msg <id> <salida> [campos extra JSON]: una línea assistant con usage
  printf '{"type":"assistant","requestId":"r%s",%s"message":{"id":"m%s","model":"modelo-x","usage":{"input_tokens":1,"cache_creation_input_tokens":10,"cache_read_input_tokens":100,"output_tokens":%s}}}\n' "$1" "${3:-}" "$1" "$2"
}
CP=python3; CS="$RAIZ/scripts/consumo.py"; K="$W/consumo"
mkdir -p "$K/solo" "$K/sub/s1/subagents" "$K/amb/s1/otra" "$K/dup/s1/subagents"
{ msg 1 5 '"isSidechain":false,'; msg 2 7 '"isSidechain":false,'; } > "$K/solo/s1.jsonl"
espera pasa "consumo: solo principal (sin anidados) se atribuye al principal y avisa que no vio subagentes" "principal 2, subagentes 0, sin atribuir 0.*NO está aquí|NO está aquí.*principal 2, subagentes 0, sin atribuir 0" -- sh -c "$CP '$CS' --dir '$K/solo' 2>&1 | tr '\n' ' '"
msg 1 5 '"isSidechain":false,' > "$K/sub/s1.jsonl"; msg 3 11 '"isSidechain":true,"agentId":"a1",' > "$K/sub/s1/subagents/agent-a1.jsonl"
espera pasa "consumo: subagente anidado (subagents/, isSidechain, agentId) se atribuye a subagentes" "principal 1, subagentes 1, sin atribuir 0" -- $CP "$CS" --dir "$K/sub"
espera pasa "consumo: el subtotal medido suma ambos orígenes sin duplicar (salida 5+11)" "^subtotal medido +2 +20 +200 +16$" -- $CP "$CS" --dir "$K/sub"
{ msg 1 5; msg 2 7 '"isSidechain":true,"agentId":"a9",'; } > "$K/amb/s1.jsonl"; msg 3 11 '"isSidechain":true,"agentId":"a1",' > "$K/amb/s1/otra/agent-a1.jsonl"
espera pasa "consumo: datos incompletos o ambiguos quedan sin atribuir, con aviso (no se fuerzan)" "principal 0, subagentes 0, sin atribuir 3.*hay llamadas sin atribuir|hay llamadas sin atribuir.*principal 0, subagentes 0, sin atribuir 3" -- sh -c "$CP '$CS' --dir '$K/amb' 2>&1 | tr '\n' ' '"
{ msg 1 5 '"isSidechain":false,'; msg 1 5 '"isSidechain":false,'; } > "$K/dup/s1.jsonl"
{ msg 2 7 '"isSidechain":true,"agentId":"a1",'; msg 2 7 '"isSidechain":true,"agentId":"a1",'; msg 1 5 '"isSidechain":true,"agentId":"a1",'; } > "$K/dup/s1/subagents/agent-a1.jsonl"
espera pasa "consumo: mensaje repetido cuenta una vez; si aparece en dos orígenes queda sin atribuir" "2 llamadas: principal 0, subagentes 1, sin atribuir 1" -- $CP "$CS" --dir "$K/dup"
espera pasa "consumo: --json conserva los campos anteriores y añade por_origen sin cambiar por_modelo" "" -- sh -c "$CP '$CS' --dir '$K/sub' --json | $CP -I -c 'import json,sys; d=json.load(sys.stdin); assert {\"dir\",\"archivos\",\"archivos_anidados\",\"llamadas\",\"por_modelo\"} <= set(d); assert d[\"por_modelo\"][\"modelo-x\"][\"output_tokens\"] == 16 and d[\"llamadas\"] == 2; assert d[\"por_origen\"][\"subagentes\"][\"modelo-x\"][\"output_tokens\"] == 11; assert d[\"llamadas_por_origen\"] == {\"principal\": 1, \"subagentes\": 1, \"sin_atribuir\": 0}'"
mkdir -p "$K/vacio"; printf '{"type":"user"}\n' > "$K/vacio/s1.jsonl"
espera falla "consumo: sin mensajes con usage falla en voz alta (nunca ceros que parezcan respuesta)" "0 mensajes con usage" -- $CP "$CS" --dir "$K/vacio"

echo
echo "regresion: $((TOTAL-MAL))/$TOTAL casos en verde"
if [ "$MAL" -gt 0 ]; then echo "FALLARON:$FALLIDOS"; exit 1; fi
exit 0
