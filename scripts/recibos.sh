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
#   sh scripts/recibos.sh incrementos-sin-hito [archivo]   → cuántos incrementos DISTINTOS tienen
#                                                            recibo PASA del juez de código desde la
#                                                            última pasada PASA del juez de conjunto
#                                                            (hito o F4). Es el contador del hito.
#
# Gramática de una línea (campos clave=valor separados por espacio, sin repetir claves;
# las líneas que empiezan por # y las vacías se ignoran en ambos modos):
#   fecha=<ISO>  rol=revisor-funcional|juez-codigo|juez-conjunto|juez-seguridad
#   tipo=encuadre|incremento|hito|conjunto   alcance=F2|F4|I<n>|hito:I<a>-I<b>|reentrada:C<n>
#   veredicto=PASA|FALLA  bloqueantes=<n>  huella=<12 hex>  ejecutor=<quién>
#   seguridad=requerida|no-aplica   (obligatorio en juez-codigo y juez-conjunto)
#   cubre=<C..>  excluye=<C..|ninguno>  componentes=<..>   (obligatorios en tipo=hito)
# Relaciones: PASA ⇒ bloqueantes=0; FALLA ⇒ bloqueantes≥1; rol↔tipo↔alcance coherentes.
MODE="${1:-validar}"
case "$MODE" in
  validar) FILE="${2:-docs/revisiones.log}" ;;
  ultimo)  R="$2"; T="$3"; A="$4"; FILE="${5:-docs/revisiones.log}" ;;
  incrementos-sin-hito) FILE="${2:-docs/revisiones.log}" ;;
  *) echo "recibos.sh: modo desconocido '$MODE' (validar | ultimo | incrementos-sin-hito)" >&2; exit 2 ;;
esac
[ -f "$FILE" ] || { [ "$MODE" = "incrementos-sin-hito" ] && echo 0; exit 0; }

awk -v mode="$MODE" -v R="${R:-}" -v T="${T:-}" -v A="${A:-}" '
function bad(msg) { print "  ✗ recibos: línea " NR ": " msg " → " substr($0,1,80) > "/dev/stderr"; fail=1; return 0 }
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
  if (f["rol"] !~ /^(revisor-funcional|juez-codigo|juez-conjunto|juez-seguridad)$/) ok=bad("rol desconocido")
  if (f["tipo"] !~ /^(encuadre|incremento|hito|conjunto)$/) ok=bad("tipo desconocido")
  if (f["veredicto"] !~ /^(PASA|FALLA)$/) ok=bad("veredicto debe ser PASA|FALLA")
  if (f["bloqueantes"] !~ /^[0-9]+$/) ok=bad("bloqueantes debe ser un entero")
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
  if (mode=="incrementos-sin-hito") {
    if (r=="juez-codigo" && f["veredicto"]=="PASA") seen[a]=1
    if (r=="juez-conjunto" && f["veredicto"]=="PASA") delete seen
  }
}
END {
  if (mode=="validar") exit fail ? 1 : 0
  if (fail) exit 1              # un registro inválido no entrega ningún recibo ni conteo
  if (mode=="incrementos-sin-hito") { n=0; for (k in seen) n++; print n; exit 0 }
  if (last!="") print last
}' "$FILE"
