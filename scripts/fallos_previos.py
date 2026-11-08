#!/usr/bin/env python3
"""Fallos previos de una adopción (viene con la plantilla; docs/arranque-existente.md §F y §G).

Un proyecto que se adopta con pruebas que YA fallaban puede commitear sin ocultarlas: los fallos de la
línea base inicial se declaran, y cualquier otro resultado FALLA. Nada se acredita con ello: los criterios
afectados siguen en `pendiente`.

    python3 -I scripts/fallos_previos.py capturar --adaptador unittest [--inicio tests] [--superior .]
        ejecuta la suite una vez y escribe la LÍNEA BASE (contexto/exploracion/linea-base-pruebas.xml) y el
        REGISTRO (docs/fallos-previos.md) con sus fallos. Rehúsa si alguno existe. Paso F de la adopción.
    python3 -I scripts/fallos_previos.py comprobar --adaptador unittest [--inicio tests] [--superior .]
        lo llama scripts/check.sh: ejecuta la suite y compara con la línea base y el registro. Con
        FALLOS_PREVIOS_TESTIGO y FALLOS_PREVIOS_FICHA (los pone el pre-commit, nuevos en cada ejecución,
        cuando existe el registro) anota `inicio <ficha> <pid> <directorio real>` al empezar y
        `fin <ficha> <pid> <código>` al terminar: el hook comprueba que se ejecutó, que cada llamada corrió en
        la raíz del candidato y terminó, y que check.sh propagó su fallo. Detecta la omisión y el
        enmascaramiento, no la falsificación: no autentica al comparador, y un check.sh que escribe ese
        registro, o que cambia las pruebas y las restaura antes de terminar, no se detecta (check.sh es de
        confianza; docs/arranque-existente.md §G).
    python3 -I scripts/fallos_previos.py testigo <ruta> <ficha> <raíz>
        lo llama el pre-commit tras un check.sh en 0: valida ese registro (gramática de arriba).
    python3 -I scripts/fallos_previos.py destinos [--cierre]
        lo llama scripts/check_docs.sh desde F2: cada fila declarada tiene destino, un I<n> PENDIENTE de
        docs/plan.md (leído con `check_docs.sh plan`) o un ADR aceptado, no retrospectivo, que la nombra; un I<n> cerrado con
        su fila viva FALLA. Con --cierre (F4/F5) FALLA toda fila viva: ningún destino, tampoco un ADR,
        habilita una excepción al cierre ni verifica un criterio.
    python3 -I scripts/fallos_previos.py guarda <base> <candidato|INDICE>
        lo llama scripts/guardas.sh (pre-commit y replay): la línea base no cambia ni se añade tras un
        `Ref: F2` (en NINGÚN padre, también en un merge; el F2 se reconoce con el mismo patrón que el commit-msg),
        el registro no desaparece, cada fila es un fallo de la línea base con su firma y cada
        retirada del inventario cita un ADR aceptado, no retrospectivo, que la nombra.

Línea base: inmutable una vez versionada; su inventario (cada prueba, ejecutada u omitida) y sus fallos son
la ÚNICA fuente de «previo». Fija también DÓNDE se ejecuta la suite (`inicio` y `superior`, resueltos y
relativos al directorio de la ejecución): `comprobar` con otros valores FALLA, y el pre-commit exige que ese
directorio sea la raíz del candidato (testigo), así que no se compara una copia de las pruebas en otro directorio; sustituirlas en la raíz y restaurarlas (C4) o escribir el registro (T5) no se detecta. Registro: `| Prueba | Firma | Destino |` (identificadores exactos, sin patrones)
y `| Prueba | Motivo | ADR |` para retirar una prueba del inventario (revisado en ese commit; la línea base
nunca se recaptura). Retirar es sacarla de la suite: una retirada ya no se ejecuta, no puede figurar también
como fallo declarado, y su ADR es una sección `## ADR-NNN` de docs/decisiones.md en `**Estado:** aceptada`
que nombra la prueba (el protocolo de aceptación del método: la aceptación la da la persona en el gate; la
guarda solo comprueba el estado escrito).

Firma: `fallo|error · <tipo de excepción> · <12 hex>` del mensaje normalizado SOLO así: finales de línea
unificados y sin blancos finales, la raíz de la ejecución → `<raiz>`. Ningún otro valor del mensaje se toca
(`3 != 2` y `4 != 2`, o `0x10 != 0x20` y `0x30 != 0x40`, son firmas distintas); un mensaje que cambia en cada
ejecución (p. ej. con una dirección de memoria) no se puede declarar: falla «con otra firma».

Contrato del adaptador (hoy solo `unittest`; ningún otro stack está probado): recibe un directorio NUEVO y
un identificador de ejecución; escribe ahí un JUnit XML con ese identificador, la raíz y `completa="si"` al
terminar. Códigos: 0 todo ejecutado sin fallos · 1 todo ejecutado con fallos o errores de prueba · 3 error
de recolección · 4 interrumpida · 5 resultado no soportado · otro: caída del ejecutor. Solo 0 y 1 se
comparan; un XML presente no prueba por sí solo una ejecución completa, y uno ajeno a esta ejecución nunca
se lee. En unittest, una subprueba (`subTest`) fallida hace fallar a su prueba, con la descripción de cada
subprueba en el mensaje; una omisión dentro de `subTest`, un error u omisión de fixture de clase o de módulo
(`setUpClass`, `tearDownClass`, `setUpModule`…: llegan fuera del ciclo de una prueba) o una prueba que termina
sin resultado no están soportados (código 5).

Veredicto de `comprobar` (salida 0): toda prueba del inventario (salvo retiradas) aparece, y las ejecutadas
en la línea base siguen ejecutándose; los fallos son EXACTAMENTE los declarados, cada uno con su firma.
Con fallos declarados imprime «sin fallos nuevos; N fallos previos declarados» y, con CHECK_ESTRICTO=1,
termina en 2. Cualquier otra cosa: salida 1 y los motivos.
"""
import hashlib
import os
import re
import subprocess
import sys
import tempfile
import uuid
import xml.etree.ElementTree as ET

