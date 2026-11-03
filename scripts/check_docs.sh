#!/bin/sh
# Integridad del rastro documental (viene con la plantilla; ver AGENTS.md §8).
#
# Modo "commit" (por defecto): lo corre el pre-commit sobre una exportación del ÍNDICE
# (lo que de verdad se versiona), y el agente lo corre a mano al inicio de sesión. Siempre
# aplica lo estructural (archivos de la plantilla, roles, skills, frontmatter, recibos) y,
# dentro de un repo, la INSTALACIÓN (hooks activos y ejecutables: un clon nuevo FALLA hasta
# el Bootstrap, a propósito). "Plantilla sin iniciar" es SOLO: estado.md sin fase legible Y
# ningún commit del historial con fase (no solo HEAD: ver fase_historica). Una vez iniciado, una fase ausente o ilegible (F_, vacía) es FALLA, no plantilla.
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

# --- Última fase legible del HISTORIAL --------------------------------------------------------
# Un commit que borra o estropea la fase no puede devolver el proyecto a «plantilla»: lo que
# decide si el proyecto está iniciado es si ALGÚN commit declaró una fase, no solo el último.
# `sh scripts/check_docs.sh fase-historica [rev]` imprime esa fase (F1..F5) o nada. El
# pre-commit y el replay, que corren el validador sin .git, la pasan en FASE_HISTORICA.
RE_FASE='Fase actual:\*?\*?[[:space:]]*F[1-5]'
fase_historica() {  # $1 = revisión desde la que mirar hacia atrás (por defecto HEAD)
  git rev-parse --verify -q "${1:-HEAD}^{commit}" >/dev/null 2>&1 || return 0
  for c in $(git log --format=%H -E -G"$RE_FASE" "${1:-HEAD}" -- docs/estado.md 2>/dev/null); do
    for x in "$c" "$c^"; do   # el commit que la quitó no la tiene; su padre sí
      f=$(git show "$x:docs/estado.md" 2>/dev/null | grep -oE "$RE_FASE" | grep -oE 'F[1-5]' | head -1)
      [ -n "$f" ] && { echo "$f"; return 0; }
    done
  done
}
if [ "$MODE" = "fase-historica" ]; then fase_historica "${2:-HEAD}"; exit 0; fi

# --- Lector ÚNICO del plan -------------------------------------------------------------------
# Una sola gramática de incremento para el doctor y el commit-msg: `- [ ] I<n> «alias» — …`
# (o `- [x]`), al inicio de línea. `sh scripts/check_docs.sh plan [archivo | -]` imprime
#   I <id> pendiente|hecho <sección>   línea canónica (sección: inc | backlog | otra)
#   MAL <nlínea> <sección>             parece un incremento (casilla con I<n>, o ítem I<n> bajo
#                                      ## Incrementos) pero no tiene la forma canónica
# Así un incremento no se vuelve invisible por su formato ni por el encabezado bajo el que esté.
# Lo que NO se renderiza como plan no es plan: comentarios HTML (`<!-- … -->`, de una o varias
# líneas) y bloques de código cercados (``` o ~~~, ejemplos) se excluyen del inventario.
leer_plan() {
  awk '
    function quita_comentarios(t,   a, b, o) { o=""
      while (1) {
        if (encom) { b=index(t, "-->"); if (!b) return o; t=substr(t, b+3); encom=0 }
        a=index(t, "<!--"); if (!a) return o t
        o=o substr(t, 1, a-1); t=substr(t, a+4); encom=1
      } }
    # Cerco de CommonMark (§4.5): hasta 3 espacios, ≥3 ` o ~; cierra solo el MISMO carácter
    # con longitud ≥ la de apertura y nada más en la línea. Una línea interior que «parece»
    # otro delimitador no lo cierra.
    function cerca(t,   ind, c, n, resto) {
      ind=0; while (substr(t,1,1)==" " && ind<4) { t=substr(t,2); ind++ }
      if (ind>=4) return 0
      c=substr(t,1,1); if (c!="`" && c!="~") return 0
      n=0; while (substr(t,n+1,1)==c) n++
      if (n<3) return 0
      resto=substr(t,n+1)
      if (!cerco) { if (c=="`" && index(resto, "`")) return 0; fc=c; fl=n; return 1 }
      return (c==fc && n>=fl && resto ~ /^[ \t]*$/)
    }
    !encom && cerca($0) { cerco = !cerco; next }
    cerco { next }
    { linea = quita_comentarios($0); if (linea ~ /^[ \t]*$/) next }
    linea ~ /^## / { l=tolower(linea); sec = (l ~ /^## incrementos/) ? "inc" : (l ~ /backlog|fuera de alcance/) ? "backlog" : "otra"; next }
    linea ~ /^- \[[ xX]\] I[0-9]+ / { st = (linea ~ /^- \[ \]/) ? "pendiente" : "hecho"; id = substr(linea, 7); sub(/ .*$/, "", id); print "I", id, st, (sec==""?"otra":sec); next }
    linea ~ /^[ \t]*[-*+]?[ \t]*\[[^]]*\][ \t]*[*_`]*I[0-9]+/ { print "MAL", NR, (sec==""?"otra":sec); next }
    sec=="inc" && linea ~ /^[ \t]*[-*+][ \t]+[*_`]*I[0-9]+/ { print "MAL", NR, sec }
  ' "$1"
}
if [ "$MODE" = "plan" ]; then
  F="${2:-docs/plan.md}"; if [ "$F" = "-" ]; then F=/dev/stdin; else [ -f "$F" ] || exit 0; fi
  leer_plan "$F"; exit 0
