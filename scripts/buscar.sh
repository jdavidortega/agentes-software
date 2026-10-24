#!/bin/sh
# Captura de evidencia de búsquedas (viene con la plantilla; docs/arranque-existente.md §Marcas).
# LEE el código con `git grep` contra un commit resuelto y ESCRIBE evidencia: una entrada
# append-only en el registro que se le indica. Nunca ejecuta texto tomado de un documento.
#
#   sh scripts/buscar.sh registrar --registro <archivo> [--commit <ref>] [-i] [-F]
#        (-e <patrón> | --nombre <búsqueda>) [--control <ruta>] -- <ruta>...
#   sh scripts/buscar.sh repetir --registro <archivo> B-<n>      (no escribe: compara y dice)
#
# --registro   ubicación AUTORIZADA del registro (obligatoria, sin valor por defecto): el
#              ejecutor usa contexto/exploracion/busquedas.md; un revisor solo escribe en su
#              directorio autorizado. Se rechaza un enlace simbólico.
# --commit     por defecto HEAD; se registra el sha resuelto. La búsqueda lee el COMMIT, no el
#              árbol de trabajo (el estado del árbol se registra igual).
# -e           patrón libre (ERE; -F lo trata como literal; -i ignora mayúsculas). Sin saltos de
#              línea ni comillas invertidas, sin cabeceras de llave ni tokens largos: un patrón
#              no debe contener valores secretos.
# --nombre     búsqueda con nombre cuyo patrón vive aquí: llaves-privadas, credenciales.
# --control    ruta donde el MISMO patrón debería encontrar algo (control positivo).
# <ruta>...    alcance exacto (pathspecs de git); una ruta sin archivos de texto es ERROR, no
#              «sin coincidencias».
#
# Qué cuenta como coincidencia: una LÍNEA coincidente, identificada por archivo y línea únicos.
# El registro guarda archivo:línea, nunca el contenido (el contenido sale solo por pantalla).
# Excluidos siempre, de la búsqueda y del registro: .env y variantes, *.pem, *.key, *.p12, *.pfx,
# id_rsa*, id_ed25519*, y los binarios.
# Resultado: «coincidencias», «sin coincidencias en el alcance» (vale solo para ese commit y esas
# rutas) o «error» (también se registra). Una referencia B-<n> acredita que la búsqueda se
# ejecutó y qué devolvió; NO acredita la interpretación de su resultado.
# Salida: 0 registrada (con o sin coincidencias); 1 repetir no reproduce; 2 uso o error.
set -eu

uso() { sed -n '6,8p' "$0" >&2; exit 2; }
fallo() { echo "buscar: $1" >&2; exit 2; }

EXCLUIR=':(exclude,glob)**/.env :(exclude,glob)**/.env.* :(exclude,glob)**/*.pem :(exclude,glob)**/*.key :(exclude,glob)**/*.p12 :(exclude,glob)**/*.pfx :(exclude,glob)**/id_rsa* :(exclude,glob)**/id_ed25519*'
EXCLUIDOS_TXT='.env y variantes, *.pem, *.key, *.p12, *.pfx, id_rsa*, id_ed25519*; binarios'
MAX_LISTA=200

# Búsquedas con nombre: el patrón vive aquí (partido para no detectarse a sí mismo, como en
# scripts/guardas.sh) y en el registro solo queda el nombre.
patron_nombre() {
  case "$1" in
    llaves-privadas) printf '%s' 'BEGIN [A-Z ]*PRIVATE K''EY' ;;
    credenciales) printf '%s' 'AKIA[0-9A-Z]{16}|client_secret[[:space:]]*[=:]|glpat-' ;;
    *) return 1 ;;
  esac
}
descripcion_nombre() {
  case "$1" in
    llaves-privadas) echo "cabecera PEM de llave privada" ;;
    credenciales) echo "identificador de llave AWS, asignación de client_secret o prefijo de token de GitLab" ;;
  esac
}

