#!/bin/sh
# Lector ÚNICO de docs/trazabilidad.md (viene con la plantilla; AGENTS.md §8). Lo usan
# check_docs (doctor), el commit-msg (trailers) y validar_historial (replay): una fila
# significa lo mismo en los tres. Lee por TABLA y COLUMNA (el encabezado real decide qué
# columna es Estado e Incr.), nunca por patrones sueltos.
#
#   sh scripts/trazabilidad.sh [archivo | -]     (por defecto docs/trazabilidad.md; - = stdin)
#
# Imprime una línea por fila: "TIPO ID INCR ESTADO" donde TIPO es
#   C | E | R      fila legible de Cobertura | Vacíos | Registro del juez (ESTADO = 1.ª palabra de la columna Estado;
#                  en R, 5.º campo = columna Criterio con espacios como _)
#   H              entrada del Histórico (ESTADO = verificado | desconocido)
#   HDR tipo cols  encabezado de tabla (cols separadas por coma, espacios como _)
#   EJ id          fila de ejemplo de la plantilla (C_, R-E._, R-I_._, C1 con I_, histórico _(ejemplo)_)
#   NOEST id       fila bajo un encabezado sin columna Estado
#   ARIDAD id n m  fila con n celdas bajo un encabezado de m columnas
#   X id           ID fuera de la gramática (C<n> | R-E.<n> | R-I<i>.<n> | R-S<i>.<n> | R-F4.<n> | R-SF4.<n>)
#   T id           ID en la tabla equivocada
#   INCR id incr want  la columna Incr. no nombra el incremento del ID (R-I3.n ⇒ I3; R-F4.n / R-SF4.n ⇒ F4)
#   SANGRIA nlinea fila de tabla o entrada del Histórico con sangría (se lee igual; el doctor avisa)
#   RES id texto…  la celda «Resuelto» de una fila E/R legible (tal cual, con sus espacios; vacío si
#                  no hay nada o solo «—») o el texto de una entrada del Histórico. Va en un registro
#                  aparte para que las filas conserven sus campos; se lee con substr($0, index($0,$3)).
# Una fila con sangría SE LEE (nada se vuelve invisible por espacios); el doctor la señala
# porque Markdown puede mostrarla como código.
F="${1:-docs/trazabilidad.md}"
if [ "$F" = "-" ]; then F=/dev/stdin; else [ -f "$F" ] || exit 0; fi
awk -F'|' '
  function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  /^[ \t]*\|/ {
    if ($0 ~ /^[ \t]+\|/) print "SANGRIA", NR, "-", "-"
    n=0; for(i=2;i<NF;i++){ n++; f[n]=trim($i) }
    if (f[1] ~ /^-+$/) next                                   # separador
    if (f[1]=="Criterio"||f[1]=="Vacío"||f[1]=="Hallazgo") {  # encabezado: ubicar columnas
      tipo = (f[1]=="Criterio") ? "C" : (f[1]=="Vacío") ? "E" : "R"
      ncol=n; ce=0; ci=0
      ncc=0; cr=0; for(k=1;k<=n;k++){ if(f[k]=="Estado") ce=k; if(f[k] ~ /^Incr/) ci=k; if(f[k]=="Criterio" && k>1) ncc=k; if(f[k] ~ /^Resuelto/) cr=k }
      hdr=""; for(k=1;k<=n;k++) { c=f[k]; gsub(/ /,"_",c); hdr = hdr (k>1?",":"") c }
      print "HDR", tipo, hdr, "-"
      next
    }
    if (tipo=="") next
    id=f[1]
    ej = (id=="C_" || id=="R-E._" || id=="R-I_._" || (tipo=="C" && ci>0 && f[ci]=="I_"))
    if (ej) { print "EJ", id, "-", "-"; next }
    if (ce==0) { print "NOEST", id, "-", "-"; next }
    if (n!=ncol) { print "ARIDAD", id, n, ncol; next }
    if (id !~ /^(C[0-9]+|R-(E|I[0-9]+|S[0-9]+|F4|SF4)\.[0-9]+)$/) { print "X", id, "-", "-"; next }
    if ((tipo=="C" && id !~ /^C/) || (tipo=="E" && id !~ /^R-E\./) || (tipo=="R" && (id ~ /^C/ || id ~ /^R-E\./))) { print "T", id, "-", "-"; next }
    incr = (ci>0) ? f[ci] : "-"; gsub(/ /,"",incr); if(incr=="") incr="-"
    if (tipo=="R") {
      # Familias de conjunto primero (R-F4, R-SF4 ⇒ F4), después las de incremento (R-I3, R-S3 ⇒ I3).
      want=id; sub(/\.[0-9]+$/,"",want)
      if (want ~ /^R-S?F4$/) want="F4"; else sub(/^R-(I|S)/,"I",want)
      if (incr!=want) { print "INCR", id, incr, want; next }
    }
    est=f[ce]; sub(/ .*$/,"",est)
    if (tipo=="R" && ncc>0) { c=f[ncc]; gsub(/ /,"_",c); if (c=="") c="-"; print tipo, id, incr, est, c } else print tipo, id, incr, est
    if (tipo!="C" && cr>0) { r=f[cr]; if (r ~ /^[ —–-]*$/) r=""; print "RES", id, r }
    next
  }
  /^## Histórico/ { hist=1; next }
  /^## / { hist=0 }
  hist && /^[ \t]*- / {
    if ($0 ~ /^[ \t]+- /) print "SANGRIA", NR, "-", "-"
    if ($0 ~ /_\(ejemplo\)_/) { print "EJ", "historico", "-", "-"; next }
    if (match($0, /R-(E|I[0-9]+|S[0-9]+|F4|SF4)\.[0-9]+/)) {
      id=substr($0, RSTART, RLENGTH)
      print "H", id, "-", (($0 ~ /· *verificado/) ? "verificado" : "desconocido")
      t=$0; sub(/^[ \t]*- */, "", t); print "RES", id, t
    }
  }
' "$F"
