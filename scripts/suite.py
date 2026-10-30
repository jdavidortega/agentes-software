#!/usr/bin/env python3
"""Watched suite runs: no run goes unnoticed, none outlives its deadline (docs/convenciones.md §Recursos).

    python3 scripts/suite.py correr --plazo SEG [--dir D] [--informe F] -- <command...>
    python3 scripts/suite.py estado [<id>] [--abiertas]
    python3 scripts/suite.py terminar <id>

Guarantees:
- REGISTRY: each run leaves a record (id, command, start, deadline, launcher, guard, process group,
  run folder) in SUITE_REGISTRO or, by default, in <git common dir of --dir>/suite-runs: shared by
  every worktree, outside the reviewable tree. A copy without .git and without SUITE_REGISTRO stops.
  Records change under an exclusive flock (the kernel releases it when its holder dies, so a stale
  lock never has to be taken over) and are replaced atomically. Local filesystems; not NFS.
- ONE AT A TIME: `correr` refuses (exit 75) while another run is open, and refuses a nested call
  (SUITE_ID already set). A run with no process left (forced termination) is recovered first:
  its record is closed and its temp folder deleted. Recovery needs PROOF of absence: if `ps` fails
  ("no pude comprobarlo" is not "no existe"), nothing is recovered, signalled or deleted.
- DEADLINE, ALWAYS: a single mode. At 80 % the launcher warns; at 100 % the guard ends the run
  (exit 124, state excedida). The deadline is mandatory: --plazo, else SUITE_PLAZO, else the project's
  single source, the line «- **Plazo de la suite:** N s» of docs/convenciones.md in --dir.
- DETACHED GUARD: the suite runs under a guard in its own session, so the deadline holds even if
  the launcher dies (an assistant's tool timing out, the editor closing). The suite leads its own
  process group. The guard detects its exit WITHOUT reaping it (waitid WNOWAIT): while the leader
  is an unreaped child, its group id cannot be reused, so signalling the group is provably ours.
  It ends the whole group (TERM, then KILL) also when the suite exits leaving descendants behind.
  If any survive (or cannot be checked), the run is INCOMPLETA: never aprobada; the record stays
  open, blocking new runs, and its temps are kept until those processes are gone.
- PROVABLE OWNERSHIP OR NOTHING: without the guard, the group is signalled only while its leader
  is alive with the recorded start time. Leader gone and members alive = ownership not provable:
  report them, send no signal, clean nothing, keep blocking.
- OWN TEMPS: TMPDIR/TMP/TEMP point to a folder of the run (suite-<id>-*), deleted on close. Tools
  that ignore those variables are not covered: on macOS `mktemp -d` without a template (it uses the
  per-user temp dir; `mktemp -d "$TMPDIR/x.XXXXXX"` does honor it), a configured basetemp, caches
  under $HOME, container volumes. The log (SUITE_LOG_MAX bytes, two rotating halves) stays local; the last 10 closed
  runs keep theirs and older ones are pruned, only folders whose name proves they belong to it.

Exit: 0 aprobada; the suite's code if fallida; 124 excedida; 130 terminada/interrumpida;
75 blocked (another run open, nested call, unprovable ownership, incomplete ending); 2 usage. --informe writes
`id= estado= rc=` so a caller never confuses those codes with the suite's own.
Verified on macOS; POSIX only. A process that leaves the group on purpose (setsid, a daemon) escapes.
"""
import argparse
import fcntl
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

OPEN = "abierta"
STATES = {OPEN, "aprobada", "fallida", "excedida", "terminada", "interrumpida"}
EXIT_EXCEEDED, EXIT_STOPPED, EXIT_BLOCKED = 124, 130, 75
LOG_MAX = int(os.environ.get("SUITE_LOG_MAX", "2000000"))
KEEP_CLOSED = 10
WARN_AT = 0.8
GRACE = 5.0


def say(msg: str) -> None:
    print(f"suite: {msg}", file=sys.stderr, flush=True)


def die(msg: str, code: int = 2) -> "NoReturn":
    say(msg)
    sys.exit(code)


