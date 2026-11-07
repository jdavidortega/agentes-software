#!/usr/bin/env python3
"""Aviso de inicio de sesión (hook SessionStart de Claude Code, registrado en .claude/settings.json).

Ejecuta el doctor (scripts/check_docs.sh) con plazo y resume el estado en ocho líneas como máximo. Es un AVISO:
no es otra entrada al método (remite a README.md, docs/arranque*.md y docs/estado.md) ni sustituye la lectura
que pide AGENTS.md §0. No modifica documentos, configuración de git ni archivos del producto, y no repara nada.

Vigilancia: no tiene una propia. El doctor corre bajo scripts/suite.py correr (M02/M13): plazo con guardián
desacoplado (se cumple aunque este aviso muera o se interrumpa), señales solo al grupo cuya propiedad está
demostrada, ps con plazo y «no pude comprobarlo» distinto de «no hay procesos». Con un registro propio dentro del
temporal del aviso: no escribe en .git, no choca con una suite del proyecto ni la anida. Al doctor le llega el
entorno sin variables SUITE_*, así que su resultado no cambia por correr vigilado.
- Resultado: PASA solo si la ejecución quedó «aprobada»; «fallida» con salida 1 es FALLA con su primera causa;
  cualquier otro estado, salida o error es «sin veredicto».
- Este aviso solo espera a su propio lanzador (un hijo aún sin recoger: su identidad está demostrada), siempre con
  límite. Si no responde, o el aviso recibe una interrupción, le pide terminar y no espera más de lo acordado.
- El temporal del aviso se borra solo cuando suite.py demuestra que no quedó nada abierto; si no, se conserva y se
  informa su ruta. Un proceso que abandona el grupo a propósito (setsid) escapa: es el límite declarado de suite.py.
- Automatiza una invocación: no prueba que el agente entienda el estado ni que no lo eluda. Su salida puede
  añadirse al contexto de la sesión.

Plazo del doctor: 30 s (METODO_INICIO_PLAZO lo cambia, para las pruebas del plazo).
"""
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

PLAZO = float(os.environ.get("METODO_INICIO_PLAZO", "30"))
MARGEN = 20.0      # espera máxima del lanzador más allá del plazo del doctor
GRACIA = 5.0       # espera máxima tras pedirle terminar
MAX_LINEAS = 8
CERRADOS = {"aprobada", "fallida", "excedida", "terminada", "interrumpida"}


class Interrumpido(Exception):
    pass


