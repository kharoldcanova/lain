"""Convierte experiencias exportadas por la app en filas de entrenamiento SFT.

Lee `lain_experiences.jsonl`, valida el esquema del vault y agrega a
`personality_es.jsonl` los pares instruction/response con bloque `<thought>` JSON.

Uso:
    python scripts/import_experiences.py --dry-run
    python scripts/import_experiences.py
    python scripts/import_experiences.py --input ~/Descargas/lain_experiences.jsonl
"""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "experiences" / "lain_experiences.jsonl"
DEFAULT_OUTPUT = ROOT / "datasets" / "personality_es.jsonl"
THOUGHT_KEYS = ("thought_trace", "prior_belief", "belief_shift", "axiom_alignment_check")


def parse_args():
    parser = argparse.ArgumentParser(description="Importa experiencias como dataset SFT.")
    parser.add_argument("--input", default=str(DEFAULT_INPUT), help="JSONL exportado por la app.")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Dataset de entrenamiento.")
    parser.add_argument("--dry-run", action="store_true", help="Solo mostrar conteos.")
    parser.add_argument(
        "--include-incomplete",
        action="store_true",
        help="Aceptar registros con campos de metacognición en null.",
    )
    return parser.parse_args()


def load_jsonl(path):
    if not path.is_file():
        raise SystemExit(f"No existe el archivo: {path}")
    rows = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError as error:
            print(f"  línea {number} inválida, se omite: {error}")
    return rows


def to_training_row(record, include_incomplete):
    context = record.get("context") or {}
    meta = record.get("metacognition") or {}
    response = record.get("response") or {}
    training = record.get("training_metadata") or {}

    instruction = (context.get("user_input") or "").strip()
    output = (response.get("model_output") or "").strip()
    if not instruction or not output:
        return None
    if training.get("suitable_for_sft") is False:
        return None

    thought = {key: meta.get(key) for key in THOUGHT_KEYS}
    if not include_incomplete and not all(thought.values()):
        return None

    return {
        "instruction": instruction,
        "response": f"<thought>\n{json.dumps(thought, ensure_ascii=False)}\n</thought>\n{output}",
    }


def main():
    args = parse_args()
    source = Path(args.input).expanduser()
    target = Path(args.output).expanduser()

    records = load_jsonl(source)
    existing = []
    if target.is_file():
        existing = [json.loads(line) for line in target.read_text(encoding="utf-8").splitlines() if line.strip()]
    known = {row.get("instruction") for row in existing}

    new_rows, skipped, duplicates = [], 0, 0
    for record in records:
        row = to_training_row(record, args.include_incomplete)
        if row is None:
            skipped += 1
        elif row["instruction"] in known:
            duplicates += 1
        else:
            new_rows.append(row)
            known.add(row["instruction"])

    print(f"Registros leídos: {len(records)}")
    print(f"Válidos nuevos: {len(new_rows)} | omitidos: {skipped} | duplicados: {duplicates}")

    if args.dry_run or not new_rows:
        return

    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("a", encoding="utf-8") as handle:
        for row in new_rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(f"Agregados {len(new_rows)} ejemplos a {target}")


if __name__ == "__main__":
    main()
