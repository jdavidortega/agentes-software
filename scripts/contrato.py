#!/usr/bin/env python3
"""Lector ÚNICO del contrato revisado de docs/encuadre.md (viene con la plantilla; AGENTS.md §8).

Lo usan check_docs (estructura y referencias, desde F1) y el commit-msg (comparación contra el
último `Ref: F2`): las mismas reglas en los dos. Se invoca con intérprete explícito y aislado:

    python3 -I scripts/contrato.py revisa [docs/encuadre.md]   el archivo y sus referencias en disco
    python3 -I scripts/contrato.py objetos INDICE|<commit>     el contrato desde los objetos de git

Contrato = las líneas `- C<n>:` + el cuerpo de la ÚNICA sección «## Set de oro» (sin blancos finales
ni líneas vacías) + el contenido exacto de cada archivo que ese cuerpo referencia directamente (no
recursivo, nunca toda contexto/). Se lee; nada referenciado se ejecuta.

Sección: exactamente «## Set de oro» o «## Set de oro (ejemplos de salida esperada)» (el título de la
plantilla). Ausente, duplicada o un encabezado parecido que no es ninguno de los dos («## Set de Oro»,
«### Set de oro», «## Set de oro v2») es ERROR, nunca un contrato vacío. Comentarios HTML y bloques cercados
se siguen en TODO el documento (un cerco lo cierra solo su mismo carácter con al menos su longitud): un
encabezado, un criterio o una referencia que solo están dentro de uno de ellos no cuentan.

Referencias (las identifica la SINTAXIS, no que el destino exista; fuera de comentarios HTML y de
bloques cercados, que Markdown no muestra como enlaces):
  - enlace Markdown en línea `[texto](destino)` o `[texto](<destino con espacios>)`, con %XX
    decodificado y sin #fragmento: se resuelve respecto de docs/encuadre.md, p. ej.
    `[par 1](../contexto/oro/par1.md)` → contexto/oro/par1.md. Los externos (`https:`, `mailto:`…) y las
    anclas (`#seccion`) no son archivos. Un enlace que no se puede leer o la definición aparte
    (`[id]: ruta`) es ERROR: no se admiten, y no se ignoran en silencio.
  - ruta entre acentos graves que empieza EXACTAMENTE por `contexto/` o `./`, desde la raíz del
    repositorio, p. ej. `contexto/oro/par 2.md` o `./ejemplos/salida.json`. Cualquier otro texto entre
    acentos graves (`suma(1, 2) → 3`, `oro/x.md`) es un dato, no una referencia.
Una referencia es ERROR si es absoluta, sale del repositorio, entra en .git, no nombra un archivo,
o su destino no existe, es un directorio, es o pasa por un enlace simbólico, o no es un archivo regular.

Salida (una línea por registro, campos separados por tabulador):
  C <línea>            criterio                 ORO <línea>   línea del cuerpo del set de oro (los dos modos)
  REF <ruta> <objeto>  archivo referenciado (objeto = id del blob; INVALIDA si no lo es) — solo «objetos»
  ERR <motivo>         la estructura o una referencia no valen (el consumidor FALLA)
Código de salida: 0 si pudo leer (aunque haya ERR); 2 si no (uso, git): el consumidor FALLA.
"""
import os
import posixpath
import re
import stat
import subprocess
import sys
import unicodedata
from urllib.parse import unquote

ENCUADRE = "docs/encuadre.md"
TITULOS = ("## Set de oro", "## Set de oro (ejemplos de salida esperada)")
CRITERIO = re.compile(r"^- C[0-9]+:")
ENCABEZADO = re.compile(r"^(#{1,6})[ \t]+(.*)$")
SPAN = re.compile(r"(`+)(.+?)\1")
ENLACE = re.compile(r"!?\[(?:[^\[\]]|\[[^\[\]]*\])*\]\(\s*(<[^<>\n]*>|[^\s()<>]*)"
                    r"(?:\s+(?:\"[^\"]*\"|'[^']*'|\([^()]*\)))?\s*\)")
DEFINICION = re.compile(r"^ {0,3}\[[^\]]+\]:")
APERTURA = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
CIERRE = re.compile(r"^ {0,3}(`{3,}|~{3,})[ \t]*$")
ESQUEMA = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def parece_set_de_oro(texto):
    t = unicodedata.normalize("NFKD", texto.lower())
    return "setdeoro" in re.sub(r"[^a-z]", "", t)


