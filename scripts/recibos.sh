#!/bin/sh
# Parser ÚNICO de docs/revisiones.log (viene con la plantilla; AGENTS.md §9). Lo usan el
# commit-msg y check_docs: un recibo significa lo mismo para los dos.
#
#   sh scripts/recibos.sh validar [archivo]                → 0 si TODAS las líneas son válidas;
#                                                            1 y los motivos en stderr si no
#   sh scripts/recibos.sh ultimo <rol> <tipo> <alcance> [archivo]
#                                                          → imprime la ÚLTIMA línea válida que
#                                                            coincide (alcance exacto, o prefijo
#                                                            "reentrada:" para alcance=F2); vacío si no hay
#
# El hito NO se cuenta aquí: un hito es un commit `Ref: hito:I<a>-I<b>` (su recibo se exige al
# commitearlo) y el commit-msg cuenta los commits `Ref: I<n>` posteriores. Un solo significado.
#
# Gramática de una línea (campos clave=valor separados por espacio, sin repetir claves;
# las líneas que empiezan por # y las vacías se ignoran en todos los modos):
#   fecha=<ISO: AAAA-MM-DD, opcional Thh:mm[:ss][Z]>
#   rol=revisor-funcional|juez-codigo|juez-conjunto|juez-seguridad
#   tipo=encuadre|incremento|hito|conjunto   alcance=F2|F4|I<n>|hito:I<a>-I<b>|reentrada:C<n>
#   veredicto=PASA|FALLA  bloqueantes=<entero sin ceros a la izquierda>  huella=<12 hex>  ejecutor=<quién>
#   seguridad=requerida|no-aplica   (obligatorio en juez-codigo y juez-conjunto)
#   cubre=<C..>  excluye=<C..|ninguno>  componentes=<..>   (obligatorios en tipo=hito)
#   modalidad=lectura|experimentos  filtro=comprobado|desactivado|sin-verificar
#   aislamiento=ninguno|sandbox-configurado|sandbox-verificado   (los tres juntos; ver abajo)
#   evidencia=docs/revisiones/<id>@<12 hex>   (opcional: carpeta con lo que sostiene el veredicto
#                                              y su huella, `sh scripts/huella.sh evidencia <carpeta>`)
# Relaciones: PASA ⇒ bloqueantes=0; FALLA ⇒ bloqueantes≥1; rol↔tipo↔alcance coherentes.
#
# HITO (rol=juez-conjunto tipo=hito alcance=hito:I<a>-I<b>; fuente canónica de esta gramática):
#   cubre=C<n>[,C<n>…]               los criterios CONSTRUIDOS: todo incremento de su fila de Cobertura
#                                     (docs/trazabilidad.md) ya tiene su commit `Ref: I`. Nunca vacío ni
#                                     «ninguno».
#   excluye=ninguno | C<n>[,C<n>…]   solo criterios de incrementos futuros («ninguno» si no hay).
#   componentes=<..>                 lo ensamblado que se revisó.
#   Ambas listas: forma cerrada (sin vacíos ni mezclas), criterios que existen en el encuadre, sin
#   repetir y disjuntas; entre las dos PARTEN los criterios del encuadre. El rango I<a>..I<b> incluye
#   todo incremento cerrado desde el hito anterior y cada uno tiene ya su commit. Lo comprueba el
#   commit-msg al commitear `Ref: hito:I<a>-I<b>`. Ejemplo: C1..C3 construidos en I1..I3, C4 en I4
#   aún sin commit → `cubre=C1,C2,C3 excluye=C4`.
#
# CONTRATO DE RECIBOS (marcador): la línea exacta `# contrato-recibos: 2` (puede seguirle texto) es la
# frontera. Es ÚNICA. Todo recibo POSTERIOR declara modalidad=, filtro= y aislamiento=; los anteriores
# son históricos. SIN marcador, todo recibo los declara (estricto por defecto): un registro de una
# versión anterior de la plantilla se migra AÑADIENDO el marcador al FINAL del registro existente,
# sin tocar lo que ya hay. Que un recibo NUEVO (ausente de HEAD) los declare aunque quede antes del
# marcador o con fecha antigua lo exige scripts/guardas.sh, que conoce HEAD; este parser no.
# Los tres campos registran la modalidad DECLARADA; no demuestran que el aislamiento se aplicara.
# REPLAY de un commit hecho con una versión anterior (su propio scripts/recibos.sh no conoce el
# marcador): el commit-msg en modo REV lo deriva DE ESE COMMIT y pasa el argumento final `previo`;
# entonces los campos no se exigen (el commit se rige por el contrato con que se hizo). Nunca sale
# del entorno: una validación local no puede pedirlo. scripts/guardas.sh impide que la
# instrumentación retroceda respecto de CUALQUIER padre, así que no es un atajo tras migrar.
# SEPARADOR: un espacio. Tabuladores u otros blancos son error: todos los lectores parten igual.
MODE="${1:-validar}"
case "$MODE" in
  validar) FILE="${2:-docs/revisiones.log}"; PREVIO="${3:-}" ;;
  ultimo)  R="$2"; T="$3"; A="$4"; FILE="${5:-docs/revisiones.log}"; PREVIO="${6:-}" ;;
  *) echo "recibos.sh: modo desconocido '$MODE' (validar | ultimo)" >&2; exit 2 ;;
