#!/bin/sh
# Regresión de los HOOKS y SCRIPTS de la plantilla (viene con ella; README §Enforcement).
# Crea repositorios temporales y comprueba cada regla con su caso NEGATIVO (el hook
# rechaza) y su caso POSITIVO (acepta). Sin red, sin credenciales, sin clientes de IA:
# solo git, sh, awk y python3. Sin duración garantizada: crece con los casos (mediciones en
# README §Enforcement). Se ejecuta al cambiar lo que cubre (probando-con-datos-reales regla 10)
# y en CI de cada proyecto.
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
exec 3>&2   # acotado deja su foto de procesos aquí: fuera de la salida que espera captura y recorta
# Al salir, además de borrar $W, termina los PID que un caso dejó anotados en $W/pids (si falló).
trap 'find "$W/pids" -type f 2>/dev/null | while IFS= read -r f; do kill -9 "$(cat "$f")" 2>/dev/null; done; rm -rf "$W"' EXIT INT TERM
export GIT_AUTHOR_NAME=regresion GIT_AUTHOR_EMAIL=regresion@local
export GIT_COMMITTER_NAME=regresion GIT_COMMITTER_EMAIL=regresion@local
export GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_CONFIG_SYSTEM=/dev/null   # sin config del usuario
: > "$W/gitconfig"; git config --file "$W/gitconfig" --add safe.directory "*"
unset FASE_PREVIA REV SUITE_ID SUITE_REGISTRO SUITE_PLAZO SUITE_ENVUELTO SUITE_INFORME SUITE_PROPIA
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
C1_PEND='| C1 | «suma» | I1 | pendiente | |'
C1_VERIF='| C1 | «suma» | I1 | verificado | |'
# Todo check.sh, en cualquier fase, empieza por el bloque de la suite vigilada (check_docs lo exige y lo prueba).
BLOQUE=$(awk '/^# --- suite vigilada/{f=1} f{print} /^# --- fin suite vigilada/{exit}' "$RAIZ/docs/convenciones.md")
[ -n "$BLOQUE" ] || die "no encontré el bloque de la suite vigilada en docs/convenciones.md"
SUITE="#!/bin/sh
$BLOQUE"'
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
  printf '# Encuadre\n\n## Criterios de éxito\n\n- C1:\n\n## Set de oro (ejemplos de salida esperada)\n\n- Entrada: _…_ → Salida esperada: _…_\n' > "$B/docs/encuadre.md"
  printf '# Plan\n\n- [ ] I1 «…» — _…_ (satisface: C_)\n' > "$B/docs/plan.md"
  trazabilidad "$B" '| C1 | «…» | I_ | pendiente / cubierto / verificado | |' '| R-E._ | «…» | _…_ | abierto | — |' '| R-I_._ | «…» | I_ | C_ | _…_ | abierto | — |' '- _(ejemplo)_ `R-I_._ «alias» · verificado AAAA-MM-DD · commit abc1234`'
  for f in decisiones convenciones definicion-de-hecho despliegue MEMORIA; do printf '# %s\n\n(sintético)\n' "$f" > "$B/docs/$f.md"; done
  printf -- '- **Plazo de la suite:** 60 s\n' >> "$B/docs/convenciones.md"
  printf '# Registro de recibos (sintético). Las líneas que empiezan por # se ignoran.\n# contrato-recibos: 2\n' > "$B/docs/revisiones.log"
fi
rm -rf "$B/mejoras"
en "$B" git init -q && en "$B" git config core.hooksPath .githooks
chmod +x "$B"/.githooks/* "$B"/scripts/*.sh "$B"/scripts/pruebas/*.sh 2>/dev/null
en "$B" git add -A >/dev/null
for x in .githooks/pre-commit .githooks/pre-merge-commit .githooks/commit-msg scripts/check_docs.sh scripts/huella.sh scripts/recibos.sh scripts/trazabilidad.sh scripts/guardas.sh; do
  en "$B" git update-index --chmod=+x "$x"
done
echo "== etapa: plantilla recién copiada ($([ "$PRISTINA" -eq 1 ] && echo 'documentos de la plantilla' || echo 'documentos sintéticos'))"
espera pasa "arranque nuevo: primer commit Ref: F1 sobre la plantilla" "" -- commitea "$B" "Encuadre inicial

Ref: F1"

# E1: F2 cerrado (encuadre + plan + trazabilidad sembrada + suite), listo para I1.
P="$W/etapas/f2"; cp -R "$B" "$P"
printf '# AGENTS.md\n\nProyecto Demo: sumar dos números. Ver docs/.\n' > "$P/AGENTS.md"
printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: la función suma devuelve a+b para enteros.\n\n## Set de oro\n\n- suma(1, 2) → 3\n' > "$P/docs/encuadre.md"
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
copia f3 cr6; printf -- '- suma(2, 2) → 4\n' >> "$D/docs/encuadre.md"; printf 'y2 = 2\n' >> "$D/app.py"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "cambiar el set de oro dentro de Ref: I2 se rechaza" "contrato revisado" -- commitea "$D" "I2

Ref: I2"
copia f3 cr7; printf -- '- suma(2, 2) → 4\n' >> "$D/docs/encuadre.md"; recibo "$D" revisor-funcional encuadre reentrada:C1 PASA 0
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
copia plantilla cr10; for f in AGENTS.md docs/encuadre.md docs/plan.md docs/trazabilidad.md docs/decisiones.md docs/estado.md scripts/check.sh; do cp "$W/etapas/f2/$f" "$D/$f"; done
fase "$D" F3 "I1 «suma»"; printf 'def suma(a, b):\n    return a + b\n' > "$D/app.py"; recibo "$D" juez-codigo incremento I1 PASA 0 seguridad=no-aplica
espera falla "Ref: I1 sin ningún commit Ref: F2 en el historial se rechaza (sin plan aprobado no hay contrato)" "no hay ningún commit 'Ref: F2'" -- commitea "$D" "I1

Ref: I1"
copia f3 cr11; fase "$D" F5 "— «ninguno»"
espera falla "estado.md pasa a F5 con Ref: F1 (sin cierre) se rechaza" "entrar a la Fase 5" -- commitea "$D" "cierre fingido

Ref: F1"

echo "== Criterios históricos: lo que el último contrato revisado definía no se borra ni se renumera"
sin_c1() { python3 -I - "$1/docs/encuadre.md" <<'EOF'
import sys; p = sys.argv[1]; l = open(p).read().split("\n"); n = [x for x in l if not x.startswith("- C1:")]
assert len(n) == len(l) - 1; open(p, "w").write("\n".join(n))
EOF
}
copia f3 ch1; sin_c1 "$D"; printf -- '- C2: la función resta devuelve a-b.\n' >> "$D/docs/encuadre.md"; trazabilidad "$D" '| C2 | «resta» | I2 | pendiente | |' "" ""
espera falla "borrar C1 y su fila a la vez (coherente para el doctor) en un commit Ref: F1 se rechaza" "C1 estaba en el último contrato revisado.*desaparece" -- commitea "$D" "sin C1

Ref: F1"
copia f3 ch2; sed -i.bak 's/^- C1: /- C7: /' "$D/docs/encuadre.md" && rm -f "$D/docs/encuadre.md.bak"; trazabilidad "$D" '| C7 | «suma» | I1 | pendiente | |' "" ""
fase "$D" F2 "I2 «resta»"; recibo "$D" revisor-funcional encuadre F2 PASA 0
espera falla "renumerar C1 como C7 en una reentrada Ref: F2 con revisor funcional se rechaza" "C1 estaba en el último contrato revisado.*desaparece" -- commitea "$D" "renumera

Ref: F2"
copia f3 ch3; trazabilidad "$D" "" "" ""
espera falla "quitar solo la fila de Cobertura de C1 ya lo rechaza el doctor" "C1 está en encuadre.md pero no tiene fila" -- commitea "$D" "sin fila

Ref: F1"
copia f3 ch4; sin_c1 "$D"; printf -- '- C2: la función resta devuelve a-b.\n' >> "$D/docs/encuadre.md"; trazabilidad "$D" '| C2 | «resta» | I2 | pendiente | |' "" ""; sin_hooks "$D" "sin C1 colado

Ref: F1"
espera falla "validar_historial rechaza el criterio borrado con --no-verify" "C1 estaba en el último contrato revisado" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia f3 ch5; reescribe_c1 "$D"; fase "$D" F2 "I2 «resta»"; recibo "$D" revisor-funcional encuadre reentrada:C1 PASA 0
espera pasa "ajustar el texto de C1 por reentrada (mismo identificador) se acepta" "" -- commitea "$D" "reentrada C1

Ref: F2"
copia f3 ch6; printf -- '- C2: la función resta devuelve a-b.\n' >> "$D/docs/encuadre.md"; trazabilidad "$D" "$C1_PEND
| C2 | «resta» | I2 | pendiente | |" "" ""
fase "$D" F2 "I2 «resta»"; recibo "$D" revisor-funcional encuadre F2 PASA 0
espera pasa "añadir C2 por reentrada conservando C1 se acepta" "" -- commitea "$D" "requisito nuevo

Ref: F2"
# Ramas con contratos revisados distintos: al fusionarlas no desaparece un criterio de ninguno de los dos.
enc_crit() { printf '# Encuadre\n\n## Criterios de éxito\n\n%s\n## Set de oro\n\n- suma(1, 2) → 3\n' "$2" > "$1/docs/encuadre.md"; }
CR1='- C1: la función suma devuelve a+b para enteros.
'; CR2='- C2: la función resta devuelve a-b.
'; CR3='- C3: la función multiplica devuelve a*b.
'; CR4='- C4: la función divide devuelve a/b.
'
F_C2='| C2 | «resta» | I2 | pendiente | |'; F_C3='| C3 | «multiplica» | I3 | pendiente | |'; F_C4='| C4 | «divide» | I4 | pendiente | |'
principal() { en "$1" git checkout -q master 2>/dev/null || en "$1" git checkout -q main; }
contrato_f2() {  # contrato_f2 <dir> "<criterios>" "<filas>": reentrada Ref: F2 revisada (con hooks)
  enc_crit "$1" "$2"; trazabilidad "$1" "$3" "" ""; fase "$1" F2 "I2 «resta»"; recibo "$1" revisor-funcional encuadre F2 PASA 0
  commitea "$1" "contrato

Ref: F2"; }
ramas_contratos() {  # rama-a añade C2, rama-b añade C3, ambas desde el contrato con C1; deja rama-b activa
  en "$1" git checkout -q -b rama-a && contrato_f2 "$1" "$CR1$CR2" "$C1_PEND
$F_C2" || die "no pude preparar rama-a"
  principal "$1"; en "$1" git checkout -q -b rama-b && contrato_f2 "$1" "$CR1$CR3" "$C1_PEND
$F_C3" || die "no pude preparar rama-b"; }
# fusiona_resuelve <dir> <rama> "<criterios>" "<filas>": merge con conflictos, resuelto así; recibos de ambos lados
fusiona_resuelve() {
  log_p=$(en "$1" git show HEAD:docs/revisiones.log); en "$1" git -c core.hooksPath=/dev/null merge -q --no-ff --no-commit "$2" >/dev/null 2>&1
  { printf '%s\n' "$log_p"; en "$1" git show "$2:docs/revisiones.log" | grep -vxF "$log_p"; } > "$1/docs/revisiones.log"
  enc_crit "$1" "$3"; trazabilidad "$1" "$4" "" ""; fase "$1" F2 "I2 «resta»"; recibo "$1" revisor-funcional encuadre F2 PASA 0; }
copia f3 rm1; ramas_contratos "$D"; fusiona_resuelve "$D" rama-a "$CR1$CR2$CR3" "$C1_PEND
$F_C2
$F_C3"
espera pasa "ramas: el merge que conserva C1, C2 y C3 de los dos contratos se acepta" "" -- commitea "$D" "integra rama-a

Ref: F2"
copia f3 rm2; ramas_contratos "$D"; fusiona_resuelve "$D" rama-a "$CR1$CR3" "$C1_PEND
$F_C3"
espera falla "ramas: el merge que pierde C2 (del contrato de la rama integrada) se rechaza" "C2 .*contrato revisado" -- commitea "$D" "integra rama-a sin C2

Ref: F2"
copia f3 rm3; ramas_contratos "$D"; fusiona_resuelve "$D" rama-a "$CR1$CR3" "$C1_PEND
$F_C3"; en "$D" git add -A && en "$D" git -c core.hooksPath=/dev/null commit -q --no-verify -m "integra rama-a sin C2 (colado)

Ref: F2" || die "no pude colar el merge"
espera falla "ramas: el replay rechaza el merge colado que pierde C2" "C2 .*contrato revisado" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia f3 rm4; ramas_contratos "$D"; fusiona_resuelve "$D" rama-a "$CR1$CR2" "$C1_PEND
$F_C2"
espera falla "ramas: el merge que pierde C3 (del contrato del primer padre) se rechaza" "C3 .*contrato revisado" -- commitea "$D" "integra rama-a sin C3

Ref: F2"
# Un requisito retirado ANTES de esta regla (aquí, un Ref: F2 colado en la principal que quita C1) no se
# vuelve a exigir al integrar una rama que se abrió antes de esa retirada.
copia f3 rm5; en "$D" git checkout -q -b rama-a && contrato_f2 "$D" "$CR1$CR2" "$C1_PEND
$F_C2" || die "no pude preparar rama-a en rm5"
principal "$D"; enc_crit "$D" "$CR4"; trazabilidad "$D" "$F_C4" "" ""; fase "$D" F2 "I2 «resta»"
sin_hooks "$D" "retira C1 antes de la regla (colado)

Ref: F2"
fusiona_resuelve "$D" rama-a "$CR2$CR4" "$F_C2
$F_C4"
espera pasa "ramas: un criterio retirado antes de la regla (C1) no se vuelve a exigir al integrar una rama antigua" "" -- commitea "$D" "integra rama-a

Ref: F2"

# Selección del contrato sin depender de fechas: una rama antigua con un Ref: F2 de fecha POSTERIOR,
# integrada por un merge que no es Ref: F2, no pasa a ser «el último contrato» de la línea integrada.
copia f3 rm6; en "$D" git checkout -q -b vieja; principal "$D"
contrato_f2 "$D" "$CR1$CR2" "$C1_PEND
$F_C2" || die "no pude preparar el contrato con C2 en la principal"
en "$D" git checkout -q vieja; reescribe_c1 "$D"; fase "$D" F2 "I2 «resta»"; recibo "$D" revisor-funcional encuadre reentrada:C1 PASA 0
en "$D" git add -A && GIT_COMMITTER_DATE="2030-01-01T00:00:00Z" GIT_AUTHOR_DATE="2030-01-01T00:00:00Z" en "$D" git -c core.hooksPath=.githooks commit -q -m "reentrada C1 en una rama vieja (fecha posterior)

Ref: F2" || die "no pude preparar la rama vieja"
principal "$D"; C1V=$(en "$D" git show vieja:docs/encuadre.md | grep '^- C1:')
fusiona_resuelve "$D" vieja "$C1V
$CR2" "$C1_PEND
$F_C2"
commitea "$D" "integra la rama vieja conservando C2 (sin nueva revisión)

Ref: F1" || die "no pude integrar la rama vieja"
sin_c2() { python3 -I - "$1/docs/encuadre.md" <<'EOF'
import sys; p = sys.argv[1]; l = open(p).read().split("\n"); n = [x for x in l if not x.startswith("- C2:")]
assert len(n) == len(l) - 1; open(p, "w").write("\n".join(n))
EOF
}
sin_c2 "$D"; trazabilidad "$D" "$C1_PEND" "" ""
espera falla "ramas: tras integrar una rama vieja con un Ref: F2 de fecha posterior, quitar C2 se rechaza (no se elige el contrato por fecha)" "C2 estaba en el último contrato revisado" -- commitea "$D" "quita C2

Ref: F1"

# Errores del cálculo de criterios exigidos: una lectura imposible o un calculador que falla rechazan el
# commit con diagnóstico; nunca equivalen a «sin criterios exigidos».
copia f3 ce1; printf -- '- C2: la función resta devuelve a-b.\n' >> "$D/docs/encuadre.md"; trazabilidad "$D" "$C1_PEND
$F_C2" "" ""
commitea "$D" "borrador con C2

Ref: F1" || die "no pude preparar ce1"
b=$(en "$D" git rev-parse HEAD~1:docs/encuadre.md); o="$D/.git/objects/$(printf '%s' "$b" | cut -c1-2)/$(printf '%s' "$b" | cut -c3-)"
[ "$b" != "$(en "$D" git rev-parse HEAD:docs/encuadre.md)" ] && [ -f "$o" ] && rm -f "$o" || die "PREPARACIÓN: no pude retirar el encuadre del contrato en ce1"
rm -rf "$W/ce1b"; cp -R "$D" "$W/ce1b"
printf -- '- nota\n' >> "$D/docs/MEMORIA.md"
espera falla "errores: si el encuadre del contrato revisado no se puede leer, el commit se rechaza con diagnóstico" "no pude calcular los criterios que exige el contrato revisado \(salida 2\).*git show" -- commitea "$D" "nota

Ref: F1"
printf -- '- nota\n' >> "$W/ce1b/docs/MEMORIA.md"; sin_hooks "$W/ce1b" "nota colada

Ref: F1"
espera falla "errores: el replay también rechaza ese commit con diagnóstico" "no pude calcular los criterios que exige el contrato revisado" -- en "$W/ce1b" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
# Un python3 de prueba que solo intercepta el calculador (lo reconoce por su código) y simula su fallo.
REAL_PY=$(command -v python3); mkdir -p "$W/py-falla" "$W/py-parcial" "$W/py-forma"
for m in falla parcial forma; do
  printf '#!/bin/sh\ncase "$*" in *"class NoCalculable"*)\n  case %s in falla) echo "Traceback: fallo simulado" >&2; exit 1 ;; parcial) echo "C1 0123456789abcdef0123456789abcdef01234567"; exit 137 ;; forma) echo "C1"; exit 0 ;; esac ;;\nesac\nexec "%s" "$@"\n' "$m" "$REAL_PY" > "$W/py-$m/python3"; chmod +x "$W/py-$m/python3"
done
copia f3 ce2; printf -- '- nota\n' >> "$D/docs/MEMORIA.md"
espera falla "errores: un calculador que termina con error rechaza el commit" "no pude calcular los criterios que exige el contrato revisado \(salida 1\)" -- env PATH="$W/py-falla:$PATH" sh -c 'cd "$1" && git add -A && git -c core.hooksPath=.githooks commit -q -m "nota

Ref: F1"' _ "$D"
copia f3 ce3; printf -- '- nota\n' >> "$D/docs/MEMORIA.md"
espera falla "errores: una salida parcial seguida de un error no vale como resultado" "no pude calcular los criterios que exige el contrato revisado \(salida 137\)" -- env PATH="$W/py-parcial:$PATH" sh -c 'cd "$1" && git add -A && git -c core.hooksPath=.githooks commit -q -m "nota

Ref: F1"' _ "$D"
copia f3 ce4; printf -- '- nota\n' >> "$D/docs/MEMORIA.md"
espera falla "errores: una salida sin la forma «C<n> sha» no vale aunque termine con 0" "no pude calcular los criterios que exige el contrato revisado \(salida 0\)" -- env PATH="$W/py-forma:$PATH" sh -c 'cd "$1" && git add -A && git -c core.hooksPath=.githooks commit -q -m "nota

Ref: F1"' _ "$D"
copia f3 ce5; printf -- '- nota\n' >> "$D/docs/MEMORIA.md"
espera pasa "errores: control del envoltorio: sin interceptar, el mismo commit se acepta" "" -- commitea "$D" "nota

Ref: F1"

copia plantilla ch7; sin_c1 "$D"
espera pasa "sin contrato anterior (antes del primer Ref: F2) no se exige ningún criterio: el borrador se edita libremente" "" -- commitea "$D" "borrador

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
copia f3 cc1; printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: la función suma devuelve a+b para enteros.\n  Las entradas inválidas se rechazan.\n\n## Set de oro\n\n- suma(1, 2) → 3\n' > "$D/docs/encuadre.md"
espera falla "el doctor rechaza un criterio con texto de continuación (sangrado)" "continuación" -- en "$D" sh scripts/check_docs.sh
copia f3 cc1b; printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: la función suma devuelve a+b para enteros.\nLas entradas inválidas se rechazan.\n\n## Set de oro\n\n- suma(1, 2) → 3\n' > "$D/docs/encuadre.md"
espera falla "el doctor rechaza un criterio con continuación perezosa (sin sangría)" "continuación" -- en "$D" sh scripts/check_docs.sh
copia f3 cc2; printf '# Encuadre\n\n## Criterios de éxito\n\n<!-- nota -->\n- C1: la función suma devuelve a+b para enteros.\n- C2: resta devuelve a-b.\n\n## Set de oro\n\n- par\n' > "$D/docs/encuadre.md"; trazabilidad "$D" "$C1_PEND
| C2 | «resta» | I2 | pendiente | |" "" ""
espera pasa "criterios de una línea seguidos de otro ítem, blanco, comentario o encabezado pasan el doctor" "" -- en "$D" sh scripts/check_docs.sh
copia f3 cc3; printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: la función suma devuelve a+b para enteros.\n\n  Las entradas inválidas se rechazan.\n\n## Set de oro\n\n- suma(1, 2) → 3\n' > "$D/docs/encuadre.md"
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
suite_es() { printf '#!/bin/sh\n%s\n%s\n' "$BLOQUE" "$2" > "$1/scripts/check.sh"; sin_hooks "$1" "suite (preparación)

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
printf '#!/bin/sh\n%s\ngit ls-files --error-unmatch README.md >/dev/null && [ -z "$(git status --porcelain --untracked-files=no)" ]\n' "$BLOQUE" > "$N/scripts/check.sh"
en "$N" git init -q; en "$N" git config core.hooksPath .githooks; chmod +x "$N"/.githooks/*; en "$N" git add -A
for x in .githooks/pre-commit .githooks/pre-merge-commit .githooks/commit-msg; do en "$N" git update-index --chmod=+x "$x"; done
espera pasa "primer commit del repositorio (sin HEAD): la suite corre en la instantánea" "" -- commitea "$N" "Encuadre inicial

Ref: F1"

echo "== Suite vigilada en el pre-commit (arranque protegido de check.sh sobre la instantánea)"
# El bloque, tal cual de docs/convenciones.md; los temporales de estos casos (instantánea, carpeta de
# la ejecución) van a $W/tmpd: TMPDIR explícito, que el pre-commit respeta con su plantilla de mktemp.
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
  suite_es "$1" "$3"
}
# acotado <seg> cmd...: si la garantía se rompe y el commit se cuelga, el caso FALLA (124) en vez de colgar.
# Antes de matar su grupo, deja en el fd 3 (stderr de la suite) la foto de los procesos de ese grupo y de
# los que nombran $W (guardianes y suites en otra sesión): es la evidencia de QUÉ se colgó.
acotado() { python3 -c '
import os, signal, subprocess, sys
w, secs, cmd = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
p = subprocess.Popen(cmd, start_new_session=True)
try:
    sys.exit(p.wait(timeout=secs))
except subprocess.TimeoutExpired:
    try:
        ps = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,pgid=,stat=,etime=,command="], capture_output=True,
                            text=True, timeout=10).stdout.splitlines()
        foto = [l for l in ps if l.split()[2] == str(p.pid) or w in l]
    except Exception as exc:
        foto = [f"(sin foto: {exc})"]
    try:
        with os.fdopen(3, "w") as f3:
            print(f"acotado: no terminó en {secs}s: {cmd[:3]}; procesos (pid ppid pgid stat etime command):", file=f3)
            print("\n".join("    " + l[:300] for l in foto), file=f3)
    except OSError:
        pass
    os.killpg(p.pid, signal.SIGKILL); p.wait(); print("acotado: no terminó", file=sys.stderr); sys.exit(124)
' "$W" "$@"; }
# nota_acotada <dir> <nombre>: nota_f1 con el commit acotado, TMPDIR y ps de prueba (casos sv*).
nota_acotada() { acotado 90 sh -c 'cd "$1" && export TMPDIR="$2" PATH="$3:$PATH" && printf -- "- nota %s\n" "$4" >> docs/MEMORIA.md && git add -A && git -c core.hooksPath=.githooks commit -q -m "nota

Ref: F1"' _ "$1" "$W/tmpd" "$W/bin" "$2"; }
registro_de() { python3 -c 'import json,glob,sys; r=sorted((json.load(open(p)) for p in glob.glob(sys.argv[1]+"/.git/suite-runs/*.json")), key=lambda x: x["inicio"]); print(r[-1]["estado"], r[-1]["dir"], r[-1].get("incompleta","")) if r else print("sin-registro")' "$1"; }
copia f3 sv1; vigilada "$D" 20 'echo "cuerpo en $(pwd -P)"; python3 app.py || exit 1'
espera pasa "check.sh con el bloque: el pre-commit lo corre vigilado y el commit pasa" "cuerpo en /.*/tmpd/precommit-snap\." -- nota_acotada "$D" sv1
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
espera falla "superviviente a KILL (simulado) en el pre-commit: rechaza por terminación incompleta" "quedaron procesos suyos vivos" -- nota_acotada "$D" sv3a
espera pasa "... el registro sigue abierto e incompleto" "^abierta .* aprobada$" -- registro_de "$D"
espera pasa "... y su instantánea (directorio de trabajo de los procesos vivos) se conserva con sus archivos" "" -- test -f "$(registro_de "$D" | cut -d' ' -f2)/scripts/check.sh"
S3=$(dirname "$(registro_de "$D" | cut -d' ' -f2)")
espera falla "... el siguiente commit se rechaza: hay otra ejecución abierta" "otra ejecución de la suite abierta" -- nota_acotada "$D" sv3b
rm -f "$W/fantasma"
espera pasa "... ido el superviviente, el siguiente commit la recupera y pasa" "recupero la ejecución" -- nota_acotada "$D" sv3c
espera falla "... y recupera sola la instantánea conservada (reclamada, hook terminado, ejecución cerrada)" "" -- test -e "$S3"
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
S4=$(dirname "$(registro_de "$D" | cut -d' ' -f2)")
espera pasa "... terminarla después es posible y no deja vivo al líder" "" -- en "$D" python3 scripts/suite.py terminar "${sid:-sin-id}"
espera falla "... (líder muerto)" "" -- kill -0 "$(cat "$P/lider" 2>/dev/null)"
espera pasa "... cerrada, recuperar borra la instantánea sin intervención" "recupero la carpeta propia $S4" -- en "$D" python3 scripts/suite.py recuperar
espera falla "... (ya no existe)" "" -- test -e "$S4"
# sv8: el hook muere (KILL, sin trampa) con su lanzador atascado ANTES de sumarse a la reclamación: el
# lanzamiento anunciado y la identidad dejada antes del exec conservan la instantánea mientras el
# lanzador viva, y se recupera cuando termine. (Solo se atasca dentro de una instantánea: la prueba
# aislada de check_docs usa el mismo suite.py y no debe colgarse.)
P="$W/pids/sv8"; mkdir -p "$P"
copia f3 sv8; vigilada "$D" 20 "python3 app.py || exit 1"
python3 - "$D/scripts/suite.py" "$P/lanzador" <<'PY'
import sys
p, f = sys.argv[1], sys.argv[2]; t = open(p).read()
hook = (f"    if 'precommit-snap' in os.getcwd():\n"
        f"        open({f!r}, 'w').write(str(os.getpid())); time.sleep(300)\n")