def normaliza(ruta, base, n, cruda, errs):
    """Ruta relativa a la raíz, o None (y un ERR) si no es una ruta local admisible."""
    if any(c in ruta for c in "\x00\n\r\t"):
        errs.append(f"docs/encuadre.md, línea {n}: la referencia «{cruda}» tiene caracteres de control")
        return None
    if ruta.startswith("/"):
        errs.append(f"docs/encuadre.md, línea {n}: la referencia «{cruda}» es una ruta absoluta")
        return None
    r = posixpath.normpath(posixpath.join(base, ruta))
    if r == ".." or r.startswith("../"):
        errs.append(f"docs/encuadre.md, línea {n}: la referencia «{cruda}» sale del repositorio")
        return None
    if r == ".":
        errs.append(f"docs/encuadre.md, línea {n}: la referencia «{cruda}» no nombra un archivo")
        return None
    if r.split("/")[0] == ".git":
        errs.append(f"docs/encuadre.md, línea {n}: la referencia «{cruda}» apunta dentro de .git")
        return None
    return r


def visibles(texto):
    """[(n, línea, visible)] de TODO el documento: visible es lo que Markdown muestra fuera de comentarios
    HTML y de bloques cercados, o None si la línea abre, cierra o está dentro de un cerco. Un cerco se
    cierra solo con el MISMO carácter y al menos la misma longitud que lo abrió (``` no cierra ~~~)."""
    out, comentario, cerco = [], False, None
    for n, linea in enumerate(texto.split("\n"), 1):
        linea = linea.rstrip()
        if cerco:
            m = CIERRE.match(linea)
            if m and m.group(1)[0] == cerco[0] and len(m.group(1)) >= cerco[1]:
                cerco = None
            out.append((n, linea, None))
            continue
        antes, visible, resto = comentario, "", linea
        while resto:
            if comentario:
                k = resto.find("-->")
                if k < 0:
                    resto = ""
                else:
                    comentario, resto = False, resto[k + 3:]
            else:
                k = resto.find("<!--")
                if k < 0:
                    visible, resto = visible + resto, ""
                else:
                    visible, comentario, resto = visible + resto[:k], True, resto[k + 4:]
        m = APERTURA.match(visible)
        if not antes and m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
            cerco = (m.group(1)[0], len(m.group(1)))
            out.append((n, linea, None))
            continue
        out.append((n, linea, visible.rstrip()))
    return out


def lee(texto):
    """(registros C/ORO en orden, [(n, cruda, ruta)] referencias válidas por sintaxis, [errores]).
    Encabezados, criterios y referencias se reconocen solo en lo visible; el cuerpo que se compara (ORO) es
    el texto de la sección tal cual, comentarios y cercos incluidos."""
    regs, refs, errs = [], [], []
    secciones, en_sec = 0, False
    for n, linea, visible in visibles(texto):
        m = ENCABEZADO.match(visible) if visible else None
        if m:
            if visible in TITULOS:
                secciones += 1
                en_sec = True
                continue
            if parece_set_de_oro(m.group(2)):
                errs.append(f"docs/encuadre.md, línea {n}: encabezado «{visible}» no reconocido como el set de oro; "
                            f"usa «{TITULOS[1]}» (el de la plantilla) o «{TITULOS[0]}»")
            if visible.startswith("## "):
                en_sec = False
        # Un criterio aporta su registro C (nunca ORO) y, dentro del set de oro, sus referencias igual que otra línea.
        criterio = bool(visible and CRITERIO.match(visible))
        if criterio:
            regs.append("C\t" + linea)
        if not en_sec:
            continue
        if linea and not criterio:
            regs.append("ORO\t" + linea)
        if not visible:
            continue
        for s in SPAN.finditer(visible):
            c = s.group(2).strip()
            if c.startswith("contexto/") or c.startswith("./"):
                r = normaliza(c, "", n, c, errs)
                if r:
                    refs.append((n, c, r))
        visible = SPAN.sub(lambda s: " " * len(s.group(0)), visible)
        if DEFINICION.match(visible):
            errs.append(f"docs/encuadre.md, línea {n}: enlace por referencia («[id]: ruta») no admitido en el set de oro; "
                        "usa un enlace en línea [texto](ruta)")
            continue
        for e in ENLACE.finditer(visible):
            d = e.group(1)
            d = d[1:-1] if d.startswith("<") else d
            if ESQUEMA.match(d) or d.startswith("#"):
                continue
            d = unquote(re.split(r"[#?]", d)[0])
            if not d:
                errs.append(f"docs/encuadre.md, línea {n}: enlace sin destino en el set de oro")
                continue
            r = normaliza(d, "docs", n, d, errs)
            if r:
                refs.append((n, d, r))
        if "](" in ENLACE.sub("", visible):
            errs.append(f"docs/encuadre.md, línea {n}: enlace que no se puede leer en el set de oro "
                        "(forma admitida: [texto](ruta) o [texto](<ruta con espacios>))")
    if secciones == 0:
        errs.append(f"docs/encuadre.md no tiene la sección «## Set de oro»: desde F1 es obligatoria "
                    f"(una sola, «{TITULOS[1]}»)")
    elif secciones > 1:
        errs.append(f"docs/encuadre.md tiene {secciones} secciones «## Set de oro»: debe haber una")
    return regs, refs, errs