LINEA_BASE = "contexto/exploracion/linea-base-pruebas.xml"
REGISTRO = "docs/fallos-previos.md"
DECISIONES = "docs/decisiones.md"
CLASES = {3: "recolección", 4: "interrumpida", 5: "no soportado"}
# El MISMO patrón del F2 que el commit-msg (git log -E --grep, clase POSIX [[:space:]]).
F2_GREP = "^Ref:[[:space:]]*F2[[:space:]]*$"


# --- adaptador unittest (proceso hijo) --------------------------------------------------------------
def adaptador_unittest(informe, ejecucion, inicio, superior):
    import unittest
    raiz = os.getcwd()
    sys.path.insert(0, os.path.abspath(superior))
    cargador = unittest.TestLoader()
    suite = cargador.discover(inicio, top_level_dir=superior)
    casos, recoleccion = [], list(cargador.errors)

    def aplana(s):
        for t in s:
            if isinstance(t, unittest.TestSuite):
                yield from aplana(t)
            else:
                yield t
    pruebas = []
    for t in aplana(suite):
        if type(t).__name__ == "_FailedTest":
            recoleccion.append(t.id())
        else:
            pruebas.append(t)

    # Cada prueba deja UN caso al terminar (stopTest): el suyo, o el de sus subpruebas fallidas, que nunca
    # desaparecen tras una prueba hermana que pasa. Lo que no se puede reducir a eso se declara no soportado.
    propio, subs, no_soportado = {}, {}, []

    class Resultado(unittest.TestResult):
        def startTest(self, t):
            super().startTest(t); propio.pop(t.id(), None); subs[t.id()] = []
        def addSubTest(self, t, s, e):
            super().addSubTest(t, s, e)
            if e is not None:
                est = "fallo" if issubclass(e[0], t.failureException) else "error"
                subs.setdefault(t.id(), []).append((est, e[0].__name__, "%s: %s" % (s.id()[len(t.id()):].strip(), e[1])))
        def fuera(self, t, que):
            """True (y no soportado) si el evento no es de una prueba en curso: subTest o fixture."""
            if t.id() in subs:
                return False
            if isinstance(t, unittest.case._SubTest):
                no_soportado.append("%s: %s dentro de subTest" % (t.id(), que))
            else:
                no_soportado.append("%s: %s fuera de una prueba (fixture de clase o de módulo)" % (t.id(), que))
            return True
        def addSuccess(self, t): propio[t.id()] = ("ok", "", "")
        def addFailure(self, t, e):
            if not self.fuera(t, "fallo"):
                propio[t.id()] = ("fallo", e[0].__name__, str(e[1]))
        def addError(self, t, e):
            if not self.fuera(t, "error"):
                propio[t.id()] = ("error", e[0].__name__, str(e[1]))
        def addSkip(self, t, r):
            if not self.fuera(t, "omisión"):
                propio[t.id()] = ("omitida", "", str(r))
        def addExpectedFailure(self, t, e): propio[t.id()] = ("ok", "", "")
        def addUnexpectedSuccess(self, t): propio[t.id()] = ("fallo", "UnexpectedSuccess", "")
        def stopTest(self, t):
            super().stopTest(t)
            i, fs, p = t.id(), subs.pop(t.id(), []), propio.pop(t.id(), None)
            if fs:
                fs = ([p] if p and p[0] in ("fallo", "error") else []) + fs
                casos.append((i, "error" if any(f[0] == "error" for f in fs) else "fallo",
                              ",".join(sorted({f[1] for f in fs})), "\n".join(f[2] for f in fs)))
            elif p is None:
                no_soportado.append("%s: terminó sin resultado" % i)
            else:
                casos.append((i,) + p)
    r = Resultado()
    try:
        unittest.TestSuite(pruebas).run(r)
    except KeyboardInterrupt:
        return 4
    if no_soportado:
        for m in no_soportado:
            print("fallos_previos (unittest): no soportado: " + m, file=sys.stderr)
        return 5
    raiz_x = ET.Element("testsuites", ejecucion=ejecucion, raiz=raiz, adaptador="unittest",
                        inicio=relativo(inicio), superior=relativo(superior))
    s = ET.SubElement(raiz_x, "testsuite", name="unittest", tests=str(len(casos)))
    for i, est, tipo, msj in casos:
        cl, _, nombre = i.rpartition(".")
        c = ET.SubElement(s, "testcase", classname=cl, name=nombre)
        if est in ("fallo", "error"):
            ET.SubElement(c, "failure" if est == "fallo" else "error", type=tipo, message=msj)
        elif est == "omitida":
            ET.SubElement(c, "skipped", message=msj)
    for i in recoleccion:
        ET.SubElement(s, "recoleccion", id=str(i))
    raiz_x.set("completa", "si")
    ET.ElementTree(raiz_x).write(informe, encoding="utf-8", xml_declaration=True)
    if recoleccion:
        return 3
    return 1 if any(c[1] in ("fallo", "error") for c in casos) else 0


