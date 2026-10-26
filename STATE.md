# STATE.md

## Tarea en curso
Cambio de modelo base a Qwen2.5-3B-Instruct: scripts y documentación actualizados. Siguiente: smoke test, reentrenamiento y medición de formato (T11.6).

## Objetivo actual
Validar Qwen2.5-3B-Instruct como base de LAIN (español correcto + bloque `<think>` estable) y luego iniciar la Fase 2 (Flutter).

## Concepción vigente
LAIN = LOCAL ARTIFICIAL INTELIGENCE NEURONAL. Asistente Edge AI con consciencia funcional (no fenomenológica): GWT, HOT (` thinking`), RPT, percepción multimodal (pendiente: base de visión Qwen2.5-VL-3B-Instruct) y ajuste bayesiano de creencias sobre un núcleo axiomático invariante.

## Zonas frágiles
- Consumo de RAM: Qwen2.5-3B-Instruct Q4_K_M (~1.9–2.0 GB) + proyector visual futuro + Laya/BMP (~100 MB) debe mantenerse < 3.5 GB (RNF03).
- Qwen2.5-3B-Instruct es solo texto: la multimodalidad (T9) exige Qwen2.5-VL-3B-Instruct y un `mmproj.gguf` de la misma versión.
- Qwen2.5 usa ChatML y no trae tag nativo de pensamiento: el bloque ` thinking` depende del system prompt y del dataset, hay que re-verificarlo con `check_format.py`.
- `outputs/` puede contener varios `.gguf` (MiniCPM y Qwen); los scripts eligen el más reciente por fecha.
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

## Próximos pasos
- T11.6: smoke test con Qwen2.5-3B-Instruct, reentrenamiento y `check_format.py` sobre el nuevo GGUF.
- T11.2/T11.3: set corto de evaluación en español para comparar MiniCPM5 vs Qwen2.5 y registrar resultados.
- Fase 2: T1.1 configurar Flutter y T1.2 puente FFI para llama.cpp con el GGUF de Qwen.
- Nuevas líneas (ver TASKS.md): enrutador Laya/BMP, base de visión Qwen2.5-VL-3B-Instruct, trazas ` thinking`, persistencia `lain_experiences.jsonl` y ciclo SFT/CoT + DPO.
