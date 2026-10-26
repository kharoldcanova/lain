# CHANGELOG

## [Unreleased]

### Added
- `python_ai/test/eval_es.py`: set de 8 casos (identidad, emoción, técnica, incertidumbre, adversarial, cotidiano, ortografía, matemática) con formato, latencia y salida JSON para comparar modelos base.
- `python_ai/scripts/vision.py`: visión en dos pasos (MiniCPM-V 4 describe la imagen y Qwen razona sobre el texto), con `--caption-only`, registro `vision_input` y `has_multimodal_input: true`.
- `python_ai/README.md`: sección «Visión (dos pasos)» con descarga de MiniCPM-V 4 y ejemplos de uso.
- `python_ai/scripts/common.py`: utilidad compartida que elige el `.gguf` más reciente de `outputs/`.
- `python_ai/README.md`: sección «Modelo base» con modelo, licencia, tamaño, plantilla ChatML y consecuencias del cambio.
- TASKS.md: T5.8 (reentrenar con Qwen), T9.5 (RAM de la base de visión) y T11.6 (medir Qwen tras reentrenar).
- Documentación base del proyecto: README.md, AGENTS.md, STATE.md, ARCHITECTURE.md, CHANGELOG.md, TASKS.md.
- .gitignore para stack Flutter + Python + modelos de IA.
- Intención del proyecto importada desde documento fuente.
- Entorno Python base en `python_ai/` (requirements.txt, README.md, carpetas).
- Commit inicial del repositorio.
- T5.1 Entorno Python base completado.
- `python_ai/README.md`: sección «Qué contiene realmente el modelo entrenado» explicando que el GGUF guarda pesos y no el dataset, qué es cada artefacto de `outputs/` y el riesgo de memorización.
- `python_ai/scripts/chat.py`: chat manual con historial, streaming, `--hide-thought` y registro por turno en `experiences/lain_experiences.jsonl` con el esquema del vault (context/metacognition/response/training_metadata).
- Bloque de pensamiento en JSON con `thought_trace`, `prior_belief`, `belief_shift` y `axiom_alignment_check`; el dataset y el system prompt se alinearon a ese formato.
- `python_ai/scripts/rag.py`: RAG local con embeddings on-device (`multilingual-e5-small`), SQLite y comandos `ingest`/`query`/`stats`/`clear`. `chat.py --rag` inyecta contexto recuperado.
- `python_ai/requirements_rag.txt` y documentación del RAG en el README raíz y de `python_ai/`.
- `python_ai/scripts/import_experiences.py`: convierte el JSONL exportado por la app en dataset SFT (filtra `suitable_for_sft`, exige los cuatro campos de metacognición y evita duplicados).
- README raíz: sección «Ciclo de aprendizaje» (exportar → importar → entrenar → desplegar) y regla hechos→RAG / estilo→reentrenamiento.
- TASKS.md: Funcionalidad 11 (evaluar modelo pequeño con buen español), 12 (exportar experiencias desde la app) y 13 (ciclo de aprendizaje).
- `WORKFLOW.md`: flujo completo de LAIN — entorno Python (SFT, DPO, RAG, importador), runtime en el celular, ciclo de aprendizaje y comparación SFT/DPO/RAG.
- `python_ai/scripts/validate_dataset.py`: valida el contrato del dataset (`<think>` + JSON de cuatro claves) antes de entrenar.
- `python_ai/test/check_format.py`: mide la estabilidad del bloque `<think>` en 20 prompts y exige ≥90 % de JSON válido sin bloques abiertos.
- Dataset SFT ampliado de 7 a 87 ejemplos (saludos, acompañamiento emocional, identidad, técnica, filosofía, cotidiano y adversariales).