open(p, "w").write(t.replace("def run(args) -> int:\n", "def run(args) -> int:\n" + hook, 1))
PY
acotado 60 sh -c 'cd "$1" && export TMPDIR="$2" PATH="$3:$PATH" && printf -- "- nota sv8\n" >> docs/MEMORIA.md && git add -A && git -c core.hooksPath=.githooks commit -q -m "nota

Ref: F1"' _ "$D" "$W/tmpd" "$W/bin" > "$P/salida" 2>&1 &
bg=$!
n=0; until [ -s "$P/lanzador" ] || [ $n -ge 150 ]; do n=$((n+1)); sleep 0.2; done
lz=$(cat "$P/lanzador" 2>/dev/null); hk=$(ps -o ppid= -p "${lz:-0}" 2>/dev/null | tr -d ' ')
kill -9 "${hk:-0}" 2>/dev/null; wait $bg
S8=$(ls -td "$W/tmpd"/precommit-snap.* 2>/dev/null | head -1); S8=$(cd "${S8:-/sin-instantanea}" 2>/dev/null && pwd -P)
espera pasa "hook muerto con el lanzador atascado antes de sumarse: recuperar conserva la instantánea" "carpeta propia $S8: se conserva: su lanzador \\(pid ${lz:-sin-pid}\\) sigue vivo" -- en "$D" python3 scripts/suite.py recuperar
espera pasa "... (sigue presente)" "" -- test -d "${S8:-/sin-instantanea}/r"
kill "${lz:-0}" 2>/dev/null; n=0; while kill -0 "${lz:-0}" 2>/dev/null && [ $n -lt 25 ]; do n=$((n+1)); sleep 0.2; done
espera pasa "... terminado el lanzador, se recupera" "recupero la carpeta propia $S8" -- en "$D" python3 scripts/suite.py recuperar
espera falla "... (ya no existe)" "" -- test -e "${S8:-/sin-instantanea}"
rm -rf "$W/tmpd"/precommit.* 2>/dev/null   # la exportación del índice del hook muerto (sin su trampa)
# sv9: la limpieza REAL del hook (su función limpiar, extraída tal cual) con la instantánea reclamada y
# un lanzador vivo que aún no creó su ejecución (ningún .json): no basta la falta de ejecuciones abiertas.
P="$W/pids/sv9"; mkdir -p "$P" "$W/reg-sv9" "$W/tmpd"
LIMPIAR=$(sed -n '/^  limpiar() {/,/^  }/p' "$RAIZ/.githooks/pre-commit")
[ -n "$LIMPIAR" ] || die "no encuentro la función limpiar del pre-commit"
limpia_sv9() {  # limpia_sv9 <instantánea> <token>: corre limpiar() con su contexto (exportación propia)
  mkdir -p "$W/exp-sv9/scripts" && cp "$RAIZ/scripts/suite.py" "$W/exp-sv9/scripts/"
  env tmp="$W/exp-sv9" snap="$1" sreg="$W/reg-sv9" propia="$2" LIMPIA= sh -c "$LIMPIAR
limpiar"
}
sv9() { SUITE_REGISTRO="$W/reg-sv9" python3 "$RAIZ/scripts/suite.py" "$@"; }
sleep 300 & echo $! > "$P/dueno"
S9=$(mktemp -d "$W/tmpd/precommit-snap.XXXXXX"); S9=$(cd "$S9" && pwd -P)
T9=$(sv9 reclamar "$S9" --dueno "$(cat "$P/dueno")"); sv9 anunciar "$T9"; echo t > "$S9/testigo"
sleep 300 & echo $! > "$P/lanzador"; sv9 sumar "$T9" --pid "$(cat "$P/lanzador")"
espera pasa "limpiar() con un lanzador vivo sin ejecución registrada: conserva la instantánea y dice por qué" "conservo la instantánea $S9: su lanzador \\(pid $(cat "$P/lanzador")\\) sigue vivo" -- limpia_sv9 "$S9" "$T9"
espera pasa "... (sigue con su testigo)" "" -- test -f "$S9/testigo"
S9b=$(mktemp -d "$W/tmpd/precommit-snap.XXXXXX"); S9b=$(cd "$S9b" && pwd -P)
T9b=$(sv9 reclamar "$S9b" --dueno "$(cat "$P/dueno")"); sv9 anunciar "$T9b"
espera pasa "limpiar() con un lanzamiento anunciado sin identidad: conserva la instantánea (no comprobable)" "conservo la instantánea $S9b: no comprobable \\(1 lanzamiento" -- limpia_sv9 "$S9b" "$T9b"
kill "$(cat "$P/lanzador")" "$(cat "$P/dueno")" 2>/dev/null; n=0; while kill -0 "$(cat "$P/lanzador")" 2>/dev/null && [ $n -lt 25 ]; do n=$((n+1)); sleep 0.2; done
espera pasa "... terminado el lanzador, la recuperación borra la primera" "recupero la carpeta propia $S9" -- sv9 recuperar
espera falla "... (ya no existe)" "" -- test -e "$S9"
espera pasa "... y la segunda sigue conservada: su lanzamiento nunca tuvo identidad" "$S9b: se conserva: no comprobable" -- sv9 recuperar
sleep 300 & echo $! > "$P/dueno"
S9c=$(mktemp -d "$W/tmpd/precommit-snap.XXXXXX"); S9c=$(cd "$S9c" && pwd -P)
T9c=$(sv9 reclamar "$S9c" --dueno "$(cat "$P/dueno")"); sv9 anunciar "$T9c"; sv9 sumar "$T9c" --pid "$(cat "$P/dueno")"
kill "$(cat "$P/dueno")"; n=0; while kill -0 "$(cat "$P/dueno")" 2>/dev/null && [ $n -lt 25 ]; do n=$((n+1)); sleep 0.2; done
o9=$(limpia_sv9 "$S9c" "$T9c" 2>&1)
espera pasa "limpiar() con su lanzador terminado y nada abierto: borra la instantánea sin avisar" "" -- test -z "$o9"
espera falla "... (ya no existe)" "" -- test -e "$S9c"
rm -rf "$S9b"
# sv9b: salida REAL del hook por TERM, que sí ejecuta su trampa. sh difiere la trampa hasta que acaba
# el lanzador en primer plano: mientras viva, el hook no limpia nada; al acabar, limpia y la borra.
P="$W/pids/sv9b"; mkdir -p "$P"
copia f3 sv9b; vigilada "$D" 20 "python3 app.py || exit 1"
python3 - "$D/scripts/suite.py" "$P/lanzador" <<'PY'
import sys
p, f = sys.argv[1], sys.argv[2]; t = open(p).read()
hook = (f"    if 'precommit-snap' in os.getcwd():\n"
        f"        open({f!r}, 'w').write(str(os.getpid())); time.sleep(300)\n")
open(p, "w").write(t.replace("def run(args) -> int:\n", "def run(args) -> int:\n" + hook, 1))
PY
acotado 60 sh -c 'cd "$1" && export TMPDIR="$2" PATH="$3:$PATH" && printf -- "- nota sv9b\n" >> docs/MEMORIA.md && git add -A && git -c core.hooksPath=.githooks commit -q -m "nota

Ref: F1"' _ "$D" "$W/tmpd" "$W/bin" > "$P/salida" 2>&1 &
bg=$!
n=0; until [ -s "$P/lanzador" ] || [ $n -ge 150 ]; do n=$((n+1)); sleep 0.2; done
lz=$(cat "$P/lanzador" 2>/dev/null); hk=$(ps -o ppid= -p "${lz:-0}" 2>/dev/null | tr -d ' ')
S9d=$(ls -td "$W/tmpd"/precommit-snap.* 2>/dev/null | head -1)
kill -TERM "${hk:-0}" 2>/dev/null; sleep 2
espera pasa "hook con TERM y su lanzador vivo: la instantánea sigue (la trampa espera al lanzador)" "" -- test -d "${S9d:-/sin-instantanea}/r"
kill "${lz:-0}" 2>/dev/null; wait $bg
espera pasa "... acabado el lanzador, la trampa limpia: sin ejecución ni lanzador vivo, la borra" "" -- sh -c '! test -e "$1"' _ "${S9d:-/sin-instantanea}"
espera pasa "... y no quedó su reclamación" "^0$" -- sh -c 'ls "$1"/.git/suite-runs/*.propia 2>/dev/null | wc -l | tr -d " "' _ "$D"
# sv5/sv6: la suite corre y se cierra, pero al salir el hook no puede leer el registro (dañado o sin
# permiso de lectura, provocado por el cuerpo al final): la ausencia de abiertas no está demostrada.
copia f3 sv5; vigilada "$D" 20 "python3 app.py || exit 1; echo '{roto' > '$D/.git/suite-runs/zz.json'"
espera pasa "registro dañado al salir: el commit pasa, pero la instantánea se conserva y se avisa" "conservo la instantánea .*no comprobable \\(registro .*ilegible o dañado" -- nota_acotada "$D" sv5
copia f3 sv7; vigilada "$D" 20 "python3 app.py || exit 1; echo '{\"id\": \"x\", \"dir\": \"/x\", \"inicio\": 1}' > '$D/.git/suite-runs/zz.json'"
espera pasa "registro sin «estado» al salir: no autoriza el borrado; la instantánea se conserva y se avisa" "conservo la instantánea .*no comprobable \\(registro .*ilegible o dañado" -- nota_acotada "$D" sv7
mkdir -p "$W/sin-lectura"; chmod 300 "$W/sin-lectura"
if ls "$W/sin-lectura" >/dev/null 2>&1; then
  echo "  (no aplica: este entorno lista carpetas sin permiso de lectura; registro inaccesible sin probar)"
else
  copia f3 sv6; vigilada "$D" 20 "python3 app.py || exit 1; chmod 300 '$D/.git/suite-runs'"
  espera pasa "registro que no se puede listar al salir: la instantánea se conserva y se avisa" "conservo la instantánea .*no comprobable \\(registro .*ilegible o dañado" -- nota_acotada "$D" sv6
  chmod 700 "$D/.git/suite-runs"
fi
chmod 700 "$W/sin-lectura"

echo "== check_docs: en cualquier fase, check.sh empieza por el bloque vigilado y el bloque se prueba aislado"
doc() { en "$1" sh scripts/check_docs.sh; }
copia f3 cd0
espera pasa "check.sh con el bloque al principio y plazo declarado: check_docs pasa" "" -- doc "$D"
copia f3 cd1; printf '#!/bin/sh\npython3 -I app.py || exit 1\n' > "$D/scripts/check.sh"
espera falla "check.sh sin el bloque: check_docs falla" "no EMPIEZA por el bloque de la suite vigilada" -- doc "$D"
copia f3 cd2; { printf '#!/bin/sh\n# comentario permitido\necho antes\n%s\n' "$BLOQUE"; } > "$D/scripts/check.sh"
espera falla "código antes del bloque: check_docs falla (la posición se comprueba como texto)" "no EMPIEZA por el bloque" -- doc "$D"
copia f3 cd3; grep -v 'Plazo de la suite' "$D/docs/convenciones.md" > "$D/c.tmp"; mv "$D/c.tmp" "$D/docs/convenciones.md"
espera falla "sin el plazo común en convenciones: check_docs falla" "no declara el plazo común" -- doc "$D"
# El bloque tiene que ser idéntico al canónico de convenciones.md antes de ejecutarse. Para probar la
# prueba aislada, la alteración se aplica a los DOS (la referencia local no está autenticada).
en_ambos() { for f in "$1/scripts/check.sh" "$1/docs/convenciones.md"; do sh -c "$2" _ "$f" > "$1/c.tmp" && mv "$1/c.tmp" "$f"; done; }
copia f3 cd4; en_ambos "$D" "sed 's/^  exec env SUITE_ENVUELTO=1/  : env SUITE_ENVUELTO=1/' \"\$1\""
espera falla "bloque roto (no envuelve) también en la referencia: la prueba aislada lo detecta" "no funciona aislado: no corrió vigilado" -- doc "$D"
copia f3 cd4b; awk -v e="$W/efecto-cd4b" '{ print } /^# --- suite vigilada/ { print ": > \"" e "\"" }' "$D/scripts/check.sh" > "$D/c.tmp" && mv "$D/c.tmp" "$D/scripts/check.sh"
espera falla "bloque alterado solo en check.sh: check_docs falla sin ejecutarlo" "DIFIERE del canónico" -- doc "$D"
espera falla "... (el efecto del bloque alterado no se produjo)" "" -- test -e "$W/efecto-cd4b"
copia f3 cd4c; printf '# --- suite vigilada: otra vez\n: > "%s"\n# --- fin suite vigilada ---\n' "$W/efecto-cd4c" >> "$D/scripts/check.sh"
espera falla "delimitadores duplicados en check.sh: check_docs falla sin ejecutar" "delimitadores del bloque de la suite vigilada duplicados" -- doc "$D"
espera falla "... (ningún efecto)" "" -- test -e "$W/efecto-cd4c"
copia f3 cd4d; awk '/^# --- suite vigilada/ { f = 1 } !f { print } /^# --- fin suite vigilada ---$/ { f = 0 }' "$D/docs/convenciones.md" > "$D/c.tmp" && mv "$D/c.tmp" "$D/docs/convenciones.md"
espera falla "sin la definición canónica en convenciones: check_docs falla sin ejecutar" "no tiene UNA definición completa del bloque" -- doc "$D"
# Bytes (R-S.5): el awk de macOS corta la línea en un NUL y sh ejecuta lo que sigue; la comparación es por bytes y NUL/CR se rechazan.
bytes_en() {  # bytes_en <archivo> <extra>: añade <extra> tras «pwd -P)» en la línea SUITE_RAIZ del bloque
  python3 -I -c 'import sys; p=sys.argv[1]; t=open(p,"rb").read(); n=t.replace(b"pwd -P)\n", b"pwd -P)" + sys.argv[2].encode().decode("unicode_escape").encode("latin-1") + b"\n", 1); assert n != t; open(p,"wb").write(n)' "$1" "$2"; }