patron_aceptable() {  # $1 patrón libre
  case "$1" in *'`'*) fallo "el patrón no puede contener comillas invertidas" ;; esac
  [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" = 0 ] || fallo "el patrón no puede contener saltos de línea"
  if printf '%s' "$1" | grep -Eq 'PRIVATE[[:space:]]*K''EY'; then
    fallo "el patrón nombra una cabecera de llave privada: usa --nombre llaves-privadas"
  fi
  if printf '%s' "$1" | grep -Eq '[A-Za-z0-9+/=_-]{32,}'; then
    fallo "el patrón contiene un token de 32 o más caracteres: un patrón no debe llevar valores secretos"
  fi
}

registro_aceptable() {  # $1 ruta del registro (escritura)
  [ ! -L "$1" ] || fallo "el registro es un enlace simbólico: escribiría fuera de la ubicación autorizada"
  [ ! -e "$1" ] || [ -f "$1" ] || fallo "el registro existe y no es un archivo regular"
  [ -d "$(dirname "$1")" ] || fallo "no existe el directorio del registro: $(dirname "$1")"
}

absoluta() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$(pwd)" "$1" ;; esac; }

# grep_git <sha> <modo> <icase> <patrón> -- rutas...  → imprime "ruta:línea:contenido"; rc de git grep
grep_git() {
  _sha=$1 _modo=$2 _ic=$3 _pat=$4; shift 5
  # shellcheck disable=SC2086  # EXCLUIR se parte a propósito: no lleva espacios internos
  git grep -n -I --no-color "$_modo" $_ic -e "$_pat" "$_sha" -- "$@" $EXCLUIR
}

archivos_en() {  # <sha> <ruta> → nº de archivos de texto (no vacíos) del alcance
  # shellcheck disable=SC2086
  git grep -l -I -e '' "$1" -- "$2" $EXCLUIR 2>/dev/null | wc -l | tr -d ' '
}

# ---- argumentos ----
[ $# -ge 1 ] || uso
ACCION=$1; shift
REGISTRO='' REF=HEAD IC='' MODO=-E PATRON='' NOMBRE='' CONTROL='' ID=''
while [ $# -gt 0 ]; do
  case "$1" in
    --registro) [ $# -ge 2 ] || uso; REGISTRO=$(absoluta "$2"); shift 2 ;;
    --commit) [ $# -ge 2 ] || uso; REF=$2; shift 2 ;;
    -i) IC=-i; shift ;;
    -F) MODO=-F; shift ;;
    -e) [ $# -ge 2 ] || uso; PATRON=$2; shift 2 ;;
    --nombre) [ $# -ge 2 ] || uso; NOMBRE=$2; shift 2 ;;
    --control) [ $# -ge 2 ] || uso; CONTROL=$2; shift 2 ;;
    --) shift; break ;;
    B-*) ID=$1; shift ;;
    *) uso ;;
  esac
done
[ -n "$REGISTRO" ] || fallo "falta --registro <archivo> (ubicación autorizada; no hay valor por defecto)"
RAIZ=$(git rev-parse --show-toplevel 2>/dev/null) || fallo "no estás dentro de un repositorio git"
cd "$RAIZ"

# ---- repetir: lee una entrada y la vuelve a ejecutar; no escribe nada ----
if [ "$ACCION" = repetir ]; then
  [ -n "$ID" ] || uso
  [ -f "$REGISTRO" ] || fallo "no existe el registro $REGISTRO"
  entrada=$(awk -v id="## $ID" '$0==id{e=1;next} e&&/^## /{exit} e' "$REGISTRO")
  [ -n "$entrada" ] || fallo "$ID no está en $REGISTRO"
  campo() { printf '%s\n' "$entrada" | sed -n "s/^- $1: //p" | head -1; }
  [ "$(campo resultado)" != error ] || fallo "$ID registró un error ($(campo error)): no hay resultado que reproducir"
  sin_tildes() { sed 's/^`//; s/`$//'; }
  sha=$(campo commit); modo=$(campo modo); nombre=$(campo nombre | sed 's/ (.*//')
  case "$modo" in *literal*) MODO=-F ;; *) MODO=-E ;; esac
  case "$modo" in *"sin distinguir"*) IC=-i ;; *) IC='' ;; esac
  if [ -n "$nombre" ]; then PATRON=$(patron_nombre "$nombre") || fallo "búsqueda con nombre desconocida: $nombre"
  else PATRON=$(campo patrón | sin_tildes); fi
  rutas=$(printf '%s\n' "$entrada" | sed -n 's/^- ruta: `\(.*\)` (.*/\1/p')
  esperado=$(printf '%s\n' "$entrada" | sed -n 's/^- coincidencias: //p' | tr ',' '\n' | sed 's/^ *//; / más;/d; /^$/d; /^ninguna$/d')
  esperado_n=$(campo "líneas coincidentes" | sed 's/ .*//')
  esperado_rc=$(campo "código de salida")
  set --
  while IFS= read -r r; do [ -z "$r" ] || set -- "$@" "$r"; done <<EOF
