"""Percepción visual en dos pasos: un VLM describe la imagen y el LLM de texto razona.

MiniCPM-V no comparte espacio de embeddings con Qwen, así que la imagen se
convierte primero en texto (descripción + OCR) y ese texto entra al prompt.

Uso:
    python scripts/vision.py --image foto.jpg
    python scripts/vision.py --image foto.jpg --question "¿Qué planta es?"
    python scripts/vision.py --image foto.jpg --caption-only
"""

import argparse
import base64
import gc
from pathlib import Path

import torch  # noqa: F401  (carga libcudart antes que llama_cpp)
from llama_cpp import Llama
from llama_cpp.llama_chat_format import MTMDChatHandler

from chat import log_experience, parse_thought
from common import newest_gguf

ROOT = Path(__file__).resolve().parents[1]
MODELS_DIR = ROOT / "models"
DEFAULT_VISION_MODEL = MODELS_DIR / "ggml-model-Q4_K_M.gguf"
DEFAULT_MMPROJ = MODELS_DIR / "mmproj-model-f16.gguf"
DEFAULT_LOG = ROOT / "experiences" / "lain_experiences.jsonl"
SYSTEM_PROMPT = (ROOT / "datasets" / "system_prompt.txt").read_text().strip()
CAPTION_PROMPT = (
    "Describe esta imagen de forma objetiva y detallada, en español. "
    "Indica qué se ve, los colores dominantes y transcribe cualquier texto visible."
)


class MiniCPMVHandler(MTMDChatHandler):
    """La plantilla de MiniCPM-V concatena `content` como texto, no admite listas."""

    def _get_template_messages(self, messages, media_marker):
        converted = []
        for message in messages:
            item = dict(message)
            content = item.get("content")
            if isinstance(content, list):
                parts = []
                for part in content:
                    if not isinstance(part, dict):
                        parts.append(str(part))
                    elif part.get("type") == "image_url":
                        parts.append(media_marker)
                    elif part.get("type") == "text":
                        parts.append(part.get("text") or "")
                item["content"] = "\n".join(part for part in parts if part)
            converted.append(item)
        return converted


def parse_args():
    parser = argparse.ArgumentParser(description="Visión en dos pasos (VLM describe, LLM responde).")
    parser.add_argument("--image", required=True, help="Ruta de la imagen a analizar.")
    parser.add_argument("--question", default="¿Qué ves y qué te sugiere?", help="Pregunta del usuario.")
    parser.add_argument("--vision-model", default=str(DEFAULT_VISION_MODEL), help="GGUF del VLM (MiniCPM-V).")
    parser.add_argument("--mmproj", default=str(DEFAULT_MMPROJ), help="Proyector visual del VLM.")
    parser.add_argument("--text-model", help="GGUF de texto (por defecto el más reciente en outputs/).")
    parser.add_argument("--max-tokens", type=int, default=512)
    parser.add_argument("--temperature", type=float, default=0.7)
    parser.add_argument("--hide-thought", action="store_true", help="Oculta el bloque de pensamiento.")
    parser.add_argument("--caption-only", action="store_true", help="Solo describe la imagen, sin LLM de texto.")
    parser.add_argument("--log", default=str(DEFAULT_LOG), help="Ruta del .jsonl de experiencias.")
    parser.add_argument("--no-log", action="store_true", help="No registrar la experiencia.")
    return parser.parse_args()


def data_uri(image_path):
    data = image_path.read_bytes()
    return f"data:image/jpeg;base64,{base64.b64encode(data).decode()}"


def describe_image(args, image_path):
    """Devuelve la descripción textual de la imagen (VLM liberado al terminar)."""
    if not Path(args.vision_model).is_file():
        raise SystemExit(f"Falta el VLM en {args.vision_model}")
    if not Path(args.mmproj).is_file():
        raise SystemExit(f"Falta el proyector visual en {args.mmproj}")

    handler = MiniCPMVHandler(clip_model_path=args.mmproj, verbose=False)
    vlm = Llama(
        model_path=args.vision_model,
        chat_handler=handler,
        n_ctx=4096,
        n_gpu_layers=-1,
        verbose=False,
    )
    try:
        output = vlm.create_chat_completion(
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": CAPTION_PROMPT},
                        {"type": "image_url", "image_url": {"url": data_uri(image_path)}},
                    ],
                }
            ],
            max_tokens=args.max_tokens,
            temperature=0.2,
        )
        return output["choices"][0]["message"]["content"].strip()
    finally:
        del vlm
        handler.mtmd_ctx = None
        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()


def main():
    args = parse_args()
    image_path = Path(args.image).expanduser()
    if not image_path.is_file():
        raise SystemExit(f"No existe la imagen: {image_path}")

    caption = describe_image(args, image_path)
    print(f"DESCRIPCIÓN VISUAL:\n{caption}\n")
    if args.caption_only:
        return

    text_model = Path(args.text_model).expanduser() if args.text_model else newest_gguf(ROOT / "outputs")
    if text_model is None or not text_model.is_file():
        raise SystemExit("No se encontró el GGUF de texto en outputs/")

    llm = Llama(model_path=str(text_model), n_ctx=4096, n_gpu_layers=-1, verbose=False)
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": (
                "El usuario adjuntó una imagen. Otro modelo la describió así:\n"
                f"{caption}\n\n"
                f"Pregunta del usuario: {args.question}"
            ),
        },
    ]
    output = llm.create_chat_completion(
        messages=messages,
        max_tokens=args.max_tokens,
        temperature=args.temperature,
    )
    raw = output["choices"][0]["message"]["content"].strip()
    answer, thought = parse_thought(raw)

    if args.hide_thought:
        print(answer)
    else:
        print(raw)

    if not args.no_log:
        log_experience(
            args.log,
            user_input=f"[imagen: {image_path.name}] {args.question}",
            answer=answer,
            thought=thought,
            trigger_type="vision_input",
            has_multimodal_input=True,
        )


if __name__ == "__main__":
    main()
