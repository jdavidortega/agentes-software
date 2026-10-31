#!/bin/sh
# Regresión del envoltorio de la suite (scripts/suite.py). Cada caso en un repositorio temporal propio;
# los procesos de prueba escriben sus PID en archivos para comprobar que de verdad terminaron. Sin red.
# Verificado en macOS. Tarda alrededor de un minuto: hay plazos y márgenes reales.
#
#   sh scripts/pruebas/regresion-suite.sh       → 0 si todos los casos pasan; 1 y la lista si no
#   sh scripts/pruebas/regresion-suite.sh -v    → además imprime la salida de cada caso
VERBOSE=0; [ "${1:-}" = "-v" ] && VERBOSE=1
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
SU="$RAIZ/scripts/suite.py"
# Plantilla explícita: en macOS `mktemp -d` sin ella ignora TMPDIR.
W=$(mktemp -d "${TMPDIR:-/tmp}/regresion-suite.XXXXXX"); W=$(cd "$W" && pwd -P)
export GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_CONFIG_SYSTEM=/dev/null; : > "$W/gitconfig"
export GIT_AUTHOR_NAME=r GIT_AUTHOR_EMAIL=r@local GIT_COMMITTER_NAME=r GIT_COMMITTER_EMAIL=r@local
unset SUITE_ID SUITE_REGISTRO SUITE_PLAZO SUITE_ENVUELTO SUITE_INFORME
TOTAL=0; MAL=0; FALLIDOS=""

# Al salir: termina lo que los casos dejaron vivo a propósito (solo PID anotados aquí) y borra las
# carpetas de ejecución que el registro de cada caso declara como suyas.
limpia() {
  find "$W/pids" -type f 2>/dev/null | while IFS= read -r f; do kill -9 "$(cat "$f")" 2>/dev/null; done
  for j in "$W"/*/.git/suite-runs/*.json "$W"/registro-*/*.json; do
    [ -f "$j" ] || continue
    c=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("carpeta",""))' "$j")
    case "$(basename "$c")" in suite-*) rm -rf "$c" ;; esac
  done
  rm -rf "$W"
}
trap limpia EXIT INT TERM
mkdir -p "$W/pids" "$W/bin"
# ps de prueba: delega en el real salvo tres interruptores. $W/ps-falla → ps falla (consulta imposible);
# $W/ps-cuelga → ps no responde (debe vencer su límite y contar como consulta imposible);
# $W/fantasma con un PGID → `ps -A` lista además un miembro de ese grupo que sobrevive a KILL (no se
# puede fabricar uno real: KILL no se ignora; solo un proceso bloqueado en el kernel sobrevive).
cat > "$W/bin/ps" <<EOF
#!/bin/sh
[ -f "$W/ps-falla" ] && { echo "ps: fallo simulado" >&2; exit 1; }
[ -f "$W/ps-cuelga" ] && exec sleep 300
$(command -v ps) "\$@"; rc=\$?
[ "\$1" = -A ] && [ -f "$W/fantasma" ] && echo "99999 \$(cat "$W/fantasma") S Thu Oct 29 10:00:00 2026 fantasma"
exit \$rc
EOF
chmod +x "$W/bin/ps"; export PATH="$W/bin:$PATH"