def relativo(ruta):
    """La ruta resuelta (enlaces incluidos) y relativa a la raíz de la ejecución: compara dónde corre la suite."""
    return os.path.relpath(os.path.realpath(ruta), os.path.realpath("."))


def parametros(datos):
    """(inicio, superior) que fijó la línea base."""
    x = ET.fromstring(datos)
    return x.get("inicio"), x.get("superior")


# --- lectura ------------------------------------------------------------------------------------------
def normaliza(msj, raiz):
    msj = msj.replace("\r\n", "\n").replace("\r", "\n")
    for r in {raiz, os.path.realpath(raiz)} - {""}:
        msj = msj.replace(r, "<raiz>")
    return "\n".join(l.rstrip() for l in msj.split("\n"))


def firma(clase, tipo, msj, raiz):
    return "%s · %s · %s" % (clase, tipo, hashlib.sha256(normaliza(msj, raiz).encode()).hexdigest()[:12])


def lee_informe(datos, ejecucion=None):
    """{id: (estado, firma)} o lanza ValueError. ejecucion=None solo para la línea base versionada."""
    x = ET.fromstring(datos)
    if x.tag != "testsuites" or x.get("completa") != "si":
        raise ValueError("el informe no está completo (sin completa=\"si\")")
    if ejecucion is not None and x.get("ejecucion") != ejecucion:
        raise ValueError("el informe no es de esta ejecución")
    if x.find(".//recoleccion") is not None:
        raise ValueError("el informe registra errores de recolección")
    raiz, res = x.get("raiz", ""), {}
    for c in x.iter("testcase"):
        i = c.get("classname", "") + "." + c.get("name", "")
        if i in res:
            raise ValueError("prueba repetida en el informe: " + i)
        f = c.find("failure") if c.find("failure") is not None else c.find("error")
        if f is not None:
            res[i] = ("falla", firma("fallo" if f.tag == "failure" else "error", f.get("type", ""), f.get("message", ""), raiz))
        elif c.find("skipped") is not None:
            res[i] = ("omitida", "")
        else:
            res[i] = ("ejecutada", "")
    return res