esac
[ -f "$FILE" ] || exit 0

# ¿Tiene el registro marcador? Se sabe ANTES de leer: un recibo previo al marcador es histórico.
HM=$(grep -c '^# contrato-recibos: 2\([[:space:]].*\)\{0,1\}$' "$FILE")
awk -v mode="$MODE" -v R="${R:-}" -v T="${T:-}" -v A="${A:-}" -v hm="$HM" -v previo="$([ "$PREVIO" = previo ] && echo 1)" '
function bad(msg) { print "  ✗ recibos: línea " NR ": " msg " → " substr($0,1,80) > "/dev/stderr"; fail=1; return 0 }
function fecha_valida(d,   y, m, dd, mx) {
  if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9](T[0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z?)?$/) return 0
  y=substr(d,1,4)+0; m=substr(d,6,2)+0; dd=substr(d,9,2)+0
  if (y<2020 || m<1 || m>12 || dd<1) return 0
  mx = (m==2) ? ((y%4==0 && (y%100!=0 || y%400==0)) ? 29 : 28) : ((m==4||m==6||m==9||m==11) ? 30 : 31)
  if (dd>mx) return 0
  if (length(d)>10 && (substr(d,12,2)+0>23 || substr(d,15,2)+0>59 || (length(d)>=19 && substr(d,18,2)+0>59))) return 0
  return 1
}
/^# contrato-recibos: 2([ \t].*)?$/ { if (marca) bad("marcador «# contrato-recibos: 2» repetido: es único"); marca=NR; next }
/^[ \t]*(#|$)/ { next }
/[\t\r\v\f]/ { bad("separador no admitido (tabulador u otro blanco): los campos se separan con un espacio"); next }
{
  delete f; ok=1
  for (i=1;i<=NF;i++) {
    if ($i !~ /^[a-z]+=[^ ]+$/) { ok=bad("campo sin forma clave=valor: " $i); break }
    k=$i; sub(/=.*/,"",k); v=$i; sub(/^[a-z]+=/,"",v)
    if (k in f) { ok=bad("clave repetida: " k); break }
    f[k]=v
  }
  if (!ok) next
  n=split("fecha rol tipo alcance veredicto bloqueantes huella ejecutor", req, " ")
  for (j=1;j<=n;j++) if (!(req[j] in f)) { ok=bad("falta " req[j] "="); }
  if (!ok) next
  if (!fecha_valida(f["fecha"])) ok=bad("fecha debe ser ISO real (AAAA-MM-DD[Thh:mm[:ss][Z]])")
  if (f["rol"] !~ /^(revisor-funcional|juez-codigo|juez-conjunto|juez-seguridad)$/) ok=bad("rol desconocido")
  if (f["tipo"] !~ /^(encuadre|incremento|hito|conjunto)$/) ok=bad("tipo desconocido")
  if (f["veredicto"] !~ /^(PASA|FALLA)$/) ok=bad("veredicto debe ser PASA|FALLA")
  if (f["bloqueantes"] !~ /^(0|[1-9][0-9]*)$/) ok=bad("bloqueantes debe ser un entero sin ceros a la izquierda")
  if (f["huella"] !~ /^[0-9a-f]{12}$/) ok=bad("huella debe ser 12 hex")
  if (f["alcance"] !~ /^(F2|F4|I[0-9]+|hito:I[0-9]+-I[0-9]+|reentrada:C[0-9]+)$/) ok=bad("alcance fuera de gramática")
  if (!ok) next
  # coherencia rol ↔ tipo ↔ alcance
  r=f["rol"]; t=f["tipo"]; a=f["alcance"]
  if (r=="revisor-funcional" && t!="encuadre") ok=bad("revisor-funcional solo hace tipo=encuadre")
  if (r=="juez-codigo" && t!="incremento") ok=bad("juez-codigo solo hace tipo=incremento")
  if (r=="juez-conjunto" && t!="hito" && t!="conjunto") ok=bad("juez-conjunto hace tipo=hito|conjunto")
  if (t=="encuadre" && a !~ /^(F2|reentrada:C[0-9]+)$/) ok=bad("tipo=encuadre exige alcance F2 o reentrada:C<n>")
  if (t=="incremento" && a !~ /^I[0-9]+$/) ok=bad("tipo=incremento exige alcance I<n>")
  if (t=="hito" && a !~ /^hito:/) ok=bad("tipo=hito exige alcance hito:I<a>-I<b>")
  if (t=="conjunto" && a!="F4") ok=bad("tipo=conjunto exige alcance F4")
  if (f["veredicto"]=="PASA" && f["bloqueantes"]!="0") ok=bad("PASA exige bloqueantes=0")
  if (f["veredicto"]=="FALLA" && f["bloqueantes"]=="0") ok=bad("FALLA exige bloqueantes>=1")
  if ((r=="juez-codigo" || r=="juez-conjunto") && f["seguridad"] !~ /^(requerida|no-aplica)$/) ok=bad("juez-codigo/juez-conjunto deben declarar seguridad=requerida|no-aplica")
  if (t=="hito" && (!("cubre" in f) || !("excluye" in f) || !("componentes" in f))) ok=bad("tipo=hito exige cubre=, excluye= y componentes=")
  nm = ("modalidad" in f) + ("filtro" in f) + ("aislamiento" in f)
  if (nm==0 && marca && !previo) ok=bad("recibo posterior al marcador sin modalidad=, filtro= y aislamiento=")
  if (nm==0 && !hm && !previo) ok=bad("recibo sin modalidad=, filtro= y aislamiento= en un registro sin marcador. Si son recibos de una versión anterior de la plantilla, añade al FINAL del registro (sin tocar lo existente) la línea «# contrato-recibos: 2»: lo anterior queda histórico y lo nuevo declara los tres campos")
  if (nm>0 && nm<3) ok=bad("modalidad=, filtro= y aislamiento= van los tres juntos")
  if (nm==3) {
    if (f["modalidad"] !~ /^(lectura|experimentos)$/) ok=bad("modalidad debe ser lectura|experimentos")
    if (f["filtro"] !~ /^(comprobado|desactivado|sin-verificar)$/) ok=bad("filtro debe ser comprobado|desactivado|sin-verificar")
    if (f["aislamiento"] !~ /^(ninguno|sandbox-configurado|sandbox-verificado)$/) ok=bad("aislamiento debe ser ninguno|sandbox-configurado|sandbox-verificado")
  }
  if ("evidencia" in f && f["evidencia"] !~ /^docs\/revisiones\/[A-Za-z0-9][A-Za-z0-9._:-]*@[0-9a-f]{12}$/) ok=bad("evidencia debe ser docs/revisiones/<id>@<12 hex>: una carpeta directa de docs/revisiones/ cuyo id empieza por letra o número (sin carpetas ocultas)")
  if (!ok) next
  if (mode=="ultimo" && r==R && t==T && (a==A || (A=="F2" && a ~ /^reentrada:/))) last=$0
}
END {
  if (mode=="validar") exit fail ? 1 : 0
  if (fail) exit 1              # un registro inválido no entrega ningún recibo
  if (last!="") print last
}' "$FILE"
