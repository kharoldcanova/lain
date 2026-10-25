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

Chat manual (con historial y registro de experiencias):

```bash
python scripts/chat.py                 # interactivo
python scripts/chat.py --hide-thought  # oculta la traza <think>
python scripts/chat.py --prompt "Hola" --no-log
```

Cada turno se agrega a `experiences/lain_experiences.jsonl` con el esquema del vault:
`context` (Laya), `metacognition`, `response` y `training_metadata`.
El bloque `<think>` debe ser un JSON válido con `thought_trace`, `prior_belief`, `belief_shift` y
`axiom_alignment_check`; `chat.py` lo parsea y rellena esos campos. Si el modelo no devuelve JSON válido,
usa el texto completo como `thought_trace`. Los campos que dependen de Laya/BMP o del feedback del usuario
(`laya_decision`, `user_reaction_score`, `rejected_alternative`) quedan en `null`.

Verificar la estabilidad del formato (20 prompts, exige ≥90 % de JSON válido y cero bloques sin cerrar):

```bash
python scripts/check_format.py
```

Validar el dataset antes de entrenar (contrato `<think>` + JSON de cuatro claves):

```bash
python scripts/validate_dataset.py
```

## Importar experiencias exportadas por la app

La app exporta `lain_experiences.jsonl` (esquema del vault). Para incorporarlas al dataset:

```bash
python scripts/import_experiences.py --input ~/Descargas/lain_experiences.jsonl --dry-run
python scripts/import_experiences.py --input ~/Descargas/lain_experiences.jsonl
python scripts/finetune.py --max-steps 200
```

El importador descarta registros sin `thought_trace`, sin salida o marcados `suitable_for_sft: false`,
y evita instrucciones duplicadas. Usa `--include-incomplete` para aceptar campos de creencias en `null`.

## RAG local (conocimiento descargado)

Indexa una URL o un archivo local en `rag/lain_rag.db` (SQLite + embeddings on-device):

```bash
python scripts/rag.py ingest https://ejemplo.com/nota
python scripts/rag.py ingest --file ../README.md
python scripts/rag.py query "¿qué es Laya/BMP?" --top-k 4
python scripts/rag.py stats
python scripts/rag.py clear
```

- Embeddings: `intfloat/multilingual-e5-small` (384 dims, se descarga una vez).
- Sin red, las consultas siguen funcionando con lo ya indexado.
- `chat.py --rag` inyecta los fragmentos recuperados en el prompt.

## Qué contiene realmente el modelo entrenado

En simple: **el modelo no guarda el dataset, guarda lo que aprendió de él.**

El dataset (`personality_es.jsonl`) son ejemplos de texto. Al entrenar, el modelo los mira y ajusta sus pesos
(la "memoria" interna de la red). Esos ajustes capturan **estilo, tono y formato de respuesta**, no los textos
literales. La información queda repartida en millones de números, sin copia de ninguna frase.

En este proyecto el entrenamiento usa QLoRA: en vez de reescribir el modelo completo, se entrena una capa
extra chica (el "adaptador") encima del modelo base congelado.

| Archivo | Tamaño aprox. | Qué es |
|---|---|---|
| `outputs/checkpoint-N/adapter_model.safetensors` | ~96 MB | Solo el adaptador entrenado (lo aprendido) |
| `outputs/checkpoint-N/optimizer.pt` | ~50 MB | Estado del optimizador, sirve solo para reanudar |
| `outputs/model-*.safetensors` | ~4.7 GB | Modelo base + adaptador ya fusionados |
| `outputs/MiniCPM5-2B.Q4_K_M.gguf` | ~1.5 GB | El mismo modelo fusionado, comprimido para el celular |

Conclusiones prácticas:

- El `.gguf` es el **único** archivo que se copia a `mobile_app/`. Contiene pesos, no ejemplos.
- El dataset **nunca** viaja dentro del modelo: hay que conservarlo aparte como fuente de verdad.
- Los `checkpoint-*/` son versiones de entrenamiento, no el producto final.
- Para reproducir o auditar un entrenamiento se necesitan el dataset, el script y el seed; no el `.gguf`.

Ojo con la memorización: si un ejemplo se repite mucho, el modelo puede llegar a reproducir frases
textuales (por ejemplo el system prompt). No es "todo el dataset adentro", pero es un riesgo real si algún
día se entrenan datos privados.

## Estructura

- `datasets/` — dataset de personalidad (`personality_es.jsonl`) y system prompt.
- `scripts/` — `finetune.py` (QLoRA + export GGUF) e `infer.py` (prueba con llama-cpp-python).
- `outputs/` — modelos exportados en `.gguf` (ignorado por git).
- `requirements.txt` — dependencias de inferencia; `requirements_finetune.txt` — dependencias de entrenamiento.