$rutas
EOF
  rc=0; crudo=$(grep_git "$sha" "$MODO" "$IC" "$PATRON" -- "$@" 2>/dev/null) || rc=$?
  obtenido=$(printf '%s\n' "$crudo" | sed "s/^$sha://" | awk -F: 'NF>1{print $1":"$2}' | sort -t: -k1,1 -k2,2n -u)
  obtenido_n=$(printf '%s' "$obtenido" | grep -c . || true)
  primeros=$(printf '%s\n' "$obtenido" | head -n "$MAX_LISTA")
  if [ "$rc" = "${esperado_rc:-0}" ] && [ "$obtenido_n" = "${esperado_n:-0}" ] && [ "$(printf '%s\n' "$primeros" | sed '/^$/d')" = "$(printf '%s\n' "$esperado" | sed '/^$/d')" ]; then
    echo "$ID reproduce: líneas coincidentes $obtenido_n, código de salida $rc, commit $sha"
    exit 0
  fi
  echo "$ID NO reproduce: registradas ${esperado_n:-0} líneas (código ${esperado_rc:-?}), obtenidas $obtenido_n (código $rc)"
  exit 1
fi

[ "$ACCION" = registrar ] || uso
[ $# -ge 1 ] || fallo "falta el alcance: una o más rutas después de --"
registro_aceptable "$REGISTRO"
if [ -n "$NOMBRE" ]; then
  [ -z "$PATRON" ] || fallo "usa -e o --nombre, no los dos"
  PATRON=$(patron_nombre "$NOMBRE") || fallo "búsqueda con nombre desconocida: $NOMBRE (llaves-privadas, credenciales)"
  MODO=-E
else
  [ -n "$PATRON" ] || fallo "falta el patrón: -e <patrón> o --nombre <búsqueda>"
  patron_aceptable "$PATRON"
fi

# ---- ejecución ----
fecha=$(date -u +%Y-%m-%dT%H:%MZ)
SHA=$(git rev-parse --verify --quiet "$REF^{commit}") || SHA=''
cambios=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')
if [ "$cambios" = 0 ]; then arbol="limpio"; else arbol="con cambios en $cambios rutas rastreadas (la búsqueda lee el commit, no el árbol)"; fi
case "$MODO" in -F) m="literal" ;; *) m="ERE" ;; esac
if [ -n "$IC" ]; then m="$m, sin distinguir mayúsculas"; else m="$m, distingue mayúsculas"; fi

resultado='' rc=0 err='' lista='' n=0 nf=0 rutas_txt='' ctrl_txt=''
if [ -z "$SHA" ]; then
  resultado="error"; rc="no ejecutada"; err="no se resuelve el commit «${REF}»"
else
  for r in "$@"; do
    k=$(archivos_en "$SHA" "$r")
    rutas_txt="$rutas_txt
