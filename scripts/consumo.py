#!/usr/bin/env python3
"""Cumulative token usage for this project, per model, from local Claude Code transcripts.

Usage:
    python3 scripts/consumo.py            # human-readable table
    python3 scripts/consumo.py --json     # machine-readable
    python3 scripts/consumo.py --dir DIR  # explicit transcript directory

Reads every *.jsonl under ~/.claude/projects/<slug-of-cwd>/ RECURSIVELY (main thread,
sidechains, and subagent transcripts, which live in nested directories such as
<session>/subagents/), deduplicates messages, and sums usage per model and per origin:
principal, subagentes, or sin_atribuir when the structure does not say (see origin()).
The report states how many files were read at the top level and how many in nested
directories, so a run that saw no subagent files says so instead of looking complete.
Its sum is a MEASURED SUBTOTAL of these transcripts, not a complete total, and tokens are
not cost.
Record ONE line in docs/MEMORIA.md, section "Consumo", at each increment/phase close
(see docs/convenciones.md, "Contexto por sesion y compactacion"; MEMORIA.md is outside
the review fingerprint, plan.md is not); the delta against the previous line is that
slice's consumption. This reads Claude Code transcripts only; with Codex, use its own
usage report and record the line by hand.

CAVEAT (why this script is deliberately loud): the transcript entry format is internal
to Claude Code and can change between versions. If nothing parses, this exits non-zero
and says so -- it never prints zeros that look like an answer. Interactive alternative:
/usage inside Claude Code.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

USAGE_FIELDS = (
    ("input_tokens", "entrada"),
    ("cache_creation_input_tokens", "cache-esc"),
    ("cache_read_input_tokens", "cache-lect"),
    ("output_tokens", "salida"),
)


def slug(path: Path) -> str:
    return re.sub(r"[^A-Za-z0-9]", "-", str(path))


def find_transcript_dir(cwd: Path) -> Path:
    projects = Path.home() / ".claude" / "projects"
    if not projects.is_dir():
        sys.exit(f"no existe {projects}: ¿Claude Code ha corrido en esta maquina?")
    exact = projects / slug(cwd)
    if exact.is_dir():
        return exact
    # The slug scheme is internal; if it drifted, offer the plausible candidates loudly.
    tail = slug(Path(cwd.name))
    candidates = [d for d in projects.iterdir() if d.is_dir() and d.name.endswith(tail)]
    if len(candidates) == 1:
        print(f"aviso: usando {candidates[0].name} (el slug exacto no existe)", file=sys.stderr)
        return candidates[0]
    listing = "\n  ".join(d.name for d in sorted(projects.iterdir()) if d.is_dir())
    sys.exit(
        f"no encuentro el directorio de transcripts para {cwd}\n"
        f"esperaba {exact.name} y hay {len(candidates)} candidatos por sufijo.\n"
        f"pasa --dir con uno de:\n  {listing}"
    )


ORIGINS = ("principal", "subagentes", "sin_atribuir")


def origin(fp: Path, directory: Path, entry: dict) -> str:
    """Attribute an entry only when the transcript structure says so; anything else is ambiguous.

    principal:  top-level <session>.jsonl, isSidechain explicitly false, no agentId.
    subagentes: <session>/subagents/*.jsonl, isSidechain explicitly true, with agentId.
    """
    if fp.parent == directory and entry.get("isSidechain") is False and "agentId" not in entry:
        return "principal"
    if fp.parent.name == "subagents" and entry.get("isSidechain") is True and entry.get("agentId"):
        return "subagentes"
    return "sin_atribuir"


def collect(directory: Path) -> tuple[dict, dict, dict, int, int, int]:
    files = sorted(directory.rglob("*.jsonl"))
    nested = sum(1 for f in files if f.parent != directory)
    if not files:
        sys.exit(f"{directory} no tiene archivos .jsonl")
    records: dict[tuple, list] = {}  # key -> [model, amounts, origin]
    for fp in files:
        with open(fp, encoding="utf-8") as fh:
            for line in fh:
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                message = entry.get("message")
                if entry.get("type") != "assistant" or not isinstance(message, dict):
                    continue
                usage = message.get("usage")
                if not isinstance(usage, dict):
                    continue
                model = message.get("model") or "desconocido"
                amounts = {f: usage.get(f) for f, _ in USAGE_FIELDS}
                if model == "<synthetic>" or not any(isinstance(v, int) and v for v in amounts.values()):
                    continue  # harness-internal rows carry no real usage
                key = (message.get("id"), entry.get("requestId")) if message.get("id") else (entry.get("uuid"),)
                where = origin(fp, directory, entry)
                if key in records:  # resumed/compacted sessions repeat messages: counted once
                    if records[key][2] != where:
                        records[key][2] = "sin_atribuir"  # seen in two places: not attributable
                    continue
                records[key] = [model, amounts, where]
    if not records:
        sys.exit(
            f"0 mensajes con usage en {directory} — el formato interno pudo cambiar; "
            "verifica con /usage dentro de Claude Code y ajusta este script."
        )
    per_model: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    per_origin: dict[str, dict] = {o: defaultdict(lambda: defaultdict(int)) for o in ORIGINS}
    calls_origin = dict.fromkeys(ORIGINS, 0)
    for model, amounts, where in records.values():
        calls_origin[where] += 1
        for field, _ in USAGE_FIELDS:
            if isinstance(amounts[field], int):
                per_model[model][field] += amounts[field]
                per_origin[where][model][field] += amounts[field]
    return per_model, per_origin, calls_origin, len(records), len(files), nested


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", type=Path, help="transcript directory (overrides the slug lookup)")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    args = parser.parse_args()

    directory = args.dir if args.dir else find_transcript_dir(Path.cwd())
    if not directory.is_dir():
        sys.exit(f"{directory} no existe")
    per_model, per_origin, calls_origin, calls, n_files, nested = collect(directory)

    if args.json:
        # por_modelo, llamadas, archivos y archivos_anidados conservan su significado anterior
        # (todo lo medido); por_origen y llamadas_por_origen se añaden.
        print(json.dumps({"dir": str(directory), "archivos": n_files, "archivos_anidados": nested,
                          "llamadas": calls, "por_modelo": per_model,
                          "por_origen": {o: per_origin[o] for o in ORIGINS if calls_origin[o]},
                          "llamadas_por_origen": calls_origin}, indent=1, sort_keys=True))
        return 0

    print(f"Consumo acumulado — {n_files} archivo(s) de transcript ({nested} en subdirectorios), "
          f"{calls} llamadas: principal {calls_origin['principal']}, subagentes "
          f"{calls_origin['subagentes']}, sin atribuir {calls_origin['sin_atribuir']}")
    if nested == 0:
        print("aviso: ningún transcript anidado; si hubo subagentes, su consumo NO está aquí.", file=sys.stderr)
    if calls_origin["sin_atribuir"]:
        print("aviso: hay llamadas sin atribuir (estructura ambigua o mensaje repetido en dos orígenes); "
              "no se reparten entre principal y subagentes.", file=sys.stderr)
    header = f"{'origen':<14}{'modelo':<28}" + "".join(f"{label:>12}" for _, label in USAGE_FIELDS)
    print(header)
    for where in ORIGINS:
        for model in sorted(per_origin[where]):
            print(f"{where:<14}{model:<28}" + "".join(f"{per_origin[where][model][f]:>12,}" for f, _ in USAGE_FIELDS))
    totals = {f: sum(per_model[m][f] for m in per_model) for f, _ in USAGE_FIELDS}
    print(f"{'subtotal medido':<42}" + "".join(f"{totals[f]:>12,}" for f, _ in USAGE_FIELDS))
    print("nota: «subtotal medido» suma solo estos transcripts; no es un total completo si alguna parte "
          "se ejecutó fuera de ellos (otro cliente, otra máquina, sesiones borradas). Los campos de caché "
          "van separados; tokens no son coste: el coste depende del modelo y de la tarifa vigente.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
