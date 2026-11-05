#!/bin/sh
# Genera el ejemplo completo de un ciclo del método (ejemplo/README.md) en una carpeta NUEVA.
#
#   sh ejemplo/generar.sh <carpeta-nueva>
#
# Instala la plantilla con la receta del README (git archive del último commit), recorre F1 → F2 →
# I1–I3 → hito → F4 → F5 con los hooks reales activos, y al final reejecuta el contrato sobre toda la
# historia (validar_historial.sh), el doctor (check_docs.sh) y el parser de recibos.
#
# Los recibos de revisión son SINTÉTICOS (ejecutor=ejemplo-sintetico): los emite scripts/recibos.sh con
# la huella real, así que el formato y la vigencia son los del método, pero ningún revisor revisó nada.
# Un recibo válido demuestra el formato y la vigencia, no que una revisión ocurriera (AGENTS.md §9).
# Las aprobaciones de la persona tampoco existen aquí: cada gate se marca en estado.md y en el mensaje.
#
# Sin red, credenciales ni instalaciones: git, sh, python3 y ps. Requisitos: README §Cómo usarla.
# Cada paso que falla termina el script con un código distinto de cero (`falla`); `set -e` es solo un
# respaldo: no detiene una lista `a && b` ni ve el código de un programa dentro de una tubería.
set -eu
falla() { printf 'generar: %s\n' "$1" >&2; exit "${2:-1}"; }
[ $# -eq 1 ] || falla "uso: sh ejemplo/generar.sh <carpeta-nueva>" 2
RAIZ=$(cd "$(dirname "$0")/.." && pwd -P) || falla "no encuentro la raíz de la plantilla" 2
EJ="$RAIZ/ejemplo"
# El destino: una carpeta que todavía no existe (tampoco como enlace, ni roto) dentro de una que sí.
[ -e "$1" ] || [ -L "$1" ] && falla "$1 ya existe (o es un enlace); el ejemplo solo se genera en una carpeta nueva" 2
PADRE=$(dirname "$1"); NOMBRE=$(basename "$1")
[ -d "$PADRE" ] && [ ! -L "$PADRE" ] || falla "la carpeta que contendría $1 no existe o es un enlace: $PADRE" 2
case "$NOMBRE" in .|..|/) falla "nombre de destino no válido: $1" 2 ;; esac
DEST="$(cd "$PADRE" && pwd -P)/$NOMBRE" || falla "no puedo resolver $PADRE" 2
case "$DEST/" in "$RAIZ"/*) falla "el destino no puede estar dentro de la plantilla ($RAIZ)" 2 ;; esac
# Solo lo versionado: el ejemplo y la plantilla deben estar sin cambios respecto de HEAD.
LIMPIO=$(git -C "$RAIZ" status --porcelain -- .) || falla "$RAIZ no es un repositorio git" 2
[ -z "$LIMPIO" ] || falla "$RAIZ tiene cambios sin commitear; genera desde una copia limpia" 2
# La entrega se lee UNA vez: lo que se extrae y lo que se registra como origen son el mismo commit.
ORIGEN=$(git -C "$RAIZ" rev-parse HEAD) || falla "no puedo leer el commit de la plantilla" 2

# Git aislado de la configuración del usuario (sin hooks globales, firmas ni alias).
CFG=$(mktemp -d "${TMPDIR:-/tmp}/ejemplo-git.XXXXXX"); trap 'rm -rf "$CFG"' EXIT
: > "$CFG/gitconfig"; mkdir "$CFG/tmp"
# Los temporales (también los registros de la suite vigilada) quedan en este directorio propio y se borran al salir.
export TMPDIR="$CFG/tmp"
export GIT_CONFIG_GLOBAL="$CFG/gitconfig" GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME="Persona del ejemplo" GIT_AUTHOR_EMAIL="ejemplo@example.invalid"
export GIT_COMMITTER_NAME="Persona del ejemplo" GIT_COMMITTER_EMAIL="ejemplo@example.invalid"
unset SUITE_ID SUITE_REGISTRO SUITE_PLAZO SUITE_ENVUELTO SUITE_INFORME SUITE_PROPIA 2>/dev/null || true

paso() { printf '\n== %s\n' "$1"; }
commit() {  # mensaje por stdin; un commit rechazado por los hooks termina el script
  git add -A || falla "git add falló"
  git commit -q -F - || falla "los hooks rechazaron el commit (arriba, el motivo)"
  git log -1 --format='   commit %h  %s'
}
# rellena <documento> <secciones>: cambia el cuerpo de cada «## …» de <secciones> en <documento>,
# conservando los comentarios de la plantilla (sus reglas siguen en su sitio), como haría el agente.
rellena() {
  python3 -I - "$1" "$2" <<'PY' || falla "no pude rellenar $1"
import re, sys
doc, sec = sys.argv[1], sys.argv[2]
t = open(doc, encoding="utf-8").read()
partes = re.split(r"(?m)^(## .*)$", open(sec, encoding="utf-8").read())
for i in range(1, len(partes), 2):
    titulo, cuerpo = partes[i], partes[i + 1].strip("\n")
    m = re.search(r"(?m)^" + re.escape(titulo) + r"$", t)
    if not m:
        sys.exit(f"rellena: {doc} no tiene la sección «{titulo}»")
    fin = re.search(r"(?m)^## ", t[m.end():])
    fin = m.end() + fin.start() if fin else len(t)
    comentarios = "".join(c + "\n" for c in re.findall(r"<!--.*?-->", t[m.end():fin], re.S))
    t = t[:m.end()] + "\n" + comentarios + cuerpo + "\n\n" + t[fin:]
open(doc, "w", encoding="utf-8").write(t.rstrip("\n") + "\n")
PY
}
# estado <fase> <incremento activo> <próximo paso> <esperando de la persona>: regenera la cabecera de
# estado.md y su tabla «## Criterios» desde la cobertura de trazabilidad.md (docs/estado.md, M04).
estado() {
  python3 -I - docs/estado.md docs/trazabilidad.md "$@" <<'PY' || falla "no pude regenerar docs/estado.md"
import re, sys
p, traz, fase, inc, prox, esp = sys.argv[1:]
s = open(p, encoding="utf-8").read()
s = re.sub(r"(?m)^- \*\*Fase actual:\*\*.*$", f"- **Fase actual:** {fase} · incremento activo: {inc}", s, count=1)
s = re.sub(r"(?m)^- \*\*Próximo paso:\*\*.*$", f"- **Próximo paso:** {prox}", s, count=1)
s = re.sub(r"(?m)^- \*\*Esperando de la persona:\*\*.*$", f"- **Esperando de la persona:** {esp}", s, count=1)
filas = []
t = open(traz, encoding="utf-8").read()
cob = t.split("## Cobertura de criterios", 1)[1].split("\n## ", 1)[0]
for l in cob.splitlines():
    c = [x.strip() for x in l.strip().strip("|").split("|")]
    if len(c) >= 4 and re.fullmatch(r"C\d+", c[0]):
        filas.append(f"| {c[0]} | {c[1]} | {c[3]} |")
if filas:
    tabla = "| C# | Alias | Estado |\n|----|-------|--------|\n" + "\n".join(filas) + "\n"
    s = re.sub(r"(?ms)(^## Criterios\n).*?(?=^## )", lambda m: m.group(1) + "\n" + tabla + "\n", s, count=1)
open(p, "w", encoding="utf-8").write(s)
PY
}
# criterio <C#> <estado>: cambia el estado de un criterio en la cobertura (registro, fuera de la huella).
criterio() { python3 -I -c '
import re,sys; p="docs/trazabilidad.md"; c,e=sys.argv[1:]; s=open(p,encoding="utf-8").read()
s,n=re.subn(r"(?m)^(\| "+c+r" \|[^|]*\|[^|]*\| )[^|]*?( \|)", lambda m: m.group(1)+e+m.group(2), s, count=1)
assert n==1, c; open(p,"w",encoding="utf-8").write(s)' "$1" "$2" || falla "no pude marcar $1"; }
# recibo <campos…>: lo GENERA scripts/recibos.sh (fecha y huella reales) y se registra sin alterarlo.
recibo() {
  git add -A || falla "git add falló"
  linea=$(sh scripts/recibos.sh linea "$@" ejecutor=ejemplo-sintetico modalidad=lectura filtro=sin-verificar \
    aislamiento=ninguno) || falla "scripts/recibos.sh no generó el recibo"
  printf '%s\n' "$linea" >> docs/revisiones.log || falla "no pude registrar el recibo"
  printf '   recibo: %s\n' "$(tail -n 1 docs/revisiones.log | cut -c1-110)…"
}
# cierra_incremento <I#> <C#> <dir de pasos> <línea de bitácora>
cierra_incremento() {
  i=$1; c=$2
  cp -R "$EJ/pasos/$3/." . || return 1
  # Todo lo revisable antes del PASA: código, casilla [x] y bitácora colapsada (DoD, lista A).
  python3 -I -c '
import re,sys; p="docs/plan.md"; i,b=sys.argv[1:]; s=open(p,encoding="utf-8").read()
s,n=re.subn(r"(?m)^- \[ \] "+i+" ", "- [x] "+i+" ", s, count=1); assert n==1, i
s=s.replace("\n## Fuera de alcance", "- [2026-11-05] "+b+" README: revisado, sin cambios.\n\n## Fuera de alcance",1)
open(p,"w",encoding="utf-8").write(s)' "$i" "$4" || return 1
  estado F3 "$i" "revisión del juez de código sobre $i" "—"
  recibo rol=juez-codigo tipo=incremento alcance="$i" veredicto=PASA bloqueantes=0 seguridad=no-aplica
  # Después del PASA, solo registros: el criterio queda verificado y estado.md dice qué falta.
  criterio "$c" verificado
  estado F3 "$i" "gate del incremento $i" "gate de $i: aprobar el incremento (simulado en el ejemplo)"
}

paso "Instalación (README §Cómo usarla, paso 1)"
mkdir "$DEST" || falla "no pude crear $DEST"
cd "$DEST" || falla "no pude entrar en $DEST"
# Antes de escribir nada: estamos en la carpeta recién creada, y está vacía.
[ "$(pwd -P)" = "$DEST" ] && [ -z "$(ls -A)" ] || falla "no estoy en $DEST recién creada; me detengo antes de escribir"
git -C "$RAIZ" archive "$ORIGEN" > "$CFG/plantilla.tar" || falla "git archive falló"
tar -xf "$CFG/plantilla.tar" || falla "no pude extraer la plantilla"
git init -q || falla "git init falló"
printf '%s\n' "$ORIGEN" > .git/plantilla-origen || falla "no pude registrar el origen"
git config core.hooksPath .githooks || falla "no pude activar los hooks"
git add -A || falla "git add falló"
sh scripts/check_docs.sh > /dev/null || falla "el doctor falla sobre la plantilla recién instalada"
echo "   plantilla instalada; doctor en verde"

paso "Bootstrap: la plantilla de origen se declara en convenciones §Git (docs/arranque.md, Paso 0)"
python3 -I - docs/convenciones.md "$(cat .git/plantilla-origen)" <<'PY' || falla "no pude declarar la plantilla de origen"
import re, sys
p, sha = sys.argv[1:]; s = open(p, encoding="utf-8").read()
m = re.search(r"(?m)^- \*\*Contrato revisado y límites", s)
assert m and re.fullmatch(r"[0-9a-f]{40}", sha)
open(p, "w", encoding="utf-8").write(s[:m.start()] + f"- **Plantilla de origen:** {sha}\n" + s[m.start():])
PY
echo "   - **Plantilla de origen:** $(cat .git/plantilla-origen)"

paso "F1 · Ingesta: gate de completitud (docs/arranque.md §Fase 1 a; convenciones §Git, gates intermedios)"
cp "$EJ/entrada/brief.md" "$EJ/entrada/gastos.csv" "$EJ/entrada/gastos-invalido.csv" contexto/ \
  || falla "no pude copiar las entradas"
estado F1 "—" "cerrar el set de entrada" "gate de completitud: ¿contexto/ está completo? (simulado)"
commit <<'EOF'
Ingesta: inventario de contexto/ para el gate de completitud

Ref: F1
EOF

paso "F1 · Ingesta: gate de ruteo (§Fase 1 b)"
mkdir -p contexto/exploracion || falla "no pude crear contexto/exploracion"
cat > contexto/exploracion/ruteo.md <<'EOF' || falla "no pude escribir la propuesta de ruteo"
# Propuesta de ruteo (ejemplo)

| Entrada | Tipo | Destino propuesto | Razón |
|---|---|---|---|
| `brief.md` | documento | `docs/encuadre.md` §Contexto, §Criterios, §Stack | necesidad, criterios y preferencia de stack |
| `gastos.csv` | datos de entrada | `docs/encuadre.md` §Entradas y salidas; set de oro, par 1 | muestra real válida |
| `gastos-invalido.csv` | datos de entrada | `docs/encuadre.md` §Entradas y salidas; set de oro, par 4 | muestra real con un error |
EOF
estado F1 "—" "aprobar el ruteo antes de escribir en los documentos oficiales" "gate de ruteo: contexto/exploracion/ruteo.md (simulado)"
commit <<'EOF'
Ingesta: propuesta de ruteo para su gate

Ref: F1
EOF

paso "F1 · Encuadre: siembra tras el ruteo aprobado y cierre de la fase (§Fase 1 · Encuadre)"
rellena docs/encuadre.md "$EJ/pasos/f1/encuadre.md"
# La decisión de stack se toma en el encuadre: ADR-001 sustituye al bloque de ejemplo ADR-000.
python3 -I - docs/decisiones.md "$EJ/pasos/f1/decisiones.md" <<'PY' || falla "no pude registrar ADR-001"
import re, sys
p, adr = sys.argv[1:]; s = open(p, encoding="utf-8").read()
m = re.search(r"(?ms)^## ADR-000 .*?(?=^## |\Z)", s)
open(p, "w", encoding="utf-8").write(s[:m.start()] + open(adr, encoding="utf-8").read() + "\n" + s[m.end():])
PY
python3 -I - contexto/README.md <<'PY' || falla "no pude escribir el manifiesto"
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
filas = ("| `brief.md` | documento | 2026-11-05 | `docs/encuadre.md` §Contexto, §Criterios | necesidad y criterios |\n"
         "| `gastos.csv` | datos de entrada | 2026-11-05 | `docs/encuadre.md` §Entradas y salidas | set de oro, par 1 |\n"
         "| `gastos-invalido.csv` | datos de entrada | 2026-11-05 | `docs/encuadre.md` §Entradas y salidas | set de oro, par 4 |\n")
a = s.index("| _(ejemplo)_"); b = s.index("\n", s.index("| _(ejemplo)_", a + 1)) + 1
open(p, "w", encoding="utf-8").write(s[:a] + filas + s[b:])
PY
sed -i.bak -e 's/^- \*\*Proyecto:\*\* _\[nombre\]_/- **Proyecto:** resumen de gastos (ejemplo del método)/' \
  -e 's/^- \*\*Propósito:\*\* _\[qué problema resuelve, en una frase\]_/- **Propósito:** resumir por categoría un CSV de gastos desde la terminal./' AGENTS.md \
  || falla "no pude completar AGENTS.md §1"
rm -f AGENTS.md.bak
estado F1 "—" "gate del encuadre" "gate F1: confirmar docs/encuadre.md (simulado)"
commit <<'EOF'
Encuadre: siembra desde el ruteo aprobado

Ref: F1
EOF

paso "F2 · Plan, trazabilidad sembrada, ADR, suite y revisión funcional (§Fase 2; dirigiendo-revisiones)"
rellena docs/plan.md "$EJ/pasos/f2/plan.md"
rellena docs/trazabilidad.md "$EJ/pasos/f2/trazabilidad.md"
# check.sh empieza por el bloque canónico de la suite vigilada, copiado tal cual (convenciones §Comandos clave).
cp "$EJ/pasos/f2/README.md" README.md || falla "no pude escribir el README del producto"   # escribiendo-readme
{ printf '#!/bin/sh\n'; awk '/^# --- suite vigilada/{f=1} f{print} /^# --- fin suite vigilada/{exit}' docs/convenciones.md
  cat "$EJ/pasos/f2/check-producto.sh"; } > scripts/check.sh || falla "no pude escribir scripts/check.sh"
grep -q '^# --- fin suite vigilada ---$' scripts/check.sh || falla "scripts/check.sh no tiene el bloque canónico"
estado F2 "I1 «resumen»" "revisión funcional del encuadre y el plan" "—"
recibo rol=revisor-funcional tipo=encuadre alcance=F2 veredicto=PASA bloqueantes=0
estado F2 "I1 «resumen»" "gate de diseño" "gate F2: aprobar el plan (simulado)"
commit <<'EOF'
Plan: tres incrementos y plan de pruebas

Ref: F2
EOF

paso "F3 · I1, I2 e I3, cada uno con su recibo del juez de código (DoD; revision-critica)"
cierra_incremento I1 C1 i1 "I1 «resumen»: resumir() y main() con la muestra real; pares 1–3." \
  || falla "no pude cerrar I1"
commit <<'EOF'
I1 «resumen»: resumen por categoría y total

Ref: I1
EOF
cierra_incremento I2 C2 i2 "I2 «importe-invalido»: error con número de fila y sin resumen parcial; par 4." \
  || falla "no pude cerrar I2"
commit <<'EOF'
I2 «importe-invalido»: fila con importe inválido

Ref: I2
EOF
cierra_incremento I3 C3 i3 "I3 «archivo-inexistente»: error y código 1; par 5." \
  || falla "no pude cerrar I3"
commit <<'EOF'
I3 «archivo-inexistente»: archivo que no existe

Ref: I3
EOF

paso "Hito I1–I3: el juez de conjunto sobre lo ensamblado (AGENTS.md §2, Fase 4 «también por hito»)"
estado F3 "—" "revisión del hito I1-I3" "—"
recibo rol=juez-conjunto tipo=hito alcance=hito:I1-I3 veredicto=PASA bloqueantes=0 seguridad=no-aplica \
  cubre=C1,C2,C3 excluye=ninguno componentes=resumen
estado F3 "—" "validación del conjunto (F4)" "gate del hito (simulado)"
commit <<'EOF'
Hito I1-I3: conjunto ensamblado

Ref: hito:I1-I3
EOF

paso "F4 · Validación del conjunto (docs/definicion-de-hecho.md)"
estado F4 "—" "revisión del conjunto" "—"
recibo rol=juez-conjunto tipo=conjunto alcance=F4 veredicto=PASA bloqueantes=0 seguridad=no-aplica
estado F4 "—" "cierre (F5)" "gate F4: el conjunto cumple la DoD (simulado)"
commit <<'EOF'
Validación: todos los criterios verificados y el conjunto en PASA

Ref: F4
EOF

paso "F5 · Cierre y aprendizaje (AGENTS.md §2, Fase 5)"
estado F5 "—" "triage de lo que llegue (reentrada)" "—"
printf -- '- [2026-11-05] Ejemplo: un incremento por criterio bastó; el set de oro guió las pruebas.\n' >> docs/MEMORIA.md \
  || falla "no pude escribir la lección"
commit <<'EOF'
Cierre del ciclo

Ref: F5
EOF

paso "Comprobaciones con los controles reales del método"
# Cada salida se captura con su código; solo después se abrevia para mostrarla.
if salida=$(sh scripts/pruebas/validar_historial.sh HEAD 2>&1); then
  printf '%s\n' "$salida" | tail -n 1 | sed 's/^/   /'
else
  printf '%s\n' "$salida" | tail -n 20 >&2; falla "el replay (validar_historial.sh) rechaza la historia"
fi
if salida=$(sh scripts/check_docs.sh 2>&1); then
  echo "   doctor (check_docs) en verde en F5"
else
  printf '%s\n' "$salida" >&2; falla "el doctor (check_docs.sh) falla en F5"
fi
if salida=$(sh scripts/recibos.sh validar docs/revisiones.log 2>&1); then
  echo "   recibos: todas las líneas válidas (formato; no prueban revisiones reales)"
else
  printf '%s\n' "$salida" >&2; falla "hay recibos inválidos"
fi
if salida=$(python3 resumen.py contexto/gastos.csv 2>&1); then
  printf '%s\n' "$salida" | sed 's/^/   /'
else
  printf '%s\n' "$salida" >&2; falla "el producto falla sobre contexto/gastos.csv"
fi
historia=$(git log --format='   %h  %s' --reverse) || falla "git log falló"
printf '\n%s\n' "$historia"
printf '\nListo: %s (inspecciona con git log --stat y git show <commit>).\n' "$DEST"