def raiz():
    r = os.environ.get("CLAUDE_PROJECT_DIR")
    if r and os.path.isdir(r):
        return os.path.realpath(r)
    return os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def leer(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def tipo_de_sesion(r):
    estado = leer(os.path.join(r, "docs", "estado.md"))
    if estado is None:
        return "No puedo leer docs/estado.md: sin estado no hay reanudación; entra por README.md §Cómo usarla."
    m = re.search(r"Fase actual:\**\s*(F[0-9_]+)([^\n]*)", estado)
    fase = m.group(1) if m else ""
    if re.fullmatch(r"F[1-5]", fase):
        resto = re.sub(r"\s+", " ", m.group(2)).strip(" ·")
        return ("Proyecto en %s%s." % (fase, (" · " + resto[:90]) if resto else ""))
    if os.path.exists(os.path.join(r, "contexto", "adopcion.md")):
        return "Adopción en curso (contexto/adopcion.md): sigue docs/arranque-existente.md."
    return "Plantilla o proyecto sin iniciar: entra por README.md §Cómo usarla y docs/arranque.md."


def doctor(r):
    chk, sp = os.path.join(r, "scripts", "check_docs.sh"), os.path.join(r, "scripts", "suite.py")
    for f in (chk, sp):
        if not os.path.isfile(f):
            return ["Doctor: sin veredicto: no existe %s." % os.path.relpath(f, r)]
    tmp = tempfile.mkdtemp(prefix="metodo-inicio-")
    reg, inf, vig = os.path.join(tmp, "registro"), os.path.join(tmp, "informe"), os.path.join(tmp, "vigilante.txt")
    os.mkdir(reg)
    env = {k: v for k, v in os.environ.items() if not k.startswith("SUITE_")}
    for k in ("METODO_DIR", "CIERRE_CUBRE", "CIERRE_EXCLUYE", "FASE_PREVIA", "FASE_HISTORICA"):
        env.pop(k, None)
    env.update(TMPDIR=tmp, SUITE_REGISTRO=reg)
    cmd = ["python3", "-I", sp, "correr", "--plazo", "%g" % PLAZO, "--dir", r, "--informe", inf, "--",
           "env", "-u", "SUITE_REGISTRO", "-u", "SUITE_ID", "-u", "SUITE_PLAZO", "-u", "SUITE_PROPIA", "sh", chk]
    lineas, conservar, motivo, inicio = [], False, "", time.monotonic()

    def interrumpe(signum, frame):
        raise Interrumpido(signal.Signals(signum).name)
    previos = {s: signal.signal(s, interrumpe) for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)}
    proc = None
    try:
        with open(vig, "wb") as f:
            proc = subprocess.Popen(cmd, cwd=r, env=env, stdin=subprocess.DEVNULL, stdout=f, stderr=subprocess.STDOUT)
        try:
            proc.wait(timeout=PLAZO + MARGEN)
        except subprocess.TimeoutExpired:
            conservar, motivo = True, "el vigilante no terminó en %g s" % (PLAZO + MARGEN)
            para(proc)
        except Interrumpido as e:
            conservar, motivo = True, "aviso interrumpido (%s); el guardián de suite.py sigue aplicando el plazo" % e
            para(proc)
    except OSError as e:
        return limpia(tmp, True, ["Doctor: sin veredicto: no pude lanzar el vigilante (%s)." % e], "no se lanzó")
    finally:
        for s, h in previos.items():
            signal.signal(s, h)
    dur = time.monotonic() - inicio
    m = re.search(r"id=(\S+) estado=(\S+) rc=(\S*)", leer(inf) or "")
    if conservar or not m:
        lineas.append("Doctor: sin veredicto: %s." % (motivo or "el vigilante no dejó informe (salida %s)" % proc.returncode))
        return limpia(tmp, True, lineas, motivo or "sin informe")
    rid, estado, rc = m.group(1), m.group(2), m.group(3)
    log = ""
    for d in os.listdir(tmp):
        if d.startswith("suite-%s-" % rid):
            log = leer(os.path.join(tmp, d, "salida.log")) or ""
    if estado == "aprobada":
        lineas.append("Doctor: PASA (%.1f s)." % dur)
    elif estado == "fallida" and rc == "1":
        causas = [re.sub(r"^\s*✗\s*(check_docs:\s*)?", "", l).strip() for l in log.splitlines() if "✗" in l]
        lineas.append("Doctor: FALLA (%.1f s): %s" % (dur, causas[0][:160] if causas else "sin causa legible"))
    elif estado == "excedida":
        lineas.append("Doctor: sin veredicto: plazo de %g s agotado; suite.py terminó su grupo de procesos." % PLAZO)
    else:
        lineas.append("Doctor: sin veredicto (estado %s, salida %s)." % (estado, rc or "?"))
    if "ejecuciones de la suite abiertas" in log:
        lineas.append("Hay ejecuciones de la suite abiertas: python3 scripts/suite.py estado.")
    # Solo se borra lo que suite.py demuestra cerrado: su informe en un estado cerrado. Una salida 75 (incompleta,
    # propiedad no demostrable) no deja informe o lo deja «abierta»: entonces se conserva. El registro es propio
    # y solo contiene esta ejecución, así que no hace falta otra consulta.
    cerrado = estado in CERRADOS and proc.returncode != 75
    motivo = "" if cerrado else "la ejecución no quedó cerrada (estado %s, salida %s)" % (estado, proc.returncode)
    return limpia(tmp, not cerrado, lineas, motivo)


def para(proc):
    """Pide terminar al lanzador: un hijo aún sin recoger, así que su PID es suyo. Espera con límite."""
    for sig in (signal.SIGTERM, signal.SIGKILL):
        if proc.poll() is not None:
            return
        try:
            proc.send_signal(sig)
        except OSError:
            return
        try:
            proc.wait(timeout=GRACIA)
            return
        except subprocess.TimeoutExpired:
            pass


def limpia(tmp, conservar, lineas, motivo):
    if conservar:
        lineas.append("Conservo el temporal %s: %s." % (tmp, motivo))
        return lineas
    shutil.rmtree(tmp, ignore_errors=True)
    if os.path.exists(tmp):
        lineas.append("No pude borrar el temporal del doctor: %s." % tmp)
    return lineas


def main():
    r = raiz()
    lineas = ["Método · aviso de inicio de sesión (no sustituye la lectura de docs/estado.md)."]
    lineas.append(tipo_de_sesion(r))
    lineas += doctor(r)
    lineas.append("Siguiente: lee docs/estado.md y docs/convenciones.md (AGENTS.md §0).")
    print("\n".join(lineas[:MAX_LINEAS]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