fi

# --- Fase vigente -------------------------------------------------------------
FASE=""; FASE_LINEA=""
if has docs/estado.md; then
  FASE_LINEA=$(grep -m1 'Fase actual:' docs/estado.md || true)
  FASE=$(printf '%s' "$FASE_LINEA" | grep -oE 'Fase actual:\*?\*?[[:space:]]*F[0-9]+' | grep -oE 'F[0-9]+' | head -1)
fi
# Fase previa estable: la del commit anterior (FASE_PREVIA, que pasa el pre-commit) y, si esa
# también falta, la última legible de TODO el historial (FASE_HISTORICA, o calculada aquí).
PREVIA="${FASE_PREVIA:-}"
if [ -z "$PREVIA" ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
  PREVIA=$(git show HEAD:docs/estado.md 2>/dev/null | grep -oE "$RE_FASE" | grep -oE 'F[1-5]' | head -1)
fi
HISTORICA="${FASE_HISTORICA:-}"
[ -z "$HISTORICA" ] && [ -z "$PREVIA" ] && HISTORICA=$(fase_historica HEAD)
ANTES="${PREVIA:-$HISTORICA}"
if [ "$MODE" = "iniciado" ]; then   # ¿proyecto iniciado (ahora o alguna vez)? Lo usa la CI.
  [ -n "$FASE" ] || [ -n "$ANTES" ]; exit $?
fi
INICIADO=0
case "$FASE" in
  F1) ;;
  F2|F3|F4|F5) INICIADO=1 ;;
  "") if [ -n "$ANTES" ]; then
        err "docs/estado.md no declara una fase legible (línea: '${FASE_LINEA:-sin «Fase actual:»}') y el proyecto ya estaba iniciado (última fase legible del historial: $ANTES). Una fase ausente o F_ no es 'modo plantilla': escribe 'Fase actual: F1..F5'."
        FASE="$ANTES"; case "$FASE" in F2|F3|F4|F5) INICIADO=1 ;; esac
      fi ;;
  *) err "docs/estado.md declara una fase inválida ($FASE): solo F1..F5. Una fase desconocida no es 'modo plantilla'."; INICIADO=1 ;;
esac
[ "$MODE" = "cierre" ] && INICIADO=1

# --- 0) Archivos de la plantilla: obligatorios SIEMPRE (vienen con ella; en F1 también).
#     Los registros (revisiones.log, recibos.sh, huella.sh) no desaparecen en ninguna fase.
for f in AGENTS.md README.md contexto/README.md docs/estado.md docs/encuadre.md \
         docs/plan.md docs/trazabilidad.md docs/decisiones.md docs/convenciones.md \
         docs/definicion-de-hecho.md docs/despliegue.md docs/MEMORIA.md docs/revisiones.log \
         scripts/check_docs.sh scripts/huella.sh scripts/recibos.sh scripts/trazabilidad.sh scripts/suite.py \
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