espera() {  # espera <falla|pasa> <nombre> <patrón ERE o vacío> -- cmd...
  modo=$1; nombre=$2; patron=$3; shift 4
  TOTAL=$((TOTAL+1)); out=$("$@" 2>&1); rc=$?
  if [ "$modo" = falla ]; then ok=$([ $rc -ne 0 ] && echo 1 || echo 0); else ok=$([ $rc -eq 0 ] && echo 1 || echo 0); fi
  if [ "$ok" = 1 ] && [ -n "$patron" ] && ! printf '%s' "$out" | grep -qE "$patron"; then ok=0; fi
  if [ "$ok" = 1 ]; then echo "  ok    $nombre"; else echo "  FALLO $nombre (esperaba $modo${patron:+ con «${patron}»}; rc=$rc)"; MAL=$((MAL+1)); FALLIDOS="$FALLIDOS
    - $nombre"; fi
  { [ "$VERBOSE" = 1 ] || [ "$ok" = 0 ]; } && printf '%s\n' "$out" | sed 's/^/        | /' | head -20
  return 0
}
repo() { R="$W/$1"; git init -q "$R"; REG="$R/.git/suite-runs"; }       # repo <nombre> → $R, $REG
corre() { ( cd "$R" && python3 "$SU" correr "$@" ); }                   # en $R
# La más reciente por su hora de inicio (dos en el mismo segundo no se ordenan por el nombre).
ultimo() { python3 -c 'import json,glob,sys; r=sorted((json.load(open(p)) for p in glob.glob(sys.argv[1]+"/*.json")), key=lambda x: x["inicio"]); print(r[-1]["id"] if r else "")' "$REG"; }
campo() { python3 -c 'import json,os,sys; p=sys.argv[1]; print(json.load(open(p)).get(sys.argv[2], "") if os.path.isfile(p) else "")' "$REG/$1.json" "$2"; }  # sin registro: vacío
vivo() { kill -0 "$1" 2>/dev/null && [ "$(ps -o stat= -p "$1" | cut -c1)" != Z ]; }
pid_de() { cat "$W/pids/$1"; }
hasta() { s=$1; shift; i=0; while [ $i -lt $((s*10)) ]; do "$@" && return 0; sleep 0.1; i=$((i+1)); done; return 1; }
existe() { [ -s "$1" ]; }
# acotado <seg> cmd...: un caso que se colgaría si la garantía se rompe tiene su propio límite. Al
# vencer termina su grupo y los PID que el caso anotó en $P (el guardián suelta al líder muerto), y
# sale con 124 sin la salida esperada: el caso FALLA en lugar de colgar la batería.
acotado() { python3 -c '
import glob, os, subprocess, sys
s = int(sys.argv[1]); p = subprocess.Popen(sys.argv[2:], start_new_session=True)
try:
    sys.exit(p.wait(timeout=s))
except subprocess.TimeoutExpired:
    for f in glob.glob(os.path.join(os.environ["P"], "*")):
        try: os.kill(int(open(f).read()), 9)
        except (OSError, ValueError): pass
    os.killpg(p.pid, 9); p.wait()
    print(f"acotado: el caso no terminó en {s}s", file=sys.stderr); sys.exit(124)
' "$@"; }
abierta_con_grupo() { [ -n "$(ultimo)" ] && [ -n "$(campo "$(ultimo)" grupo)" ]; }
# Toma el cerrojo del registro (flock) y avisa en <marca>; lo suelta al salir o al morir.
cerrojo() { exec python3 -c 'import fcntl,sys,time; f=open(sys.argv[1]+"/.cerrojo.lck","a"); fcntl.flock(f,fcntl.LOCK_EX); open(sys.argv[2],"w").write("1"); time.sleep(float(sys.argv[3]))' "$@"; }
libre() { python3 -c 'import fcntl,sys; fcntl.flock(open(sys.argv[1]+"/.cerrojo.lck","a"),fcntl.LOCK_EX|fcntl.LOCK_NB)' "$1"; }
# Suite que no termina: un nieto en segundo plano y un bucle que ignora TERM (obliga al KILL).
COLGADA='sleep 300 & echo $! > "$P/nieto"; echo $$ > "$P/lider"; trap "" TERM; echo arranco; while :; do sleep 1; done'

echo "== caso normal, fallo y plazo obligatorio"
repo n1
espera pasa "una suite que pasa devuelve 0 y el informe dice aprobada" "estado=aprobada" -- sh -c 'cd "$1" && python3 "$2" correr --plazo 20 --informe "$3/inf-n1" -- sh -c "echo test_uno PASSED" && cat "$3/inf-n1"' _ "$R" "$SU" "$W"
espera pasa "... su salida llega al que la lanzó" "test_uno PASSED" -- corre --plazo 20 -- sh -c 'echo test_uno PASSED'
espera falla "una suite que falla devuelve su propio código (3)" "fallida \(rc=3\)" -- corre --plazo 20 -- sh -c 'exit 3'
espera pasa "... y el informe distingue fallida de los códigos del envoltorio" "estado=fallida rc=3" -- sh -c 'cd "$1" && python3 "$2" correr --plazo 20 --informe "$3/inf-n2" -- sh -c "exit 3"; cat "$3/inf-n2"' _ "$R" "$SU" "$W"
espera falla "sin plazo no se corre: es obligatorio" "falta el plazo" -- corre -- true
espera falla "un plazo no numérico se rechaza" "plazo inválido" -- corre --plazo diez -- true
espera pasa "SUITE_PLAZO sirve como plazo" "aprobada" -- env SUITE_PLAZO=20 sh -c 'cd "$1" && python3 "$2" correr -- true' _ "$R" "$SU"
corre --plazo 20 -- python3 -c 'import tempfile,os; d=tempfile.mkdtemp(); open(d+"/x","w").write("x"*1000); print("TEMPORAL", d)' > "$W/n1-tmp.out" 2>&1
TMPD=$(sed -n 's/^TEMPORAL //p' "$W/n1-tmp.out"); ID=$(ultimo); CARP=$(campo "$ID" carpeta)
espera pasa "los temporales de la suite van a la carpeta de la ejecución" "" -- sh -c 'case "$1" in "$2"/tmp/*) exit 0 ;; esac; exit 1' _ "$TMPD" "$CARP"
espera falla "... y se borran al cerrar" "" -- test -e "$TMPD"
espera pasa "... el log se conserva y dice cuál fue la última salida" "TEMPORAL" -- cat "$CARP/salida.log"

echo "== plazo vencido: termina el grupo entero"
repo e1; P="$W/pids/e1"; mkdir -p "$P"; export P
T0=$(date +%s)
espera falla "una suite que no termina sale con 124 (excedida), no como fallo de pruebas" "EXCEDIDA.*No es un fallo de pruebas" -- acotado 30 sh -c 'cd "$0" && exec python3 "$1" correr --plazo 2 --informe "$2" -- sh -c "$3"' "$R" "$SU" "$W/inf-e1" "$COLGADA"
T1=$(date +%s)
espera pasa "... dentro del plazo más el margen de TERM→KILL (< 15 s)" "" -- test $((T1-T0)) -lt 15
espera pasa "... avisa al 80 % antes de terminar" "superó el 80%" -- sh -c 'cd "$1" && python3 "$2" correr --plazo 2 -- sh -c "sleep 30" 2>&1; true' _ "$R" "$SU"
espera pasa "... el informe dice excedida" "estado=excedida" -- cat "$W/inf-e1"
espera falla "... el líder (que ignoraba TERM) no queda vivo" "" -- vivo "$(cat "$P/lider")"
espera falla "... el nieto en segundo plano no queda vivo" "" -- vivo "$(cat "$P/nieto")"
repo e2; P="$W/pids/e2"; mkdir -p "$P"
espera pasa "líder que termina dejando un descendiente vivo: aprobada" "aprobada" -- corre --plazo 20 -- sh -c 'sleep 300 & echo $! > "$P/desc"; exit 0'
espera falla "... y el guardián termina al descendiente que sobrevivió al líder" "" -- vivo "$(cat "$P/desc")"

echo "== una a la vez: segunda invocación, arranques simultáneos, anidada"
repo u1; P="$W/pids/u1"; mkdir -p "$P"
( cd "$R" && python3 "$SU" correr --plazo 60 -- sh -c 'echo $$ > "$P/lider"; sleep 300' > "$W/u1-a.out" 2>&1 ) &
hasta 10 existe "$P/lider" || echo "  (no arrancó la primera ejecución)"
ID=$(ultimo)
espera falla "una segunda invocación con otra abierta se rechaza (75) y nombra la abierta" "otra ejecución.*abierta|$ID" -- corre --plazo 20 -- true
espera pasa "... su informe dice bloqueada" "estado=bloqueada" -- sh -c 'cd "$1" && python3 "$2" correr --plazo 20 --informe "$3/inf-u1" -- true; cat "$3/inf-u1"' _ "$R" "$SU" "$W"
espera pasa "estado muestra la ejecución en curso con su última salida y su carpeta" "$ID  en curso.*" -- sh -c 'cd "$1" && python3 "$2" estado --abiertas' _ "$R" "$SU"
espera pasa "terminar la cierra (decisión explícita)" "" -- sh -c 'cd "$1" && python3 "$2" terminar "$3"' _ "$R" "$SU" "$ID"
wait
espera pasa "... queda como terminada y el lanzador sale con 130" "terminada" -- sh -c 'grep -q "terminada" "$1" && [ "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))[\"estado\"])" "$2")" = terminada ] && echo terminada' _ "$W/u1-a.out" "$REG/$ID.json"
espera falla "... y su proceso ya no existe" "" -- vivo "$(cat "$P/lider")"
repo u2
( cd "$R" && python3 "$SU" correr --plazo 20 -- sleep 2 > "$W/u2-a.out" 2>&1; echo $? > "$W/u2-a.rc" ) &
( cd "$R" && python3 "$SU" correr --plazo 20 -- sleep 2 > "$W/u2-b.out" 2>&1; echo $? > "$W/u2-b.rc" ) &
wait
espera pasa "dos arranques simultáneos: exactamente uno corre y el otro se bloquea (75)" "^0 75$|^75 0$" -- sh -c 'echo "$(cat "$1") $(cat "$2")"' _ "$W/u2-a.rc" "$W/u2-b.rc"
repo u3
espera pasa "una invocación anidada (desde dentro de una ejecución) se rechaza con 75" "interno=75" -- corre --plazo 20 -- sh -c 'python3 "$0" correr --plazo 5 -- true; echo interno=$?' "$SU"
espera falla "... y dice que es anidada (y la externa no aprueba)" "invocación anidada" -- corre --plazo 20 -- sh -c 'python3 "$0" correr --plazo 5 -- true' "$SU"

echo "== señales y terminación forzada"
repo s1; P="$W/pids/s1"; mkdir -p "$P"
( cd "$R" && exec python3 "$SU" correr --plazo 60 -- sh -c "$COLGADA" > "$W/s1.out" 2>&1 ) & LAN=$!
hasta 10 existe "$P/lider"; ID=$(ultimo); CARP=$(campo "$ID" carpeta)
kill -TERM $LAN; wait $LAN; RC=$?
espera pasa "TERM al lanzador: sale con 130 y la ejecución queda interrumpida" "" -- sh -c '[ "$1" = 130 ] && [ "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))[\"estado\"])" "$2")" = interrumpida ]' _ "$RC" "$REG/$ID.json"
espera falla "... sin procesos vivos de la suite (líder)" "" -- vivo "$(cat "$P/lider")"
espera falla "... ni del nieto" "" -- vivo "$(cat "$P/nieto")"
espera falla "... y su carpeta temporal se borró" "" -- test -e "$CARP/tmp"
repo s2; P="$W/pids/s2"; mkdir -p "$P"
( cd "$R" && exec python3 "$SU" correr --plazo 3 -- sh -c "$COLGADA" > /dev/null 2>&1 ) & LAN=$!
hasta 10 existe "$P/lider"; ID=$(ultimo)
kill -9 $LAN; wait $LAN 2>/dev/null
espera pasa "kill -9 solo del lanzador: el guardián igual aplica el plazo (excedida)" "" -- hasta 20 sh -c '[ "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))[\"estado\"])" "$1")" = excedida ]' _ "$REG/$ID.json"
espera falla "... y no deja procesos vivos" "" -- vivo "$(cat "$P/nieto")"
repo s3; P="$W/pids/s3"; mkdir -p "$P"
( cd "$R" && exec python3 "$SU" correr --plazo 60 -- sh -c "$COLGADA" > /dev/null 2>&1 ) & LAN=$!
hasta 10 existe "$P/lider"; hasta 5 abierta_con_grupo; ID=$(ultimo); CARP=$(campo "$ID" carpeta)
kill -9 "$(campo "$ID" guardia)" $LAN; kill -9 -"$(campo "$ID" grupo)"; wait $LAN 2>/dev/null; sleep 0.5
espera pasa "kill -9 de todo: el registro queda abierto y estado la muestra abandonada" "abandonada" -- sh -c 'cd "$1" && python3 "$2" estado "$3"' _ "$R" "$SU" "$ID"
espera pasa "... la siguiente ejecución la recupera y corre" "recupero la ejecución $ID.*aprobada|aprobada" -- corre --plazo 20 -- true
espera pasa "... la recuperada queda interrumpida y marcada como recuperada" "interrumpida True" -- sh -c 'python3 -c "import json,sys;r=json.load(open(sys.argv[1]));print(r[\"estado\"], r.get(\"recuperada\"))" "$1"' _ "$REG/$ID.json"
espera falla "... y su carpeta temporal se borró" "" -- test -e "$CARP/tmp"

echo "== pertenencia: huérfana demostrable frente a incierta"
repo p1; P="$W/pids/p1"; mkdir -p "$P"
( cd "$R" && exec python3 "$SU" correr --plazo 60 -- sh -c "$COLGADA" > /dev/null 2>&1 ) & LAN=$!
hasta 10 existe "$P/lider"; hasta 5 abierta_con_grupo; ID=$(ultimo)
kill -9 "$(campo "$ID" guardia)" $LAN; wait $LAN 2>/dev/null; sleep 0.3
espera pasa "sin guardián pero con el líder vivo e idéntico: huérfana" "huérfana" -- sh -c 'cd "$1" && python3 "$2" estado "$3"' _ "$R" "$SU" "$ID"
espera falla "... bloquea una nueva ejecución" "abierta" -- corre --plazo 20 -- true
espera pasa "... terminar la cierra porque la pertenencia es demostrable" "" -- sh -c 'cd "$1" && python3 "$2" terminar "$3"' _ "$R" "$SU" "$ID"
espera falla "... y no queda el nieto" "" -- vivo "$(cat "$P/nieto")"
repo p2; P="$W/pids/p2"; mkdir -p "$P"
( cd "$R" && exec python3 "$SU" correr --plazo 60 -- sh -c "$COLGADA" > /dev/null 2>&1 ) & LAN=$!
hasta 10 existe "$P/nieto"; hasta 5 abierta_con_grupo; ID=$(ultimo)
kill -9 "$(campo "$ID" guardia)" $LAN; kill -9 "$(cat "$P/lider")"; wait $LAN 2>/dev/null; sleep 0.3
cp "$P/nieto" "$W/pids/p2-nieto"   # la limpieza final lo termina si el caso falla
espera pasa "líder terminado y descendiente vivo sin guardián: pertenencia incierta" "incierta.*|NO demostrable" -- sh -c 'cd "$1" && python3 "$2" estado "$3"' _ "$R" "$SU" "$ID"
espera falla "... terminar se niega a enviar señales" "no termino nada" -- sh -c 'cd "$1" && python3 "$2" terminar "$3"' _ "$R" "$SU" "$ID"
espera pasa "... y el descendiente sigue vivo (no se tocó)" "" -- vivo "$(cat "$P/nieto")"
espera falla "... una nueva ejecución sigue bloqueada (no se limpia nada)" "NO demostrable" -- corre --plazo 20 -- true
espera pasa "... la carpeta temporal sigue ahí" "" -- test -d "$(campo "$ID" carpeta)/tmp"
kill -9 "$(cat "$P/nieto")"; sleep 0.3
espera pasa "... terminado a mano el descendiente, la siguiente ejecución recupera y corre" "recupero la ejecución $ID" -- corre --plazo 20 -- true

echo "== terminación incompleta: procesos que sobreviven a KILL"
repo x1; P="$W/pids/x1"; mkdir -p "$P"
espera falla "líder sale con 0 dejando un miembro que sobrevive a KILL: INCOMPLETA, nunca aprobada" "INCOMPLETA.*No cuenta como aprobada" -- corre --plazo 30 --informe "$W/inf-x1" -- sh -c 'echo $$ > "$0"; exit 0' "$W/fantasma"
ID=$(ultimo); CARP=$(campo "$ID" carpeta)
espera pasa "... sale con 75 y el informe dice incompleta" "estado=incompleta rc=0" -- cat "$W/inf-x1"
espera pasa "... el registro sigue abierto" "^abierta$" -- campo "$ID" estado
espera pasa "... sus temporales se conservan" "" -- test -d "$CARP/tmp"
espera pasa "... estado la explica" "terminación INCOMPLETA.*fantasma" -- sh -c 'cd "$1" && python3 "$2" estado "$3"' _ "$R" "$SU" "$ID"
espera falla "... y bloquea una nueva ejecución" "$ID" -- corre --plazo 20 -- true
rm -f "$W/fantasma"
espera pasa "... ido el superviviente, la siguiente la recupera y corre" "recupero la ejecución $ID" -- corre --plazo 20 -- true
espera falla "... y entonces sí borra sus temporales" "" -- test -e "$CARP/tmp"
repo x2; P="$W/pids/x2"; mkdir -p "$P"
( cd "$R" && exec python3 "$SU" correr --plazo 60 -- sh -c "$COLGADA" > /dev/null 2>&1 ) & LAN=$!
hasta 10 existe "$P/lider"; hasta 5 abierta_con_grupo; ID=$(ultimo); CARP=$(campo "$ID" carpeta)
kill -9 "$(campo "$ID" guardia)" $LAN; wait $LAN 2>/dev/null; cat "$P/lider" > "$W/fantasma"
espera falla "terminar una huérfana con un superviviente a KILL: no la da por cerrada (75)" "incompleta" -- sh -c 'cd "$1" && python3 "$2" terminar "$3"' _ "$R" "$SU" "$ID"
espera pasa "... queda abierta e incompleta, con sus temporales" "" -- sh -c '[ "$(cd "$1" && python3 -c "import json,sys;r=json.load(open(sys.argv[1]));print(r[\"estado\"], r.get(\"incompleta\"))" "$2")" = "abierta terminada" ] && test -d "$3/tmp"' _ "$R" "$REG/$ID.json" "$CARP"
rm -f "$W/fantasma"; sleep 0.3
espera pasa "... ido el superviviente, la siguiente la recupera" "recupero la ejecución $ID" -- corre --plazo 20 -- true

echo "== consulta de procesos imposible: no comprobar no es no existir"
repo q1; P="$W/pids/q1"; mkdir -p "$P"
( cd "$R" && exec python3 "$SU" correr --plazo 60 -- sh -c "$COLGADA" > /dev/null 2>&1 ) & LAN=$!
hasta 10 existe "$P/lider"; hasta 5 abierta_con_grupo; ID=$(ultimo); CARP=$(campo "$ID" carpeta)
kill -9 "$(campo "$ID" guardia)" $LAN; kill -9 -"$(campo "$ID" grupo)"; wait $LAN 2>/dev/null; sleep 0.3
: > "$W/ps-falla"
espera pasa "abandonada con ps fallando: estado dice no comprobable, no abandonada" "ps falló\): su ausencia no está demostrada" -- sh -c 'cd "$1" && python3 "$2" estado "$3"' _ "$R" "$SU" "$ID"
espera falla "... una nueva ejecución no la recupera: se bloquea (75)" "no comprobable" -- corre --plazo 20 -- true
rm -f "$W/ps-falla"; : > "$W/ps-cuelga"; T0=$(date +%s)
espera pasa "ps que no responde: vence su límite y estado dice no comprobable (no espera para siempre)" "ausencia no está demostrada" -- sh -c 'cd "$1" && python3 "$2" estado "$3"' _ "$R" "$SU" "$ID"
espera pasa "... en menos de 30 s" "" -- test $(( $(date +%s) - T0 )) -lt 30
rm -f "$W/ps-cuelga"; : > "$W/ps-falla"
espera falla "... terminar se niega" "no termino nada" -- sh -c 'cd "$1" && python3 "$2" terminar "$3"' _ "$R" "$SU" "$ID"
espera pasa "... el registro sigue abierto y los temporales intactos" "" -- sh -c '[ "$(cd / && python3 -c "import json,sys;print(json.load(open(sys.argv[1]))[\"estado\"])" "$1")" = abierta ] && test -d "$2/tmp"' _ "$REG/$ID.json" "$CARP"
repo q2
espera falla "sin ejecuciones abiertas y ps fallando: no lanza (75) en vez de lanzar a ciegas" "no pude comprobarlo" -- corre --plazo 20 -- true
espera pasa "... y no deja registro ni carpeta" "^0$" -- sh -c 'ls "$1"/*.json 2>/dev/null | wc -l | tr -d " "' _ "$REG"
rm -f "$W/ps-falla"
R="$W/q1"; REG="$R/.git/suite-runs"
espera pasa "... con ps de vuelta, la abandonada se recupera" "recupero la ejecución $ID" -- corre --plazo 20 -- true

echo "== registro ilegible o dañado: no poder leerlo no es estar vacío"
repo ri; P="$W/pids/ri"; mkdir -p "$P"
( cd "$R" && exec python3 "$SU" correr --plazo 60 -- sh -c "$COLGADA" > /dev/null 2>&1 ) & LAN=$!
hasta 10 existe "$P/lider"; hasta 5 abierta_con_grupo; ID=$(ultimo)
chmod 300 "$REG"
if ls "$REG" > /dev/null 2>&1; then
  echo "  (no aplica: este entorno lista $REG sin permiso de lectura; registro inaccesible sin probar)"
else
  espera falla "registro que no se puede listar, con una ejecución abierta: no lanza otra (75)" "ilegible" -- corre --informe "$W/ri.inf" --plazo 20 -- true
  espera pasa "... y lo informa como no comprobable" "estado=no-comprobable" -- sh -c 'cat "$1" 2>/dev/null' _ "$W/ri.inf"
fi
chmod 700 "$REG"
echo '{roto' > "$REG/zz.json"
espera falla "registro dañado: no lanza (75) ni lo trata como vacío" "dañado" -- corre --plazo 20 -- true
echo '{"id": "x"}' > "$REG/zz.json"
espera falla "registro sin sus campos: también es dañado (75)" "dañado" -- corre --plazo 20 -- true
echo '{"id": "x", "estado": "aprobada", "inicio": 1}' > "$REG/zz.json"
espera falla "registro sin «dir»: también es dañado (75)" "dañado" -- corre --informe "$W/ri-dir.inf" --plazo 20 -- true
espera pasa "... e informa no comprobable" "estado=no-comprobable" -- sh -c 'cat "$1" 2>/dev/null' _ "$W/ri-dir.inf"
echo '{"id": "x", "estado": "rara", "inicio": 1, "dir": "/x"}' > "$REG/zz.json"
espera falla "registro con un estado desconocido: también es dañado (75)" "dañado" -- corre --plazo 20 -- true
rm -f "$REG/zz.json"
espera pasa "... legible otra vez, la abierta se termina" "" -- sh -c 'cd "$1" && python3 "$2" terminar "$3"' _ "$R" "$SU" "$ID"
wait $LAN 2>/dev/null
# poda con un registro dañado: 12 cerradas con carpeta propia (testigos) superan las 10 que se
# conservan; con un registro roto al lado, prune no borra ninguna carpeta ni registro.
repo rp; mkdir -p "$REG"
python3 - "$REG" "$W/rp-carpetas" <<'EOF'
import json, sys
from pathlib import Path
reg, base = Path(sys.argv[1]), Path(sys.argv[2])
for i in range(12):
    rid = f"2026010{i // 10}T0000{i % 10}0Z-00{i:02d}"
    c = base / f"suite-{rid}-t"; (c / "tmp").mkdir(parents=True)
    (reg / f"{rid}.json").write_text(json.dumps({"id": rid, "estado": "aprobada", "inicio": i, "fin": i, "carpeta": str(c), "dir": "/x", "comando": ["true"], "plazo": 1}))
(reg / "zz.json").write_text("{roto")
EOF
espera pasa "poda con un registro dañado: no borra carpetas testigo ni registros (12 y 12)" "^12 12$" -- python3 -c '
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("suite", sys.argv[1]); s = importlib.util.module_from_spec(spec); spec.loader.exec_module(s)
s.prune(Path(sys.argv[2]))
print(len(list(Path(sys.argv[3]).iterdir())), len([p for p in Path(sys.argv[2]).iterdir() if p.name.startswith("2026")]))' "$SU" "$REG" "$W/rp-carpetas"
rm -f "$REG/zz.json"
espera pasa "... (control) con el registro sano, la poda sí deja solo 10 carpetas" "^10$" -- python3 -c '
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("suite", sys.argv[1]); s = importlib.util.module_from_spec(spec); spec.loader.exec_module(s)
s.prune(Path(sys.argv[2])); print(len(list(Path(sys.argv[3]).iterdir())))' "$SU" "$REG" "$W/rp-carpetas"

echo "== cerrojo del registro (flock: el núcleo lo suelta al morir su dueño)"
repo c1; mkdir -p "$REG"
cerrojo "$REG" "$W/c1-marca" 300 & HOLD=$!; echo $HOLD > "$W/pids/c1"
hasta 10 existe "$W/c1-marca"; kill -9 $HOLD; wait $HOLD 2>/dev/null
espera pasa "un cerrojo cuyo dueño murió (kill -9) no bloquea: la ejecución corre" "aprobada" -- corre --plazo 20 -- true
espera pasa "... y no queda tomado" "" -- libre "$REG"
cerrojo "$REG" "$W/c2-marca" 300 & HOLD=$!; echo $HOLD > "$W/pids/c2"
hasta 10 existe "$W/c2-marca"; kill -9 $HOLD; wait $HOLD 2>/dev/null
( cd "$R" && python3 "$SU" correr --plazo 20 -- sleep 2 > "$W/c2-a.out" 2>&1; echo $? > "$W/c2-a.rc" ) &
( cd "$R" && python3 "$SU" correr --plazo 20 -- sleep 2 > "$W/c2-b.out" 2>&1; echo $? > "$W/c2-b.rc" ) &
wait
espera pasa "dos recuperadores simultáneos sobre un cerrojo obsoleto: exactamente uno corre (0) y el otro 75" "^0 75$|^75 0$" -- sh -c 'echo "$(cat "$1") $(cat "$2")"' _ "$W/c2-a.rc" "$W/c2-b.rc"
cerrojo "$REG" "$W/c3-marca" 1.5 & HOLD=$!; echo $HOLD > "$W/pids/c3"
hasta 10 existe "$W/c3-marca"
T0=$(date +%s)
espera pasa "un cerrojo de un proceso vivo se respeta: espera a que lo suelte y luego corre" "aprobada" -- corre --plazo 20 -- true
espera pasa "... (esperó al menos un segundo)" "" -- test $(( $(date +%s) - T0 )) -ge 1
wait $HOLD 2>/dev/null

echo "== arranque protegido de check.sh (recorrido directo; el bloque, tal cual de docs/convenciones.md)"
BLOQUE=$(awk '/^# --- suite vigilada/{f=1} f{print} /^# --- fin suite vigilada/{exit}' "$RAIZ/docs/convenciones.md")
# proyecto <nombre> <plazo o vacío> <cuerpo>: repositorio con suite.py, convenciones con el plazo y check.sh = bloque + cuerpo
proyecto() {
  repo "$1"; mkdir -p "$R/scripts" "$R/docs"; cp "$SU" "$R/scripts/suite.py"
  if [ -n "$2" ]; then printf '# Convenciones\n\n## Comandos clave\n\n- **Plazo de la suite:** %s s\n' "$2"; else printf '# Convenciones\n'; fi > "$R/docs/convenciones.md"
  printf '#!/bin/sh\n%s\n%s\n' "$BLOQUE" "$3" > "$R/scripts/check.sh"
}
espera pasa "el bloque canónico se extrae de docs/convenciones.md" "fin suite vigilada" -- printf '%s' "$BLOQUE"
mkdir -p "$W/otra"; proyecto b1 20 'echo "cuerpo id=$SUITE_ID args=$* cwd=$(pwd -P)"'
espera pasa "invocado a mano, check.sh corre bajo suite.py: tiene ID y recibe sus argumentos" "cuerpo id=2[0-9]{7}T.* args=a b" -- sh -c 'cd "$1" && sh scripts/check.sh a b' _ "$R"
espera pasa "... y queda registrada como aprobada" "^aprobada$" -- campo "$(ultimo)" estado
espera pasa "desde otra carpeta: corre en la raíz del proyecto y registra allí" "cwd=$R" -- sh -c 'cd "$1" && sh "$2/scripts/check.sh"' _ "$W/otra" "$R"
espera pasa "el plazo sale de docs/convenciones.md (fuente única)" "plazo 20s" -- sh -c 'cd "$1" && sh scripts/check.sh' _ "$R"
espera pasa "SUITE_PLAZO lo sobrescribe de forma explícita" "plazo 7s" -- env SUITE_PLAZO=7 sh -c 'cd "$1" && sh scripts/check.sh' _ "$R"
espera pasa "SUITE_ENVUELTO=1 heredado sin ejecución abierta no salta el envoltorio" "cuerpo id=2" -- env SUITE_ENVUELTO=1 sh -c 'cd "$1" && sh scripts/check.sh' _ "$R"
proyecto b2 "" 'echo cuerpo'
espera falla "sin plazo en ninguna fuente no corre" "falta el plazo.*Plazo de la suite" -- sh -c 'cd "$1" && sh scripts/check.sh' _ "$R"
proyecto b3 20 'sh scripts/check.sh; echo "interno=$?"'
espera pasa "un check.sh lanzado desde dentro de otro se rechaza (75)" "interno=75" -- sh -c 'cd "$1" && sh scripts/check.sh' _ "$R"
P="$W/pids/b4"; mkdir -p "$P"
proyecto b4 2 "sleep 300 & echo \$! > '$P/nieto'; echo \$\$ > '$P/lider'; trap '' TERM; echo arranco; while :; do sleep 1; done"
T0=$(date +%s)
espera falla "suite colgada invocada a mano: sale con 124 al vencer el plazo de convenciones" "EXCEDIDA" -- acotado 30 sh -c 'cd "$0" && exec sh scripts/check.sh' "$R"
espera pasa "... en menos de 15 s" "" -- test $(( $(date +%s) - T0 )) -lt 15
espera falla "... sin el líder vivo" "" -- vivo "$(cat "$P/lider" 2>/dev/null)"
espera falla "... ni el nieto" "" -- vivo "$(cat "$P/nieto" 2>/dev/null)"
proyecto b5 20 "[ -e '$W/b5-hecho' ] || { : > '$W/b5-hecho'; echo \$\$ > '$W/fantasma'; }; exit 0"  # solo la primera vez
espera falla "superviviente a KILL (simulado) en el recorrido directo: INCOMPLETA (75)" "INCOMPLETA" -- sh -c 'cd "$1" && sh scripts/check.sh' _ "$R"
proyecto_b5_id=$(ultimo)
espera falla "... y la siguiente invocación queda bloqueada" "$proyecto_b5_id" -- sh -c 'cd "$1" && sh scripts/check.sh' _ "$R"
rm -f "$W/fantasma"
espera pasa "... ido el superviviente, se recupera y corre" "recupero la ejecución $proyecto_b5_id" -- sh -c 'cd "$1" && sh scripts/check.sh' _ "$R"
mkdir -p "$W/copia-b"; cp -R "$W/b1/scripts" "$W/b1/docs" "$W/copia-b/"
espera falla "una copia sin .git y sin SUITE_REGISTRO se detiene explicando por qué" "no está en un repositorio git" -- sh -c 'cd "$1" && sh scripts/check.sh' _ "$W/copia-b"
espera pasa "... con SUITE_REGISTRO corre y registra allí" "cuerpo" -- env SUITE_REGISTRO="$W/registro-copia-b" sh -c 'cd "$1" && sh scripts/check.sh && ls "$2"/*.json >/dev/null 2>&1' _ "$W/copia-b" "$W/registro-copia-b"

echo "== registro y rutas"
repo r1
mkdir -p "$W/otra"
espera pasa "desde otra carpeta con --dir: registra en el repositorio de --dir" "aprobada" -- sh -c 'cd "$1" && python3 "$2" correr --plazo 20 --dir "$3" -- true' _ "$W/otra" "$SU" "$R"
espera pasa "... el registro quedó en ese repositorio" "" -- test -n "$(ls "$REG"/*.json)"
git -C "$R" commit -q --allow-empty -m base; git -C "$R" worktree add -q "$W/r1-wt" 2>/dev/null
P="$W/pids/r1"; mkdir -p "$P"
( cd "$R" && python3 "$SU" correr --plazo 60 -- sh -c 'echo $$ > "$P/lider"; sleep 300' > /dev/null 2>&1 ) &
hasta 10 existe "$P/lider"; ID=$(ultimo)
espera falla "un worktree comparte el registro: con una abierta en el principal, se bloquea" "$ID" -- sh -c 'cd "$1" && python3 "$2" correr --plazo 20 -- true' _ "$W/r1-wt" "$SU"
( cd "$R" && python3 "$SU" terminar "$ID" ) > /dev/null 2>&1; wait
mkdir -p "$W/copia"
espera falla "una copia sin .git y sin SUITE_REGISTRO se detiene explicando por qué" "no está en un repositorio git y no hay SUITE_REGISTRO" -- sh -c 'cd "$1" && python3 "$2" correr --plazo 20 -- true' _ "$W/copia" "$SU"
espera pasa "... con SUITE_REGISTRO del repositorio real, registra allí" "aprobada" -- env SUITE_REGISTRO="$W/registro-copia" sh -c 'cd "$1" && python3 "$2" correr --plazo 20 -- true' _ "$W/copia" "$SU"
espera pasa "... y el registro está en esa ruta" "" -- test -n "$(ls "$W/registro-copia"/*.json)"
espera falla "SUITE_REGISTRO relativo se rechaza" "ruta absoluta" -- env SUITE_REGISTRO=relativo sh -c 'cd "$1" && python3 "$2" correr --plazo 20 -- true' _ "$W/copia" "$SU"

echo "== log acotado y poda"
repo l1
SUITE_LOG_MAX=20000 corre --plazo 30 -- python3 -c 'import sys; [print("linea %06d " % i + "x"*90) for i in range(3000)]' > /dev/null 2>&1
ID=$(ultimo); CARP=$(campo "$ID" carpeta)
espera pasa "con 300 KB de salida, el log no pasa del tope (20 KB en dos mitades)" "" -- sh -c 'n=$(cat "$1"/salida.log* | wc -c); [ "$n" -le 20000 ]' _ "$CARP"
espera pasa "... y conserva el final de la salida" "linea 002999" -- cat "$CARP/salida.log"
repo l2
i=0; while [ $i -lt 12 ]; do corre --plazo 20 -- true > /dev/null 2>&1; i=$((i+1)); done
espera pasa "tras 12 ejecuciones solo quedan los 10 registros cerrados más recientes" "^10$" -- sh -c 'ls "$1"/*.json | wc -l | tr -d " "' _ "$REG"

echo
if [ "$MAL" -eq 0 ]; then echo "regresion-suite: $TOTAL casos, todos pasan."; exit 0; fi
echo "regresion-suite: $MAL de $TOTAL casos FALLARON:$FALLIDOS"; exit 1
