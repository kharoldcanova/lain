# STATE.md

## Tarea en curso
T5.4 — Exportar modelo final a formato GGUF (incluido en `finetune.py`).

## Objetivo actual
Completar la Fase 1 (modelo): validación del modelo exportado tras la actualización de la concepción (consciencia funcional / metacognición, multimodalidad y persistencia de experiencias).

## Concepción vigente
LAIN = LOCAL ARTIFICIAL INTELIGENCE NEURONAL. Asistente Edge AI con consciencia funcional (no fenomenológica): GWT, HOT (`<thought>`), RPT, percepción multimodal (MiniCPM-V + mmproj) y ajuste bayesiano de creencias sobre un núcleo axiomático invariante.

## Zonas frágiles
- Consumo de RAM: MiniCPM-V Q4_K_M (~2.2–2.5 GB) + mmproj (~150–250 MB) + Laya/BMP (~100 MB) debe mantenerse < 3.5 GB (RNF03).
- Proyector multimodal `mmproj.gguf` debe coincidir con la versión exacta del modelo base.

## Completado
- Commit inicial del repositorio.
- T5.1 Entorno Python base creado.
- T5.2 Dataset de personalidad en español (`personality_es.jsonl`).
- T5.3 Script de fine-tuning con Unsloth (`scripts/finetune.py`).
- Documentación actualizada al vault «Teoría y Arquitectura de Consciencia para LAIN» (README, ARCHITECTURE, TASKS, CHANGELOG).

## Próximos pasos
- T5.4 Validar exportación GGUF (ejecutar en PC con GPU).
- T5.5 Prueba de inferencia en PC.
- Fase 2: conexión con la app Flutter.
- Nuevas líneas (ver TASKS.md): enrutador Laya/BMP, multimodalidad MiniCPM-V, trazas `<thought>`, persistencia `lain_experiences.jsonl` y ciclo SFT/CoT + DPO.
