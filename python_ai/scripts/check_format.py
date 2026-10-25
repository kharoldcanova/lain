"""Mide la estabilidad del bloque <think> JSON en un conjunto fijo de prompts.

Éxito si al menos `--min-valid` fracción produce JSON válido con las cuatro
claves y ningún bloque queda sin cerrar.

Uso:
    python scripts/check_format.py
    python scripts/check_format.py --count 10 --model outputs/MiniCPM5-2B.Q4_K_M.gguf
"""

import argparse
import json
import re
import sys
from pathlib import Path

import torch  # noqa: F401  (carga libcudart antes que llama_cpp)
from llama_cpp import Llama

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = ROOT / "outputs"
SYSTEM_PROMPT = (ROOT / "datasets" / "system_prompt.txt").read_text().strip()
KEYS = ("thought_trace", "prior_belief", "belief_shift", "axiom_alignment_check")

BLOCK_RE = re.compile(r"<(?:think|thought)>(.*?)</(?:think|thought)>", re.S)
OPEN_RE = re.compile(r"<(?:think|thought)>")

PROMPTS = [
    "Hola, ¿qué tal?",
    "Hoy me siento raro.",
    "¿Qué piensas de la muerte?",
    "Ayúdame a decidir entre dos trabajos.",
    "¿Eres feliz?",
    "Cuéntame algo que no sepas.",
    "No entiendo a mi pareja.",
    "¿Qué es la empatía?",
    "Dame una idea para un proyecto.",
    "Me da miedo fracasar.",
    "¿Por qué existes?",
    "Estoy cansado de estudiar.",
    "¿Qué harías tú en mi lugar?",
    "Háblame de la soledad.",
    "¿Puedes guardar un secreto?",
    "Quiero aprender a programar.",
    "¿Qué opinas del dinero?",
    "Mi perro está enfermo.",
    "¿Cómo sé si estoy mejorando?",
    "Buenas tardes.",
]


def parse_args():
    parser = argparse.ArgumentParser(description="Verifica el formato <think> JSON.")
    parser.add_argument("--model", help="Ruta al .gguf (por defecto el primero en outputs/).")
    parser.add_argument("--count", type=int, default=20, help="Prompts a evaluar (máximo 20).")
    parser.add_argument("--max-tokens", type=int, default=420)
    parser.add_argument("--temperature", type=float, default=0.7)
    parser.add_argument("--min-valid", type=float, default=0.9, help="Fracción mínima de JSON válido.")
    parser.add_argument("--seed", type=int, default=42)
    return parser.parse_args()


def resolve_model(path):
    if path:
        model_path = Path(path).expanduser()
        if not model_path.is_file():
            raise SystemExit(f"No existe el modelo: {model_path}")
        return model_path
    model_path = next(DEFAULT_OUTPUT_DIR.glob("*.gguf"), None)
    if model_path is None:
        raise SystemExit(f"No se encontró ningún .gguf en {DEFAULT_OUTPUT_DIR}")
    return model_path


def check(raw):
    """Devuelve (estado, detalle). estado: ok | unclosed | json | keys."""
    match = BLOCK_RE.search(raw)
    if match is None:
        if OPEN_RE.search(raw):
            return "unclosed", "bloque abierto sin cierre"
        return "json", "sin bloque de pensamiento"

    body = match.group(1).strip()
    try:
        data = json.loads(body)
    except json.JSONDecodeError as error:
        return "json", f"JSON inválido ({error.msg})"

    if not isinstance(data, dict):
        return "json", "el bloque no es un objeto"

    missing = [key for key in KEYS if not isinstance(data.get(key), str) or not data[key].strip()]
    if missing:
        return "keys", f"faltan claves: {', '.join(missing)}"

    return "ok", ""


def main():
    args = parse_args()
    model_path = resolve_model(args.model)
    prompts = PROMPTS[: args.count]

    llm = Llama(
        model_path=str(model_path),
        n_ctx=4096,
        n_gpu_layers=-1,
        seed=args.seed,
        verbose=False,
    )

    results = []
    for index, prompt in enumerate(prompts, 1):
        out = llm.create_chat_completion(
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            max_tokens=args.max_tokens,
            temperature=args.temperature,
        )
        raw = out["choices"][0]["message"].get("content") or ""
        status, detail = check(raw)
        results.append(status)
        mark = "ok " if status == "ok" else "FAIL"
        print(f"[{index:02d}] {mark} {prompt[:40]:42} {detail}")

    valid = results.count("ok")
    total = len(results)
    ratio = valid / total if total else 0.0
    unclosed = results.count("unclosed")

    print(f"\nVálidos: {valid}/{total} ({ratio:.0%}) | sin cerrar: {unclosed} | mínimo: {args.min_valid:.0%}")

    if ratio < args.min_valid or unclosed > 0:
        print("Resultado: FAIL")
        sys.exit(1)
    print("Resultado: PASS")


if __name__ == "__main__":
    main()