def tablas(texto, destinos=None):
    """(declarados {id: firma}, retiradas {id: adr}, errores) del registro; con `destinos` (dict), además
    {id: destino} de cada declarada. Es el ÚNICO lector del registro (comparador, guarda y destinos)."""
    dec, ret, errs, sec = {}, {}, [], None
    for n, l in enumerate(texto.splitlines(), 1):
        if l.startswith("## "):
            sec = {"## Fallos previos declarados": "d", "## Retiradas del inventario": "r"}.get(l.strip())
            continue
        if sec is None or not l.startswith("|"):
            continue
        celdas = [c.strip() for c in l.strip().strip("|").split("|")]
        if celdas[0] in ("Prueba", "") or set(celdas[0]) <= set("-: "):
            continue
        quita = lambda s: s.strip("`")
        i = quita(celdas[0])
        if len(celdas) < 3:
            errs.append("%s, línea %d: fila con menos de tres celdas" % (REGISTRO, n)); continue
        if not re.fullmatch(r"[A-Za-z_][\w.]*", i) or "*" in i:
            errs.append("%s, línea %d: «%s» no es un identificador exacto de prueba" % (REGISTRO, n, i)); continue
        d = dec if sec == "d" else ret
        if i in d:
            errs.append("%s, línea %d: %s está repetida" % (REGISTRO, n, i)); continue
        d[i] = quita(celdas[1]) if sec == "d" else quita(celdas[2])
        if sec == "d" and destinos is not None:
            destinos[i] = quita(celdas[2])
    return dec, ret, errs


def adr_aceptado(decisiones, adr):
    """El texto de la sección `## ADR-NNN` si su **Estado:** es `aceptada`; si no, None."""
    m = re.search(r"^## %s\b.*?(?=^## |\Z)" % re.escape(adr), decisiones, re.M | re.S)
    if m and re.search(r"^[-*][ \t]+\*\*Estado:\*\*[ \t]*aceptada[ \t]*$", m.group(0), re.M):
        return m.group(0)
    return None


def adr_decide(decisiones, adr, i):
    """None si `adr` es un ADR aceptado de decisiones.md que nombra la prueba `i` y no es retrospectivo; si no,
    el motivo. Un ADR cuyo campo **Aprobación:** empieza por `retrospectivo` documenta una decisión anterior
    al método: no decide el tratamiento de una prueba (decisiones.md, «Aceptación»). Un ADR sin el campo
    (anterior a él) se lee como antes; la guarda solo comprueba lo escrito, no autentica la aprobación."""
    texto = adr_aceptado(decisiones, adr) if re.fullmatch(r"ADR-\d{3}", adr) else None
    if texto is None:
        return "«%s», que no es un ADR en estado «aceptada» de %s (sección «## ADR-NNN» con «- **Estado:** aceptada»)" % (adr, DECISIONES)
    if re.search(r"^[-*][ \t]+\*\*Aprobación:\*\*[ \t]*`?retrospectivo\b", texto, re.M):
        return "%s, que es un registro retrospectivo (Aprobación «retrospectivo»): documenta lo vigente y no decide retirar ni tratar la prueba; eso es una decisión nueva con su aprobación" % adr
    if not re.search(r"(?<![\w.])%s(?![\w.])" % re.escape(i), texto):
        return "%s, que no nombra esa prueba: el ADR aceptado tiene que decidirla" % adr
    return None