# --- 0a') Suite vigilada (docs/convenciones.md §Comandos clave): desde que existe, en cualquier fase
#     (también F_ en el Paso 0 de una adopción y F1), scripts/check.sh empieza por el bloque que la
#     corre bajo scripts/suite.py, y el plazo común está declarado. El pre-commit corre esto ANTES de
#     lanzar check.sh: un check.sh sin el bloque no llega a ejecutarse desde el hook. El bloque se
#     PRUEBA aislado: en un proyecto temporal mínimo (copia de suite.py + un check.sh ficticio = el
#     bloque + un eco del identificador), con registro propio, sin las SUITE_* heredadas y con un
#     límite propio (no depende del envoltorio que comprueba). El cuerpo real nunca se ejecuta.
#     Antes de ejecutar nada, un único validador (python3 -I) lee check.sh y docs/convenciones.md como
#     BYTES (sin awk ni variables de shell que los transformen) y exige: ningún NUL ni CR en ninguno de
#     los dos (sh ejecuta lo que hay tras un NUL; el chequeo no lo vería); un solo par de delimitadores
#     completo en cada uno; antes del bloque de check.sh solo shebang, comentarios y blancos; y el bloque
#     IDÉNTICO a la única definición canónica (docs/convenciones.md §Comandos clave). Si algo falla, no
#     ejecuta nada; si pasa, escribe la prueba temporal desde esos MISMOS bytes. Alcance: rechaza un
#     bloque alterado respecto a la referencia LOCAL; no autentica convenciones.md ni suite.py, que se
#     pueden cambiar en el mismo commit, ni impide que otro código del candidato se ejecute.
INICIO_BLOQUE='# --- suite vigilada'
FIN_BLOQUE='# --- fin suite vigilada ---'
if has scripts/check.sh && has scripts/suite.py; then
  grep -qE '^- \*\*Plazo de la suite:\*\* [0-9]+ s' docs/convenciones.md \
    || err "docs/convenciones.md no declara el plazo común de la suite («- **Plazo de la suite:** N s», §Comandos clave)"
  aisl=$(mktemp -d "${TMPDIR:-/tmp}/check-docs-suite.XXXXXX") && mkdir -p "$aisl/p/scripts" "$aisl/p/docs" \
    || err "no pude preparar el proyecto temporal para probar el bloque de la suite vigilada"
  v=$(python3 -I -c '
import re, sys
INI, FIN = b"# --- suite vigilada", b"# --- fin suite vigilada ---"
def lee(p):
    try:
        with open(p, "rb") as f: return f.read()
    except OSError: return None
def delim(datos):
    l = datos.split(b"\n")
    return l, [n for n, x in enumerate(l) if x.startswith(INI)], [n for n, x in enumerate(l) if x == FIN]
chk, conv = lee(sys.argv[1]), lee(sys.argv[2])
if conv is None: sys.exit(print("sin-referencia"))
if b"\0" in conv or b"\r" in conv: sys.exit(print("referencia-nul-cr"))
cl, ci, cf = delim(conv)
if len(ci) != 1 or len(cf) != 1 or cf[0] < ci[0]: sys.exit(print("sin-referencia"))
canonico = b"\n".join(cl[ci[0]:cf[0] + 1])
if chk is None: sys.exit(print("no-empieza"))
if b"\0" in chk or b"\r" in chk: sys.exit(print("nul-cr"))
l, i, f = delim(chk)
if not i or not all(re.fullmatch(rb"[ \t]*(#.*)?", x) for x in l[:i[0]]) or not any(n > i[0] for n in f): sys.exit(print("no-empieza"))
if len(i) != 1 or len(f) != 1: sys.exit(print("duplicados"))
if b"\n".join(l[i[0]:f[0] + 1]) != canonico: sys.exit(print("difiere"))
with open(sys.argv[3], "wb") as o: o.write(b"#!/bin/sh\n" + canonico + b"\n" + b"echo \"vigilada:${SUITE_ID:-}\"\n")
print("ok")
' scripts/check.sh docs/convenciones.md "$aisl/p/scripts/check.sh" 2>&1)
  case "$v" in
    ok) ;;
    sin-referencia) err "docs/convenciones.md no tiene UNA definición completa del bloque de la suite vigilada (un «${INICIO_BLOQUE}» y un «${FIN_BLOQUE}», §Comandos clave): sin referencia no ejecuto el de scripts/check.sh" ;;
    referencia-nul-cr) err "docs/convenciones.md contiene bytes NUL o CR: sin una referencia legible tal cual no ejecuto el bloque de scripts/check.sh" ;;
    nul-cr) err "scripts/check.sh contiene bytes NUL o CR (sh ejecutaría lo que la comprobación no ve): no lo ejecuto" ;;
    no-empieza) err "scripts/check.sh no EMPIEZA por el bloque de la suite vigilada (de «${INICIO_BLOQUE}» a «${FIN_BLOQUE}», docs/convenciones.md §Comandos clave): sin él, la suite corre sin plazo ni registro" ;;
    duplicados) err "scripts/check.sh tiene delimitadores del bloque de la suite vigilada duplicados (debe haber un «${INICIO_BLOQUE}» y un «${FIN_BLOQUE}»): no lo ejecuto" ;;
    difiere) err "el bloque de la suite vigilada de scripts/check.sh DIFIERE del canónico (docs/convenciones.md §Comandos clave; cópialo sin cambios): no lo ejecuto" ;;
    *) err "no pude validar el bloque de la suite vigilada ($v): no lo ejecuto" ;;
  esac
  if [ "$v" != ok ]; then
    rm -rf "$aisl"
  else
    cp scripts/suite.py "$aisl/p/scripts/suite.py" \
      && printf -- '- **Plazo de la suite:** 30 s\n' > "$aisl/p/docs/convenciones.md" \
      || err "no pude preparar el proyecto temporal para probar el bloque de la suite vigilada"
    r=$(python3 -I -c '
import json, os, re, signal, subprocess, sys
d = sys.argv[1]
env = {k: v for k, v in os.environ.items() if not k.startswith("SUITE_")}
env["SUITE_REGISTRO"] = os.path.join(d, "reg")
def corre(extra):
    p = subprocess.Popen(["sh", os.path.join(d, "p/scripts/check.sh")], cwd=os.path.join(d, "p"), env={**env, **extra},
                         stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=60)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL); p.wait()
        sys.exit("no terminó en 60 s")
    return p.returncode, out.decode(errors="replace")
