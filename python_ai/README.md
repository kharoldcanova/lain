# python_ai — Entorno de fine-tuning (PC)

Fine-tuning de un modelo chico (MiniCPM) para personalidad en español, exportado a GGUF.

## Requisitos

- GPU NVIDIA con CUDA (probado en RTX 3050 6 GB, driver 615).
- Python 3.10-3.12 (Unsloth no soporta 3.13+).
- `uv` para gestionar el entorno.

## Setup

```bash
cd python_ai
uv venv .venv --python 3.12
source .venv/bin/activate
uv pip install torch --index-url https://download.pytorch.org/whl/cu126
uv pip install -r requirements_finetune.txt
```

`cmake` lo instala Unsloth en el entorno para compilar llama.cpp durante la exportación GGUF.

## Comandos

Smoke test (1 paso, sin dataset de HuggingFace, sin exportar):

```bash
python scripts/finetune.py --max-steps 1 --skip-hf --no-export
```

Entrenamiento completo (60 pasos + dataset HF + export GGUF):

```bash
python scripts/finetune.py
```

Probar el modelo exportado:

```bash
python scripts/infer.py
```

## Estructura

- `datasets/` — dataset de personalidad (`personality_es.jsonl`) y system prompt.
- `scripts/` — `finetune.py` (QLoRA + export GGUF) e `infer.py` (prueba con llama-cpp-python).
- `outputs/` — modelos exportados en `.gguf` (ignorado por git).
- `requirements.txt` — dependencias de inferencia; `requirements_finetune.txt` — dependencias de entrenamiento.