def coherencia(base, dec, ret, decisiones):
    """Errores de origen: cada declarada falló en la línea base con su firma; cada retirada cita un ADR
    aceptado que la nombra, y ninguna prueba es a la vez fallo declarado y retirada."""
    e = []
    for i in sorted(set(dec) & set(ret)):
        e.append("%s figura a la vez como fallo previo declarado y como retirada del inventario: una retirada sale de la suite y deja de tolerarse como fallo; quita una de las dos filas" % i)
    for i, f in sorted(dec.items()):
        b = base.get(i)
        if b is None or b[0] != "falla":
            e.append("%s está declarada como fallo previo, pero no falló en la línea base inicial (%s): no es previo" % (i, LINEA_BASE))
        elif b[1] != f:
            e.append("%s: la firma declarada (%s) no es la de la línea base (%s)" % (i, f, b[1]))
    for i, adr in sorted(ret.items()):
        if i not in base:
            e.append("%s figura en las retiradas, pero no está en el inventario de la línea base" % i)
        m = adr_decide(decisiones, adr, i)
        if m:
            e.append("la retirada de %s cita %s" % (i, m))
    return e


def compara(base, dec, ret, actual):
    e = []
    for i, (est, _) in sorted(base.items()):
        if i in ret:
            continue
        if i not in actual:
            e.append("%s está en el inventario de la línea base y no aparece en esta ejecución (borrada, renombrada o no recolectada); retirarla exige una fila en «Retiradas del inventario» con su ADR" % i)
        elif est != "omitida" and actual[i][0] == "omitida":
            e.append("%s se ejecutaba en la línea base y ahora se omite" % i)
    for i, (est, f) in sorted(actual.items()):
        if i in ret:
            e.append("%s figura en las retiradas del inventario y sigue en esta ejecución (%s): retirarla es sacarla de la suite" % (i, est))
        elif est == "falla" and i not in dec:
            if base.get(i) == (est, f):
                e.append("%s falla como en la línea base y no está declarada: si es una omisión del registro, añade su fila (la línea base la demuestra)" % i)
            else:
                e.append("fallo NUEVO: %s (%s)" % (i, f))
        elif est == "falla" and dec[i] != f:
            e.append("%s falla con otra firma (%s; declarada %s): cambió el resultado" % (i, f, dec[i]))
        elif est == "ejecutada" and i in dec:
            e.append("%s está declarada como fallo previo y ahora pasa: retira su fila de %s en este mismo commit" % (i, REGISTRO))
    return e


def ejecuta(args):
    d = tempfile.mkdtemp(prefix="fallos-previos-")
    informe, ej = os.path.join(d, "informe.xml"), uuid.uuid4().hex
    cmd = [sys.executable, "-I", os.path.abspath(__file__), "_unittest", informe, ej, args.inicio, args.superior]
    rc = subprocess.run(cmd).returncode
    try:
        if rc not in (0, 1):
            raise ValueError("el ejecutor no completó la suite: clase «%s» (código %d)" % (CLASES.get(rc, "ejecutor"), rc))
        try:
            datos = open(informe, "rb").read()
        except OSError:
            raise ValueError("falta el informe de esta ejecución")
        actual = lee_informe(datos, ej)
        if not actual:
            raise ValueError("la ejecución no tiene ninguna prueba")
        if (rc == 1) != any(v[0] == "falla" for v in actual.values()):
            raise ValueError("el código del adaptador (%d) no coincide con el informe" % rc)
        return actual, datos
    finally:
        for f in os.listdir(d):
            os.remove(os.path.join(d, f))
        os.rmdir(d)


def opciones(argv):
    import argparse
    p = argparse.ArgumentParser(prog="fallos_previos.py")
    p.add_argument("modo", choices=("capturar", "comprobar"))
    p.add_argument("--adaptador", required=True, choices=("unittest",))
    p.add_argument("--inicio", default="tests")
    p.add_argument("--superior", default=".")
    return p.parse_args(argv)