copia f3 cd4e; bytes_en "$D/scripts/check.sh" "\\x00; : > '$W/efecto-cd4e'"
espera falla "NUL dentro del bloque de check.sh: check_docs falla sin ejecutarlo" "contiene bytes NUL o CR" -- doc "$D"
espera falla "... (ningún efecto)" "" -- test -e "$W/efecto-cd4e"
copia f3 cd4f; bytes_en "$D/scripts/check.sh" "\\x00; : > '$W/efecto-cd4f'"; bytes_en "$D/docs/convenciones.md" "\\x00; : > '$W/efecto-cd4f'"
espera falla "NUL en el bloque y en la referencia por igual: check_docs falla sin ejecutarlo" "convenciones.md contiene bytes NUL o CR" -- doc "$D"
espera falla "... (ningún efecto)" "" -- test -e "$W/efecto-cd4f"
copia f3 cd4g; bytes_en "$D/scripts/check.sh" "\\r"
espera falla "CR en el bloque de check.sh: check_docs falla sin ejecutarlo" "contiene bytes NUL o CR" -- doc "$D"

echo "== check_docs: desde F2, la tabla de criterios de estado.md no contradice la cobertura"
copia f3 ce0
espera pasa "control: estado.md con la tabla regenerada desde la cobertura (F3)" "" -- doc "$D"
copia f3 ce1; sed -i.bak 's/^| C1 | «suma» | pendiente |$/| C1 | «suma» | verificado |/' "$D/docs/estado.md" && rm -f "$D/docs/estado.md.bak"
espera falla "estado.md dice verificado y la cobertura pendiente: check_docs falla" "docs/estado.md: C1 dice «suma» verificado y trazabilidad.md \\(la fuente\\) dice «suma» pendiente" -- doc "$D"
copia f3 ce2; python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read(); i=s.index("## Criterios"); j=s.index("## ", i+3); open(p,"w").write(s[:i]+s[j:])' "$D/docs/estado.md"
espera falla "sin la sección «## Criterios» desde F2: check_docs falla (no es «nada que comparar»)" "docs/estado.md no tiene la sección «## Criterios»" -- doc "$D"
copia f3 ce3; trazabilidad "$D" '| C1 | C1 suma  de C1 | I1 | pendiente | |' "" ""
espera pasa "control: alias con espacios internos y con el texto de su identificador (extracción por posición)" "" -- doc "$D"
copia f3 cd5; rm "$D/scripts/suite.py"
espera falla "sin scripts/suite.py: check_docs falla" "falta scripts/suite.py" -- doc "$D"
# El cuerpo real nunca se ejecuta: deja un testigo si corriera.
copia f3 cd6; printf '#!/bin/sh\n%s\n: > "%s"\n' "$BLOQUE" "$W/cuerpo-real" > "$D/scripts/check.sh"
espera pasa "la prueba aislada no ejecuta el cuerpo real de check.sh" "" -- doc "$D"
espera falla "... (ningún testigo del cuerpo real)" "" -- test -e "$W/cuerpo-real"
copia f3 cd7; mkdir -p "$W/otro-reg"
espera pasa "variables SUITE_* heredadas (dentro de otra ejecución, otro registro): no alteran la prueba aislada" "" -- env SUITE_ID=fuera SUITE_REGISTRO="$W/otro-reg" SUITE_ENVUELTO=1 SUITE_PROPIA=x sh -c 'cd "$1" && sh scripts/check_docs.sh' _ "$D"
espera pasa "... y no deja temporales propios" "^0$" -- sh -c 'ls -d "${TMPDIR:-/tmp}"/check-docs-suite.* 2>/dev/null | wc -l | tr -d " "'
# Un bloque que deja pasar la llamada anidada (olvida el SUITE_ID heredado) no pasa la prueba aislada.
copia f3 cd7b; en_ambos "$D" "awk '{ print } /^# --- suite vigilada/ { print \"[ \\\"\\\${SUITE_ENVUELTO:-}\\\" = 1 ] || unset SUITE_ID\" }' \"\$1\""
espera falla "bloque que no rechaza la llamada anidada: la prueba aislada lo detecta" "una llamada anidada no se rechazó" -- doc "$D"
# El registro temporal se lee como JSON validado (el parser de suite.py), nunca como texto. Las líneas
# se inyectan al final del bloque (corren ya vigiladas) y escriben en el registro temporal; cada caso
# usa su propio TMPDIR para borrar luego solo lo que conservó.
inyecta() {  # inyecta <dir> <línea>: en check.sh y en la referencia canónica por igual
  python3 - "$1/scripts/check.sh" "$1/docs/convenciones.md" "$2" <<'PY'
import sys
l = sys.argv[3]; fin = "# --- fin suite vigilada ---"
for p in sys.argv[1:3]:
    t = open(p).read(); open(p, "w").write(t.replace(fin, l + "\n" + fin, 1))
PY
}
COPIA_REG='import json,os,sys; r=os.environ["SUITE_REGISTRO"]; d=json.load(open(os.path.join(r, os.environ["SUITE_ID"] + ".json"))); d.update(json.loads(sys.argv[1])); open(os.path.join(r, d["id"] + ".json"), "w").write(json.dumps(d, separators=(",", ":")))'
doc_t() { mkdir -p "$W/tmpcd-$2"; en "$1" env TMPDIR="$W/tmpcd-$2" sh scripts/check_docs.sh; }   # doc_t <dir> <caso>
conservadas() { ls -d "$W/tmpcd-$1"/check-docs-suite.* 2>/dev/null | wc -l | tr -d ' '; }
# Carpetas de ejecución de la prueba aislada: «dentro» de su mktemp y «fuera», en el TMPDIR del caso.
dentro_fuera() { echo "$(ls -d "$W/tmpcd-$1"/check-docs-suite.*/tmp/suite-* 2>/dev/null | wc -l | tr -d ' ') $(ls -d "$W/tmpcd-$1"/suite-* 2>/dev/null | wc -l | tr -d ' ')"; }
copia f3 cd14
espera pasa "prueba aislada cerrada con TMPDIR propio: pasa" "" -- doc_t "$D" cd14
espera pasa "... no deja carpeta de ejecución en el TMPDIR del llamador ni su mktemp" "^0 0$" -- sh -c 'echo "$(ls -d "$1"/suite-* 2>/dev/null | wc -l | tr -d " ") $(ls -d "$1"/check-docs-suite.* 2>/dev/null | wc -l | tr -d " ")"' _ "$W/tmpcd-cd14"
copia f3 cd11; inyecta "$D" "[ -z \"\${SUITE_ID:-}\" ] || python3 -c '$COPIA_REG' '{\"id\": \"compacta\"}'"
espera falla "registro abierto en JSON compacto («\"estado\":\"abierta\"»): se detecta y la prueba aislada se conserva" "dejó una ejecución abierta \\(compacta" -- doc_t "$D" cd11
espera pasa "... (conservada)" "^1$" -- conservadas cd11
espera pasa "... con la carpeta de su ejecución dentro, ninguna fuera (temporales propios)" "^1 0$" -- dentro_fuera cd11
copia f3 cd12; inyecta "$D" "[ -z \"\${SUITE_ID:-}\" ] || echo '{roto' > \"\$SUITE_REGISTRO/zz.json\""
espera falla "registro temporal dañado: no acredita la limpieza, se conserva" "no pude comprobar el registro temporal .*conservo" -- doc_t "$D" cd12
espera pasa "... (conservada)" "^1$" -- conservadas cd12
espera pasa "... con la carpeta de su ejecución dentro, ninguna fuera (temporales propios)" "^1 0$" -- dentro_fuera cd12
copia f3 cd13; inyecta "$D" "[ -z \"\${SUITE_ID:-}\" ] || { python3 -c '$COPIA_REG' '{\"id\": \"falsa\", \"estado\": \"fallida\", \"rc\": 1, \"nota\": \"aprobada\"}'; echo vigilada:falsa; }"
espera falla "«aprobada» en otro campo de un registro fallido: no cuenta como aprobada" "la ejecución falsa no quedó registrada como aprobada" -- doc_t "$D" cd13
rm -rf "$W"/tmpcd-cd1[1234]
# Límite propio: un bloque que se cuelga ANTES de llegar a suite.py no cuelga check_docs.
copia f3 cd8; en_ambos "$D" "awk '{ print } /^# --- suite vigilada/ { print \"sleep 300\" }' \"\$1\""
espera falla "bloque que se cuelga fuera del envoltorio: check_docs vence su propio límite" "no terminó en 60 s" -- acotado 90 sh -c 'cd "$1" && sh scripts/check_docs.sh' _ "$D"
# Inicio de sesión: una ejecución abierta se avisa (sin fallar).
P="$W/pids/cd9"; mkdir -p "$P"; copia f3 cd9
( cd "$D" && exec python3 scripts/suite.py correr --plazo 60 -- sh -c 'echo $$ > "$1/lider"; sleep 300' _ "$P" > /dev/null 2>&1 ) & bg=$!
n=0; until [ -s "$P/lider" ] || [ $n -ge 50 ]; do n=$((n+1)); sleep 0.2; done
espera pasa "al inicio de sesión, una ejecución abierta se avisa sin fallar" "⚠ check_docs: hay ejecuciones de la suite abiertas" -- doc "$D"
id9=$(python3 -c 'import json,glob,sys; print(next(json.load(open(p))["id"] for p in glob.glob(sys.argv[1]+"/*.json")))' "$D/.git/suite-runs")
en "$D" python3 scripts/suite.py terminar "$id9" > /dev/null 2>&1; wait $bg 2>/dev/null
copia f3 cd10; printf '#!/bin/sh\npython3 -I app.py || exit 1\n' > "$D/scripts/check.sh"
espera falla "el pre-commit rechaza un check.sh sin el bloque (check_docs sobre el índice)" "no EMPIEZA por el bloque" -- nota_acotada "$D" cd10
# Antes de F2 también (M02): desde que check.sh existe, el bloque se exige; el pre-commit no llega a lanzarlo sin él.
copia plantilla cd14; printf '#!/bin/sh\npython3 -I app.py || exit 1\n' > "$D/scripts/check.sh"
espera falla "plantilla F_ con check.sh sin el bloque: check_docs falla (no espera a F2)" "no EMPIEZA por el bloque" -- doc "$D"
copia plantilla cd15; fase "$D" F1; printf '#!/bin/sh\npython3 -I app.py || exit 1\n' > "$D/scripts/check.sh"
espera falla "F1 con check.sh sin el bloque: check_docs falla" "no EMPIEZA por el bloque" -- doc "$D"
copia plantilla cd16; fase "$D" F1; printf '#!/bin/sh\necho "id=${SUITE_ID:-}" > "%s"\n' "$W/cuerpo-cd16" > "$D/scripts/check.sh"
espera falla "el pre-commit en F1 rechaza un check.sh sin el bloque" "no EMPIEZA por el bloque" -- nota_acotada "$D" cd16
espera falla "... y su cuerpo no llegó a correr" "" -- test -e "$W/cuerpo-cd16"
copia plantilla cd17; fase "$D" F1; printf '#!/bin/sh\n%s\necho "id=${SUITE_ID:-}" > "%s"\n' "$BLOQUE" "$W/cuerpo-cd17" > "$D/scripts/check.sh"
espera pasa "control: en F1 con el bloque, el pre-commit acepta" "" -- nota_acotada "$D" cd17
espera pasa "... y el cuerpo corrió vigilado (con identificador de la suite)" "" -- grep -qE '^id=[0-9]{8}T' "$W/cuerpo-cd17"
# SUITE_ID y SUITE_ENVUELTO heredadas: el pre-commit las quita al lanzar (el cuerpo corre vigilado);
# SUITE_ID sin SUITE_ENVUELTO (así está el entorno dentro de una ejecución) se rechaza como anidado.
copia f3 cd18; printf '#!/bin/sh\n%s\necho "id=${SUITE_ID:-}" > "%s"\n' "$BLOQUE" "$W/cuerpo-cd18" > "$D/scripts/check.sh"
sin_hooks "$D" "suite (preparación)

Ref: F1" || die "cd18: preparación"; rm -f "$W/cuerpo-cd18"
evade() { ( export SUITE_ENVUELTO=1 SUITE_ID=evasion; nota_acotada "$@" ); }
espera pasa "SUITE_ENVUELTO=1 y SUITE_ID heredadas: el commit pasa" "" -- evade "$D" cd18
espera pasa "... y el cuerpo corrió vigilado, no con la identidad heredada" "" -- grep -qE '^id=[0-9]{8}T' "$W/cuerpo-cd18"
copia f3 cd19; printf '#!/bin/sh\n%s\necho "id=${SUITE_ID:-}" > "%s"\n' "$BLOQUE" "$W/cuerpo-cd19" > "$D/scripts/check.sh"
anida() { ( export SUITE_ID=dentro; unset SUITE_ENVUELTO; nota_acotada "$@" ); }
espera falla "commit desde dentro de una ejecución (SUITE_ID sin SUITE_ENVUELTO): se rechaza" "desde dentro de otra ejecución de la suite" -- anida "$D" cd19
espera falla "... sin lanzar el cuerpo" "" -- test -e "$W/cuerpo-cd19"

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
# M10: de .github/ solo el workflow del método es instrumentación; los demás workflows y la
# configuración de .github/ son configuración operativa del producto y exigen Ref: I<n>.
copia f3 b5; mkdir -p "$D/.github/workflows"; printf 'name: despliegue\non: push\n' > "$D/.github/workflows/despliegue.yml"
espera falla "workflow del producto (.github/workflows/despliegue.yml) con Ref: F1 se rechaza" "sin 'Ref: I<n>'" -- commitea "$D" "ci del producto

Ref: F1"
copia f3 b6; mkdir -p "$D/.github"; printf 'version: 2\n' > "$D/.github/dependabot.yml"
espera falla "configuración del producto en .github/ (dependabot.yml) con Ref: F1 se rechaza" "sin 'Ref: I<n>'" -- commitea "$D" "dependencias

Ref: F1"
copia f3 b7; mkdir -p "$D/.github/workflows"; printf 'name: metodo\non: push\n' > "$D/.github/workflows/metodo.yml"
espera pasa "el workflow del método (.github/workflows/metodo.yml) con Ref: F1 se acepta" "" -- commitea "$D" "ci del método

Ref: F1"
copia f3 b8; mkdir -p "$D/.github/workflows"; printf 'name: despliegue\non: push\n' > "$D/.github/workflows/despliegue.yml"
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "workflow del producto con Ref: I2 y recibo vigente se acepta" "" -- commitea "$D" "ci del producto

Ref: I2"
# Documentos puramente informativos de .github/, nombrados uno a uno: no por su extensión.
copia f3 b9; mkdir -p "$D/.github"; printf '# Guía del repositorio\n' > "$D/.github/README.md"
espera pasa "documento informativo (.github/README.md) con Ref: F1 se acepta" "" -- commitea "$D" "guía

Ref: F1"
copia f3 b10; mkdir -p "$D/.github/ISSUE_TEMPLATE"; printf '# Error\n\nPasos para reproducir.\n' > "$D/.github/ISSUE_TEMPLATE/error.md"
espera pasa "plantilla de issue en Markdown con Ref: F1 se acepta" "" -- commitea "$D" "plantilla de issue

Ref: F1"
copia f3 b11; mkdir -p "$D/.github"; printf 'Usa siempre la API v2.\n' > "$D/.github/copilot-instructions.md"
espera falla "un .md operativo de .github/ (instrucciones de agente) con Ref: F1 se rechaza" "sin 'Ref: I<n>'" -- commitea "$D" "instrucciones

Ref: F1"
copia f3 b12; mkdir -p "$D/.github"; printf '* @equipo\n' > "$D/.github/CODEOWNERS"
espera falla "propietarios de revisión (.github/CODEOWNERS) con Ref: F1 se rechaza" "sin 'Ref: I<n>'" -- commitea "$D" "propietarios

Ref: F1"
# scripts/pruebas/: solo las regresiones y el validador del método; una prueba propia es producto.
copia f3 b13; mkdir -p "$D/scripts/pruebas"; printf '#!/bin/sh\npython3 app.py\n' > "$D/scripts/pruebas/prueba_propia.sh"
espera falla "prueba propia del producto en scripts/pruebas/ con Ref: F1 se rechaza" "sin 'Ref: I<n>'" -- commitea "$D" "prueba propia

Ref: F1"
copia f3 b14; mkdir -p "$D/scripts/pruebas"; printf '#!/bin/sh\nexit 0\n' > "$D/scripts/pruebas/regresion-producto.sh"
espera falla "un nombre que solo empieza como el del método (regresion-producto.sh) con Ref: F1 se rechaza" "sin 'Ref: I<n>'" -- commitea "$D" "regresión propia

Ref: F1"
copia f3 b15; mkdir -p "$D/scripts/pruebas"; printf '#!/bin/sh\npython3 app.py\n' > "$D/scripts/pruebas/prueba_propia.sh"
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "prueba propia con Ref: I2 y recibo vigente se acepta" "" -- commitea "$D" "prueba propia

Ref: I2"
copia f3 b16; mkdir -p "$D/scripts/pruebas"; printf '#!/bin/sh\n# regresión del método\n' >> "$D/scripts/pruebas/regresion.sh"; printf '#!/bin/sh\n' >> "$D/scripts/pruebas/validar_historial.sh"
espera pasa "la instrumentación del método en scripts/pruebas/ con Ref: F1 se acepta" "" -- commitea "$D" "actualiza el método

Ref: F1"
# Renombrados: el origen y el destino cuentan (índice, replay y merge); si no, un git mv hacia una ruta
# exenta retira un workflow o código sin Ref: I<n>.
con_workflow() { mkdir -p "$D/.github/workflows"; printf 'name: escaneo\non: push\n' > "$D/.github/workflows/escaneo.yml"; printf '# Guía\n' > "$D/.github/README.md"; sin_hooks "$D" "producto con workflow" || die "no pude preparar el workflow del producto"; }
copia f3 b17; con_workflow; en "$D" git mv .github/workflows/escaneo.yml docs/escaneo.yml
espera falla "renombrar un workflow del producto hacia docs/ con Ref: F1 se rechaza" "escaneo\.yml" -- commitea "$D" "archiva

Ref: F1"
copia f3 b18; con_workflow; en "$D" git rm -q .github/workflows/escaneo.yml
espera falla "control: borrar el workflow del producto con Ref: F1 se rechaza" "escaneo\.yml" -- commitea "$D" "borra

Ref: F1"
copia f3 b19; con_workflow; en "$D" git mv .github/README.md docs/guia.md
espera pasa "renombrado documental (.github/README.md a docs/guia.md) con Ref: F1 se acepta" "" -- commitea "$D" "mueve la guía

Ref: F1"
copia f3 b20; en "$D" git mv app.py docs/app.py
espera falla "renombrar código del producto hacia docs/ con Ref: F1 se rechaza" "app\.py" -- commitea "$D" "archiva código

Ref: F1"
copia f3 b21; con_workflow; en "$D" git mv .github/workflows/escaneo.yml docs/escaneo.yml; sin_hooks "$D" "archiva colado

Ref: F1" || die "no pude colar el renombrado"
espera falla "validar_historial rechaza el renombrado colado con --no-verify" "escaneo\.yml" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia f3 b22; con_workflow; en "$D" git checkout -q -b lado; printf 'n\n' > "$D/docs/nota.md"; sin_hooks "$D" "nota

Ref: F1" || die "no pude preparar la rama"
en "$D" git checkout -q -; printf 'm\n' > "$D/docs/otra.md"; sin_hooks "$D" "otra

Ref: F1" || die "no pude preparar la principal"
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-commit lado >/dev/null 2>&1 || die "no pude preparar el merge"
en "$D" git mv .github/workflows/escaneo.yml docs/escaneo.yml
espera falla "merge que además renombra un workflow hacia docs/ con Ref: F1 se rechaza" "escaneo\.yml" -- en "$D" git -c core.hooksPath=.githooks commit -q -m "integra

Ref: F1"
# CODEOWNERS decide quién aprueba: GitHub lo lee de .github/, la raíz o docs/.
copia f3 b23; printf '* @equipo\n' > "$D/docs/CODEOWNERS"
espera falla "docs/CODEOWNERS con Ref: F1 se rechaza" "docs/CODEOWNERS" -- commitea "$D" "propietarios

Ref: F1"
copia f3 b24; printf '* @equipo\n' > "$D/CODEOWNERS"
espera falla "CODEOWNERS en la raíz con Ref: F1 se rechaza" "CODEOWNERS" -- commitea "$D" "propietarios