### Changed
- Scripts de prueba y evaluación del modelo movidos de `python_ai/scripts/` a `python_ai/test/` (`check_format.py`, `eval_es.py`, `infer.py`); se actualizaron las rutas de los comandos en la documentación.
- Multimodalidad rediseñada a dos pasos: se descarta compartir embeddings visuales con el LLM; MiniCPM-V 4 (GGUF Q4_K_M + `mmproj`) genera descripción + OCR y ese texto entra al prompt de Qwen. VLM y LLM se cargan en secuencia para no sumar RAM.
- `chat.py`: `log_experience` acepta `trigger_type` y `has_multimodal_input` (por defecto `chat_message` / `false`).
- Modelo base cambiado de `openbmb/MiniCPM5-2B` a `Qwen/Qwen2.5-3B-Instruct` (3.1B, solo texto, licencia Qwen Research: uso no comercial): MiniCPM5 sostenía el formato `<think>` y el tono, pero su español era pobre (léxico inventado, concordancias rotas, definiciones erróneas).
- `finetune.py` entrena solo con `datasets/personality_es.jsonl`: se retiró el corpus guanaco y el flag `--skip-hf`.
- `finetune.py`, `chat.py`, `infer.py` y `check_format.py` usan el `.gguf` más reciente, no el primero, para convivir con varios modelos en `outputs/`.
- Documentación alineada al nuevo base: README, AGENTS, ARCHITECTURE, CONSCIENCIA, WORKFLOW, STATE y python_ai/README. La multimodalidad (T9) se resuelve con visión en dos pasos (MiniCPM-V 4 describe, Qwen razona).
- Proyección de memoria actualizada: Qwen2.5-3B-Instruct Q4_K_M ~1.9–2.0 GB (antes MiniCPM-V ~2.2–2.5 GB + mmproj).
- Reescrita la concepción del proyecto a partir del vault de Obsidian «Teoría y Arquitectura de Consciencia para LAIN».
- README.md actualizado: nombre conceptual LOCAL ARTIFICIAL INTELIGENCE NEURONAL, consciencia funcional/metacognitiva, pilares cognitivos y restricciones de memoria (MiniCPM-V + mmproj + Laya/BMP).
- ARCHITECTURE.md actualizado: marcos teóricos (GWT, HOT, RPT), capacidades metacognitivas, percepción multimodal, núcleo axiomático y ajuste bayesiano de creencias, flujo metacognitivo de 4 pasos y ciclo de reentrenamiento offline (`.jsonl` + SFT/CoT + DPO).
- TASKS.md actualizado con funcionalidades de consciencia funcional, multimodalidad y persistencia de experiencias.
- `finetune.py` migrado a la API actual de Unsloth/TRL (`SFTConfig`, `processing_class`), modelo por defecto `openbmb/MiniCPM5-2B`, argumentos CLI (`--max-steps`, `--skip-hf`, `--no-export`) y movimiento del GGUF a `outputs/`.
- `infer.py` usa el chat template del GGUF, valida la existencia del modelo y recorta el bloque de pensamiento.
- `python_ai/README.md` con setup con `uv` (Python 3.12 + CUDA 12.6) y comandos de smoke test.
- `.gitignore` incluye `python_ai/outputs_gguf/`.
- El bloque de pensamiento se unificó en `<think>` (tag nativo de MiniCPM5). Con `<thought>` la plantilla de chat inyectaba un bloque vacío y el modelo aprendía a dejar el JSON fuera. Verificado: 20/20 en `check_format.py`.
- Se corrigió el dataset inicial, que omitía el `</think>` de cierre.

### Verified
- Smoke test de fine-tuning: 1 paso, loss 3.004, 30 s en RTX 3050 6 GB.
- Export GGUF Q4_K_M correcto (`MiniCPM5-2B.Q4_K_M.gguf`, 1.5 GB).
- Inferencia con `llama-cpp-python` sobre el GGUF exportado: respuesta en español.
- Corrida completa: 60 pasos con dataset local + guanaco, loss 2.30 → 0.68, GGUF final exportado y verificado.
- Reentrenamiento con el dataset de 87 ejemplos: 120 pasos y GGUF Q4_K_M exportado.
- `validate_dataset.py`: 87/87 filas válidas.
- `check_format.py`: 20/20 bloques ` thinking` con JSON válido, 0 sin cerrar (baseline con el adaptador anterior: 0/10).
- `chat.py --hide-thought` oculta el bloque y registra la metacognición completa; `--rag` recupera contexto sin regresión.