def capturar(args):
    for f in (LINEA_BASE, REGISTRO):
        if os.path.lexists(f):
            print("✗ fallos_previos: %s ya existe: la línea base se captura una sola vez y no se recaptura" % f, file=sys.stderr)
            return 1
    try:
        actual, datos = ejecuta(args)
    except ValueError as e:
        print("✗ fallos_previos: no hay línea base: %s" % e, file=sys.stderr); return 1
    for f in (LINEA_BASE, REGISTRO):   # los dos directorios ANTES de escribir: nunca línea base sin registro
        os.makedirs(os.path.dirname(f), exist_ok=True)
    open(LINEA_BASE, "wb").write(datos)
    filas = ["| `%s` | %s | _pendiente: I<n> que la corrige o ADR_ |" % (i, f) for i, (e, f) in sorted(actual.items()) if e == "falla"]
    open(REGISTRO, "w", encoding="utf-8").write(
        "# Fallos previos de la adopción\n\n"
        "> Lo escribió `python3 -I scripts/fallos_previos.py capturar` desde la línea base inicial (`%s`,\n"
        "> inmutable). Una fila solo vale si esa prueba falló allí con esa firma; se retira en el commit que la\n"
        "> corrige. Ningún criterio que dependa de ellas pasa a verificado (docs/arranque-existente.md §G).\n\n"
        "## Fallos previos declarados\n\n| Prueba | Firma | Destino |\n|---|---|---|\n%s\n\n"
        "## Retiradas del inventario\n\n| Prueba | Motivo | ADR |\n|---|---|---|\n" % (LINEA_BASE, "\n".join(filas)))
    print("fallos_previos: línea base de %d pruebas, %d fallos (%s, %s)" % (len(actual), len(filas), LINEA_BASE, REGISTRO))
    return 0


def comprobar(args):
    def lee(f):
        try:
            return open(f, "rb").read()
        except OSError:
            return None
    b, r = lee(LINEA_BASE), lee(REGISTRO)
    if b is None or r is None:
        print("✗ fallos_previos: falta %s: sin línea base y registro no hay comparación (fallos_previos.py capturar)" % (LINEA_BASE if b is None else REGISTRO), file=sys.stderr)
        return 1
    try:
        base = lee_informe(b)
    except (ValueError, ET.ParseError) as e:
        print("✗ fallos_previos: la línea base no se puede leer: %s" % e, file=sys.stderr); return 1
    dec, ret, errs = tablas(r.decode("utf-8", "replace"))
    errs += coherencia(base, dec, ret, (lee(DECISIONES) or b"").decode("utf-8", "replace"))
    fijados, ahora = parametros(b), (relativo(args.inicio), relativo(args.superior))
    if None in fijados:
        errs.append("la línea base no fija dónde se ejecuta la suite (inicio y superior): no se puede comparar")
    elif fijados != ahora:
        errs.append("la suite se ejecuta en otro lugar que la línea base (inicio=%s superior=%s; la línea base fija inicio=%s superior=%s): se compararía otra copia de las pruebas" % (ahora + fijados))
    if not errs:
        try:
            actual, _ = ejecuta(args)
            errs = compara(base, dec, ret, actual)
        except (ValueError, ET.ParseError) as e:
            errs = [str(e)]
    if errs:
        for e in errs:
            print("✗ fallos_previos: " + e, file=sys.stderr)
        return 1
    if not dec:
        print("fallos_previos: sin fallos; %d pruebas ejecutadas" % len(actual))
        return 0
    print("fallos_previos: sin fallos nuevos; %d fallos previos declarados (no es una suite aprobada: sus criterios siguen pendientes)" % len(dec))
    return 2 if os.environ.get("CHECK_ESTRICTO") == "1" else 0