Ref: F1"
# .githooks/: solo los tres hooks del método; un hook propio del proyecto es código.
copia f3 b25; printf '#!/bin/sh\nexit 0\n' > "$D/.githooks/pre-push"; chmod +x "$D/.githooks/pre-push"
espera falla "hook propio (.githooks/pre-push) con Ref: F1 se rechaza" "pre-push" -- commitea "$D" "hook propio

Ref: F1"
copia f3 b26; printf '#!/bin/sh\nexit 0\n' > "$D/.githooks/pre-push"; chmod +x "$D/.githooks/pre-push"
recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "hook propio con Ref: I2 y recibo vigente se acepta" "" -- commitea "$D" "hook propio

Ref: I2"
copia f3 b27; printf '\n# comentario\n' >> "$D/.githooks/pre-commit"
espera pasa "un hook del método (.githooks/pre-commit) con Ref: F1 se acepta" "" -- commitea "$D" "actualiza el hook

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
  printf '# Encuadre\n\n## Criterios de éxito\n\n- C1: suma devuelve a+b.\n- C2: resta devuelve a-b.\n- C3: multiplica devuelve a*b.\n- C4: divide devuelve a/b.\n\n## Set de oro\n\n- suma(1, 2) → 3\n' > "$1/docs/encuadre.md"
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
copia cierre z1; printf '# Encuadre\n\n- Objetivo: sumar\n\n## Set de oro\n\n- suma(1, 2) → 3\n' > "$D/docs/encuadre.md"
trazabilidad "$D" "" "" '| R-I1.1 | «sin-prueba» | I1 | general | falta prueba | verificado | 2026-10-19 10:00 · app.py:1 |'
recibo "$D" revisor-funcional encuadre F2 PASA 0
espera falla "quitar todos los criterios en una reentrada Ref: F2 se rechaza (criterios históricos)" "C1 estaba en el último contrato revisado" -- commitea "$D" "encuadre sin criterios

Ref: F2"
# Para probar la guarda del cierre, el estado sin criterios se cuela (preparación).
sin_hooks "$D" "encuadre sin criterios (colado)

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
copia cierre z16; printf '# Plan\n\n## Incrementos\n\n- [x] I1 «suma» — (satisface: C1)\n\n## Bitácora\n\n- [2026-11-04] I1 «suma»: cerrado\n\n## Fuera de alcance / backlog\n\n- nada\n' > "$D/docs/plan.md"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera pasa "cierre con una línea de bitácora que empieza por el incremento (- [fecha] I1 «…») se acepta" "" -- commitea "$D" "cierre

Ref: F5"
copia cierre z17; printf '# Plan\n\n## Incrementos\n\n- [x] I1 «suma» — (satisface: C1)\n- [2026-11-04] I2 «resta» — (satisface: C1)\n\n## Bitácora\n\n- [2026-11-04] I1 «suma»: cerrado\n\n## Fuera de alcance / backlog\n\n- nada\n' > "$D/docs/plan.md"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "un incremento con fecha en lugar de casilla bajo ## Incrementos sigue sin forma canónica" "parece un incremento" -- commitea "$D" "cierre

Ref: F5"
copia cierre z2; trazabilidad "$D" "$C1_VERIF
| C999 | «fantasma» | I1 | verificado | |" "" ""
espera falla "criterio huérfano C999 en trazabilidad se rechaza" "huérfano" -- commitea "$D" "docs

Ref: F1"
copia cierre z3; printf '# Encuadre\n\n- **C1**: la función suma devuelve a+b.\n\n## Set de oro\n\n- suma(1, 2) → 3\n' > "$D/docs/encuadre.md"
espera falla "criterio en negrita (**C1**) se rechaza como formato no admitido" "fuera de la gramática" -- commitea "$D" "docs

Ref: F1"
copia cierre z4; trazabilidad "$D" "$C1_VERIF" "" '| R-I1_1 | «raro» | I1 | C1 | abierto escondido | abierto | — |'
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica
espera falla "ID con guion bajo (R-I1_1) se rechaza, no se omite" "fuera de la gramática" -- commitea "$D" "cierre

Ref: F5"
copia f2 z5
espera falla "fila de ejemplo de la plantilla con proyecto iniciado se rechaza" "fila de ejemplo" -- sh -c 'cd "$1" && printf "| R-I_._ | «…» | I_ | C_ | _…_ | abierto | — |\n" >> docs/trazabilidad.md && git add -A && git -c core.hooksPath=.githooks commit -q -m "x

Ref: F1"' sh "$D"
copia cierre z6; printf '# Encuadre\n\n- C1:\n\n## Set de oro\n\n- suma(1, 2) → 3\n' > "$D/docs/encuadre.md"
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
# M14: con el comparador de fallos previos dentro de check.sh, sus líneas deciden. Una excepción al importar
# (la suite no se completa) y arreglar el fallo declarado no son detecciones; un fallo NUEVO por aserción, o
# por una excepción dentro de la prueba de la garantía (el total vacío sin valor inicial), sí.
S3="$W/sab3"; mkdir -p "$S3/scripts" "$S3/docs" "$S3/tests"; en "$S3" git init -q
cp "$RAIZ/scripts/suite.py" "$RAIZ/scripts/fallos_previos.py" "$S3/scripts/"
printf -- '- **Plazo de la suite:** 60 s\n' > "$S3/docs/convenciones.md"
printf 'from decimal import Decimal\ndef total(xs):\n    return sum((Decimal(x) for x in xs), Decimal("0")).quantize(Decimal("0.01"))\ndef doble(x):\n    return x * 2\ndef mitad(x):\n    return x / 3\n' > "$S3/mod.py"
: > "$S3/tests/__init__.py"
printf 'import unittest\nimport mod\nclass T(unittest.TestCase):\n    def test_doble(self):\n        self.assertEqual(mod.doble(2), 4)\n    def test_vacio(self):\n        self.assertEqual(str(mod.total([])), "0.00")\n    def test_mitad(self):\n        self.assertEqual(mod.mitad(4), 2)\n' > "$S3/tests/test_mod.py"
printf '#!/bin/sh\npython3 -I scripts/fallos_previos.py comprobar --adaptador unittest --inicio tests\n' > "$S3/scripts/check.sh"
en "$S3" python3 -I scripts/fallos_previos.py capturar --adaptador unittest --inicio tests >/dev/null || die "no pude capturar la línea base de sab3"
printf '[{"label":"aserto","file":"mod.py","before":"return x * 2","after":"return x * 3"}]\n' > "$S3/aserto.json"
printf '[{"label":"excepcion-defecto","file":"mod.py","before":", Decimal(\\"0\\")).quantize","after":").quantize"}]\n' > "$S3/excepcion.json"
printf '[{"label":"importacion","file":"mod.py","before":"def doble(x):","after":"raise RuntimeError(\\"x\\")\\ndef doble(x):"}]\n' > "$S3/importa.json"
printf '[{"label":"arregla-previo","file":"mod.py","before":"return x / 3","after":"return x / 2"}]\n' > "$S3/arregla.json"
espera pasa "comparador: un fallo NUEVO por aserción es DIES y lo dice" "by assertion" -- en "$S3" python3 -I "$SAB" aserto.json
espera pasa "comparador: una excepción dentro de la prueba de la garantía es DIES y lo dice" "by EXCEPTION AttributeError" -- en "$S3" python3 -I "$SAB" excepcion.json
espera falla "comparador: una excepción al importar (suite incompleta) es INVALID, no DIES" "INVALID .*no completó la suite" -- en "$S3" python3 -I "$SAB" importa.json
espera falla "comparador: arreglar el fallo previo declarado no es una detección" "UNVERIFIED" -- en "$S3" python3 -I "$SAB" arregla.json
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
sabv() { acotado 90 sh -c 'cd "$1" && export TMPDIR="$2" PATH="$3:$PATH" && shift 3 && python3 -I "$0" "$@"' "$SAB" "$SV" "$W/tmpd-sab" "$W/bin" "$@"; }
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
espera pasa "... y recupera sola la copia conservada (reclamada antes de lanzar, dueño terminado)" "^0$" -- copias_sv
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
recupera_sv() { ( cd "$SV" && python3 scripts/suite.py recuperar >/dev/null 2>&1 ); copias_sv; }
n=0; until [ "$(recupera_sv)" = 0 ] || [ $n -ge 20 ]; do n=$((n+1)); sleep 0.5; done   # el lanzador sale tras el cierre
espera pasa "... cerrada y fuera su lanzador, recuperar borra la copia" "^0$" -- recupera_sv
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
espera pasa "... con el lanzador vivo y el sabotaje terminado, recuperar la conserva: lo registró quien lo lanzó" "se conserva: su lanzador \\(pid $(cat "$P/lanzador" 2>/dev/null)\\) sigue vivo" -- en "$SV" python3 scripts/suite.py recuperar
espera pasa "... (la copia sigue)" "^1$" -- copias_sv
kill "$(cat "$P/lanzador" 2>/dev/null)" 2>/dev/null
n=0; until [ "$(recupera_sv)" = 0 ] || [ $n -ge 20 ]; do n=$((n+1)); sleep 0.5; done
espera pasa "... terminado el lanzador, recuperar borra la copia (nunca se unió él mismo a la reclamación)" "^0$" -- recupera_sv
echo '{roto' > "$SV/.git/suite-runs/zz.json"
espera falla "lanzador vivo con el registro no comprobable: se detiene sin señalar nada" "STOPPED.*launcher [0-9]* still alive 4s after starting and the registry could not be checked; nothing was signalled" -- respaldo m.json
espera pasa "... no señala al lanzador (sigue vivo)" "" -- kill -0 "$(cat "$P/lanzador" 2>/dev/null)"
espera pasa "... y conserva la copia" "^1$" -- copias_sv
kill "$(cat "$P/lanzador" 2>/dev/null)" 2>/dev/null
espera pasa "... con el registro dañado, recuperar no borra nada" "^1$" -- recupera_sv
rm -f "$SV/.git/suite-runs/zz.json"
espera pasa "... legible de nuevo, la recupera" "^0$" -- recupera_sv
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