rc, out = corre({})
m = re.search(r"^vigilada:([0-9A-Za-z-]+)$", out, re.M)
if rc != 0 or not m:
    sys.exit(f"no corrió vigilado (rc={rc}; sin «vigilada:<id>»): {out.strip()[-300:]}")
reg = os.path.join(d, "reg", m.group(1) + ".json")
try:
    rec = json.load(open(reg))
except (OSError, ValueError) as exc:
    sys.exit(f"el registro de la ejecución {m.group(1)} no se puede leer o está dañado: {exc}")
if not isinstance(rec, dict) or rec.get("estado") != "aprobada":
    sys.exit(f"la ejecución {m.group(1)} no quedó registrada como aprobada en el registro temporal")
rc, out = corre({"SUITE_ID": "externa"})
if rc != 75 or "vigilada:" in out:
    sys.exit(f"una llamada anidada no se rechazó (rc={rc}): {out.strip()[-300:]}")
' "$aisl" 2>&1) || err "el bloque de la suite vigilada no funciona aislado: $r"
    # Borrarla exige DEMOSTRAR que no quedó nada abierto: lo decide el parser de suite.py (JSON validado;
    # registro dañado o ilegible = no comprobable), nunca una búsqueda de texto.
    abiertas=$(cd "$aisl" && env -u SUITE_ID SUITE_REGISTRO="$aisl/reg" python3 -I "$aisl/p/scripts/suite.py" estado --abiertas 2>&1)
    ec=$?
    if [ "$ec" -ne 0 ]; then
      err "no pude comprobar el registro temporal de la prueba aislada (salida $ec: $abiertas); conservo $aisl para inspeccionarlo"
    elif [ -n "$abiertas" ]; then
      err "la prueba aislada dejó una ejecución abierta ($abiertas); conservo $aisl para inspeccionarla"
    else
      rm -rf "$aisl"
    fi
  fi
fi

# --- 0a'') Al inicio de sesión (dentro del repo): ejecuciones abiertas o carpetas propias que siguen
#     conservadas se AVISAN (no fallan): son lo primero que se revisa antes de lanzar otra suite.
if has scripts/suite.py && git rev-parse --git-dir >/dev/null 2>&1 && [ -d "$(git rev-parse --git-common-dir)/suite-runs" ]; then
  if pend=$(python3 -I scripts/suite.py estado --abiertas 2>&1); then
    [ -z "$pend" ] || printf '⚠ check_docs: hay ejecuciones de la suite abiertas o carpetas propias conservadas (python3 scripts/suite.py estado):\n%s\n' "$pend" >&2
  else
    printf '⚠ check_docs: no pude leer el registro de la suite: %s\n' "$pend" >&2
  fi
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

