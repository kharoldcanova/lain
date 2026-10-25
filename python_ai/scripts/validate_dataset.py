"""Valida el contrato del dataset SFT antes de entrenar.

Uso:
    python scripts/validate_dataset.py
    python scripts/validate_dataset.py --path datasets/personality_es.jsonl
"""

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATH = ROOT / "datasets" / "personality_es.jsonl"
KEYS = ("thought_trace", "prior_belief", "belief_shift", "axiom_alignment_check")
ROW_RE = re.compile(r"^<think>\n(\{.*\})\n</think>\n\n\n(.+)$", re.S)


def parse_args():
    parser = argparse.ArgumentParser(description="Valida el dataset de entrenamiento.")
    parser.add_argument("--path", default=str(DEFAULT_PATH))
    return parser.parse_args()


def validate(row, index):
    instruction = (row.get("instruction") or "").strip()
    response = row.get("response") or ""
    if not instruction:
        return f"fila {index}: instrucción vacía"
    if "<thought>" in response:
        return f"fila {index}: usa el tag antiguo <thought>"

    match = ROW_RE.match(response)
    if match is None:
        return f"fila {index}: falta el cierre </think> o el separador"

    try:
        data = json.loads(match.group(1))
    except json.JSONDecodeError as error:
        return f"fila {index}: JSON inválido ({error.msg})"

    if list(data.keys()) != list(KEYS):
        return f"fila {index}: claves incorrectas {list(data.keys())}"
    if not all(isinstance(data[key], str) and data[key].strip() for key in KEYS):
        return f"fila {index}: hay una clave vacía"
    return None


def main():
    args = parse_args()
    path = Path(args.path).expanduser()
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]

    errors = [error for index, row in enumerate(rows, 1) if (error := validate(row, index))]
    if errors:
        for error in errors[:10]:
            print(f"FAIL {error}")
        print(f"\n{len(errors)} errores de {len(rows)} filas")
        raise SystemExit(1)

    print(f"OK {len(rows)} filas válidas")


if __name__ == "__main__":
    main()