echo "== Merges automáticos: el pre-commit también corre en ellos (pre-merge-commit)"
# git no ejecuta pre-commit en un merge que termina solo; pre-merge-commit delega en él. Un rechazo deja el
# merge en curso (MERGE_HEAD) sin mover HEAD. corridas: ejecuciones de la suite en el registro del repositorio.
corridas() { find "$1/.git/suite-runs" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
en_curso() { en "$1" git rev-parse -q --verify MERGE_HEAD >/dev/null && [ "$(en "$1" git rev-parse HEAD)" = "$2" ]; }
fusiona() { en "$1" git -c core.hooksPath=.githooks merge -q --no-ff --no-edit "$2"; }
rama_con_env() {  # rama_con_env <dir> <rama nueva o existente>: un .env colado en esa rama; vuelve a la principal
  pr=$(en "$1" git branch --show-current); en "$1" git checkout -q "$2" 2>/dev/null || en "$1" git checkout -q -b "$2"
  printf 'SECRETO=x\n' > "$1/.env"; en "$1" git add -f .env; sin_hooks "$1" "cuela un .env en la rama

Ref: F1" || die "no pude colar el .env en $2"; en "$1" git checkout -q "$pr"
}
copia ramas pm1; N0=$(corridas "$D")
espera pasa "merge automático correcto se acepta" "" -- fusiona "$D" rama
espera pasa "... y la suite corrió una vez sobre su resultado" "" -- sh -c "[ \"\$(find '$D/.git/suite-runs' -name '*.json' | wc -l)\" -eq $((N0+1)) ]"
copia ramas pm2; rama_con_env "$D" rama; H0=$(en "$D" git rev-parse HEAD)
espera falla "merge automático que trae un .env (colado en la rama) se rechaza por las guardas" "guardas: intenta versionar un \.env" -- fusiona "$D" rama
espera pasa "... HEAD no avanza y el merge queda en curso (corregir y git commit, o git merge --abort)" "" -- en_curso "$D" "$H0"
copia ramas pm3; en "$D" git checkout -q rama; printf -- '- [ ] I2 «resta-bis» — duplicado (satisface: C1)\n' >> "$D/docs/plan.md"; sin_hooks "$D" "plan roto en la rama

Ref: F1" || die "pm3"; en "$D" git checkout -q -; H0=$(en "$D" git rev-parse HEAD)
espera falla "merge automático que trae un rastro inválido (I2 duplicado en el plan) se rechaza por check_docs" "I2 está definido más de una vez" -- fusiona "$D" rama
espera pasa "... y queda en curso" "" -- en_curso "$D" "$H0"
copia ramas pm4; en "$D" git checkout -q rama; printf 'assert suma(2, 2) == 5\n' >> "$D/app.py"; sin_hooks "$D" "prueba nueva en rojo en la rama

Ref: I4" || die "pm4"; en "$D" git checkout -q -; H0=$(en "$D" git rev-parse HEAD)
espera falla "merge automático con una prueba nueva en rojo se rechaza por la suite" "check\.sh falló \(lint/formato/tests\)" -- fusiona "$D" rama
espera pasa "... y queda en curso" "" -- en_curso "$D" "$H0"
# Dos ramas que pasan solas y fallan juntas: lado-a cambia la firma de total(); lado-b añade una prueba con la firma vieja.
copia ramas pm5; PRIN=$(en "$D" git branch --show-current)
suite_es "$D" 'for t in pruebas/t_*.py; do python3 "$t" || exit 1; done'
mkdir -p "$D/pruebas"; printf 'def total(xs):\n    return sum(xs)\n' > "$D/pruebas/lib.py"; printf 'from lib import total\nassert total([1, 2]) == 3\n' > "$D/pruebas/t_total.py"
sin_hooks "$D" "base: total() y su prueba

Ref: F1" || die "pm5 base"
en "$D" git checkout -q -b lado-a; printf 'def total(xs, impuesto):\n    return sum(xs) * (1 + impuesto)\n' > "$D/pruebas/lib.py"; printf 'from lib import total\nassert total([1, 2], 0) == 3\n' > "$D/pruebas/t_total.py"
sin_hooks "$D" "lado-a: total() exige el impuesto

Ref: F1" || die "pm5 lado-a"
en "$D" git checkout -q "$PRIN"; en "$D" git checkout -q -b lado-b; printf 'from lib import total\nassert total([2, 2]) == 4\n' > "$D/pruebas/t_informe.py"
sin_hooks "$D" "lado-b: prueba del informe

Ref: F1" || die "pm5 lado-b"
en "$D" git checkout -q "$PRIN"
for l in lado-a lado-b; do
  espera pasa "combinado: $l pasa la suite sola" "" -- sh -c "cd '$D' && git checkout -q $l && sh scripts/check.sh; r=\$?; git checkout -q '$PRIN'; exit \$r"
done
espera pasa "combinado: el merge de lado-a se acepta" "" -- fusiona "$D" lado-a
H0=$(en "$D" git rev-parse HEAD)
espera falla "combinado: el merge de lado-b, que pasa sola, se rechaza porque el resultado combinado falla" "check\.sh falló \(lint/formato/tests\)" -- fusiona "$D" lado-b
espera pasa "... y queda en curso" "" -- en_curso "$D" "$H0"
# Conflicto: git se detiene sin hooks; el commit que lo termina ejecuta pre-commit y commit-msg, como antes.
# La rama «notas» sale de antes de la nota de la principal y solo trae rastro (con código, el conflicto exige Ref: I<n>).
copia ramas pm6; PRIN=$(en "$D" git branch --show-current)
en "$D" git checkout -q -b notas HEAD~1; printf -- '- nota de la rama\n' >> "$D/docs/MEMORIA.md"; sin_hooks "$D" "nota en la rama

Ref: F1" || die "pm6 rama"; en "$D" git checkout -q "$PRIN"; N0=$(corridas "$D")
espera falla "conflicto: git se detiene antes de los hooks de commit" "CONFLICT" -- en "$D" git -c core.hooksPath=.githooks merge --no-ff --no-edit notas
espera pasa "... y no corrió ninguna suite" "" -- sh -c "[ \"\$(find '$D/.git/suite-runs' -name '*.json' 2>/dev/null | wc -l)\" -eq $N0 ]"
en "$D" git checkout -q --ours docs/MEMORIA.md; printf -- '- nota de la rama\n' >> "$D/docs/MEMORIA.md"; en "$D" git add docs/MEMORIA.md
espera falla "conflicto resuelto, commit sin trailer: lo rechaza el commit-msg, como antes" "cambia contenido respecto de la fusión" -- en "$D" git -c core.hooksPath=.githooks commit -q --no-edit
espera pasa "conflicto resuelto, commit con trailer: se acepta, como antes" "" -- en "$D" git -c core.hooksPath=.githooks commit -q -m "integra notas resolviendo MEMORIA

Ref: F1"
espera pasa "... y la suite corrió en cada uno de esos dos commits (pre-commit)" "" -- sh -c "[ \"\$(find '$D/.git/suite-runs' -name '*.json' | wc -l)\" -eq $((N0+2)) ]"
copia ramas pm7; printf 'local\n' >> "$D/README.md"
espera falla "merge automático con un archivo rastreado modificado sin stagear (ajeno al merge) se rechaza" "cambios sin stagear" -- fusiona "$D" rama
# Límites declarados: --no-verify y el fast-forward no ejecutan hooks; el replay del gate sí lo ve.
copia ramas pm8; rama_con_env "$D" rama
espera pasa "límite: con --no-verify el merge con el .env entra (git salta los hooks)" "" -- en "$D" git -c core.hooksPath=.githooks merge -q --no-ff --no-edit --no-verify rama
espera falla "... y el replay del gate lo rechaza" "guardas: .*\.env" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia ramas pm9; rama_con_env "$D" ff-rama; N0=$(corridas "$D")
espera pasa "límite: un fast-forward no crea commit y no ejecuta hooks (entra el .env de la rama)" "" -- sh -c "cd '$D' && git -c core.hooksPath=.githooks merge -q --ff-only ff-rama && [ \"\$(find .git/suite-runs -name '*.json' 2>/dev/null | wc -l)\" -eq $N0 ]"
espera falla "... y el replay del gate lo rechaza" "guardas: .*\.env" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
# Instalación: obligatorio, ejecutable en el árbol y en el índice, y del método (no código del producto).
copia f3 pmx1; rm "$D/.githooks/pre-merge-commit"
espera falla "doctor: sin .githooks/pre-merge-commit falla" "falta \.githooks/pre-merge-commit" -- en "$D" sh scripts/check_docs.sh
copia f3 pmx2; chmod -x "$D/.githooks/pre-merge-commit"
espera falla "doctor: pre-merge-commit sin bit de ejecución (git lo ignoraría en silencio)" "pre-merge-commit no es ejecutable" -- en "$D" sh scripts/check_docs.sh
copia f3 pmx3; en "$D" git update-index --chmod=-x .githooks/pre-merge-commit
espera falla "doctor: pre-merge-commit versionado sin bit ejecutable" "pre-merge-commit está versionado sin bit ejecutable" -- en "$D" sh scripts/check_docs.sh
copia f3 pmx4; printf '\n# comentario\n' >> "$D/.githooks/pre-merge-commit"
espera pasa "pre-merge-commit es instrumentación del método: cambiarlo con Ref: F1 se acepta" "" -- commitea "$D" "actualiza el hook

Ref: F1"

echo "== Replay anclado: juzgan los validadores del ancla, no los del checkout (docs/convenciones.md §Git)"
# La orden de entrada se toma LITERAL de docs/convenciones.md (el bloque ```sh que nombra replay_anclado.sh), sin
# sus tres líneas de asignación: así lo que se prueba es lo que la regla manda escribir.
ENTRADA=$(awk '/^ *```sh$/ { b = ""; f = 1; next }
  f && /^ *```$/ { if (b ~ /replay_anclado\.sh/) { printf "%s", b; exit } f = 0; next }
  f { sub(/^      /, ""); b = b $0 "\n" }' "$RAIZ/docs/convenciones.md" | grep -vE '^(ancla|inicio|fin)=')
printf '%s' "$ENTRADA" | grep -q 'cat-file blob "\${ancla}:scripts/pruebas/replay_anclado.sh"' || die "no encontré la orden de entrada del replay anclado en docs/convenciones.md"
TA="$W/tmp-anclado"; TR="$W/trampas"; mkdir -p "$TA" "$TR"
# anclado <dir> <ancla> <inicio> <fin> [shell] → ejecuta la orden de entrada en <dir> con esos valores
anclado() { ( cd "$1" && TMPDIR="$TA" ancla="$2" inicio="$3" fin="$4" "${5:-sh}" -c "$ENTRADA" ); }
sha() { en "$1" git rev-parse "$2"; }
# anclado_t: la misma ejecución, con la salida en una línea (para patrones entre líneas) y su código de salida.
anclado_t() { out=$(anclado "$@" 2>&1); rc=$?; printf '%s' "$out" | tr '\n' ' '; return $rc; }
vacia() { [ -z "$(ls -A "$1")" ]; }

copia f3 an1; A=$(sha "$D" HEAD~1)   # el commit del gate F2: el rango trae I1 (producto con recibo)
printf '\n# adaptación local: comentario\n' >> "$D/scripts/check_docs.sh"; commitea "$D" "adaptación local del doctor

Ref: F1" || die "no pude preparar la adaptación"
espera pasa "válido: producto con recibo y una adaptación de check_docs, juzgados con el ancla" "resultado PASA" -- anclado "$D" "$A" "$A" HEAD
espera pasa "válido: el informe da el final como SHA completo y lista el validador que el rango modifica" "final:  [0-9a-f]{40}.*modifica validadores.*scripts/check_docs.sh" -- anclado_t "$D" "$A" "$A" HEAD
espera pasa "la orden no deja carpetas en su TMPDIR" "" -- vacia "$TA"

copia f3 an2; A=$(sha "$D" HEAD)
printf '#!/bin/sh\nexit 0\n' > "$D/.githooks/commit-msg"; printf 'x = 1\n' >> "$D/app.py"
sin_hooks "$D" "commit-msg debilitado y código

Ref: F1"
espera falla "manipulado (sonda M10): commit-msg reducido a exit 0 junto con código → FALLA con el ancla" "fuera del rastro.*resultado FALLA" -- anclado_t "$D" "$A" "$A" HEAD
espera pasa "límite conocido: el replay sin ancla juzga con el commit-msg debilitado del checkout" "1/1 commits cumplen" -- en "$D" sh scripts/pruebas/validar_historial.sh "$A..HEAD"
if command -v zsh >/dev/null 2>&1; then
  espera falla "la misma orden de entrada, en zsh, también FALLA (las llaves de \${ancla}: evitan el modificador :s)" "resultado FALLA" -- anclado "$D" "$A" "$A" HEAD zsh
fi

copia f3 an3; A=$(sha "$D" HEAD)
printf '#!/bin/sh\n# contrato-set-de-oro: 1\n# contrato-merges: 1\n# contrato-check: 1\nexit 0\n' > "$D/scripts/check_docs.sh"; sin_hooks "$D" "doctor debilitado

Ref: F1"
printf '#!/bin/sh\n# pruebas sin la suite vigilada\nexit 0\n' > "$D/scripts/check.sh"; sin_hooks "$D" "check.sh sin el bloque vigilado

Ref: F1"
espera falla "manipulado: el doctor debilitado en un commit ANTERIOR del rango no juzga el siguiente" "no EMPIEZA por el bloque.*" -- anclado "$D" "$A" "$A" HEAD
espera falla "límite conocido: sin ancla, el doctor debilitado del checkout acepta su propio commit (el replay sale con error por el siguiente)" "ok +[0-9a-f]+ doctor debilitado" -- en "$D" sh scripts/pruebas/validar_historial.sh "$A..HEAD"
espera falla "... acotado por el contrato de check.sh: el check.sh sin el bloque lo rechaza el commit-msg" "scripts/check\.sh \(cuerpo\)" -- en "$D" sh scripts/pruebas/validar_historial.sh "$A..HEAD"

copia plantilla an4; A=$(sha "$D" HEAD)
printf '#!/bin/sh\n# pruebas sin la suite vigilada\nexit 0\n' > "$D/scripts/check.sh"; printf '/scripts/check.sh export-ignore\n' >> "$D/.gitattributes"
sin_hooks "$D" "check.sh sin bloque, oculto con export-ignore

Ref: F1"
espera falla "H2: export-ignore no oculta check.sh al replay anclado" "no EMPIEZA por el bloque" -- anclado "$D" "$A" "$A" HEAD
espera falla "H2: tampoco al replay sin ancla (la materialización es por blobs en los dos modos)" "no EMPIEZA por el bloque" -- en "$D" sh scripts/pruebas/validar_historial.sh "$A..HEAD"

copia f3 an5; A=$(sha "$D" HEAD)
printf 'docs/convenciones.md text eol=crlf export-subst\ndocs/estado.md ident\n' >> "$D/.gitattributes"
sin_hooks "$D" "atributos que transforman al extraer

Ref: F1"
espera pasa "fidelidad: eol=crlf, export-subst e ident no cambian el veredicto del replay anclado" "resultado PASA" -- anclado "$D" "$A" "$A" HEAD
mkdir "$W/mat-an5"
espera pasa "fidelidad: lo materializado tiene el id guardado (hash-object --no-filters)" "" -- sh -c 'cd "$1" && sh scripts/pruebas/validar_historial.sh --materializa HEAD "$2" && for f in docs/convenciones.md docs/estado.md; do [ "$(git hash-object --no-filters "$2/$f")" = "$(git rev-parse "HEAD:$f")" ] || exit 1; done' _ "$D" "$W/mat-an5"
espera pasa "contraste: git archive sí transforma docs/convenciones.md (CR añadidos)" "" -- sh -c 'cd "$1" && n=$(git archive HEAD docs/convenciones.md | tar -xOf - | tr -dc "\r" | wc -c) && [ "$n" -gt 0 ]' _ "$D"

# Materialización: enlaces, submódulos y nombres especiales (se conservan o se detiene; nada en silencio).
copia plantilla an6
ln -s estado.md "$D/docs/enlace.md"; printf 'x\n' > "$D/docs/con
salto.md"; sin_hooks "$D" "enlace interno y nombre con salto de línea

Ref: F1"
en "$D" git update-index --add --cacheinfo "160000,$(sha "$D" HEAD),sub" && en "$D" git -c core.hooksPath=/dev/null commit -q --no-verify -m "submódulo

Ref: F1" || die "no pude preparar el submódulo"
mkdir "$W/mat-an6"
espera pasa "materializa: enlace interno conservado, nombre con salto y submódulo como carpeta vacía avisada" "submódulo sub" -- sh -c 'cd "$1" && sh scripts/pruebas/validar_historial.sh --materializa HEAD "$2" && [ "$(readlink "$2/docs/enlace.md")" = estado.md ] && [ -f "$2/docs/con
salto.md" ] && [ -d "$2/sub" ] && [ -z "$(ls -A "$2/sub")" ]' _ "$D" "$W/mat-an6"
copia plantilla an7; ln -s ../../.. "$D/docs/fuera"; sin_hooks "$D" "enlace que sale

Ref: F1"
mkdir "$W/mat-an7"
espera falla "materializa: un enlace que resuelve fuera de la carpeta detiene" "resuelve fuera" -- en "$D" sh scripts/pruebas/validar_historial.sh --materializa HEAD "$W/mat-an7"
espera falla "replay: ese enlace es un FALLO con su motivo, no se omite" "resuelve fuera" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
copia plantilla an8; ln -s /etc/hosts "$D/docs/absoluto"; sin_hooks "$D" "enlace absoluto

Ref: F1"
mkdir "$W/mat-an8"
espera falla "materializa: un enlace con destino absoluto detiene" "destino absoluto" -- en "$D" sh scripts/pruebas/validar_historial.sh --materializa HEAD "$W/mat-an8"
copia plantilla an9
b=$(printf '[core]\n\tfsmonitor = touch %s/fsmonitor\n' "$TR" | en "$D" git hash-object -w --stdin)
t=$(printf '100644 blob %s\tconfig\n' "$b" | en "$D" git mktree)
r=$( { en "$D" git ls-tree HEAD; printf '040000 tree %s\t.GIT\n' "$t"; } | en "$D" git mktree --missing)
c=$(en "$D" git commit-tree "$r" -p HEAD -m "nombre .GIT

Ref: F1"); en "$D" git update-ref HEAD "$c"
mkdir "$W/mat-an9"
espera falla "materializa: un componente .git (sin distinguir mayúsculas) detiene" "no materializable" -- en "$D" sh scripts/pruebas/validar_historial.sh --materializa HEAD "$W/mat-an9"
espera pasa "materializa: nada se escribió en la carpeta ni se ejecutó el fsmonitor del árbol" "" -- sh -c '[ -z "$(ls -A "$1")" ] && ! ls -A "$2" | grep -q fsmonitor' _ "$W/mat-an9" "$TR"

# Prueba de bloqueo: todas las copias del candidato de la lista cerrada son trampas; ninguna debe ejecutarse.
trampa_sh() { printf '#!/bin/sh\n# contrato-recibos: 2\n# contrato-set-de-oro: 1\n# contrato-merges: 1\n# contrato-check: 1\necho "$0" >> %s/disparos; exit 1\n' "$TR"; }
trampa_py() { printf '# contrato-recibos: 2\nimport sys\nopen("%s/disparos", "a").write(sys.argv[0] + "\\n"); sys.exit(1)\n' "$TR"; }
LISTA_T05="scripts/pruebas/replay_anclado.sh scripts/pruebas/validar_historial.sh .githooks/commit-msg scripts/guardas.sh scripts/check_docs.sh scripts/recibos.sh scripts/huella.sh scripts/trazabilidad.sh scripts/contrato.py scripts/fallos_previos.py scripts/suite.py"
copia f3 an10; A=$(sha "$D" HEAD)
for f in $LISTA_T05; do case "$f" in *.py) trampa_py > "$D/$f" ;; *) trampa_sh > "$D/$f" ;; esac; done
sin_hooks "$D" "trampas en la lista cerrada

Ref: F1"
copia f3 an11; A2=$(sha "$D" HEAD)
for f in $LISTA_T05; do printf '\n# comentario\n' >> "$D/$f"; done
sin_hooks "$D" "copias íntegras con un comentario

Ref: F1"
espera pasa "prueba de bloqueo: con las copias íntegras, el veredicto es PASA" "resultado PASA" -- anclado "$W/an11" "$A2" "$A2" HEAD
espera pasa "prueba de bloqueo: con trampas, el mismo veredicto" "resultado PASA" -- anclado "$W/an10" "$A" "$A" HEAD
espera pasa "prueba de bloqueo: ninguna trampa del candidato se ejecutó" "" -- vacia "$TR"
espera falla "control de la trampa: sin ancla, el replay sí las ejecuta" "" -- en "$W/an10" sh scripts/pruebas/validar_historial.sh "$A..HEAD"
espera pasa "control de la trampa: quedó su registro de disparos" "" -- test -s "$TR/disparos"
rm -f "$TR/disparos"

# Anclas inválidas, historia reescrita, inicio posterior: sin veredicto y con su motivo.
copia f3 an12; A=$(sha "$D" HEAD)
espera falla "ancla abreviada" "Ancla inválida" -- anclado "$D" "$(en "$D" git rev-parse --short HEAD)" "$A" HEAD
espera falla "ancla como referencia (HEAD)" "Ancla inválida" -- anclado "$D" HEAD "$A" HEAD
espera falla "ancla que es un árbol, no un commit" "Ancla inválida" -- anclado "$D" "$(sha "$D" 'HEAD^{tree}')" "$A" HEAD
printf -- '- nota\n' >> "$D/docs/MEMORIA.md"; commitea "$D" "nota

Ref: F1" || die "no pude avanzar an12"
espera falla "inicio posterior al ancla" "posterior al ancla" -- anclado "$D" "$A" "$(sha "$D" HEAD)" HEAD
en "$D" git reset -q --hard HEAD~2; printf -- '- otra\n' >> "$D/docs/MEMORIA.md"; commitea "$D" "historia reescrita

Ref: F1" || die "no pude reescribir an12"
espera falla "historia reescrita: el ancla ya no es antecesora; se detiene con la base común y sin elegir otra" "no es antecesora.*Base común.*decide en un gate" -- anclado_t "$D" "$A" "$A" HEAD
copia plantilla an13; rm "$D/scripts/pruebas/replay_anclado.sh"; sin_hooks "$D" "ancla anterior al replay anclado

Ref: F1"
X=$(sha "$D" HEAD); printf -- '- nota\n' >> "$D/docs/MEMORIA.md"; commitea "$D" "nota

Ref: F1" || die "no pude avanzar an13"
espera falla "ancla sin replay_anclado.sh (primera adopción o transición): se detiene y remite a «Primera ancla»" "no contiene scripts/pruebas/replay_anclado.sh.*Primera ancla" -- anclado "$D" "$X" "$X" HEAD
copia plantilla an14; rm "$D/scripts/fallos_previos.py"; sin_hooks "$D" "ancla incompleta

Ref: F1"
X=$(sha "$D" HEAD); printf -- '- nota\n' >> "$D/docs/MEMORIA.md"; commitea "$D" "nota

Ref: F1" || true
espera falla "ancla incompleta: falta un validador de la lista" "está incompleta" -- anclado "$D" "$X" "$X" HEAD

# Retirada de la protección en el candidato: no afecta al rango que se juzga.
copia f3 an15; A=$(sha "$D" HEAD)
rm "$D/scripts/pruebas/replay_anclado.sh"; printf '#!/bin/sh\nexit 0\n' > "$D/scripts/pruebas/validar_historial.sh"; printf '#!/bin/sh\nexit 0\n' > "$D/.githooks/commit-msg"; printf 'y = 2\n' >> "$D/app.py"
sin_hooks "$D" "retira el replay anclado y cuela código

Ref: F1"
espera falla "retirada en el candidato: se juzga con el ancla y FALLA" "fuera del rastro" -- anclado "$D" "$A" "$A" HEAD

# Actualización legítima del contrato: U trae la regla R; V la incumple.
copia plantilla an16; A=$(sha "$D" HEAD)
python3 - "$D/scripts/check_docs.sh" <<'EOF'
import sys; p = sys.argv[1]; s = open(p).read()
a = "MET=${METODO_DIR:-.}\n"; assert a in s
open(p, "w").write(s.replace(a, a + '[ "$MODE" = commit ] && ! grep -q "Riesgos:" docs/estado.md 2>/dev/null && err "regla R: docs/estado.md no declara Riesgos:"\n', 1))
EOF
sin_hooks "$D" "U: regla R en el doctor

Ref: F1"
U=$(sha "$D" HEAD); printf -- '- nota\n' >> "$D/docs/MEMORIA.md"; sin_hooks "$D" "V: trabajo que incumple R

Ref: F1"
espera pasa "actualización: con el ancla anterior el rango pasa y el informe dice que R no se ejercitó" "scripts/check_docs.sh.*resultado PASA.*no acredita las reglas nuevas" -- anclado_t "$D" "$A" "$A" HEAD
espera falla "actualización: con U como ancla, V se juzga con R y FALLA" "regla R" -- anclado "$D" "$U" "$U" HEAD
mkdir "$W/r-sin" "$W/r-con"
en "$D" sh scripts/pruebas/validar_historial.sh --materializa HEAD "$W/r-sin" >/dev/null 2>&1; cp -R "$W/r-sin/." "$W/r-con/"; printf -- '- Riesgos: ninguno\n' >> "$W/r-con/docs/estado.md"
en "$D" git show "$U:scripts/check_docs.sh" > "$W/check_docs-U.sh"
espera falla "prueba aparte de R: el doctor de U rechaza un árbol sin Riesgos:" "regla R" -- en "$W/r-sin" sh "$W/check_docs-U.sh"
espera pasa "prueba aparte de R: el doctor de U acepta un árbol con Riesgos:" "" -- en "$W/r-con" sh "$W/check_docs-U.sh"

# Informe: un validador modificado y después restaurado sigue apareciendo (no basta la diferencia entre extremos).
copia f3 an20; A=$(sha "$D" HEAD)
printf '\n# cambio temporal\n' >> "$D/scripts/check_docs.sh"; commitea "$D" "cambia el doctor

Ref: F1" || die "no pude preparar an20"
en "$D" git checkout -q "$A" -- scripts/check_docs.sh; commitea "$D" "lo restaura

Ref: F1" || die "no pude restaurar en an20"
espera pasa "informe: modificado y restaurado, los extremos no difieren" "" -- sh -c 'cd "$1" && [ -z "$(git diff --name-only "$2" HEAD -- scripts/check_docs.sh)" ]' _ "$D" "$A"
espera pasa "informe: aun así lista el validador con los dos commits" "scripts/check_docs.sh \([0-9a-f]+ [0-9a-f]+\).*resultado PASA" -- anclado_t "$D" "$A" "$A" HEAD
copia f3 an21; A=$(sha "$D" HEAD)
en "$D" git checkout -q -b lateral
printf '\n# cambio en la rama\n' >> "$D/scripts/guardas.sh"; commitea "$D" "rama: cambia las guardas

Ref: F1" || die "no pude preparar la rama de an21"
en "$D" git checkout -q "$A" -- scripts/guardas.sh; commitea "$D" "rama: las restaura

Ref: F1" || die "no pude restaurar en la rama de an21"
en "$D" git checkout -q master 2>/dev/null || en "$D" git checkout -q main
printf -- '- nota\n' >> "$D/docs/MEMORIA.md"; commitea "$D" "principal: nota

Ref: F1" || die "no pude avanzar la principal de an21"
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-edit lateral || die "no pude integrar la rama de an21"
espera pasa "informe: el cambio y la restauración en una rama lateral integrada también aparecen" "scripts/guardas.sh \([0-9a-f]+ [0-9a-f]+\).*\(merge\).*resultado PASA" -- anclado_t "$D" "$A" "$A" HEAD

# Controles positivos: historia completa F1→F2→I1 y merge limpio con rama.
copia f3 an17
R0=$(en "$D" git rev-list --max-parents=0 HEAD)
espera pasa "positivo: el historial de la etapa F3 (F2 e I1 con recibos), anclado en su primer commit" "2/2 commits cumplen.*resultado PASA" -- anclado_t "$D" "$R0" "$R0" HEAD
copia cierre an19; R0=$(en "$D" git rev-list --max-parents=0 HEAD)
espera pasa "positivo: la etapa de cierre (Ref: F4 lanza check_docs cierre, el del ancla) anclada en su primer commit" "3/3 commits cumplen.*resultado PASA" -- anclado_t "$D" "$R0" "$R0" HEAD
copia ramas an18; A=$(sha "$D" HEAD)
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-edit rama || die "no pude hacer el merge en an18"
espera pasa "positivo: merge limpio con la rama del hito e I4, anclado en la principal" "ok .*\(merge\).*resultado PASA" -- anclado_t "$D" "$A" "$A" HEAD
espera pasa "la orden de entrada no dejó carpetas en su TMPDIR" "" -- vacia "$TA"

echo "== Actualización desde la entrega anterior: una historia con los dos contratos de los merges"
# La entrega anterior (sin pre-merge-commit) son los validadores de este repositorio sin lo que añadió PR-1: sin el
# hook, sin el marcador «# contrato-merges: 1» y con el commit-msg que no lo nombraba. Un proyecto válido hecho entero
# con ella (F1, F2, I1 y un merge) se actualiza y sigue (I2 y otro merge); el replay actual y el anclado juzgan rangos
# que atraviesan los dos contratos.
anterior() {
  rm -f "$1/.githooks/pre-merge-commit"
  sed -e 's/(commit-msg|pre-commit|pre-merge-commit)/(commit-msg|pre-commit)/' -e 's#De \.githooks/ solo sus tres hooks;#De .githooks/ solo sus dos hooks;#' "$1/.githooks/commit-msg" > "$W/ant-cm" && cat "$W/ant-cm" > "$1/.githooks/commit-msg"
  sed -e '/^# contrato-merges: 1$/d' -e '/^# contrato-check: 1$/d' "$1/scripts/check_docs.sh" > "$W/ant-cd" && cat "$W/ant-cd" > "$1/scripts/check_docs.sh"
  sed -e '/^# 8b) La versión del contrato de los merges/,/^done$/d' -e '/^# 8c) La versión del contrato de scripts\/check.sh/,/^done$/d' "$1/scripts/guardas.sh" > "$W/ant-gu" && cat "$W/ant-gu" > "$1/scripts/guardas.sh"
  grep -v '^#' "$1/scripts/guardas.sh" | grep -qE 'contrato-(merges|check)' && die "anterior: guardas.sh conserva la regla 8b u 8c"
  return 0
}
nota_en() { printf -- '- %s\n' "$3" >> "$1/$2"; }
trae() { d=$1; shift; for f in "$@"; do cp "$RAIZ/$f" "$d/$f"; done; chmod +x "$d"/.githooks/*; }   # trae <dir> <archivos del método nuevo>
proyecto_anterior() {  # proyecto_anterior <dir>: F1, F2, I1 y un merge, todo con la entrega anterior; deja A_ANT (gate de I1)
  rm -rf "$1"; mkdir -p "$1"; ( cd "$W/etapas/plantilla" && tar cf - --exclude ./.git . ) | ( cd "$1" && tar xf - )
  anterior "$1"; en "$1" git init -q; en "$1" git config core.hooksPath .githooks
  commitea "$1" "Encuadre inicial

Ref: F1" || die "anterior: F1"
  for f in AGENTS.md docs/encuadre.md docs/plan.md docs/decisiones.md docs/trazabilidad.md docs/estado.md scripts/check.sh; do cp "$W/etapas/f2/$f" "$1/$f"; done
  recibo "$1" revisor-funcional encuadre F2 PASA 0
  commitea "$1" "Plan

Ref: F2" || die "anterior: F2"
  fase "$1" F3 "I1 «suma»"; cp "$W/etapas/f3/app.py" "$1/app.py"; recibo "$1" juez-codigo incremento I1 PASA 0 seguridad=no-aplica
  commitea "$1" "I1

Ref: I1" || die "anterior: I1"
  A_ANT=$(sha "$1" HEAD); PRIN=$(en "$1" git branch --show-current)
  en "$1" git checkout -q -b notas-ant; nota_en "$1" docs/MEMORIA.md "nota de la rama (entrega anterior)"; commitea "$1" "nota

Ref: F1" || die "anterior: rama"
  en "$1" git checkout -q "$PRIN"; nota_en "$1" docs/despliegue.md "nota de la principal (entrega anterior)"; commitea "$1" "nota

Ref: F1" || die "anterior: principal"
  en "$1" git -c core.hooksPath=.githooks merge -q --no-ff --no-edit notas-ant || die "anterior: merge"
  git -C "$1" cat-file -e HEAD:.githooks/pre-merge-commit 2>/dev/null && die "anterior: el proyecto ya tiene pre-merge-commit"
  return 0
}
sigue_nuevo() {  # sigue_nuevo <dir>: I2 y un merge con la entrega nueva
  printf 'y2 = 2\n' >> "$1/app.py"; recibo "$1" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
  espera pasa "actualiza: I2 después de actualizar" "" -- commitea "$1" "I2

Ref: I2"
  en "$1" git checkout -q -b notas-nue; nota_en "$1" docs/MEMORIA.md "nota de la rama (entrega nueva)"; commitea "$1" "nota

Ref: F1" || die "nuevo: rama"
  en "$1" git checkout -q "$PRIN"; nota_en "$1" docs/despliegue.md "nota de la principal (entrega nueva)"; commitea "$1" "nota

Ref: F1" || die "nuevo: principal"
  espera pasa "actualiza: merge con la entrega nueva (pre-merge-commit)" "" -- fusiona "$1" notas-nue
}
NUEVOS=".githooks/commit-msg .githooks/pre-merge-commit scripts/check_docs.sh scripts/guardas.sh"
# Un paso: todo junto.
U="$W/actualiza"; proyecto_anterior "$U"
espera pasa "actualiza: el doctor nuevo da por válido el árbol de la entrega anterior (sin el marcador)" "" -- sh -c "d=\$(mktemp -d '$W/ant.XXXXXX') && git -C '$U' archive HEAD | tar -x -C \"\$d\" && cp '$RAIZ/scripts/check_docs.sh' \"\$d/scripts/check_docs.sh.nuevo\" && cd \"\$d\" && ! grep -qx '# contrato-merges: 1' scripts/check_docs.sh && sh scripts/check_docs.sh.nuevo commit"
trae "$U" $NUEVOS
espera pasa "actualiza (un paso): hooks, doctor y guardas nuevos entran con Ref: F1" "" -- commitea "$U" "actualiza el método

Ref: F1"
A_NUE=$(sha "$U" HEAD); sigue_nuevo "$U"
espera pasa "actualiza (un paso): el replay actual juzga toda la historia, con los dos contratos" "commits cumplen" -- en "$U" sh scripts/pruebas/validar_historial.sh HEAD
espera pasa "actualiza (un paso): replay anclado en la actualización, desde el gate de I1 (commits de los dos contratos)" "resultado PASA" -- anclado_t "$U" "$A_NUE" "$A_ANT" HEAD
espera falla "actualiza (un paso): con el ancla anterior, su commit-msg no conoce el hook y lo trata como producto (la regla nueva rige desde su gate)" "código fuera del rastro \(\.githooks/pre-merge-commit" -- anclado_t "$U" "$A_ANT" "$A_ANT" HEAD
# Dos pasos, con un gate entre ambos: primero el commit-msg (la regla nueva), después lo que depende de ella.
U2="$W/actualiza2"; proyecto_anterior "$U2"
trae "$U2" .githooks/commit-msg
espera pasa "actualiza (dos pasos): primero el commit-msg, con Ref: F1" "" -- commitea "$U2" "actualiza el commit-msg

Ref: F1"
A_P1=$(sha "$U2" HEAD)
espera pasa "actualiza (dos pasos): el ancla anterior acepta el primer paso" "resultado PASA" -- anclado_t "$U2" "$A_ANT" "$A_ANT" HEAD
trae "$U2" $NUEVOS
espera pasa "actualiza (dos pasos): después el hook, el doctor y las guardas" "" -- commitea "$U2" "trae pre-merge-commit

Ref: F1"
sigue_nuevo "$U2"
espera pasa "actualiza (dos pasos): con el ancla del primer paso, el rango desde el gate de I1 pasa" "resultado PASA" -- anclado_t "$U2" "$A_P1" "$A_ANT" HEAD
espera pasa "actualiza (dos pasos): el replay actual juzga toda la historia" "commits cumplen" -- en "$U2" sh scripts/pruebas/validar_historial.sh HEAD
# Fingir la entrega anterior en un proyecto ya actualizado. En local, git ejecuta los hooks del árbol: quien revierte
# también sus validadores ya no tiene la guarda nueva. Lo que lo detecta es el replay anclado en la actualización.
F="$W/finge1"; rm -rf "$F"; cp -R "$U" "$F"; rm "$F/.githooks/pre-merge-commit"; nota_en "$F" docs/MEMORIA.md "x"
espera falla "fingir: borrar el hook en un proyecto actualizado se rechaza" "pre-merge-commit" -- commitea "$F" "quita el hook

Ref: F1"
F="$W/finge2"; rm -rf "$F"; cp -R "$U" "$F"; anterior "$F"
espera falla "fingir: volver entera a la entrega anterior (hook, marcador, guarda y commit-msg) se rechaza en local (el commit-msg anterior trata el borrado del hook como producto)" "código fuera del rastro \(\.githooks/pre-merge-commit" -- commitea "$F" "vuelve a la entrega anterior

Ref: F1"
sin_hooks "$F" "vuelve a la entrega anterior

Ref: F1" || die "fingir: no pude colar la vuelta atrás"
espera falla "fingir: el replay anclado en la actualización rechaza esa vuelta atrás colada" "deja de declarar «# contrato-merges: 1».*resultado FALLA" -- anclado_t "$F" "$A_NUE" "$A_NUE" HEAD

echo "== scripts/check.sh: el cuerpo es producto desde el primer Ref: F2 (# contrato-check: 1)"
# El cuerpo es lo posterior a «# --- fin suite vigilada ---». Antes del primer Ref: F2 (diseño inicial, primera
# adopción) entra como el rastro; desde entonces exige Ref: I<n> salvo que quede idéntico al de algún padre.
cuerpo_mas() { printf '%s\n' "$2" >> "$1/scripts/check.sh"; }
solo_bloque() {  # la plantilla actualiza el bloque: igual en check.sh y en su referencia de convenciones
  python3 - "$1/scripts/check.sh" "$1/docs/convenciones.md" <<'EOF'
import sys
for p in sys.argv[1:]:
    s = open(p).read(); a = "\n# --- fin suite vigilada ---\n"; assert s.count(a) == 1, p
    open(p, "w").write(s.replace(a, "\n# (bloque actualizado por la plantilla)" + a))
EOF
}
copia f3 ck1; cuerpo_mas "$D" 'echo lint >/dev/null'
espera falla "check.sh: cambiar el cuerpo con Ref: F1 tras el F2 se rechaza" "código fuera del rastro \(scripts/check\.sh \(cuerpo\)" -- commitea "$D" "ajusta check.sh

Ref: F1"
copia f3 ck2; cuerpo_mas "$D" 'echo lint >/dev/null'; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera pasa "check.sh: cambiar el cuerpo con Ref: I2 y recibo se acepta" "" -- commitea "$D" "I2: lint en check.sh

Ref: I2"
copia f3 ck3; solo_bloque "$D"
espera pasa "check.sh: actualizar solo el bloque canónico (cuerpo idéntico) con Ref: F1 se acepta" "" -- commitea "$D" "actualiza el bloque

Ref: F1"
copia f3 ck4; solo_bloque "$D"; cuerpo_mas "$D" 'echo lint >/dev/null'
espera falla "check.sh: bloque y cuerpo a la vez con Ref: F1 se rechaza (el cuerpo exige revisión)" "scripts/check\.sh \(cuerpo\)" -- commitea "$D" "bloque y cuerpo

Ref: F1"
# La instalación legítima: antes del primer Ref: F2.
copia plantilla ck5; printf '%s' "$SUITE" > "$D/scripts/check.sh"
espera pasa "check.sh: crearlo durante el diseño inicial (antes del primer F2) con Ref: F1 se acepta" "" -- commitea "$D" "check.sh del diseño

Ref: F1"
cuerpo_mas "$D" 'echo lint >/dev/null'
espera pasa "check.sh: cambiar su cuerpo aún antes del primer F2 se acepta" "" -- commitea "$D" "ajusta check.sh en el diseño

Ref: F1"
espera pasa "check.sh: la creación en el commit del primer Ref: F2 (etapa f2) quedó aceptada" "" -- sh -c "git -C '$W/etapas/f2' log -1 --format=%B | grep -qx 'Ref: F2' && git -C '$W/etapas/f2' diff --name-only HEAD~1 HEAD | grep -qx scripts/check.sh"
# Negativos de la excepción de instalación: tras el F2, la ausencia en el padre no exime.
copia f3 ck6; en "$D" git rm -q scripts/check.sh; sin_hooks "$D" "borra check.sh (colado)

Ref: F1" || die "ck6"; printf '%s' "$SUITE" > "$D/scripts/check.sh"; cuerpo_mas "$D" ': otro cuerpo'
espera falla "check.sh: borrarlo y recrearlo con otro cuerpo tras el F2 se rechaza" "scripts/check\.sh \(cuerpo\)" -- commitea "$D" "recrea check.sh

Ref: F1"
copia f3 ck7; cp "$D/scripts/check.sh" "$W/ck7-original"; en "$D" git rm -q scripts/check.sh; sin_hooks "$D" "borra check.sh (colado)

Ref: F1" || die "ck7"; cp "$W/ck7-original" "$D/scripts/check.sh"
espera falla "check.sh: borrarlo y recrearlo idéntico tras el F2 también se rechaza (el padre no tiene cuerpo con que compararlo)" "scripts/check\.sh \(cuerpo\)" -- commitea "$D" "recrea check.sh

Ref: F1"
copia f3 ck8; printf '#!/bin/sh\n%s\n' "$BLOQUE" > "$D/scripts/check.sh"; sin_hooks "$D" "check.sh solo con el bloque (colado)

Ref: F1" || die "ck8"; printf '%s' "$SUITE" > "$D/scripts/check.sh"
espera falla "check.sh: un primer cuerpo ejecutable tardío (sobre un check.sh solo con el bloque) se rechaza" "scripts/check\.sh \(cuerpo\)" -- commitea "$D" "añade el cuerpo

Ref: F1"
copia f3 ck9; printf '#!/bin/sh\necho sin bloque\n' > "$D/scripts/check.sh"; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
espera falla "check.sh: sin el cierre del bloque no hay cuerpo separable: cuenta como cambio (y check_docs lo rechaza)" "check\.sh" -- commitea "$D" "check.sh sin bloque

Ref: F1"
# Un error de lectura rechaza: nunca equivale a un cuerpo vacío. Se ve aislado en el commit-msg del replay.
copia f3 ck10; solo_bloque "$D"; sin_hooks "$D" "actualiza el bloque

Ref: F1" || die "ck10"
b=$(en "$D" git rev-parse HEAD~1:scripts/check.sh); rm -f "$D/.git/objects/$(printf '%s' "$b" | cut -c1-2)/$(printf '%s' "$b" | cut -c3-)"
espera falla "check.sh: si el blob del padre no se puede leer, el commit se rechaza por ese motivo" "no pude leer scripts/check\.sh \(en " -- en "$D" env REV=HEAD sh .githooks/commit-msg /dev/null
# Replay: lo colado se detecta; el anclado juzga con el ancla.
copia f3 ck11; A=$(sha "$D" HEAD); cuerpo_mas "$D" ': pruebas desactivadas'; sin_hooks "$D" "ajusta check.sh (colado)

Ref: F1" || die "ck11"
espera falla "check.sh: el replay actual rechaza un cambio del cuerpo colado con --no-verify" "scripts/check\.sh \(cuerpo\)" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
espera falla "check.sh: el replay anclado también" "scripts/check\.sh \(cuerpo\).*resultado FALLA" -- anclado_t "$D" "$A" "$A" HEAD
# Merge limpio de una rama donde el cuerpo se cambió con revisión.
copia f3 ck12; PRIN=$(en "$D" git branch --show-current); en "$D" git checkout -q -b lint; cuerpo_mas "$D" 'echo lint >/dev/null'; recibo "$D" juez-codigo incremento I2 PASA 0 seguridad=no-aplica
commitea "$D" "I2: lint

Ref: I2" || die "ck12 rama"; en "$D" git checkout -q "$PRIN"; nota_en "$D" docs/MEMORIA.md "nota"; commitea "$D" "nota

Ref: F1" || die "ck12 principal"
espera pasa "check.sh: un merge limpio que integra un cuerpo revisado en la rama se acepta" "" -- fusiona "$D" lint
# Transición: sin el marcador (historia anterior) rige la regla anterior; el marcador no se retira.
V="$W/ck13"; proyecto_anterior "$V"; cuerpo_mas "$V" 'echo lint >/dev/null'
espera pasa "check.sh (transición): con la entrega anterior, cambiar el cuerpo con Ref: F1 tras el F2 se aceptaba" "" -- commitea "$V" "ajusta check.sh

Ref: F1"
trae "$V" $NUEVOS; commitea "$V" "actualiza el método

Ref: F1" || die "ck13: actualización"
espera pasa "check.sh (transición): con los validadores nuevos, el replay de toda la historia la sigue dando por válida" "commits cumplen" -- en "$V" sh scripts/pruebas/validar_historial.sh HEAD
cuerpo_mas "$V" ': otro ajuste'
espera falla "check.sh (transición): activado el marcador, el mismo tipo de cambio exige revisión" "scripts/check\.sh \(cuerpo\)" -- commitea "$V" "ajusta check.sh otra vez

Ref: F1"
copia f3 ck14; sed '/^# contrato-check: 1$/d' "$D/scripts/check_docs.sh" > "$W/ck14.cd" && cat "$W/ck14.cd" > "$D/scripts/check_docs.sh"
espera falla "check.sh: retirar el marcador se rechaza (guardas 8c)" "deja de declarar «# contrato-check: 1»" -- commitea "$D" "retira el marcador

Ref: F1"
# Un error al buscar el F2 no es «aún no hay contrato»: la búsqueda tiene tres resultados (hay F2, completa sin F2,
# no se pudo determinar) y el tercero rechaza. El fallo se inyecta SOLO en esa búsqueda con un git sustituto en un
# espejo de git-core (git antepone su exec-path al PATH de los hooks; con GIT_EXEC_PATH el sustituto los alcanza).
# Falla con FALLA_F2_EN=<sha> solo si busca desde ese commit; sin él, siempre. Anota quién lo invocó.
GX="$W/gx-falla-f2"; mkdir -p "$GX"; GC=$(git --exec-path)
for f in "$GC"/*; do ln -s "$f" "$GX/${f##*/}"; done; rm -f "$GX/git"
cat > "$GX/git" <<EOF
#!/bin/sh
for a in "\$@"; do
  [ "\$a" = '--grep=^Ref:[[:space:]]*F2[[:space:]]*\$' ] || continue
  if [ -z "\${FALLA_F2_EN:-}" ] || printf '%s\n' "\$@" | grep -qx "\$FALLA_F2_EN"; then
    printf '%s\n' "\$(ps -o command= -p \$PPID)" >> "\$FALLA_F2_LOG"; echo "fatal: fallo simulado en la búsqueda del F2" >&2; exit 128
  fi
done
exec "$GC/git" "\$@"
EOF
chmod +x "$GX/git"
falla_f2() { ( export GIT_EXEC_PATH="$GX" PATH="$GX:$PATH" FALLA_F2_LOG="$1"; shift; "$@" ); }  # PATH: también fuera de un git commit (replays)
solo_commit_msg() { sh -c 'test -s "$1" && ! grep -v "\.githooks/commit-msg" "$1"' _ "$1"; }
copia f3 bf1; cuerpo_mas "$D" ': pruebas desactivadas'
espera falla "check.sh (búsqueda del F2): con un F2 real y un fallo solo en esa búsqueda, cambiar el cuerpo con Ref: F1 se rechaza por no poder determinar el contrato" "no pude determinar si hay un 'Ref: F2' anterior \(en [0-9a-f]+, git log terminó con error\)" -- falla_f2 "$W/bf1.log" commitea "$D" "ajusta check.sh

Ref: F1"
espera pasa "check.sh (búsqueda del F2): el fallo ocurrió solo en esa búsqueda, dentro del commit-msg" "" -- solo_commit_msg "$W/bf1.log"
copia f3 bf1b; cuerpo_mas "$D" ': pruebas desactivadas'
espera falla "check.sh (búsqueda del F2): sin el fallo, el mismo commit se rechaza por el cuerpo (el F2 es real)" "scripts/check\.sh \(cuerpo\)" -- commitea "$D" "ajusta check.sh

Ref: F1"
copia f3 bf1r; A=$(sha "$D" HEAD); cuerpo_mas "$D" ': pruebas desactivadas'; sin_hooks "$D" "ajusta check.sh (colado)

Ref: F1" || die "bf1r colado"
espera falla "check.sh (búsqueda del F2): el replay actual con el mismo fallo lo rechaza por no poder determinar el contrato" "no pude determinar si hay un 'Ref: F2' anterior" -- falla_f2 "$W/bf1r.log" en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
espera falla "check.sh (búsqueda del F2): el replay anclado también" "no pude determinar si hay un 'Ref: F2' anterior.*resultado FALLA" -- falla_f2 "$W/bf1a.log" anclado_t "$D" "$A" "$A" HEAD
espera pasa "check.sh (búsqueda del F2): en los replays el fallo también ocurrió solo en el commit-msg" "" -- sh -c 'cat "$1" "$2" > "$3"' _ "$W/bf1r.log" "$W/bf1a.log" "$W/bf1ra.log" && solo_commit_msg "$W/bf1ra.log"
# Positivo: búsqueda completa sin F2 (diseño inicial), en el hook y en el replay.
copia plantilla bf2; printf '%s' "$SUITE" > "$D/scripts/check.sh"
commitea "$D" "check.sh del diseño

Ref: F1" || die "bf2 crea"; cuerpo_mas "$D" 'echo lint >/dev/null'
espera pasa "check.sh (búsqueda del F2): sin ningún F2 (búsqueda completa), cambiar el cuerpo con Ref: F1 se acepta" "" -- commitea "$D" "ajusta check.sh en el diseño

Ref: F1"
espera pasa "check.sh (búsqueda del F2): el replay de esos dos commits sin F2 los acepta" "commits cumplen" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~2..HEAD
# Todos los padres: el error en uno no queda oculto porque el otro tenga F2.
copia f3 bf3; PRIN=$(en "$D" git branch --show-current); en "$D" git checkout -q -b otra; nota_en "$D" docs/MEMORIA.md "en la rama"
commitea "$D" "nota en la rama

Ref: F1" || die "bf3 rama"; en "$D" git checkout -q "$PRIN"; nota_en "$D" docs/plan.md "en la principal"; commitea "$D" "nota

Ref: F1" || die "bf3 principal"
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-commit otra || die "bf3 merge"; cuerpo_mas "$D" ': pruebas desactivadas'
sin_hooks "$D" "merge con cambio del cuerpo

Ref: F1" || die "bf3 commit"; P2=$(sha "$D" HEAD^2)
espera falla "check.sh (búsqueda del F2): en un merge, un error al buscar desde el segundo padre se rechaza aunque el primero tenga F2" "no pude determinar si hay un 'Ref: F2' anterior \(en $(printf '%s' "$P2" | cut -c1-7)" -- falla_f2 "$W/bf3.log" en "$D" env FALLA_F2_EN="$P2" REV=HEAD sh .githooks/commit-msg /dev/null
# Búsqueda incompleta: un clon superficial sin el F2 dentro de su profundidad no se presume sin contrato.
rm -rf "$W/bf4"; git clone -q --depth 1 "file://$W/etapas/f3" "$W/bf4" 2>/dev/null || die "bf4 clon"; cuerpo_mas "$W/bf4" ': pruebas desactivadas'
sin_hooks "$W/bf4" "ajusta check.sh (colado)

Ref: F1" || die "bf4 commit"
espera falla "check.sh (búsqueda del F2): en un clon superficial sin el F2 a la vista, se rechaza por historia recortada" "no pude determinar si hay un 'Ref: F2' anterior \(en [0-9a-f]+, la historia está recortada" -- en "$W/bf4" env REV=HEAD sh .githooks/commit-msg /dev/null
# El marcador tampoco se presume ausente si su check_docs.sh no se puede leer.
copia f3 bf5; cuerpo_mas "$D" ': pruebas desactivadas'; sin_hooks "$D" "ajusta check.sh (colado)

Ref: F1" || die "bf5"
b=$(en "$D" git rev-parse HEAD:scripts/check_docs.sh); rm -f "$D/.git/objects/$(printf '%s' "$b" | cut -c1-2)/$(printf '%s' "$b" | cut -c3-)"
espera falla "check.sh: si check_docs.sh (el marcador) no se puede leer, el commit que toca check.sh se rechaza por ese motivo" "no pude leer scripts/check_docs\.sh \(en " -- en "$D" env REV=HEAD sh .githooks/commit-msg /dev/null

echo "== Contrato de referencia por la estructura de la historia (PR-2): fechas, ramas, paralelos y errores"
# El contrato al que se ata Ref: I<n> | hito | F4 | F5 y contra el que se acota reentrada:C<n> es el Ref: F2 más
# cercano; en un merge, los maximales de los de sus padres. Nunca la fecha. Revisiones paralelas con contratos
# distintos exigen revisar su combinación con alcance F2. Un error al determinarlo rechaza; nunca es «sin contrato».
i2() {  # i2 <dir>: deja listo un Ref: I2 (fase, código y recibo del juez)
  fase "$1" F3 "I2 «resta»"; printf 'y2 = 2\n' >> "$1/app.py"; recibo "$1" juez-codigo incremento I2 PASA 0 seguridad=no-aplica; }
con_fecha() { ( export GIT_COMMITTER_DATE="$1" GIT_AUTHOR_DATE="$1"; shift; "$@" ); }
reentrada_c1() {  # reentrada_c1 <dir> [fecha]: Ref: F2 que solo reescribe C1, con recibo reentrada:C1
  reescribe_c1 "$1"; fase "$1" F2 "I2 «resta»"; recibo "$1" revisor-funcional encuadre reentrada:C1 PASA 0
  con_fecha "${2:-2026-10-19T10:00:00Z}" commitea "$1" "reentrada C1

Ref: F2"; }
# Fechas invertidas, sentido 1: la reentrada de una rama lateral tiene fecha ANTERIOR al contrato que reemplaza.
copia f3 pr2a; PRIN=$(en "$D" git branch --show-current); en "$D" git checkout -q -b lateral
reentrada_c1 "$D" 2020-01-01T00:00:00Z || die "pr2a lateral"; en "$D" git checkout -q "$PRIN"; nota_en "$D" docs/MEMORIA.md "en la principal"
commitea "$D" "nota

Ref: F1" || die "pr2a principal"; fusiona "$D" lateral || die "pr2a merge"; i2 "$D"
espera pasa "PR-2 fechas: una reentrada en rama lateral con fecha anterior, integrada sin Ref: F2, rige para el Ref: I2 siguiente" "" -- commitea "$D" "I2

Ref: I2"
espera pasa "PR-2 fechas: el replay de esa historia la acepta" "commits cumplen" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~4..HEAD
# Sentido 2: con la reentrada fechada en el pasado, una fusión que vuelve al contrato anterior no se ata a él.
copia f3 pr2b; PRIN=$(en "$D" git branch --show-current); en "$D" git checkout -q -b otra; nota_en "$D" docs/MEMORIA.md "en la rama"
commitea "$D" "nota en la rama

Ref: F1" || die "pr2b rama"; en "$D" git checkout -q "$PRIN"; reentrada_c1 "$D" 2020-01-01T00:00:00Z || die "pr2b reentrada"
B7=$(en "$D" git rev-parse --short HEAD); fusiona "$D" otra || die "pr2b merge"
cp "$W/etapas/f3/docs/encuadre.md" "$D/docs/encuadre.md"; commitea "$D" "vuelve al texto anterior de C1

Ref: F1" || die "pr2b vuelta"; i2 "$D"
espera falla "PR-2 fechas: tras volver al contrato anterior, el Ref: I2 se compara con la reentrada (no con el F2 de fecha posterior) y se rechaza" "no son los del último contrato revisado \(commit $B7" -- commitea "$D" "I2

Ref: I2"
sin_hooks "$D" "I2 (colado)

Ref: I2" || die "pr2b colado"; A=$(sha "$D" HEAD~1)
espera falla "PR-2 fechas: el replay actual también lo rechaza" "no son los del último contrato revisado" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
espera falla "PR-2 fechas: y el anclado" "no son los del último contrato revisado.*resultado FALLA" -- anclado_t "$D" "$A" "$A" HEAD
# Revisiones paralelas con contratos distintos, integradas sin revisar la combinación.
paralelas() {  # paralelas <dir>: rama-a (C2) y rama-b (C3) desde C1, integradas en rama-b con Ref: F1 conservando ambos
  ramas_contratos "$1"; fusiona_resuelve "$1" rama-a "$CR1$CR2$CR3" "$C1_PEND
$F_C2
$F_C3"; commitea "$1" "integra rama-a sin revisar la combinación

Ref: F1"; }
copia f3 pr2c; paralelas "$D" || die "pr2c"; i2 "$D"
espera falla "PR-2 paralelas: dos contratos revisados distintos integrados sin revisión conjunta rechazan el Ref: I2" "revisiones paralelas distintas \([0-9a-f]+, [0-9a-f]+\)" -- commitea "$D" "I2

Ref: I2"
cp -R "$D" "$W/pr2c-r"; sin_hooks "$W/pr2c-r" "I2 (colado)

Ref: I2" || die "pr2c colado"; A=$(sha "$W/pr2c-r" HEAD~1)
espera falla "PR-2 paralelas: el replay actual también" "revisiones paralelas distintas" -- en "$W/pr2c-r" sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD
espera falla "PR-2 paralelas: y el anclado" "revisiones paralelas distintas.*resultado FALLA" -- anclado_t "$W/pr2c-r" "$A" "$A" HEAD
copia f3 pr2d; paralelas "$D" || die "pr2d"; reescribe_c1 "$D"; fase "$D" F2 "I2 «resta»"; recibo "$D" revisor-funcional encuadre reentrada:C1 PASA 0
espera falla "PR-2 paralelas: una reentrada:C1 sobre ellas exige alcance F2" "revisiones paralelas distintas .*alcance F2" -- commitea "$D" "reentrada C1

Ref: F2"
copia f3 pr2e; paralelas "$D" || die "pr2e"; fase "$D" F2 "I2 «resta»"; recibo "$D" revisor-funcional encuadre F2 PASA 0
espera pasa "PR-2 paralelas: un Ref: F2 con alcance F2 revisa la combinación" "" -- commitea "$D" "revisa la combinación

Ref: F2"
i2 "$D"
espera pasa "PR-2 paralelas: después, el Ref: I2 se acepta" "" -- commitea "$D" "I2

Ref: I2"
espera pasa "PR-2 paralelas: el replay de esa historia la acepta" "commits cumplen" -- en "$D" sh scripts/pruebas/validar_historial.sh HEAD~2..HEAD
copia f3 pr2f; ramas_contratos "$D"; fusiona_resuelve "$D" rama-a "$CR1$CR2$CR3" "$C1_PEND
$F_C2
$F_C3"; commitea "$D" "integra rama-a

Ref: F2" || die "pr2f"; i2 "$D"
espera pasa "PR-2 paralelas: tras un merge que es Ref: F2, el Ref: I2 se ata a él" "" -- commitea "$D" "I2

Ref: I2"
# Paralelas con el mismo contrato.
copia f3 pr2g; en "$D" git checkout -q -b rama-a && contrato_f2 "$D" "$CR1$CR2" "$C1_PEND
$F_C2" || die "pr2g a"; principal "$D"; en "$D" git checkout -q -b rama-b && contrato_f2 "$D" "$CR1$CR2" "$C1_PEND
$F_C2" || die "pr2g b"; fusiona_resuelve "$D" rama-a "$CR1$CR2" "$C1_PEND
$F_C2"; commitea "$D" "integra rama-a

Ref: F1" || die "pr2g merge"; i2 "$D"
espera pasa "PR-2 paralelas: dos revisiones paralelas con el mismo contrato aceptan el Ref: I2" "" -- commitea "$D" "I2

Ref: I2"
# Errores: no poder determinar el contrato de referencia rechaza en cada consumidor, en el hook y en el replay.
copia f3 pr2h; i2 "$D"
espera falla "PR-2 errores: si el cálculo falla, el Ref: I2 se rechaza por no poder determinar el contrato" "no pude determinar el contrato revisado de referencia \(el cálculo salió con 1" -- env PATH="$W/py-falla:$PATH" sh -c 'cd "$1" && git add -A && git -c core.hooksPath=.githooks commit -q -m "I2

Ref: I2"' _ "$D"
sin_hooks "$D" "I2 (colado)

Ref: I2" || die "pr2h colado"
espera falla "PR-2 errores: el replay también" "no pude determinar el contrato revisado de referencia" -- env PATH="$W/py-falla:$PATH" sh -c 'cd "$1" && sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD' _ "$D"
copia f3 pr2i; reescribe_c1 "$D"; fase "$D" F2 "I2 «resta»"; recibo "$D" revisor-funcional encuadre reentrada:C1 PASA 0
espera falla "PR-2 errores: reentrada:C1 se rechaza si no se puede determinar el contrato con que acotarla" "no pude determinar el contrato revisado de referencia .*para acotar la reentrada" -- env PATH="$W/py-falla:$PATH" sh -c 'cd "$1" && git add -A && git -c core.hooksPath=.githooks commit -q -m "reentrada C1

Ref: F2"' _ "$D"
sin_hooks "$D" "reentrada C1 (colada)

Ref: F2" || die "pr2i colado"
espera falla "PR-2 errores: el replay de esa reentrada también" "para acotar la reentrada" -- env PATH="$W/py-falla:$PATH" sh -c 'cd "$1" && sh scripts/pruebas/validar_historial.sh HEAD~1..HEAD' _ "$D"
# Un contrato ilegible entre varias referencias no se trata como igual ni como distinto.
copia f3 pr2j; paralelas "$D" || die "pr2j"; i2 "$D"; RA=$(sha "$D" rama-a); mkdir -p "$W/py-contrato"
printf '#!/bin/sh\ncase "$*" in *"contrato.py objetos %s"*) echo "fallo simulado del lector" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$RA" "$REAL_PY" > "$W/py-contrato/python3"; chmod +x "$W/py-contrato/python3"
espera falla "PR-2 errores: si el contrato de una de las referencias no se puede leer, el Ref: I2 se rechaza con diagnóstico" "no pude leer el contrato de $(printf '%s' "$RA" | cut -c1-7) para compararlo" -- env PATH="$W/py-contrato:$PATH" sh -c 'cd "$1" && git add -A && git -c core.hooksPath=.githooks commit -q -m "I2

Ref: I2"' _ "$D"
# Historia insuficiente: un clon superficial sin el F2 a la vista no se presume sin contrato.
rm -rf "$W/pr2k"; git clone -q --depth 1 "file://$W/etapas/f3" "$W/pr2k" 2>/dev/null || die "pr2k clon"; i2 "$W/pr2k"
sin_hooks "$W/pr2k" "I2 (colado)

Ref: I2" || die "pr2k commit"
espera falla "PR-2 errores: en un clon superficial, el Ref: I2 se rechaza por historia recortada" "no pude determinar el contrato revisado de referencia \(.*historia está recortada" -- en "$W/pr2k" env REV=HEAD sh .githooks/commit-msg /dev/null

echo "== Cierre acotado de un ciclo posterior: pendientes históricos, ramas y alcance de F5"
C1L='- C1: la función suma devuelve a+b para enteros.'; C2L='- C2: la función resta devuelve a-b.'
RI11='| R-I1.1 | «sin-prueba» | I1 | C1 | falta prueba | verificado | 2026-10-19 10:00 · app.py:1 |'
encc() { printf '# Encuadre\n\n## Criterios de éxito\n\n%s\n## Set de oro\n\n- suma(1, 2) → 3\n%s' "$2" "${3:-}" > "$1/docs/encuadre.md"; }
planc() { printf '# Plan\n\n## Incrementos\n\n- [x] I1 «suma» — función suma (satisface: C1)\n- [%s] I2 «resta» — función resta (satisface: C2)\n\n## Fuera de alcance / backlog\n\n- multiplica: fuera de este ciclo (ADR-001)\n' "${2:- }" > "$1/docs/plan.md"; }
decc() { printf '# Decisiones\n\n## ADR-001 — Alcance del primer ciclo\n\n- **Estado:** aceptada\n\n## ADR-002 — C1 queda como pendiente histórico\n\n- **Estado:** aceptada\n- **Contexto:** su evidencia dependía de un insumo retirado, ajeno al trabajo de este ciclo.\n' > "$1/docs/decisiones.md"; }
trazc() { trazabilidad "$1" "| C1 | «suma» | I1 | $2 | ${4:-} |
| C2 | «resta» | I2 | $3 | |" "" "$RI11"; }
cierra_c1() { fase "$1" F5 "— «ninguno»"; commitea "$1" "cierre del ciclo 1

Ref: F5"; }
# abre_c2 <dir> <estado C1 en la apertura> [línea C1] [extra del encuadre] → reentrada Ref: F2 (la apertura R)
abre_c2() { encc "$1" "${3:-$C1L}
$C2L
" "${4:-}"; planc "$1"; decc "$1"; trazc "$1" "$2" pendiente "$([ "$2" = verificado ] || echo 'pendiente histórico: ADR-002')"
  fase "$1" F2 "I2 «resta»"; recibo "$1" revisor-funcional encuadre F2 PASA 0; commitea "$1" "apertura del ciclo 2

Ref: F2"; }
construye_c2() { fase "$1" F3 "I2 «resta»"; printf '\ndef resta(a, b):\n    return a - b\n' >> "$1/app.py"; trazc "$1" "$2" verificado "$([ "$2" = verificado ] || echo 'pendiente histórico: ADR-002')"
  recibo "$1" juez-codigo incremento I2 PASA 0 seguridad=no-aplica; commitea "$1" "I2

Ref: I2"; }
cierra_f4() { fase "$1" F4 "— «ninguno»"; shift_d=$1; shift; recibo "$shift_d" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica "$@"; }
f4() { commitea "$1" "validación del ciclo

Ref: F4"; }
ciclo2() {  # ciclo2 <nombre> <estado C1 en R y al cerrar>: ciclo 1 cerrado (P5), ciclo 2 abierto (R) y C2 construido
  copia cierre "$1"; cierra_c1 "$D" || die "no pude cerrar el ciclo 1 en $1"
  abre_c2 "$D" "$2" || die "no pude abrir el ciclo 2 en $1"; construye_c2 "$D" "$2" || die "no pude construir C2 en $1"; }

ciclo2 ca1 verificado; cierra_f4 "$D"
espera pasa "B1 reentrada ordinaria con todo vigente: cierre global como siempre" "" -- f4 "$D"
ciclo2 ca2 verificado; cierra_f4 "$D" cubre=C1,C2 excluye=ninguno
espera pasa "B1/C1' cierre con cubre=C1,C2 excluye=ninguno: C1 se da por vigente sin repetir sus pruebas (regla 10)" "" -- f4 "$D"
ciclo2 ca3 pendiente; cierra_f4 "$D" cubre=C2 excluye=C1
espera pasa "C1 pendiente histórico (pendiente en la apertura, ADR) excluido del cierre del ciclo" "" -- f4 "$D"
fase "$D" F5 "— «ninguno»"
espera pasa "C1 ... y F5 con el mismo recibo y alcance de su F4" "" -- commitea "$D" "cierre del ciclo 2

Ref: F5"
espera pasa "C1 ... estado.md sigue mostrando C1 pendiente (estado global del producto)" "" -- sh -c 'grep -qE "^\| C1 \| «suma» \| pendiente" "$1/docs/estado.md"' _ "$D"
ciclo2 ca4 pendiente; cierra_f4 "$D"
espera falla "C2 cierre global solicitado con un pendiente histórico se rechaza" "C1 no está en Estado 'verificado'" -- f4 "$D"
# A2: primer ciclo (sin Ref: F5 previo) con exclusiones
copia cierre ca5; printf '# Plan\n\n## Incrementos\n\n- [x] I1 «suma» — función suma (satisface: C1)\n\n## Fuera de alcance / backlog\n\n- [ ] I2 «resta» — función resta (satisface: C2), fuera de este ciclo (ADR-001)\n' > "$D/docs/plan.md"; encc "$D" "$C1L
$C2L
"; trazabilidad "$D" "$C1_VERIF
| C2 | «resta» | I2 | pendiente | |" "" "$RI11"; fase "$D" F2 "I2 «resta»"; recibo "$D" revisor-funcional encuadre F2 PASA 0
commitea "$D" "C2 en el primer ciclo

Ref: F2" || die "no pude preparar ca5"
cierra_f4 "$D" cubre=C1 excluye=C2
espera falla "A2 primer ciclo con excluye=: se cierra completo" "no hay un ciclo cerrado anterior" -- f4 "$D"
# N1: C1 verificado al abrir; una segunda reentrada lo pasa a pendiente
ciclo2 ca6 verificado; fase "$D" F2 "I2 «resta»"; trazc "$D" pendiente verificado "pasado a pendiente después de abrir el ciclo"
recibo "$D" revisor-funcional encuadre F2 PASA 0; commitea "$D" "segunda reentrada

Ref: F2" || die "no pude preparar la segunda reentrada"
cierra_f4 "$D" cubre=C2 excluye=C1
espera falla "N1 regresión seguida de una segunda reentrada: no se excluye" "C1 está en excluye= pero estaba verificado al abrir el ciclo" -- f4 "$D"
# N2: criterio nuevo del ciclo, con un F5 antiguo en la historia
copia cierre ca7; cierra_c1 "$D" || die "ca7"; abre_c2 "$D" verificado "$C1L" || die "ca7 apertura"
construye_c2 "$D" verificado || die "ca7 C2"
encc "$D" "$C1L
$C2L
- C9: la función eleva devuelve a**b.
"; trazabilidad "$D" "$C1_VERIF
| C2 | «resta» | I2 | verificado | |
| C9 | «eleva» | I2 | pendiente | |" "" "$RI11"; fase "$D" F2 "I2 «resta»"; recibo "$D" revisor-funcional encuadre F2 PASA 0
commitea "$D" "C9 nuevo

Ref: F2" || die "ca7 C9"
cierra_f4 "$D" cubre=C1,C2 excluye=C9
espera falla "N2 criterio nuevo con un F5 antiguo en la historia: no es pendiente histórico" "C9 está en excluye= pero no estaba en el contrato del ciclo anterior" -- f4 "$D"
# N3: garantía reemplazada en el ciclo; N3': cambio por otra vía (set de oro), solo aviso
copia cierre ca8; cierra_c1 "$D" || die ca8; abre_c2 "$D" pendiente "- C1: la función suma devuelve a+b para enteros y para reales." || die "ca8 apertura"
construye_c2 "$D" pendiente || die "ca8 C2"; cierra_f4 "$D" cubre=C2 excluye=C1
espera falla "N3 garantía reemplazada (otro texto de C1 en el ciclo): no se excluye" "C1 está en excluye= pero su criterio cambió" -- f4 "$D"
copia cierre ca9; cierra_c1 "$D" || die ca9; abre_c2 "$D" pendiente "$C1L" "- resta(3, 1) → 2
" || die "ca9 apertura"; construye_c2 "$D" pendiente || die "ca9 C2"; cierra_f4 "$D" cubre=C2 excluye=C1
espera pasa "N3' set de oro cambiado sin tocar C1: se acepta con aviso (lo deciden revisor y juez)" "set de oro o los archivos del contrato cambiaron" -- f4 "$D"
# N5: F5 conserva el alcance de su F4
ciclo2 ca10 pendiente; cierra_f4 "$D" cubre=C2 excluye=C1; f4 "$D" || die "ca10 F4"
fase "$D" F5 "— «ninguno»"; recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica cubre=C1,C2 excluye=ninguno
espera falla "N5 F5 con un recibo de otro alcance que el de su F4: se rechaza por el alcance (aquí C1 tampoco está verificado; el control aislado de esta regla es N5b)" "conserva el alcance de su F4" -- commitea "$D" "cierre

Ref: F5"
# N5b: el F4 cubre C1 (pendiente histórico al abrir el ciclo, arreglado y verificado en él). Antes del F5, C1
# vuelve a pendiente con un recibo nuevo excluye=C1, que por sí solo sería admisible (a, b, c, d): solo la
# comparación con el alcance del F4 impide cerrar sin lo que el F4 validó.
ciclo2 ca18 pendiente; trazc "$D" verificado verificado "verificado en este ciclo"; cierra_f4 "$D" cubre=C1,C2 excluye=ninguno
f4 "$D" || die "ca18 F4"
rm -rf "$W/ca18b"; cp -R "$D" "$W/ca18b"
fase "$D" F5 "— «ninguno»"
espera pasa "N5b positivo: el F5 conserva el alcance de su F4 (cubre=C1,C2 excluye=ninguno)" "" -- commitea "$D" "cierre del ciclo 2

Ref: F5"
D="$W/ca18b"; trazc "$D" pendiente verificado "vuelve a pendiente antes del F5"; fase "$D" F5 "— «ninguno»"
recibo "$D" juez-conjunto conjunto F4 PASA 0 seguridad=no-aplica cubre=C2 excluye=C1
espera falla "N5b el F5 que cambia el alcance (excluye=C1, que el F4 cubría) se rechaza aunque esa exclusión sería admisible" "conserva el alcance de su F4" -- commitea "$D" "cierre del ciclo 2 sin C1

Ref: F5"

# G1: forma de la partición y gramática del recibo
for v in "C1,C2 excluye=C1" "C2 excluye=ninguno" "C1,C2 excluye=C7"; do
  ciclo2 "ca-g$(printf '%s' "$v" | cksum | cut -c1-6)" pendiente; cierra_f4 "$D" "cubre=${v%% *}" "${v#* }"
  espera falla "G1 forma: cubre=$v" "a la vez en cubre= y excluye=|no está ni en cubre= ni en excluye=|no está definido en docs/encuadre.md" -- f4 "$D"
done
ciclo2 ca11 pendiente; cierra_f4 "$D" cubre=C2
espera falla "G1 recibo con cubre= sin excluye=: no es un recibo válido" "cubre= y excluye= van juntos" -- f4 "$D"
# Ramas. S1: el cierre de una rama lateral, integrado sin Ref: F5, no es el cierre anterior de la línea integrada
copia cierre ca12; en "$D" git checkout -q -b lado; cierra_c1 "$D" || die "ca12 lado"; principal "$D"
en "$D" git -c core.hooksPath=/dev/null merge -q --no-ff --no-commit lado >/dev/null 2>&1; en "$D" git checkout -q HEAD -- docs/estado.md
commitea "$D" "integra la rama sin cerrar el ciclo

Ref: F1" || die "ca12 merge"
abre_c2 "$D" pendiente || die "ca12 apertura"; construye_c2 "$D" pendiente || die "ca12 C2"; cierra_f4 "$D" cubre=C2 excluye=C1
espera falla "S1 el F5 de una rama lateral no cuenta como cierre anterior" "no hay un ciclo cerrado anterior" -- f4 "$D"
# S3: la apertura en una rama que sale de P5, integrada con un merge limpio
copia cierre ca13; cierra_c1 "$D" || die ca13; en "$D" git checkout -q -b apertura; abre_c2 "$D" pendiente || die "ca13 apertura"
principal "$D"; printf -- '- nota\n' >> "$D/docs/MEMORIA.md"; commitea "$D" "nota

Ref: F1" || die "ca13 nota"
en "$D" git -c core.hooksPath=.githooks merge -q --no-ff --no-edit apertura || die "ca13 merge limpio"
construye_c2 "$D" pendiente || die "ca13 C2"; cierra_f4 "$D" cubre=C2 excluye=C1
espera pasa "S3 apertura en una rama desde P5 integrada con merge limpio: es R" "" -- f4 "$D"
# S4: dos aperturas independientes desde P5
copia cierre ca14; cierra_c1 "$D" || die ca14; P5=$(en "$D" git rev-parse HEAD)
en "$D" git checkout -q -b ap-a; abre_c2 "$D" pendiente || die "ca14 a"
en "$D" git checkout -q -b ap-b "$P5"; abre_c2 "$D" pendiente "$C1L" "- resta(2, 2) → 0
" || die "ca14 b"
principal "$D"; en "$D" git merge -q --ff-only ap-a || die "ca14 ff"
fusiona_resuelve "$D" ap-b "$C1L
$C2L
" "| C1 | «suma» | I1 | pendiente | pendiente histórico: ADR-002 |
$F_C2"; encc "$D" "$C1L
$C2L
" "- resta(2, 2) → 0
"; planc "$D"; decc "$D"; trazc "$D" pendiente pendiente "pendiente histórico: ADR-002"; recibo "$D" revisor-funcional encuadre F2 PASA 0
commitea "$D" "integra las dos aperturas

Ref: F2" || die "ca14 merge"
construye_c2 "$D" pendiente || die "ca14 C2"; cierra_f4 "$D" cubre=C2 excluye=C1
espera falla "S4 aperturas independientes: diagnóstico y sin elegir" "aperturas independientes" -- f4 "$D"
# S5: fechas invertidas respecto de la topología (la apertura con fecha antigua, el cierre con fecha futura)
copia cierre ca15; fase "$D" F5 "— «ninguno»"; en "$D" git add -A && GIT_COMMITTER_DATE=2030-01-01T00:00:00Z en "$D" git -c core.hooksPath=.githooks commit -q -m "cierre del ciclo 1

Ref: F5" || die "ca15 F5"
encc "$D" "$C1L
$C2L
"; planc "$D"; decc "$D"; trazc "$D" pendiente pendiente "pendiente histórico: ADR-002"; fase "$D" F2 "I2 «resta»"; recibo "$D" revisor-funcional encuadre F2 PASA 0
en "$D" git add -A && GIT_COMMITTER_DATE=2001-01-01T00:00:00Z en "$D" git -c core.hooksPath=.githooks commit -q -m "apertura

Ref: F2" || die "ca15 apertura"
construye_c2 "$D" pendiente || die "ca15 C2"; cierra_f4 "$D" cubre=C2 excluye=C1
espera pasa "S5 fechas invertidas: mismo P5 y misma R" "" -- f4 "$D"
# S6: N1 con ramas: la segunda reentrada en una rama lateral, integrada después
ciclo2 ca16 verificado; en "$D" git checkout -q -b baja; fase "$D" F2 "I2 «resta»"; trazc "$D" pendiente verificado "pasado a pendiente en una rama"
recibo "$D" revisor-funcional encuadre F2 PASA 0; commitea "$D" "segunda reentrada en una rama

Ref: F2" || die "ca16 rama"
principal "$D"; printf -- '- nota\n' >> "$D/docs/MEMORIA.md"; commitea "$D" "nota

Ref: F1" || die "ca16 nota"
en "$D" git -c core.hooksPath=.githooks merge -q --no-ff --no-edit baja || die "ca16 merge"
cierra_f4 "$D" cubre=C2 excluye=C1
espera falla "S6 la segunda reentrada en una rama lateral tampoco convierte C1 en pendiente histórico" "estaba verificado al abrir el ciclo" -- f4 "$D"
# Errores del cálculo de P5/R: rechazo con diagnóstico, nunca «no hay cierre anterior».
REAL_PY2=$(command -v python3); mkdir -p "$W/py-ciclo"
printf '#!/bin/sh\ncase "$*" in *"F2, F4, F5 = trailer"*) echo "fallo simulado" >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$REAL_PY2" > "$W/py-ciclo/python3"; chmod +x "$W/py-ciclo/python3"
ciclo2 ca17 pendiente; cierra_f4 "$D" cubre=C2 excluye=C1
espera falla "errores: si el cálculo de P5/R falla, el cierre acotado se rechaza con diagnóstico" "no pude determinar el cierre anterior y la apertura del ciclo" -- env PATH="$W/py-ciclo:$PATH" sh -c 'cd "$1" && git add -A && git -c core.hooksPath=.githooks commit -q -m "validación

Ref: F4"' _ "$D"

echo "== Aviso de inicio de sesión (SessionStart): el script, sin abrir sesiones de Claude"
# Se prueba el SCRIPT: que el cliente lo ejecute de verdad al iniciar una sesión queda por observar en VSCode.
TI="$W/tmp-inicio"; mkdir -p "$TI"
inicio() { ( cd "${2:-/}" && env CLAUDE_PROJECT_DIR="$1" TMPDIR="$TI" ${3:-} python3 "$1/.claude/hooks/inicio-sesion.py" ); }
inicio_t() { out=$(inicio "$@" 2>&1); rc=$?; n=$(printf '%s\n' "$out" | grep -c .); printf '%s ' "$out" | tr '\n' ' '; printf '[lineas=%s rc=%s]' "$n" "$rc"; [ "$rc" -eq 0 ] && [ "$n" -le 8 ]; }
foto() { ( cd "$1" && { git status --porcelain --ignored; git config --list --local; find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do shasum "$f"; done; } | shasum ); }
copia f3 in1; F0=$(foto "$D")
espera pasa "inicio: reanudación en F3 con hooks activos: fase, doctor PASA, ≤8 líneas, salida 0" "Proyecto en F3.*Doctor: PASA.*Siguiente: lee docs/estado.md.*lineas=[1-8] rc=0" -- inicio_t "$D"
espera pasa "inicio: no modifica nada (árbol, estado de git, configuración local) ni deja temporales" "" -- sh -c '[ "$(cd "$1" && { git status --porcelain --ignored; git config --list --local; find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do shasum "$f"; done; } | shasum)" = "$2" ] && [ -z "$(ls -A "$3")" ]' _ "$D" "$F0" "$TI"
copia f3 in2; en "$D" git config --unset core.hooksPath
espera pasa "inicio: hooks inactivos: FALLA con su causa, nunca PASA" "Doctor: FALLA .*core.hooksPath" -- inicio_t "$D"
espera pasa "inicio: ... y no dice PASA" "" -- sh -c '! CLAUDE_PROJECT_DIR="$1" TMPDIR="$2" python3 "$1/.claude/hooks/inicio-sesion.py" | grep -q "Doctor: PASA"' _ "$D" "$TI"
copia f3 in3; rm "$D/docs/estado.md"
espera pasa "inicio: estado.md ausente: lo dice y el doctor FALLA" "No puedo leer docs/estado.md.*Doctor: FALLA" -- inicio_t "$D"
copia plantilla in4
espera pasa "inicio: plantilla o proyecto sin iniciar: remite a README §Cómo usarla y docs/arranque.md" "sin iniciar: entra por README.md §Cómo usarla y docs/arranque.md" -- inicio_t "$D"
copia plantilla in5; printf '# Adopción\n' > "$D/contexto/adopcion.md"
espera pasa "inicio: adopción ya copiada: remite a docs/arranque-existente.md" "Adopción en curso.*docs/arranque-existente.md" -- inicio_t "$D"
copia plantilla in6; printf '#!/bin/sh\necho "estado intermedio"\nexit 3\n' > "$D/scripts/check_docs.sh"
espera pasa "inicio: doctor con una salida inesperada (3): sin veredicto, nunca PASA" "Doctor: sin veredicto \(estado fallida, salida 3" -- inicio_t "$D"
# Plazo con un descendiente en el grupo del doctor y un temporal: suite.py termina el grupo y el aviso lo borra.
vivos_de() { ps -A -o command= | grep -v grep | grep -c "$1"; }
espera_sin() { n=0; while [ "$(vivos_de "$1")" -gt 0 ] && [ $n -lt 45 ]; do sleep 1; n=$((n+1)); done; [ "$(vivos_de "$1")" -eq 0 ]; }
limpia_ti() { espera_sin "$1" && rm -rf "$TI" && mkdir -p "$TI"; }   # solo tras demostrar que no queda ningún proceso propio
copia plantilla in7; M7="marca-inicio-plazo-$$"
printf '#!/bin/sh\n: > "$TMPDIR/temporal-del-doctor"\npython3 -c "import time; time.sleep(300)" %s-hijo &\nexec python3 -c "import time; time.sleep(300)" %s-principal\n' "$M7" "$M7" > "$D/scripts/check_docs.sh"
F7=$(foto "$D")
espera pasa "inicio: plazo agotado (2 s): sin veredicto, suite.py termina el grupo del doctor" "Doctor: sin veredicto: plazo de 2 s agotado; suite.py terminó su grupo.*rc=0" -- inicio_t "$D" / METODO_INICIO_PLAZO=2
espera pasa "inicio: ... desde fuera, ningún proceso del doctor sigue vivo (hijo y principal)" "" -- espera_sin "$M7"
espera pasa "inicio: ... y el temporal se borró porque suite.py demostró el cierre" "" -- sh -c '[ -z "$(ls -A "$1")" ]' _ "$TI"
espera pasa "inicio: ... ni cambió nada del proyecto" "" -- sh -c '[ "$(cd "$1" && { git status --porcelain --ignored; git config --list --local; find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do shasum "$f"; done; } | shasum)" = "$2" ]' _ "$D" "$F7"
# ps que falla: «no pude comprobarlo» no es «no hay procesos»: el temporal se conserva y se informa.
mkdir -p "$W/ps-falla" "$W/ps-cuelga"; printf '#!/bin/sh\necho "ps simulado: fallo" >&2\nexit 1\n' > "$W/ps-falla/ps"; chmod +x "$W/ps-falla/ps"
M8="marca-inicio-psfalla-$$"; copia plantilla in8; printf '#!/bin/sh\necho %s >/dev/null\nexit 0\n' "$M8" > "$D/scripts/check_docs.sh"
espera pasa "inicio: con ps fallando, no da PASA y conserva el temporal con su motivo" "Conservo el temporal .*metodo-inicio-" -- sh -c 'out=$(cd / && env CLAUDE_PROJECT_DIR="$1" TMPDIR="$2" PATH="$3:$PATH" python3 "$1/.claude/hooks/inicio-sesion.py" 2>&1); printf "%s" "$out" | tr "\n" " "; ! printf "%s" "$out" | grep -q "Doctor: PASA"' _ "$D" "$TI" "$W/ps-falla"
espera pasa "inicio: ... el temporal sigue ahí (no se borra lo no demostrado)" "" -- sh -c '[ -n "$(ls -A "$1")" ]' _ "$TI"
limpia_ti "$M8" || die "no pude limpiar tras ps-falla"
# ps que se cuelga más que el plazo de suite.py: todas las esperas tienen límite.
printf '#!/bin/sh\nsleep 15 # %s\n' "marca-inicio-pscuelga-$$" > "$W/ps-cuelga/ps"; chmod +x "$W/ps-cuelga/ps"
copia plantilla in9; printf '#!/bin/sh\nexit 0\n' > "$D/scripts/check_docs.sh"
espera pasa "inicio: con ps colgado, el aviso termina dentro de su límite (plazo + margen + gracia), sin PASA" "duracion_ok" -- sh -c 't=$(date +%s); out=$(cd / && env CLAUDE_PROJECT_DIR="$1" TMPDIR="$2" PATH="$3:$PATH" METODO_INICIO_PLAZO=2 python3 "$1/.claude/hooks/inicio-sesion.py" 2>&1); d=$(( $(date +%s) - t )); printf "%s [%s s] " "$out" "$d" | tr "\n" " "; [ "$d" -le 45 ] && ! printf "%s" "$out" | grep -q "Doctor: PASA" && echo duracion_ok' _ "$D" "$TI" "$W/ps-cuelga"
limpia_ti "marca-inicio-pscuelga-$$" || die "no pude limpiar tras ps-cuelga"
# Un vigilante que no responde e ignora SIGTERM: el aviso solo señala a su hijo sin recoger y conserva el temporal.
M10="marca-inicio-vigilante-$$"; copia plantilla in10
printf 'import signal, sys, time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nsys.argv.append("%s")\ntime.sleep(300)\n' "$M10" > "$D/scripts/suite.py"
espera pasa "inicio: vigilante que no responde: sin veredicto con su motivo, se le pide terminar y se conserva el temporal" "el vigilante no terminó en 22 s.*Conservo el temporal" -- inicio_t "$D" / METODO_INICIO_PLAZO=2
espera pasa "inicio: ... desde fuera, el vigilante ya no está vivo (TERM ignorado, KILL a su propio hijo)" "" -- sh -c '! ps -A -o pid=,command= | grep -v grep | grep -q "$1/scripts/suite.py"' _ "$D"
rm -rf "$TI" && mkdir -p "$TI"
# Interrupción del propio aviso: lo dice, conserva el temporal y el guardián de suite.py termina el doctor a su plazo.
M11="marca-inicio-interrupcion-$$"; copia plantilla in11
printf '#!/bin/sh\nexec python3 -c "import time; time.sleep(300)" %s\n' "$M11" > "$D/scripts/check_docs.sh"
( cd / && exec env CLAUDE_PROJECT_DIR="$D" TMPDIR="$TI" METODO_INICIO_PLAZO=3 python3 "$D/.claude/hooks/inicio-sesion.py" > "$W/in11.out" 2>&1 ) & AV=$!
sleep 1.5; kill -TERM "$AV" 2>/dev/null; wait "$AV"
espera pasa "inicio: interrumpido: lo informa, sin PASA, y conserva el temporal" "aviso interrumpido \(SIGTERM\).*Conservo el temporal" -- sh -c 'tr "\n" " " < "$1"; ! grep -q "Doctor: PASA" "$1"' _ "$W/in11.out"
espera pasa "inicio: ... desde fuera, el guardián termina el doctor a su plazo: ningún proceso suyo queda vivo" "" -- espera_sin "$M11"
limpia_ti "$M11" || die "no pude limpiar tras la interrupción"
# Arranque desde otro directorio y con espacios en la ruta; también sin CLAUDE_PROJECT_DIR (raíz por la ubicación del script).
mkdir -p "$W/con espacios"; rm -rf "$W/con espacios/proyecto"; cp -R "$W/etapas/f3" "$W/con espacios/proyecto"
espera pasa "inicio: ruta con espacios, lanzado desde otro directorio" "Proyecto en F3.*Doctor: PASA" -- inicio_t "$W/con espacios/proyecto" "$W"
espera pasa "inicio: sin CLAUDE_PROJECT_DIR, la raíz sale de la ubicación del script" "Proyecto en F3.*Doctor: PASA" -- sh -c 'cd / && env -u CLAUDE_PROJECT_DIR TMPDIR="$2" python3 "$1/.claude/hooks/inicio-sesion.py" | tr "\n" " "' _ "$W/con espacios/proyecto" "$TI"
espera pasa "inicio: la configuración del proyecto registra el aviso en SessionStart y conserva el filtro en PreToolUse" "" -- python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1]))["hooks"]; assert "inicio-sesion.py" in d["SessionStart"][0]["hooks"][0]["command"]; assert "guarda-revisor.py" in d["PreToolUse"][0]["hooks"][0]["command"]' "$RAIZ/.claude/settings.json"

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
# El rechazo no puede leerse como «no corras nada»: dice que los chequeos autorizados siguen permitidos
# (caso real de la ronda 14: un revisor citó «escritura permitida en ningún sitio» para no correr check.sh).
espera falla "revisor en lectura: el rechazo de la prueba de bloqueo dice que los chequeos autorizados siguen permitidos" "Los chequeos autorizados .*siguen permitidos" -- gr revisor-funcional "touch $GW/.git/prueba-de-bloqueo"
sin_ningun_sitio() { out=$(gr "$1" "$2" 2>&1); [ -n "$out" ] && ! printf '%s' "$out" | grep -q "en ningún sitio"; }
espera pasa "revisor en lectura: el rechazo ya no dice «en ningún sitio»" "" -- sin_ningun_sitio juez-codigo "touch $GW/.git/prueba-de-bloqueo"
printf 'experimentos %s/aut\n' "$GW" > "$GW/.git/revision-modalidad"
espera pasa "revisor en experimentos: escribir en el directorio autorizado pasa" "" -- gr juez-conjunto "python3 x.py > $GW/aut/out.txt"
espera falla "revisor en experimentos: escribir fuera del directorio autorizado se rechaza" "solo en $GW/aut" -- gr juez-conjunto 'cp a /tmp/b'
espera falla "revisor en experimentos: el rechazo también dice que los chequeos autorizados siguen permitidos" "Los chequeos autorizados .*siguen permitidos" -- gr juez-conjunto 'cp a /tmp/b'
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