# --- processes -----------------------------------------------------------------------------
class Unverifiable(Exception):
    """A process query failed. Absence is not proven: nothing may be recovered, signalled or deleted."""


def ps(*args: str) -> str:
    try:
        out = subprocess.run(["ps", *args], capture_output=True, text=True)
    except OSError as exc:
        raise Unverifiable(f"ps: {exc}") from exc
    if out.returncode or not out.stdout.strip():  # every query here names a process that should exist
        raise Unverifiable(f"ps {' '.join(args)}: {out.stderr.strip() or f'rc={out.returncode}, sin salida'}")
    return out.stdout


def exists(pid: int) -> bool:
    """kill 0 answers without ps: ESRCH proves absence, anything else is presence."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def started(pid: int | None) -> str | None:
    """Start time of a live (non-zombie) process: with the pid it names the process unequivocally.
    None only when absence is proven; Unverifiable when ps cannot tell."""
    if not pid or not exists(pid):
        return None
    try:
        out = ps("-o", "stat=,lstart=", "-p", str(pid)).split()
    except Unverifiable:
        if not exists(pid):
            return None  # it died between both checks
        raise
    return None if out[0].startswith("Z") else " ".join(out[1:])


def same(pid: int | None, start: str | None) -> bool:
    return bool(pid and start) and started(pid) == start


def members(pgid: int | None) -> list[str]:
    """Live (non-zombie) processes of the group, as `pid start command` lines."""
    if not pgid:
        return []
    found = []
    for line in ps("-A", "-o", "pid=,pgid=,stat=,lstart=,command=").splitlines():
        f = line.split()
        if len(f) >= 8 and f[1] == str(pgid) and not f[2].startswith("Z"):
            found.append(f"{f[0]} {' '.join(f[3:8])} {' '.join(f[8:])}".strip())
    return found


def survivors(pgid: int | None) -> list[str]:
    """members(), where a failed query counts as a survivor: emptiness must be proven."""
    try:
        return members(pgid)
    except Unverifiable as exc:
        return [f"no comprobable ({exc})"]


def end_group(pgid: int) -> list[str]:
    """TERM, then KILL, the group; returns the members still alive afterwards (or not checkable)."""
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pgid, sig)
        except (ProcessLookupError, PermissionError):
            pass  # EPERM: only the unreaped leader is left
        limit = time.time() + GRACE
        while time.time() < limit:
            if not survivors(pgid):
                return []
            time.sleep(0.1)
    return survivors(pgid)


# --- registry ------------------------------------------------------------------------------
def registry(workdir: Path) -> Path:
    env = os.environ.get("SUITE_REGISTRO")
    if env:
        reg = Path(env)
        if not reg.is_absolute():
            die(f"SUITE_REGISTRO debe ser una ruta absoluta (recibí {env!r})")
    else:
        out = subprocess.run(["git", "-C", str(workdir), "rev-parse", "--git-common-dir"], capture_output=True, text=True)
        if out.returncode:
            die(f"{workdir} no está en un repositorio git y no hay SUITE_REGISTRO: no sé dónde registrar la "
                "ejecución. Una copia (instantánea, sabotaje) recibe SUITE_REGISTRO del repositorio real.")
        reg = (workdir / out.stdout.strip()).resolve() / "suite-runs"  # relative to -C when not absolute
    reg.mkdir(parents=True, exist_ok=True)
    return reg


class Lock:
    """Exclusive flock on the registry, reentrant within the process. The kernel releases it when the
    holder dies, so there is no stale lock to take over and no takeover that could displace a live one."""
    depth, fh = 0, None

    def __init__(self, reg: Path):
        self.path = reg / ".cerrojo.lck"

    def __enter__(self):
        if Lock.depth:
            Lock.depth += 1
            return self
        fh = open(self.path, "a")
        limit = time.time() + 30
        while True:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.time() > limit:
                    fh.close()
                    die(f"el cerrojo del registro sigue tomado por un proceso vivo tras 30 s: {self.path}")
                time.sleep(0.05)
        Lock.depth, Lock.fh = 1, fh
        return self

    def __exit__(self, *_):
        Lock.depth -= 1
        if Lock.depth == 0:
            Lock.fh.close()  # closing releases the lock
            Lock.fh = None


def record_path(reg: Path, rid: str) -> Path:
    return reg / f"{rid}.json"


def load(reg: Path, rid: str) -> dict:
    return json.loads(record_path(reg, rid).read_text())


def save(reg: Path, rec: dict) -> None:
    tmp = reg / f".{rec['id']}.{os.getpid()}.tmp"
    tmp.write_text(json.dumps(rec, ensure_ascii=False, indent=1))
    os.replace(tmp, record_path(reg, rec["id"]))


def update(reg: Path, rid: str, **changes) -> dict:
    with Lock(reg):
        rec = load(reg, rid)
        rec.update(changes)
        save(reg, rec)
        return rec


def records(reg: Path) -> list[dict]:
    """Every record. A registry that cannot be listed or read, or a damaged record, is Unverifiable:
    never an empty registry (glob would return [] in silence on an unlistable folder)."""
    found = []
    try:
        for p in reg.iterdir():
            if p.name.endswith(".json"):
                rec = json.loads(p.read_text())
                if (not isinstance(rec, dict) or not {"id", "estado", "inicio", "dir"} <= rec.keys()
                        or rec["estado"] not in STATES):
                    raise ValueError(f"{p.name}: registro dañado")
                found.append(rec)
    except (OSError, ValueError) as exc:
        raise Unverifiable(f"registro {reg} ilegible o dañado: {exc}") from exc
    return sorted(found, key=lambda r: r["inicio"])


def owned_folder(rec: dict) -> Path | None:
    """The run folder, only if its name proves it belongs to this run."""
    folder = Path(rec.get("carpeta") or "")
    return folder if folder.name.startswith(f"suite-{rec['id']}-") and folder.is_dir() else None


def situation(rec: dict) -> str:
    """abierta → en curso | huérfana | incierta | abandonada | no comprobable; otherwise the closed state."""
    if rec["estado"] != OPEN:
        return rec["estado"]
    try:
        return open_situation(rec)
    except Unverifiable:
        return "no comprobable"  # like incierta: no signal, no cleanup, keeps blocking


def open_situation(rec: dict) -> str:
    if same(rec.get("guardia"), rec.get("guardia_inicio")):
        return "en curso"
    if not rec.get("guardia") and same(rec.get("lanzador"), rec.get("lanzador_inicio")):
        return "en curso"  # launcher still starting the guard
    if same(rec.get("grupo"), rec.get("grupo_inicio")):
        return "huérfana"  # leader alive and provably ours: the group can be ended
    return "incierta" if members(rec.get("grupo")) else "abandonada"


# --- log -----------------------------------------------------------------------------------
class Log:
    """Two rotating halves: salida.log (current) and salida.log.1 (previous)."""

    def __init__(self, path: Path):
        self.path, self.half = path, max(LOG_MAX // 2, 4096)
        self.fh = open(path, "ab")

    def write(self, data: bytes) -> None:
        while data:
            room = self.half - self.fh.tell()
            self.fh.write(data[:room])
            self.fh.flush()
            data = data[room:]
            if self.fh.tell() >= self.half:
                self.fh.close()
                os.replace(self.path, self.path.with_name(self.path.name + ".1"))
                self.fh = open(self.path, "ab")


def last_line(folder: Path | None) -> tuple[str, float | None]:
    """Last non-empty output line and its age in seconds (the run's sign of life)."""
    if not folder:
        return "", None
    for name in ("salida.log", "salida.log.1"):
        p = folder / name
        try:
            with open(p, "rb") as fh:
                fh.seek(max(0, p.stat().st_size - 4096))
                lines = [l for l in fh.read().decode("utf-8", "replace").splitlines() if l.strip()]
            if lines:
                return lines[-1].strip()[:160], time.time() - p.stat().st_mtime
        except OSError:
            continue
    return "", None


# --- closing -------------------------------------------------------------------------------
def close(reg: Path, rid: str, state: str, rc: int | None, **extra) -> dict:
    """Close the record and delete the run's temp folder; the log stays (pruned later)."""
    with Lock(reg):
        rec = load(reg, rid)
        folder = owned_folder(rec)
        line, _ = last_line(folder)
        if folder:
            shutil.rmtree(folder / "tmp", ignore_errors=True)
        rec.update(estado=state, rc=rc, fin=time.time(), ultima=line, **extra)
        save(reg, rec)
        prune(reg)
        return rec


def prune(reg: Path) -> None:
    try:
        found = records(reg)
    except Unverifiable:
        return  # nothing is deleted on an unreadable registry
    closed = sorted((r for r in found if r["estado"] != OPEN), key=lambda r: r.get("fin") or 0)
    for rec in closed[:-KEEP_CLOSED]:
        folder = owned_folder(rec)
        if folder:
            shutil.rmtree(folder, ignore_errors=True)
        record_path(reg, rec["id"]).unlink(missing_ok=True)


def recover(reg: Path, rec: dict) -> None:
    say(f"recupero la ejecución {rec['id']}: ningún proceso suyo sigue vivo (terminación forzada); "
        "cierro su registro y borro sus temporales")
    close(reg, rec["id"], "interrumpida", None, recuperada=True)


def describe(rec: dict) -> str:
    now = time.time()
    sit = situation(rec)
    line, age = last_line(owned_folder(rec))
    if rec["estado"] == OPEN:
        head = f"{rec['id']}  {sit}  {now - rec['inicio']:.0f}s de {rec['plazo']}s"
    else:
        head = f"{rec['id']}  {sit}  rc={rec.get('rc')}  {(rec.get('fin') or now) - rec['inicio']:.0f}s"
    out = [head, f"    comando: {' '.join(rec['comando'])}  (en {rec['dir']})"]
    if line:
        out.append(f"    última salida{f' hace {age:.0f}s' if age is not None else ''}: «{line}»")
    elif rec.get("ultima"):
        out.append(f"    última salida: «{rec['ultima']}»")
    out.append(f"    carpeta: {rec.get('carpeta')}")
    if rec.get("incompleta"):
        out.append(f"    terminación INCOMPLETA: acabó como {rec['incompleta']} (rc={rec.get('rc')}), pero quedaron "
                   f"procesos de su grupo vivos tras TERM y KILL: {rec.get('restos')}")
    if sit in ("huérfana", "incierta"):
        alive = survivors(rec.get("grupo"))
        out.append(f"    procesos vivos del grupo {rec.get('grupo')}: {len(alive)}")
        out += [f"      {m}" for m in alive[:10]]
    if sit == "incierta":
        out.append("    pertenencia NO demostrable (el líder ya no existe): no se envía ninguna señal ni se limpia.")
        out.append("    Comprueba esos procesos y termínalos a mano; luego `correr` recupera el registro.")
    if sit == "no comprobable":
        out.append("    no pude consultar los procesos (ps falló): su ausencia no está demostrada, así que no se "
                   "envía ninguna señal ni se limpia. Reintenta cuando ps funcione.")
    return "\n".join(out)


# --- guard (detached) ------------------------------------------------------------------------
def guard(reg: Path, rid: str) -> None:
    rec = load(reg, rid)
    folder = Path(rec["carpeta"])
    env = dict(os.environ, SUITE_ID=rid, TMPDIR=str(folder / "tmp"), TMP=str(folder / "tmp"), TEMP=str(folder / "tmp"))
    log = Log(folder / "salida.log")
    try:
        proc = subprocess.Popen(rec["comando"], cwd=rec["dir"], env=env, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    except OSError as exc:
        log.write(f"suite: no pude lanzar el comando: {exc}\n".encode())
        close(reg, rid, "fallida", 127)
        return
    try:
        leader = started(proc.pid)
    except Unverifiable:
        leader = None  # without its start time the leader is never signalled from outside the guard
    update(reg, rid, grupo=proc.pid, grupo_inicio=leader)
    reader = threading.Thread(target=lambda: [log.write(c) for c in iter(lambda: proc.stdout.read1(65536), b"")],
                              daemon=True)
    reader.start()
    stop: list[str] = []
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, lambda *_: stop.append("interrumpida"))
    ending, warned = None, False
    while True:
        # Exit detected WITHOUT reaping: the leader stays a zombie child, so its group id is ours.
        if os.waitid(os.P_PID, proc.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT):
            break
        rec = load(reg, rid)
        elapsed = time.time() - rec["inicio"]
        if stop:
            ending = stop[0]
        elif rec.get("orden"):
            ending = rec["orden"]  # terminada (terminar) or interrumpida (the launcher was interrupted)
        elif elapsed >= rec["plazo"]:
            ending = "excedida"
        elif not warned and elapsed >= WARN_AT * rec["plazo"]:
            warned = True
            update(reg, rid, aviso=True)
        if ending:
            break
        time.sleep(0.2)
    left = end_group(proc.pid)  # descendants that outlive the leader die with the run
    try:
        rc = proc.wait(timeout=GRACE)
    except subprocess.TimeoutExpired:  # the leader survived even KILL: never wait forever
        rc, left = None, left or survivors(proc.pid)
    reader.join(timeout=GRACE)
    state = ending or ("aprobada" if rc == 0 else "fallida")
    if left:  # not over while processes of the run live: keep it open (blocking) and keep its temps
        update(reg, rid, incompleta=state, rc=rc, restos=left)
        return
    close(reg, rid, state, rc)


# --- launcher ------------------------------------------------------------------------------
class Interrupted(Exception):
    pass


def follow(reg: Path, rid: str, guard_proc: subprocess.Popen) -> dict:
    """Stream the log to stdout until the record closes; warn once at 80 % of the deadline."""
    rec = load(reg, rid)
    path = Path(rec["carpeta"]) / "salida.log"
    fh = open(path, "rb")
    warned = False

    def pump() -> None:
        nonlocal fh
        while True:
            data = fh.read(65536)
            if data:
                sys.stdout.buffer.write(data)
                sys.stdout.flush()
                continue
            try:  # rotated: finish the old half (already read), then follow the new file
                if os.stat(path).st_ino != os.fstat(fh.fileno()).st_ino:
                    fh.close()
                    fh = open(path, "rb")
                    continue
            except OSError:
                pass
            return

    while True:
        guard_proc.poll()
        pump()
        rec = load(reg, rid)
        if rec["estado"] != OPEN or rec.get("incompleta"):
            pump()
            return rec
        if rec.get("aviso") and not warned:
            warned = True
            line, age = last_line(owned_folder(rec))
            say(f"ejecución {rid}: superó el {WARN_AT:.0%} del plazo ({time.time() - rec['inicio']:.0f}s de "
                f"{rec['plazo']}s); al vencer se termina. Última salida"
                f"{f' hace {age:.0f}s' if age is not None else ''}: «{line}». "
                f"Para terminarla antes: python3 scripts/suite.py terminar {rid}")
        if situation(rec) not in ("en curso", "no comprobable"):  # unverifiable: ask again, never act on it
            say(f"el guardián de la ejecución {rid} desapareció sin cerrarla")
            return terminate(reg, rid, state="interrumpida") or load(reg, rid)
        time.sleep(0.2)


def exit_code(rec: dict) -> int:
    state, rc = rec["estado"], rec.get("rc")
    if state == "aprobada":
        return 0
    if state == "fallida":
        return rc if rc and rc > 0 else 128 + abs(rc or 1)
    if state == "excedida":
        return EXIT_EXCEEDED
    if state in ("terminada", "interrumpida"):
        return EXIT_STOPPED
    return EXIT_BLOCKED  # still open: ownership not provable


def report(path: str | None, rid: str, state: str, rc) -> None:
    if path:
        Path(path).write_text(f"id={rid} estado={state} rc={'' if rc is None else rc}\n")


DEADLINE_LINE = re.compile(r"^\s*-\s*\*\*Plazo de la suite:\*\*\s*(\S+?)\s*s\b", re.MULTILINE)


def deadline_of(given: str | None, workdir: Path) -> int:
    """--plazo, else SUITE_PLAZO, else the project's single source: docs/convenciones.md of --dir."""
    for source, value in (("--plazo", given), ("SUITE_PLAZO", os.environ.get("SUITE_PLAZO"))):
        if value:
            if not value.isdigit() or int(value) <= 0:
                die(f"plazo inválido en {source} ({value!r}): segundos enteros positivos")
            return int(value)
    try:
        found = DEADLINE_LINE.search((workdir / "docs" / "convenciones.md").read_text())
    except OSError:
        found = None
    if found and found.group(1).isdigit() and int(found.group(1)) > 0:
        return int(found.group(1))
    die("falta el plazo (obligatorio): --plazo SEG, SUITE_PLAZO o la línea «- **Plazo de la suite:** N s» "
        f"de docs/convenciones.md §Comandos clave (en {workdir})")


def run(args) -> int:
    if os.environ.get("SUITE_ID"):
        report(args.informe, os.environ["SUITE_ID"], "anidada", None)
        die(f"invocación anidada: ya estás dentro de la ejecución {os.environ['SUITE_ID']}. "
            "Una suite no lanza otra; córrela por separado cuando esta termine.", EXIT_BLOCKED)
    command = args.comando[1:] if args.comando[:1] == ["--"] else args.comando
    if not command:
        die("falta el comando: correr --plazo SEG -- <comando...>")
    workdir = Path(args.dir or ".").resolve()
    if not workdir.is_dir():
        die(f"--dir no es una carpeta: {workdir}")
    deadline = deadline_of(args.plazo, workdir)
    reg = registry(workdir)
    rid = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + "-" + secrets.token_hex(2)
    with Lock(reg):
        busy = []
        try:
            found = records(reg)
        except Unverifiable:
            report(args.informe, rid, "no-comprobable", None)
            raise
        for rec in found:
            if rec["estado"] != OPEN:
                continue
            if situation(rec) == "abandonada":
                recover(reg, rec)
            else:
                busy.append(rec)
        if busy:
            report(args.informe, rid, "bloqueada", None)
            say("hay otra ejecución de la suite abierta; no lanzo otra hasta que se decida qué hacer con ella:")
            for rec in busy:
                print(describe(rec), file=sys.stderr)
            say("consulta: python3 scripts/suite.py estado <id>   |   termina: python3 scripts/suite.py terminar <id>")
            return EXIT_BLOCKED
        me = started(os.getpid())  # before creating anything: unverifiable here leaves no trace
        folder = Path(tempfile.mkdtemp(prefix=f"suite-{rid}-"))
        (folder / "tmp").mkdir()
        (folder / "salida.log").touch()
        rec = {"id": rid, "estado": OPEN, "comando": command, "dir": str(workdir), "plazo": int(deadline),
               "inicio": time.time(), "lanzador": os.getpid(), "lanzador_inicio": me,
               "carpeta": str(folder)}
        save(reg, rec)
        guard_proc = subprocess.Popen([sys.executable, "-I", os.path.abspath(__file__), "_guardia", str(reg), rid],
                                      start_new_session=True, stdin=subprocess.DEVNULL,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        rec.update(guardia=guard_proc.pid, guardia_inicio=started(guard_proc.pid))
        save(reg, rec)
    say(f"ejecución {rid} (plazo {deadline}s; registro {reg}). Estado: python3 scripts/suite.py estado {rid}")

    def interrupt(*_):
        raise Interrupted()

    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, interrupt)
    try:
        final = follow(reg, rid, guard_proc)
    except Interrupted:
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, signal.SIG_IGN)
        say(f"interrumpida: termino la ejecución {rid}")
        final = terminate(reg, rid, state="interrumpida") or load(reg, rid)
    code = exit_code(final)
    state = final["estado"] if final["estado"] != OPEN else ("incompleta" if final.get("incompleta") else OPEN)
    report(args.informe, rid, state, final.get("rc"))
    dur = (final.get("fin") or time.time()) - final["inicio"]
    folder = owned_folder(final)
    log = f"; log: {folder / 'salida.log'}" if folder else ""
    if final.get("incompleta"):
        say(f"ejecución {rid} INCOMPLETA: acabó como {final['incompleta']} (rc={final.get('rc')}), pero quedaron "
            f"procesos de su grupo vivos tras TERM y KILL: {final.get('restos')}. No cuenta como aprobada; el "
            f"registro sigue abierto y bloquea nuevas ejecuciones, y sus temporales se conservan. "
            f"Revisa: python3 scripts/suite.py estado {rid}")
    elif final["estado"] == "excedida":
        say(f"ejecución {rid} EXCEDIDA: no terminó en {final['plazo']}s y se terminó su grupo de procesos. "
            f"No es un fallo de pruebas sino de tiempo; no cuenta como aprobada. "
            f"Última salida: «{final.get('ultima', '')}»{log}")
    else:
        say(f"ejecución {rid} {final['estado']} (rc={final.get('rc')}) en {dur:.0f}s{log}")
    return code


