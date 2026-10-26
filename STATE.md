# STATE.md

## Tarea en curso
Visión en dos pasos validada en PC (MiniCPM-V 4 describe → Qwen razona). Reentrenamiento de Qwen2.5-3B-Instruct en curso; después se miden formato y español (T5.8/T11.6).

## Objetivo actual
Validar Qwen2.5-3B-Instruct como base de LAIN (español correcto + bloque `<think>` estable) y luego iniciar la Fase 2 (Flutter).

## Concepción vigente
LAIN = LOCAL ARTIFICIAL INTELIGENCE NEURONAL. Asistente Edge AI con consciencia funcional (no fenomenológica): GWT, HOT (`<think>`), RPT, percepción visual en dos pasos (MiniCPM-V 4 describe, Qwen razona) y ajuste bayesiano de creencias sobre un núcleo axiomático invariante.

## Zonas frágiles
- Consumo de RAM: Qwen2.5-3B-Instruct Q4_K_M (~1.9–2.0 GB) o VLM MiniCPM-V 4 (~3.0 GB, solo con imagen) + Laya/BMP (~100 MB) debe mantenerse < 3.5 GB (RNF03).
- La visión es en dos pasos: MiniCPM-V 4 describe la imagen en texto y Qwen razona sobre esa descripción; no se comparten embeddings.
- La plantilla de chat de MiniCPM-V 4 concatena `content` como texto: `vision.py` aplana la lista de partes (`MiniCPMVHandler`).
- Qwen2.5 usa ChatML y no trae tag nativo de pensamiento: el bloque `<think>` depende del system prompt y del dataset, hay que re-verificarlo con `test/check_format.py`.
- `outputs/` puede contener varios `.gguf` (MiniCPM y Qwen); los scripts eligen el más reciente por fecha.
- VLM y LLM no deben convivir en VRAM: el VLM se libera antes de cargar Qwen (~3.0 GB + ~1.9 GB no caben juntos en 6 GB).
- Entorno Python: requiere Python 3.12 (Unsloth no soporta 3.13+); `torch`/`torchvision` deben ser de la misma build CUDA (cu126).
- Dataset local de 87 ejemplos: validar con `validate_dataset.py` antes de cada corrida.

## Completado
- Commit inicial del repositorio.
- T5.1 Entorno Python base creado.
- T5.2 Dataset de personalidad en español (`personality_es.jsonl`).
- T5.3 Script de fine-tuning con Unsloth (`scripts/finetune.py`).
- Documentación actualizada al vault «Teoría y Arquitectura de Consciencia para LAIN» (README, ARCHITECTURE, TASKS, CHANGELOG).
- Entorno recreado con uv (Python 3.12, torch 2.14.1+cu126, unsloth 2026.10.8).
- Pipeline de fine-tuning validado con MiniCPM5-2B: smoke test, 60 pasos (loss 2.30 → 0.68), export GGUF Q4_K_M (1.5 GB) e inferencia en español.
- Formato ` thinking` estabilizado con MiniCPM5: dataset de 87 ejemplos, validador y `check_format.py` con 20/20 bloques JSON válidos.
- Diagnóstico de calidad: MiniCPM5-2B mantiene el formato y el tono, pero su español es pobre (léxico inventado, concordancia rota, definiciones erróneas).
- Base cambiada a Qwen2.5-3B-Instruct en `finetune.py`; el corpus general (guanaco) se retiró: el entrenamiento usa solo `personality_es.jsonl`.
- `scripts/common.py`: selección del `.gguf` más reciente cuando hay varios modelos en `outputs/`.
- Documentación alineada al nuevo modelo base (README, AGENTS, ARCHITECTURE, CONSCIENCIA, WORKFLOW).
- `scripts/vision.py`: visión en dos pasos validada con MiniCPM-V 4 (descripción + OCR) sobre imagen sintética y foto real.
- MiniCPM-V 4 Q4_K_M + mmproj descargados en `python_ai/models/` (~3.0 GB, ignorado por git).
- Scripts de prueba/evaluación del modelo movidos de `python_ai/scripts/` a `python_ai/test/` (`check_format.py`, `eval_es.py`, `infer.py`). Comandos desde `python_ai/`: `python test/check_format.py`, `python test/eval_es.py`, `python test/infer.py`.

## Próximos pasos
- T5.8/T11.6: terminar el reentrenamiento de Qwen, exportar GGUF y correr `test/check_format.py` + `test/eval_es.py`.
- T9: portar la visión en dos pasos a la app (cámara, liberar VLM antes del LLM).
- T11.2/T11.3: set corto de evaluación en español para comparar MiniCPM5 vs Qwen2.5 y registrar resultados.
- Fase 2: T1.1 configurar Flutter y T1.2 puente FFI para llama.cpp con el GGUF de Qwen.
- Nuevas líneas (ver TASKS.md): enrutador Laya/BMP, visión en dos pasos con MiniCPM-V 4, trazas `<think>`, persistencia `lain_experiences.jsonl` y ciclo SFT/CoT + DPO.
