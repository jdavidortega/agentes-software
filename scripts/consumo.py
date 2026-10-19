#!/usr/bin/env python3
"""Cumulative token usage for this project, per model, from local Claude Code transcripts.

Usage:
    python3 scripts/consumo.py            # human-readable table
    python3 scripts/consumo.py --json     # machine-readable
    python3 scripts/consumo.py --dir DIR  # explicit transcript directory

Reads every *.jsonl under ~/.claude/projects/<slug-of-cwd>/ RECURSIVELY (main thread,
sidechains, and subagent transcripts, which live in nested directories such as
<session>/subagents/), deduplicates messages, and sums usage per model. The report states
how many files were read at the top level and how many in nested directories, so a run
that saw no subagent files says so instead of looking complete.
Record ONE line in the bitacora of docs/plan.md at each increment/phase close (see
docs/convenciones.md, "Contexto por sesion y compactacion"); the delta against the
previous line is that slice's consumption.

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


def collect(directory: Path) -> tuple[dict, int, int, int]:
    per_model: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    seen: set[tuple] = set()
    calls = 0
    files = sorted(directory.rglob("*.jsonl"))
    nested = sum(1 for f in files if f.parent != directory)
    if not files:
        sys.exit(f"{directory} no tiene archivos .jsonl")
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
                key = (message.get("id"), entry.get("requestId")) if message.get("id") else (entry.get("uuid"),)
                if key in seen:  # resumed/compacted sessions repeat messages
                    continue
                seen.add(key)
                model = message.get("model") or "desconocido"
                amounts = {f: usage.get(f) for f, _ in USAGE_FIELDS}
                if model == "<synthetic>" or not any(isinstance(v, int) and v for v in amounts.values()):
                    continue  # harness-internal rows carry no real usage
                calls += 1
                for field, _ in USAGE_FIELDS:
                    if isinstance(amounts[field], int):
                        per_model[model][field] += amounts[field]
    if calls == 0:
        sys.exit(
            f"0 mensajes con usage en {directory} — el formato interno pudo cambiar; "
            "verifica con /usage dentro de Claude Code y ajusta este script."
        )
    return per_model, calls, len(files), nested


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", type=Path, help="transcript directory (overrides the slug lookup)")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    args = parser.parse_args()

    directory = args.dir if args.dir else find_transcript_dir(Path.cwd())
    if not directory.is_dir():
        sys.exit(f"{directory} no existe")
    per_model, calls, n_files, nested = collect(directory)

    if args.json:
        print(json.dumps({"dir": str(directory), "archivos": n_files, "archivos_anidados": nested,
                          "llamadas": calls, "por_modelo": per_model}, indent=1, sort_keys=True))
        return 0

    print(f"Consumo acumulado — {n_files} archivo(s) de transcript ({nested} en subdirectorios: "
          f"subagentes), {calls} llamadas")
    if nested == 0:
        print("aviso: ningún transcript anidado; si hubo subagentes, su consumo NO está aquí.", file=sys.stderr)
    header = f"{'modelo':<28}" + "".join(f"{label:>12}" for _, label in USAGE_FIELDS)
    print(header)
    totals: dict[str, int] = defaultdict(int)
    for model in sorted(per_model):
        row = f"{model:<28}"
        for field, _ in USAGE_FIELDS:
            value = per_model[model][field]
            totals[field] += value
            row += f"{value:>12,}"
        print(row)
    print(f"{'TOTAL':<28}" + "".join(f"{totals[field]:>12,}" for field, _ in USAGE_FIELDS))
    print("nota: compara sobre entrada+salida; la cache se factura aparte (escritura ~1.25x, lectura ~0.1x de entrada).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