def terminate(reg: Path, rid: str, state: str = "terminada") -> dict | None:
    """End an open run, only where its ownership is provable. Returns the closed record, or None."""
    rec = load(reg, rid)
    if rec["estado"] != OPEN:
        say(f"la ejecución {rid} ya está cerrada ({rec['estado']})")
        return rec
    sit = situation(rec)
    if sit == "en curso":
        update(reg, rid, orden=state)
        limit = time.time() + 2 * GRACE + 10
        while time.time() < limit:
            rec = load(reg, rid)
            if rec["estado"] != OPEN:
                return rec
            if situation(rec) not in ("en curso", "no comprobable"):
                break  # the guard died meanwhile: judge again below
            time.sleep(0.2)
        sit = situation(load(reg, rid))
    if sit == "huérfana":
        left = end_group(rec["grupo"])
        if left:
            say(f"la ejecución {rid} sigue con procesos vivos tras TERM y KILL: {left}. Queda abierta e incompleta")
            return update(reg, rid, incompleta=state, restos=left)
        return close(reg, rid, state, None)
    if sit == "abandonada":
        recover(reg, load(reg, rid))
        return load(reg, rid)
    if sit in ("incierta", "no comprobable"):
        print(describe(load(reg, rid)), file=sys.stderr)
        say("no termino nada: la pertenencia de esos procesos a la ejecución no es demostrable")
        return None
    say(f"la ejecución {rid} no cerró dentro del margen; consulta su estado")
    return None


