# STATE.md

## Tarea en curso
Fase 1 completada. Siguiente: Fase 2 — conexión con la app Flutter (T1.1).

## Objetivo actual
Iniciar la integración Flutter ↔ llama.cpp con el modelo GGUF ya entrenado y validado.

## Concepción vigente
LAIN = LOCAL ARTIFICIAL INTELIGENCE NEURONAL. Asistente Edge AI con consciencia funcional (no fenomenológica): GWT, HOT (`<think>`), RPT, percepción multimodal (MiniCPM-V + mmproj) y ajuste bayesiano de creencias sobre un núcleo axiomático invariante.

## Zonas frágiles
- Consumo de RAM: MiniCPM-V Q4_K_M (~2.2–2.5 GB) + mmproj (~150–250 MB) + Laya/BMP (~100 MB) debe mantenerse < 3.5 GB (RNF03).
- Proyector multimodal `mmproj.gguf` debe coincidir con la versión exacta del modelo base.
- Entorno Python: requiere Python 3.12 (Unsloth no soporta 3.13+); `torch`/`torchvision` deben ser de la misma build CUDA (cu126).
- Dataset local muy pequeño (5 ejemplos): el fine-tuning de 60 pasos sobreajusta (loss 0.68); ampliar antes de una corrida "real".

## Completado
- Commit inicial del repositorio.
- T5.1 Entorno Python base creado.
- T5.2 Dataset de personalidad en español (`personality_es.jsonl`).
- T5.3 Script de fine-tuning con Unsloth (`scripts/finetune.py`).
- Documentación actualizada al vault «Teoría y Arquitectura de Consciencia para LAIN» (README, ARCHITECTURE, TASKS, CHANGELOG).
- Entorno recreado con uv (Python 3.12, torch 2.14.1+cu126, unsloth 2026.10.8).
- Pipeline de fine-tuning validado: smoke test 1 paso (loss 3.004, 30 s) y export GGUF Q4_K_M (1.5 GB).
- Inferencia validada con `llama-cpp-python` sobre el GGUF exportado.
- T5.4 completado: 60 pasos (loss 2.30 → 0.68), checkpoint-60 y GGUF Q4_K_M exportado.
- T5.5 completado: inferencia del modelo final en español alineada al system prompt.

## Próximos pasos
- Ampliar `personality_es.jsonl` antes de una corrida de producción (evitar sobreajuste).
- Fase 2: T1.1 configurar Flutter y T1.2 puente FFI para llama.cpp con el GGUF actual.
- Nuevas líneas (ver TASKS.md): enrutador Laya/BMP, multimodalidad MiniCPM-V, trazas `<think>`, persistencia `lain_experiences.jsonl` y ciclo SFT/CoT + DPO.
