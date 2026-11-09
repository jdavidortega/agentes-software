#!/usr/bin/env python3
"""Lector compartido de docs/decisiones.md (viene con la plantilla; formato ADR-lite de ese archivo).

Lo usan fallos_previos.py (el ADR que decide un fallo previo o la retirada de una prueba, M01) y la retirada
de un requisito (check_docs y el commit-msg, con «# contrato-retirada: 1»): una sola gramática del ADR.
Comprueba ESTRUCTURA y REFERENCIAS de lo escrito; no autentica la aprobación de la persona (eso lo da ella
en el gate, y la cita se contrasta con su fuente: decisiones.md, «Aceptación»).

    python3 -I scripts/decisiones.py ids [archivo|-]                 los ADR-NNN con sección («## ADR-NNN»)
    python3 -I scripts/decisiones.py retira <ADR-NNN> <C<n>> [archivo|-]
        ¿autoriza ese ADR que C<n> esté retirado? Sigue la sustitución existente: un ADR en
        «reemplazada-por: ADR-YYY» vale por su sustituto, que tiene que volver a decidirlo. El que decide
        está en «aceptada», su **Aprobación** no está vacía ni es `retrospectivo`, y nombra C<n>.
        Salida 0 e imprime el ADR que decide; 1 e imprime el motivo; 2 si no se pudo leer.
    python3 -I scripts/decisiones.py sustituta <ADR-NNN> [archivo|-]  el ADR-YYY de «reemplazada-por», o nada

Sección: desde «## ADR-NNN» hasta el siguiente «## ». Campos: líneas `- **Campo:** valor` (o `* `).
Por defecto el archivo es docs/decisiones.md; «-» lee la entrada estándar.
"""
import re
import sys

DECISIONES = "docs/decisiones.md"
ID = re.compile(r"ADR-\d{3}")


def seccion(texto, adr):
    """El texto de la sección `## ADR-NNN` (la primera), o None."""
    m = re.search(r"^## %s\b.*?(?=^## |\Z)" % re.escape(adr), texto, re.M | re.S)
    return m.group(0) if m else None


def aceptada(texto, adr):
    """El texto de la sección si su **Estado:** es exactamente `aceptada`; si no, None."""
    s = seccion(texto, adr)
    if s and re.search(r"^[-*][ \t]+\*\*Estado:\*\*[ \t]*aceptada[ \t]*$", s, re.M):
        return s
    return None


def retrospectivo(sec):
    return bool(re.search(r"^[-*][ \t]+\*\*Aprobación:\*\*[ \t]*`?retrospectivo\b", sec, re.M))


def nombra(sec, token, punto=True):
    """¿Aparece `token` como palabra? Con punto=True (M01: identificadores de prueba con puntos) un punto pegado
    lo prolonga; para un criterio (punto=False), «C4.» al final de una frase nombra C4."""
    return bool(re.search(r"(?<![\w.])%s(?!%s)" % (re.escape(token), r"[\w.]" if punto else r"\w"), sec))


def aprobacion(sec):
    """El valor del campo **Aprobación:** (sin blancos de los extremos), o None si no está."""
    m = re.search(r"^[-*][ \t]+\*\*Aprobación:\*\*[ \t]*(.*?)[ \t]*$", sec, re.M)
    return m.group(1) if m else None


def sustituta(sec):
    """El ADR-YYY de `**Estado:** reemplazada-por: ADR-YYY`, o None."""
    m = re.search(r"^[-*][ \t]+\*\*Estado:\*\*[ \t]*reemplazada-por:[ \t]*`?(ADR-\d{3})`?[ \t]*$", sec, re.M)
    return m.group(1) if m else None


def ids(texto):
    return sorted(set(re.findall(r"^## (ADR-\d{3})\b", texto, re.M)))


def decide(texto, adr):
    """None si `adr` es una decisión nueva vigente: sección en «aceptada», con **Aprobación** no vacía y no
    `retrospectivo`; si no, el motivo. No sigue la sustitución."""
    if not ID.fullmatch(adr):
        return "«%s» no es un identificador ADR-NNN" % adr
    s = seccion(texto, adr)
    if s is None:
        return "%s no existe en %s (sección «## %s»)" % (adr, DECISIONES, adr)
    if not aceptada(texto, adr):
        return "%s no está en estado «aceptada»: una retirada o una reactivación solo la autoriza una decisión vigente" % adr
    a = aprobacion(s)
    if a is None or a == "" or a.startswith("_("):
        return "%s no cita la aprobación de la persona (campo **Aprobación:** vacío o ausente): es una decisión nueva" % adr
    if retrospectivo(s):
        return "%s es un registro retrospectivo: documenta lo vigente y no autoriza retirar ni reactivar un requisito" % adr
    return None


def retira(texto, adr, token):
    """(ADR que decide, None) si `adr`, siguiendo la sustitución, autoriza que `token` esté retirado;
    (None, motivo) si no."""
    vistos = []
    x = adr
    while True:
        if not ID.fullmatch(x):
            return None, "«%s» no es un identificador ADR-NNN" % x
        if x in vistos:
            return None, "la sustitución de %s forma un ciclo (%s)" % (adr, " → ".join(vistos + [x]))
        vistos.append(x)
        s = seccion(texto, x)
        if s is None:
            return None, "%s no existe en %s (sección «## %s»)" % (x, DECISIONES, x)
        y = sustituta(s)
        if y:
            x = y
            continue
        if not aceptada(texto, x):
            return None, "%s no está en estado «aceptada» ni «reemplazada-por: ADR-NNN»: una retirada solo la autoriza una decisión vigente" % x
        m = decide(texto, x)
        if m:
            return None, m
        if not nombra(s, token, punto=False):
            return None, "%s no nombra %s: el ADR que decide la retirada nombra lo que retira" % (x, token)
        return x, None


def lee(ruta):
    if ruta == "-":
        return sys.stdin.read()
    with open(ruta, encoding="utf-8") as f:
        return f.read()


def main(argv):
    try:
        if argv[:1] == ["ids"] and len(argv) <= 2:
            print("\n".join(ids(lee(argv[1] if len(argv) == 2 else DECISIONES))))
            return 0
        if argv[:1] == ["retira"] and len(argv) in (3, 4):
            final, motivo = retira(lee(argv[3] if len(argv) == 4 else DECISIONES), argv[1], argv[2])
            print(final or motivo)
            return 0 if final else 1
        if argv[:1] == ["sustituta"] and len(argv) in (2, 3):
            s = seccion(lee(argv[2] if len(argv) == 3 else DECISIONES), argv[1])
            if s is None:
                return 1
            print(sustituta(s) or "")
            return 0
    except (OSError, UnicodeDecodeError) as e:
        print("no pude leer las decisiones: %s" % e, file=sys.stderr)
        return 2
    print("uso: decisiones.py ids [archivo|-] · retira <ADR-NNN> <C<n>> [archivo|-] · sustituta <ADR-NNN> [archivo|-]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