def main() -> int:
    if os.name != "posix":
        die("solo POSIX (macOS verificado): grupos de procesos y waitid no existen aquí")
    if len(sys.argv) == 4 and sys.argv[1] == "_guardia":
        guard(Path(sys.argv[2]), sys.argv[3])
        return 0
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="accion", required=True)
    p = sub.add_parser("correr")
    p.add_argument("--plazo", type=str)
    p.add_argument("--dir")
    p.add_argument("--informe")
    p.add_argument("comando", nargs=argparse.REMAINDER)
    p = sub.add_parser("estado")
    p.add_argument("id", nargs="?")
    p.add_argument("--abiertas", action="store_true")
    p.add_argument("--dir")
    p = sub.add_parser("terminar")
    p.add_argument("id")
    p.add_argument("--dir")
    args = parser.parse_args()
    try:
        return action(args)
    except Unverifiable as exc:
        die(f"no pude comprobarlo ({exc}): sin esa evidencia no lanzo, termino ni limpio nada", EXIT_BLOCKED)


def action(args) -> int:
    if args.accion == "correr":
        return run(args)
    reg = registry(Path(args.dir or ".").resolve())
    if args.accion == "estado":
        recs = records(reg)
        if args.id:
            recs = [r for r in recs if r["id"] == args.id] or die(f"no hay ejecución {args.id} en {reg}")
        elif args.abiertas:
            recs = [r for r in recs if r["estado"] == OPEN]
        for rec in recs:
            print(describe(rec))
        return 0
    if not record_path(reg, args.id).exists():
        die(f"no hay ejecución {args.id} en {reg}")
    rec = terminate(reg, args.id)
    return EXIT_BLOCKED if rec is None or rec["estado"] == OPEN else 0


if __name__ == "__main__":
    sys.exit(main())