def revisa(archivo):
    try:
        texto = open(archivo, "rb").read().decode("utf-8", "surrogateescape")
    except OSError as e:
        print(f"contrato.py: no puedo leer {archivo}: {e}", file=sys.stderr)
        return 2
    regs, refs, errs = lee(texto)
    for n, cruda, r in refs:
        motivo, cur = None, ""
        for parte in r.split("/"):
            cur = posixpath.join(cur, parte) if cur else parte
            try:
                st = os.lstat(cur)
            except OSError:
                motivo = "no existe"
                break
            if stat.S_ISLNK(st.st_mode):
                motivo = "es un enlace simbólico (o pasa por uno)"
                break
        else:
            if stat.S_ISDIR(st.st_mode):
                motivo = "es un directorio"
            elif not stat.S_ISREG(st.st_mode):
                motivo = "no es un archivo regular"
        if motivo:
            errs.append(f"docs/encuadre.md, línea {n}: la referencia «{cruda}» ({r}) {motivo}")
    sal = regs + ["ERR\t" + e for e in errs]
    sys.stdout.buffer.write(("\n".join(sal) + ("\n" if sal else "")).encode("utf-8", "surrogateescape"))
    return 0


def git(*args):
    return subprocess.run(["git", *args], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True).stdout


def objetos(rev):
    """Entradas {ruta: (modo, objeto, etapa)} del índice o del árbol de <rev>: nunca el árbol de trabajo."""
    ent = {}
    if rev == "INDICE":
        for reg in git("ls-files", "-s", "-z").split(b"\0"):
            if reg:
                meta, ruta = reg.split(b"\t", 1)
                modo, obj, etapa = meta.decode().split()
                ent[ruta.decode("utf-8", "surrogateescape")] = (modo, obj, etapa)
    else:
        for reg in git("ls-tree", "-r", "-z", "--full-tree", rev).split(b"\0"):
            if reg:
                meta, ruta = reg.split(b"\t", 1)
                modo, _, obj = meta.decode().split()
                ent[ruta.decode("utf-8", "surrogateescape")] = (modo, obj, "0")
    return ent


def contrato(rev):
    try:
        if rev != "INDICE":
            rev = git("rev-parse", "--verify", "-q", rev + "^{commit}").decode().strip()
        ent = objetos(rev)
        e = ent.get(ENCUADRE)
        texto = git("cat-file", "blob", e[1]).decode("utf-8", "surrogateescape") if e and e[0] in ("100644", "100755") else None
    except (subprocess.CalledProcessError, OSError, ValueError) as x:
        print(f"contrato.py: no puedo leer los objetos de {rev}: {x}", file=sys.stderr)
        return 2
    sal = []
    if texto is None:
        sal.append("ERR\tfalta docs/encuadre.md (o no es un archivo regular) en " + ("el índice" if rev == "INDICE" else rev[:12]))
        texto = ""
    regs, refs, errs = lee(texto)
    sal += regs
    dirs = {"/".join(p.split("/")[:k]) for p in ent for k in range(1, p.count("/") + 1)}
    vistas = {}
    for n, cruda, r in refs:
        if r in vistas:
            continue
        motivo, obj = None, "INVALIDA"
        prefijos = ["/".join(r.split("/")[:k]) for k in range(1, r.count("/") + 1)]
        if any(ent.get(p, ("",))[0] == "120000" for p in prefijos):
            motivo = "pasa por un enlace simbólico"
        elif r in ent:
            modo, o, etapa = ent[r]
            if etapa != "0":
                motivo = "está en conflicto en el índice"
            elif modo == "120000":
                motivo = "es un enlace simbólico"
            elif modo == "160000":
                motivo = "es un submódulo"
            elif modo in ("100644", "100755"):
                obj = o
            else:
                motivo = "no es un archivo regular"
        elif r in dirs:
            motivo = "es un directorio"
        else:
            motivo = "no existe en " + ("el índice" if rev == "INDICE" else rev[:12])
        vistas[r] = obj
        if motivo:
            errs.append(f"docs/encuadre.md, línea {n}: la referencia «{cruda}» ({r}) {motivo}")
    sal += [f"REF\t{r}\t{vistas[r]}" for r in sorted(vistas)]
    sal += ["ERR\t" + e for e in errs]
    sys.stdout.buffer.write(("\n".join(sal) + ("\n" if sal else "")).encode("utf-8", "surrogateescape"))
    return 0


def main(argv):
    if len(argv) >= 1 and argv[0] == "revisa" and len(argv) <= 2:
        return revisa(argv[1] if len(argv) == 2 else ENCUADRE)
    if len(argv) == 2 and argv[0] == "objetos":
        return contrato(argv[1])
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
