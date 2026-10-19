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
#   sh scripts/recibos.sh hito-vigente [archivo]           → imprime el recibo del juez de conjunto
#                                                            que reinicia el contador del hito
#                                                            (ver abajo); vacío si no hay ninguno
#   sh scripts/recibos.sh incrementos-sin-hito [archivo]   → cuántos incrementos DISTINTOS tienen
#                                                            PASA EFECTIVO del juez de código después
#                                                            del hito vigente. Es el contador del hito.
#
# Gramática de una línea (campos clave=valor separados por espacio, sin repetir claves;
# las líneas que empiezan por # y las vacías se ignoran en todos los modos):
#   fecha=<ISO: AAAA-MM-DD, opcional Thh:mm[:ss][Z]>
#   rol=revisor-funcional|juez-codigo|juez-conjunto|juez-seguridad
#   tipo=encuadre|incremento|hito|conjunto   alcance=F2|F4|I<n>|hito:I<a>-I<b>|reentrada:C<n>
#   veredicto=PASA|FALLA  bloqueantes=<entero sin ceros a la izquierda>  huella=<12 hex>  ejecutor=<quién>
#   seguridad=requerida|no-aplica   (obligatorio en juez-codigo y juez-conjunto)
#   cubre=<C..>  excluye=<C..|ninguno>  componentes=<..>   (obligatorios en tipo=hito)
# Relaciones: PASA ⇒ bloqueantes=0; FALLA ⇒ bloqueantes≥1; rol↔tipo↔alcance coherentes.
#
# "Efectivo" (lo que cuenta para el hito): un PASA es efectivo solo si es el ÚLTIMO recibo
# de su rol+tipo+alcance (un FALLA posterior lo anula). Un recibo del juez de conjunto
# reinicia el contador solo si es efectivo Y, cuando declara seguridad=requerida, el último
# recibo del juez de seguridad del mismo tipo+alcance es PASA. Que su huella corresponda a
# un commit real lo comprueba el commit-msg (scripts/huella.sh commit <sha>), no este parser.
MODE="${1:-validar}"
case "$MODE" in
  validar) FILE="${2:-docs/revisiones.log}" ;;
  ultimo)  R="$2"; T="$3"; A="$4"; FILE="${5:-docs/revisiones.log}" ;;
  hito-vigente|incrementos-sin-hito) FILE="${2:-docs/revisiones.log}" ;;
  *) echo "recibos.sh: modo desconocido '$MODE' (validar | ultimo | hito-vigente | incrementos-sin-hito)" >&2; exit 2 ;;
esac
[ -f "$FILE" ] || { [ "$MODE" = "incrementos-sin-hito" ] && echo 0; exit 0; }

awk -v mode="$MODE" -v R="${R:-}" -v T="${T:-}" -v A="${A:-}" '
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
/^[ \t]*(#|$)/ { next }
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
  if (!ok) next
  if (mode=="ultimo" && r==R && t==T && (a==A || (A=="F2" && a ~ /^reentrada:/))) last=$0
  # Para los modos del hito se guarda todo recibo válido en orden; se resuelve al final.
  N++; L[N]=$0; ROL[N]=r; TIPO[N]=t; ALC[N]=a; VER[N]=f["veredicto"]; SEG[N]=f["seguridad"]
  ULT[r SUBSEP t SUBSEP a]=N
}
END {
  if (mode=="validar") exit fail ? 1 : 0
  if (fail) exit 1              # un registro inválido no entrega ningún recibo ni conteo
  if (mode=="ultimo") { if (last!="") print last; exit 0 }
  # Hito vigente: el último recibo EFECTIVO del juez de conjunto (hito o F4).
  reset=0
  for (i=1;i<=N;i++) {
    if (ROL[i]!="juez-conjunto" || VER[i]!="PASA") continue
    if (ULT["juez-conjunto" SUBSEP TIPO[i] SUBSEP ALC[i]]!=i) continue          # lo anuló un recibo posterior
    if (SEG[i]=="requerida") {
      s=ULT["juez-seguridad" SUBSEP TIPO[i] SUBSEP ALC[i]]
      if (!s || VER[s]!="PASA") continue                                         # seguridad requerida sin PASA
    }
    reset=i
  }
  if (mode=="hito-vigente") { if (reset) print L[reset]; exit 0 }
  n=0
  for (i=reset+1;i<=N;i++)
    if (ROL[i]=="juez-codigo" && VER[i]=="PASA" && ULT["juez-codigo" SUBSEP "incremento" SUBSEP ALC[i]]==i && !(ALC[i] in seen)) { seen[ALC[i]]=1; n++ }
  print n; exit 0
}' "$FILE"
