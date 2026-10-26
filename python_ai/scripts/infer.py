"""Prueba de inferencia del modelo fine-tuneado exportado a GGUF."""

from pathlib import Path

import torch  # noqa: F401  (carga libcudart antes que llama_cpp)
from llama_cpp import Llama

from common import newest_gguf

OUTPUT_DIR = Path(__file__).resolve().parents[1] / "outputs"
SYSTEM_PROMPT = (Path(__file__).resolve().parents[1] / "datasets" / "system_prompt.txt").read_text().strip()
PROMPT = "Hola, ¿cómo estás?"


def main():
    model_path = newest_gguf(OUTPUT_DIR)
    if model_path is None:
        raise SystemExit(f"No se encontró ningún .gguf en {OUTPUT_DIR}")

    llm = Llama(model_path=str(model_path), n_ctx=2048, n_gpu_layers=-1, verbose=False)
    output = llm.create_chat_completion(
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": PROMPT},
        ],
        max_tokens=512,
        temperature=0.7,
    )
    text = output["choices"][0]["message"]["content"].strip()
    for closing in ("</thought>", "</think>"):
        if closing in text:
            text = text.split(closing, 1)[1].strip()
    print(text)


if __name__ == "__main__":
    main()