- ruta: \`$r\` ($k archivos de texto)"
    [ "$k" != 0 ] || { resultado="error"; rc="no ejecutada"; err="la ruta «${r}» no tiene archivos de texto en el commit (¿falta el directorio?)"; }
  done
  if [ -z "$resultado" ]; then
    salida_err=$(mktemp "${TMPDIR:-/tmp}/buscar.XXXXXX")
    crudo=$(grep_git "$SHA" "$MODO" "$IC" "$PATRON" -- "$@" 2>"$salida_err") || rc=$?
    err=$(head -1 "$salida_err"); rm -f "$salida_err"
    case $rc in
      0) resultado="coincidencias" ;;
      1) resultado="sin coincidencias en el alcance" ;;
      *) resultado="error" ;;
    esac
    if [ "$rc" = 0 ]; then
      printf '%s\n' "$crudo" | sed "s/^$SHA://" | cut -c1-240   # contenido solo por pantalla
      lista=$(printf '%s\n' "$crudo" | sed "s/^$SHA://" | awk -F: '{print $1":"$2}' | sort -t: -k1,1 -k2,2n -u)
      n=$(printf '%s\n' "$lista" | grep -c .)
      nf=$(printf '%s\n' "$lista" | cut -d: -f1 | sort -u | grep -c .)
    fi
  fi
  if [ -n "$CONTROL" ] && [ "$resultado" != error ]; then
    crc=0; cn=$(grep_git "$SHA" "$MODO" "$IC" "$PATRON" -- "$CONTROL" 2>/dev/null | grep -c .) || crc=$?
    [ "$cn" != 0 ] || crc=1
    ctrl_txt="
- control: \`$CONTROL\` → líneas coincidentes: $cn"
    [ "$cn" != 0 ] || ctrl_txt="$ctrl_txt (el control NO encontró nada: el patrón o la ruta no sirven como control)"
  fi
fi

# ---- registro (append-only) ----
if [ ! -f "$REGISTRO" ]; then
  cat > "$REGISTRO" <<'EOF'
# Registro de búsquedas (`scripts/buscar.sh`)

Append-only: no se edita ni se reordena. Cada entrada acredita que una búsqueda **se ejecutó**,
con su commit, su alcance y lo que devolvió; **no acredita la interpretación** de ese resultado,
que sigue siendo del agente y del revisor. «Sin coincidencias» vale solo para ese commit y esas
rutas. Se guardan archivo y línea, nunca el contenido. Repetir una entrada:
`sh scripts/buscar.sh repetir --registro <este archivo> B-<n>`.
EOF
fi
ult=$(sed -n 's/^## B-\([0-9][0-9]*\)$/\1/p' "$REGISTRO" | sort -n | tail -1)
ID="B-$(( ${ult:-0} + 1 ))"
if [ -n "$lista" ]; then
  coinc=$(printf '%s\n' "$lista" | head -n "$MAX_LISTA" | paste -sd, - | sed 's/,/, /g')
  [ "$n" -le "$MAX_LISTA" ] || coinc="$coinc, … $((n - MAX_LISTA)) más; repetir las muestra"
else
  coinc="ninguna"
fi
if [ -n "$NOMBRE" ]; then linea_patron="- nombre: $NOMBRE ($(descripcion_nombre "$NOMBRE"); patrón interno de scripts/buscar.sh)"
else linea_patron="- patrón: \`$PATRON\`"; fi
{
  echo
  echo "## $ID"
  echo "- fecha: $fecha"
  echo "- commit: ${SHA:-$REF (no resuelto)}"
  echo "- árbol de trabajo: $arbol"
  echo "- modo: $m"
  echo "$linea_patron"
  [ -z "$rutas_txt" ] || printf '%s\n' "$rutas_txt" | sed '/^$/d'
  echo "- excluidos siempre: $EXCLUIDOS_TXT"
  echo "- resultado: $resultado"
  echo "- código de salida: $rc"
  [ -z "$err" ] || echo "- error: $err"
  echo "- líneas coincidentes: $n (archivos: $nf)"
  echo "- coincidencias: $coinc"
  [ -z "$ctrl_txt" ] || printf '%s\n' "$ctrl_txt" | sed '/^$/d'
} >> "$REGISTRO"

echo "$ID registrada en $REGISTRO: $resultado (líneas: $n; archivos: $nf; commit ${SHA:-?})"
[ "$resultado" != error ] || { echo "buscar: $err" >&2; exit 2; }
exit 0