# Una fila E/R en resuelto|verificado con la celda «Resuelto» vacía (o solo «—») no dice qué la
# sostiene. Que la referencia RESUELVA (ruta del repositorio, commit del historial) lo comprueba el
# commit-msg, que tiene índice e historial; que DEMUESTRE la resolución lo juzga el revisor.
if [ "$INICIADO" -eq 1 ]; then
  for id in $(printf '%s\n' "$FILAS" | awk '$1 ~ /^(E|R)$/ && $4 ~ /^(resuelto|verificado)$/ {print $2}'); do
    printf '%s\n' "$FILAS" | awk -v id="$id" '$1=="RES" && $2==id && NF>=3 {f=1} END {exit f?0:1}' \
      || err "trazabilidad.md: $id está en Estado '$(printf '%s\n' "$FILAS" | awk -v id="$id" '$1 ~ /^(E|R)$/ && $2==id {print $4; exit}')' con la columna Resuelto vacía: escribe qué lo sostiene (ruta archivo:línea de la prueba o mutación, o commit)"
  done
fi

# Unicidad: un C# o un hallazgo con dos filas es un registro ambiguo (V04/V10).
for dup in $(printf '%s\n' "$FILAS" | awk '$1 ~ /^(C|E|R|H)$/ {print $2}' | sort | uniq -d); do
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
  # Un criterio es UNA línea. Tras `- C<n>:` lo siguiente (saltando blancos) es otro ítem, un
  # encabezado, un comentario, una tabla o un separador en la columna 1. Una continuación «perezosa»
  # (sin blanco) o un párrafo SANGRADO tras uno o más blancos pertenecen al ítem en Markdown: el hook
  # no los compara contra el contrato revisado, así que se rechazan en vez de interpretarlos.
  cont=$(awk '
    /^- C[0-9]+:/ { c=1; b=0; next }
    !c { next }
    /^[ \t]*$/ { b=1; next }
    b { if ($0 ~ /^[ \t]/) print NR": "substr($0,1,50); c=0; next }
    $0 !~ /^([-*+] |#|<!--|\||---)/ { print NR": "substr($0,1,50) }
    { c=0 }' docs/encuadre.md | head -2)
  [ -z "$cont" ] || err "encuadre.md: criterio con texto de continuación en la línea $(printf '%s' "$cont" | tr '\n' '|'); un criterio es una sola línea '- C<n>: enunciado' (el commit-msg compara esa línea con el contrato revisado)"
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
  PLAN=$(leer_plan docs/plan.md)
  plan_ids=$(printf '%s\n' "$PLAN" | awk '$1=="I" {print $2}')
  if [ "$INICIADO" -eq 1 ]; then
    for n in $(printf '%s\n' "$PLAN" | awk '$1=="MAL" {print $2}'); do
      err "plan.md línea $n parece un incremento pero no tiene la forma '- [ ] I<n> «alias» — …' (o '- [x]'): «$(sed -n "${n}p" docs/plan.md | cut -c1-60)». Ni el doctor ni el commit-msg lo leerían."
    done
  fi
  for i in $(printf '%s\n' "$plan_ids" | sort | uniq -d); do
    err "$i está definido más de una vez en plan.md"
  done
  if [ "$INICIADO" -eq 1 ]; then
    cited=$( { printf '%s\n' "$FILAS" | awk '$1 ~ /^(C|E|R)$/ {print $3}' | grep -oE 'I[0-9]+' ; \
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
# Valor de un escalar del frontmatter como lo lee YAML (un solo contrato para skills y
# agentes): entre comillas, su contenido; sin comillas, sin el comentario ` #…`, y un valor que
# EMPIEZA por # es un comentario (nulo). En "…" los escapes se DECODIFICAN antes de juzgar:
# los que dan un blanco o un control (\t, \n, \u0020, \x20, \_ …) cuentan como blanco, así
# que "\u0020" está en blanco como "   ". Siempre recortado, también de blancos Unicode
# (NBSP, espacios tipográficos, ideográfico): lo que queda tiene que ser texto.
valor_yaml() {  # $1 bloque frontmatter, $2 clave → texto (vacío si nulo, ausente o en blanco)
  # LC_ALL=C: los blancos Unicode se reconocen por sus BYTES UTF-8, igual con mawk o con gawk
  # en cualquier locale (un rango de bytes en un locale UTF-8 es «collation» inválida en gawk).
  printf '%s\n' "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | LC_ALL=C awk -v sq="'" '
    function hexval(h,   i, n, c) { n=0; h=toupper(h)
      for (i=1; i<=length(h); i++) { c=index("0123456789ABCDEF", substr(h,i,1)); if (!c) return -1; n=n*16+c-1 }
      return n }
    function blanco(n) { return n<=32 || n==127 || (n>=128 && n<=160) || n==5760 || (n>=8192 && n<=8207) || n==8232 || n==8233 || n==8239 || n==8287 || n==12288 || n==65279 }
    function decodifica(v,   o, i, c, e, L, n) { o=""; i=1
      while (i<=length(v)) { c=substr(v,i,1)
        if (c!="\\") { o=o c; i++; continue }
        e=substr(v,i+1,1); L=(e=="x")?2:(e=="u")?4:(e=="U")?8:0
        if (L) { n=hexval(substr(v,i+2,L)); o=o ((n>=0 && blanco(n)) ? " " : "x"); i+=2+L; continue }
        if (index("0abtnvfre _NLP", e)) o=o " "; else o=o e
        i+=2 }
      return o }
    { v=$0; q=substr(v,1,1)
      if (q=="\"" || q==sq) {
        for (i=length(v); i>1; i--) if (substr(v,i,1)==q) break
        v = (i>1) ? substr(v,2,i-2) : ""
        if (q==sq) gsub(sq sq, sq, v); else v=decodifica(v)
      } else if (q=="#") v=""
      else sub(/[ \t]+#.*$/, "", v)
      gsub(/\302\240|\342\200\200|\342\200\201|\342\200\202|\342\200\203|\342\200\204|\342\200\205|\342\200\206|\342\200\207|\342\200\210|\342\200\211|\342\200\212|\342\200\257|\342\201\237|\343\200\200|\357\273\277/, " ", v)
      gsub(/^[ \t]+|[ \t]+$/, "", v); print v }'
}
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
    # Claves de frontmatter de skills de Claude Code que un proyecto adoptado ya puede usar.
    check_frontmatter "$f" 'name|description|allowed-tools|argument-hint|disable-model-invocation|user-invocable|model' || continue
    fm="$FM"
    fm_name=$(valor_yaml "$fm" name)
    [ "$fm_name" = "$name" ] || err "$f: name '$fm_name' no coincide con la carpeta '$name'"
    desc=$(valor_yaml "$fm" description)
    if [ -z "$desc" ]; then
      err "$f: description vacía, en blanco, solo comentario o ausente (es el campo con que el agente decide si la abre)"
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
    afm_name=$(valor_yaml "$afm" name)
    [ "$afm_name" = "$aname" ] || err "$f: name '$afm_name' no coincide con el archivo '$aname'"
    adesc=$(valor_yaml "$afm" description)
    [ -n "$adesc" ] || err "$f: description vacía, en blanco, solo comentario o ausente (con ella Claude Code decide cuándo delegar; \"\" es YAML válido pero no dice nada)"
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

# --- 7b) Evidencia de revisiones: cada carpeta de docs/revisiones/ la registra un recibo -----------
#     (evidencia=docs/revisiones/<id>@<huella>). Una carpeta sin recibo no es evidencia de nada; que
#     la huella coincida lo comprueba scripts/guardas.sh (pre-commit y replay), que ve el árbol de git.
if [ -d docs/revisiones ]; then
  for e in docs/revisiones/* docs/revisiones/.[!.]* docs/revisiones/..?*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    case "${e##*/}" in .*) err "$e: entrada oculta en docs/revisiones/; la evidencia va en carpetas visibles cuyo nombre empieza por letra o número"; continue ;; esac
    if [ ! -d "$e" ] || [ -L "$e" ]; then err "$e: en docs/revisiones/ solo van carpetas de evidencia (una por revisión), no archivos ni enlaces"; continue; fi
    grep -v '^[[:space:]]*#' docs/revisiones.log 2>/dev/null | grep -qE "(^| )evidencia=$e@[0-9a-f]{12}( |\$)" \
      || err "$e no la registra ningún recibo de docs/revisiones.log (evidencia=$e@<huella>): una carpeta de evidencia sin su recibo no es evidencia"
  done
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
    # Bajo CUALQUIER encabezado salvo el backlog («Fuera de alcance / backlog»).
    for i in $(leer_plan docs/plan.md | awk '$1=="I" && $3=="pendiente" && $4!="backlog" {print $2}'); do
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