# --- destinos (check_docs.sh, desde F2) ------------------------------------------------------------------
def destinos(cierre):
    try:
        texto = open(REGISTRO, encoding="utf-8").read()
    except OSError:
        return 0
    dest = {}
    dec, _, e = tablas(texto, dest)
    # El lector del plan es el del método que juzga (METODO_DIR en el replay anclado), no el del árbol.
    plan = subprocess.run(["sh", os.path.join(os.environ.get("METODO_DIR") or ".", "scripts/check_docs.sh"), "plan", "docs/plan.md"],
                          capture_output=True, text=True)
    if plan.returncode != 0:
        e.append("no pude leer docs/plan.md con su parser (sh scripts/check_docs.sh plan)")
    incs = {c[1]: (c[2], c[3]) for c in (l.split() for l in plan.stdout.splitlines()) if len(c) >= 4 and c[0] == "I"}
    try:
        decisiones = open(DECISIONES, encoding="utf-8").read()
    except OSError:
        decisiones = ""
    for i in sorted(dec):
        d = dest.get(i, "")
        if cierre:
            e.append("%s sigue declarada como fallo previo al cierre (destino %s): ningún destino, tampoco un ADR, habilita una excepción al cierre; corrígela o retírala del inventario" % (i, d or "vacío"))
        elif re.fullmatch(r"I\d+", d):
            st = incs.get(d)
            if st is None:
                e.append("%s: su destino %s no existe como incremento en docs/plan.md" % (i, d))
            elif st[0] != "pendiente":
                e.append("%s: su destino %s está cerrado («- [x]») y la excepción sigue viva: el incremento que debía corregirla se cerró sin hacerlo" % (i, d))
            elif st[1] == "backlog":
                e.append("%s: su destino %s está en el backlog, no en el plan" % (i, d))
        elif d.startswith("ADR-"):
            m = adr_decide(decisiones, d, i)
            if m:
                e.append("%s: su destino cita %s" % (i, m))
        else:
            e.append("%s: destino «%s»: desde F2 cada fallo previo declarado tiene destino, un I<n> pendiente de docs/plan.md o un ADR aceptado que la nombre" % (i, d))
    for x in e:
        print(x)
    return 1 if e else 0


# --- testigo (pre-commit) -------------------------------------------------------------------------------
def testigo(ruta, ficha, raiz):
    """Valida el registro que dejó `comprobar` en esta ejecución del hook (FALLOS_PREVIOS_TESTIGO)."""
    try:
        lineas = open(ruta, encoding="utf-8").read().splitlines()
    except (OSError, UnicodeDecodeError):
        lineas = None
    if not lineas:
        print("existe docs/fallos-previos.md y scripts/check.sh no ejecutó el comparador (python3 -I scripts/fallos_previos.py comprobar …): sin él, los fallos previos no se comparan (docs/arranque-existente.md §G)."); return 1
    abiertas, codigos, e = [], [], []
    for n, l in enumerate(lineas, 1):
        m = re.fullmatch(r"inicio (\S+) (\d+) (/.*)|fin (\S+) (\d+) (-?\d+)", l)
        f = m and (m.group(1) or m.group(4))
        if not m or f != ficha:
            e.append("el registro del comparador está malformado o no es de esta ejecución (línea %d: «%s»)" % (n, l[:60])); continue
        if m.group(1):
            if m.group(2) in abiertas:
                e.append("el registro del comparador abre dos veces la llamada %s (línea %d)" % (m.group(2), n))
            if m.group(3) != os.path.realpath(raiz):
                e.append("una llamada del comparador corrió en %s, no en la raíz del candidato: se compararía otra copia de las pruebas" % m.group(3))
            abiertas.append(m.group(2))
        elif m.group(5) not in abiertas:
            e.append("el registro del comparador cierra una llamada que no abrió (línea %d)" % n)
        else:
            abiertas.remove(m.group(5)); codigos.append(int(m.group(6)))
    if not codigos and not abiertas and not e:
        e.append("el registro del comparador no tiene ninguna llamada de esta ejecución: scripts/check.sh no ejecutó el comparador")
    for p in abiertas:
        e.append("una ejecución del comparador (proceso %s) no terminó: ejecución incompleta, y scripts/check.sh terminó en 0" % p)
    e += ["el comparador de fallos previos terminó en %d y scripts/check.sh en 0: su resultado quedó oculto (p. ej. «|| true»); check.sh tiene que propagarlo" % c for c in codigos if c != 0]
    for x in e:
        print(x)
    return 1 if e else 0


# --- guarda (objetos de git) ----------------------------------------------------------------------------
def git(*a):
    return subprocess.run(["git"] + list(a), capture_output=True)


def objeto(rev, ruta):
    """bytes del archivo en <rev> (commit, árbol o INDICE), o None si no está."""
    r = git("show", (":" if rev == "INDICE" else rev + ":") + ruta)
    return r.stdout if r.returncode == 0 else None


