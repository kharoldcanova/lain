# CHANGELOG

## [Unreleased]

### Added
- Documentación base del proyecto: README.md, AGENTS.md, STATE.md, ARCHITECTURE.md, CHANGELOG.md, TASKS.md.
- .gitignore para stack Flutter + Python + modelos de IA.
- Intención del proyecto importada desde documento fuente.
- Entorno Python base en `python_ai/` (requirements.txt, README.md, carpetas).
- Commit inicial del repositorio.
- T5.1 Entorno Python base completado.
- `python_ai/README.md`: sección «Qué contiene realmente el modelo entrenado» explicando que el GGUF guarda pesos y no el dataset, qué es cada artefacto de `outputs/` y el riesgo de memorización.
- `python_ai/scripts/chat.py`: chat manual con historial, streaming, `--hide-thought` y registro por turno en `experiences/lain_experiences.jsonl` con el esquema del vault (context/metacognition/response/training_metadata).
- Bloque `<thought>` reestructurado a JSON con `thought_trace`, `prior_belief`, `belief_shift` y `axiom_alignment_check`; el dataset y el system prompt se alinearon a ese formato.
- `python_ai/scripts/rag.py`: RAG local con embeddings on-device (`multilingual-e5-small`), SQLite y comandos `ingest`/`query`/`stats`/`clear`. `chat.py --rag` inyecta contexto recuperado.
- `python_ai/requirements_rag.txt` y documentación del RAG en el README raíz y de `python_ai/`.
- `python_ai/scripts/import_experiences.py`: convierte el JSONL exportado por la app en dataset SFT (filtra `suitable_for_sft`, exige `<thought>` completo y evita duplicados).
- README raíz: sección «Ciclo de aprendizaje» (exportar → importar → entrenar → desplegar) y regla hechos→RAG / estilo→reentrenamiento.
- TASKS.md: Funcionalidad 11 (evaluar modelo pequeño con buen español), 12 (exportar experiencias desde la app) y 13 (ciclo de aprendizaje).

### Changed
- Reescrita la concepción del proyecto a partir del vault de Obsidian «Teoría y Arquitectura de Consciencia para LAIN».
- README.md actualizado: nombre conceptual LOCAL ARTIFICIAL INTELIGENCE NEURONAL, consciencia funcional/metacognitiva, pilares cognitivos y restricciones de memoria (MiniCPM-V + mmproj + Laya/BMP).
- ARCHITECTURE.md actualizado: marcos teóricos (GWT, HOT, RPT), capacidades metacognitivas, percepción multimodal, núcleo axiomático y ajuste bayesiano de creencias, flujo metacognitivo de 4 pasos y ciclo de reentrenamiento offline (`.jsonl` + SFT/CoT + DPO).
- TASKS.md actualizado con funcionalidades de consciencia funcional, multimodalidad y persistencia de experiencias.
- `finetune.py` migrado a la API actual de Unsloth/TRL (`SFTConfig`, `processing_class`), modelo por defecto `openbmb/MiniCPM5-2B`, argumentos CLI (`--max-steps`, `--skip-hf`, `--no-export`) y movimiento del GGUF a `outputs/`.
- `infer.py` usa el chat template del GGUF, valida la existencia del modelo y recorta el bloque de pensamiento.
- `python_ai/README.md` con setup con `uv` (Python 3.12 + CUDA 12.6) y comandos de smoke test.
- `.gitignore` incluye `python_ai/outputs_gguf/`.

### Verified
- Smoke test de fine-tuning: 1 paso, loss 3.004, 30 s en RTX 3050 6 GB.
- Export GGUF Q4_K_M correcto (`MiniCPM5-2B.Q4_K_M.gguf`, 1.5 GB).
- Inferencia con `llama-cpp-python` sobre el GGUF exportado: respuesta en español.
- Corrida completa: 60 pasos con dataset local + guanaco, loss 2.30 → 0.68, GGUF final exportado y verificado.
