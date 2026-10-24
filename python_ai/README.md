# python_ai — Entorno de fine-tuning (PC)

Fine-tuning de un modelo chico (MiniCPM) para personalidad en español, exportado a GGUF.

## Setup

```bash
cd python_ai
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Estructura

- `datasets/` — datasets de instrucciones/personalidad en español.
- `scripts/` — scripts de fine-tuning (Unsloth/PyTorch).
- `outputs/` — modelos finales exportados en `.gguf`.
- `requirements.txt` — dependencias.