def guarda(b, c):
    if c == "INDICE":
        mh = git("rev-parse", "--git-path", "MERGE_HEAD").stdout.decode().strip()
        padres = [b] + (open(mh).read().split() if mh and os.path.isfile(mh) else [])
    else:
        r = git("rev-list", "--parents", "-n", "1", c)
        if r.returncode != 0:
            print("✗ fallos_previos: no pude leer los padres de %s" % c, file=sys.stderr); return 2
        padres = r.stdout.decode().split()[1:] or [b]
    e = []
    lb_c, reg_c = objeto(c, LINEA_BASE), objeto(c, REGISTRO)
    lb_p = [(p, objeto(p, LINEA_BASE)) for p in padres]
    for p, lb in lb_p:
        if lb is not None and lb_c != lb:
            e.append("%s ya estaba versionada en %s y aquí %s: la línea base inicial es inmutable" % (LINEA_BASE, p[:12], "desaparece" if lb_c is None else "cambia"))
        if objeto(p, REGISTRO) is not None and reg_c is None:
            e.append("%s estaba en %s y aquí desaparece: el registro de fallos previos no se borra" % (REGISTRO, p[:12]))
    # POR PADRE: un padre sin línea base cuya historia ya tiene un `Ref: F2` la recibe tarde, aunque otro
    # padre (una rama abierta antes del F2, o huérfana) la traiga.
    if lb_c is not None:
        for p, lb in lb_p:
            if lb is not None:
                continue
            h = git("log", "-1", "--format=%H", "-E", "--grep=" + F2_GREP, p)
            if h.returncode != 0:
                e.append("no pude leer la historia de %s para buscar un 'Ref: F2'" % p[:12]); break
            if h.stdout.strip():
                e.append("%s llega a %s, cuya historia ya tiene un commit 'Ref: F2' (%s): solo la línea base INICIAL de la adopción puede declarar fallos previos (se busca en TODA la historia, también la anterior a la base del método)" % (LINEA_BASE, p[:12], h.stdout.decode().strip()[:12]))
                break
    if reg_c is not None:
        if lb_c is None:
            e.append("%s sin %s: una fila solo vale contra la línea base inicial" % (REGISTRO, LINEA_BASE))
        else:
            try:
                base = lee_informe(lb_c)
                dec, ret, errs = tablas(reg_c.decode("utf-8", "replace"))
                e += errs + coherencia(base, dec, ret, (objeto(c, DECISIONES) or b"").decode("utf-8", "replace"))
            except (ValueError, ET.ParseError) as x:
                e.append("la línea base no se puede leer: %s" % x)
    for x in e:
        print("✗ fallos_previos: " + x, file=sys.stderr)
    return 1 if e else 0


def main(argv):
    if argv[:1] == ["_unittest"] and len(argv) == 5:
        return adaptador_unittest(*argv[1:])
    if argv[:1] == ["testigo"]:
        if len(argv) != 4:
            print("uso: fallos_previos.py testigo <ruta> <ficha> <raíz>", file=sys.stderr); return 2
        return testigo(argv[1], argv[2], argv[3])
    if argv[:1] == ["destinos"]:
        if argv[1:] not in ([], ["--cierre"]):
            print("uso: fallos_previos.py destinos [--cierre]", file=sys.stderr); return 2
        return destinos(argv[1:] == ["--cierre"])
    if argv[:1] == ["guarda"]:
        if len(argv) != 3:
            print("uso: fallos_previos.py guarda <base> <candidato|INDICE>", file=sys.stderr); return 2
        return guarda(argv[1], argv[2])
    ruta, ficha = os.environ.get("FALLOS_PREVIOS_TESTIGO"), os.environ.get("FALLOS_PREVIOS_FICHA", "")

    def anota(s):
        if ruta and argv[:1] == ["comprobar"]:
            with open(ruta, "a") as t:
                t.write(s + "\n")
    anota("inicio %s %d %s" % (ficha, os.getpid(), os.path.realpath(".")))   # antes de leer opciones: una llamada que cae deja «inicio» sin «fin»
    a = opciones(argv)
    rc = capturar(a) if a.modo == "capturar" else comprobar(a)
    anota("fin %s %d %d" % (ficha, os.getpid(), rc))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
