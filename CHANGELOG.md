# CHANGELOG

## [Unreleased]

### Added
- `mobile_app/android/app/src/main/cpp/lain_llm.c`: puente C con ABI mínima sobre llama.cpp (`lain_load`, `lain_free`, `lain_context_size`, `lain_format_prompt`, `lain_generate`) que emite cada token por callback.
- `mobile_app/lib/data/llm/lain_native.dart`: bindings `dart:ffi` a `liblain_llm.so` con traducción de errores nativos a `LainException`.
- `mobile_app/lib/data/llm/lain_engine.dart`: motor de inferencia en un isolate dedicado; tokens por `SendPort` como `Stream<String>`, `NativeCallable.isolateLocal` y `Utf8Chunker` para no partir caracteres UTF-8.
- `mobile_app/lib/data/llm/model_store.dart`: localiza el GGUF en el almacenamiento externo de la app (`files/models/`).
- `mobile_app/tools/build_llama_android.sh`: compila llama.cpp (`caa8191`) y el puente para `arm64-v8a` y `x86_64`, y los copia a `jniLibs/`.
- `mobile_app/assets/system_prompt.txt`: copia del system prompt de `python_ai/datasets/` que la app inyecta con la plantilla ChatML del GGUF.
- `mobile_app/integration_test/model_smoke_test.dart`: prueba en dispositivo que carga el GGUF real y genera texto con llama.cpp.
- `mobile_app/README.md`: requisitos del toolchain, compilación de las `.so`, build del APK, copia del modelo y arquitectura del puente.
- `mobile_app/lib/domain/chat/chat_state.dart`: `EngineStatus` (starting, loading, ready, missingModel, unsupported, error) y estado de generación.
- `mobile_app/test/widget_test.dart`: pruebas con `FakeEngine` y overrides de Riverpod (estado vacío, respuesta del motor, aviso de modelo ausente, mensajes vacíos).
- `mobile_app/lib/domain/chat/think_parser.dart`: parser incremental que separa el bloque `think` del texto visible tolerando fragmentos partidos, bloques consecutivos y bloques sin cerrar.
- `mobile_app/lib/data/storage/lain_database.dart`: `lain.db` con esquema v2 sobre `package:sqlite3` (SQLite empaquetado con FTS5): `messages`, `sessions`, `observations` + FTS5 trigram, `user_prompts` + FTS5 y `memory_relations`, con migración por `user_version`.
- `mobile_app/lib/data/storage/chat_store.dart`: `ChatStore` y `SqliteChatStore` (`loadRecent`, `saveTurn` en transacción, `clear`).
- `mobile_app/lib/data/storage/memory_store.dart`: memoria estilo Engram — `save` con deduplicación por hash y revisión por `topic_key`, `search` FTS5 por términos, `context` con presupuesto, `pin`, borrado lógico, `savePrompt`, `searchPrompts` y relaciones con `judgeRelation`.
- `mobile_app/lib/domain/memory/belief_capture.dart`: extrae `prior_belief` y `belief_shift` del JSON del bloque `think` y deriva un `topic_key`.
- `mobile_app/lib/data/diagnostics/startup_log.dart`: registro de arranque en archivo (`lain_startup.log`) con cada paso de la preparación del modelo y el error con stack.
- `mobile_app/lib/presentation/memory/memory_screen.dart`: pantalla «Memoria» con búsqueda, fijar, olvidar y resolución de creencias que cambiaron.
- `mobile_app/test/chat_store_test.dart`, `memory_store_test.dart`, `belief_capture_test.dart`, `memory_screen_test.dart`: 27 pruebas nuevas (44 en total).
- `mobile_app/test/think_parser_test.dart`: 6 pruebas del parser (bloque simple, fragmentado, falso positivo, múltiples bloques, sin cierre y sin bloque).

### Changed
- `mobile_app/lib/presentation/chat/chat_controller.dart`: providers de motor, localización del modelo y system prompt; el stream de tokens se vuelca en la última burbuja.
- `mobile_app/lib/presentation/chat/chat_screen.dart`: banner de estado (falta el modelo, solo Android, error del motor), indicador de generación y burbujas con streaming.
- `mobile_app/lib/domain/chat/chat_message.dart`: campo `thought` con el razonamiento sin tags.
- `mobile_app/lib/presentation/chat/chat_controller.dart`: el stream pasa por `ThinkParser`; la burbuja recibe texto limpio y pensamiento por separado.
- `mobile_app/lib/presentation/chat/chat_screen.dart`: el razonamiento se muestra en un panel colapsable («Razonamiento») dentro de la burbuja.
- `mobile_app/lib/presentation/chat/chat_controller.dart`: `chatStoreProvider`, restauración del historial al abrir, guardado del turno al terminar y `clearHistory()`.
- `mobile_app/lib/presentation/chat/chat_screen.dart`: acción «Limpiar conversación» con diálogo de confirmación.
- `mobile_app/pubspec.yaml`: `sqlite3`, `crypto` y `path`; se retiran `sqflite` y `sqflite_common_ffi`.
- `mobile_app/lib/presentation/chat/chat_controller.dart`: `memoryStoreProvider`; guarda el prompt, inyecta el bloque `[MEMORIA]` en el system prompt y registra la creencia del turno.
- `mobile_app/lib/presentation/chat/chat_screen.dart`: acción «Memoria» en la AppBar; botones «Reintentar» y «Ver registro» (con copia al portapapeles) en los estados de error.
- `mobile_app/lib/presentation/chat/chat_controller.dart`: el arranque escribe cada paso en `StartupLog`, comprueba el espacio libre antes de copiar el GGUF (mínimo 2.4 GB) y expone `retry()`.
- `mobile_app/android/.../MainActivity.kt`: método `freeBytes` del canal para consultar el espacio disponible.
- `mobile_app/android/app/build.gradle.kts`: `packaging { jniLibs { useLegacyPackaging = true } }` para extraer las `.so` al instalar (`dlopen` por nombre).
- `mobile_app/pubspec.yaml`: dependencia `ffi`, `integration_test` en dev, assets del system prompt y SDK mínimo `>=3.1.0`.

### Fixed
- El puente se compilaba como `lain_llm.so`; `DynamicLibrary.open('liblain_llm.so')` exige el prefijo `lib`. Ahora se genera como `liblain_llm.so`.
- Con `extractNativeLibs=false` las `.so` quedaban dentro del APK y `dlopen` fallaba con «library not found»; se fuerza la extracción con `useLegacyPackaging`.

### Added (empaquetado del modelo)
- `mobile_app/lib/data/llm/model_installer.dart`: `AssetModelInstaller` que copia el GGUF de `assets/models/` al almacenamiento de la app vía `MethodChannel` + `AssetManager` en streaming, reportando progreso 0..1.
- `mobile_app/android/app/src/main/kotlin/com/lain/lain_mobile/MainActivity.kt`: canal `com.lain.lain_mobile/model` con método `copyAsset` que copia el asset en streaming con `FileOutputStream` y `fd.sync()`.
- `mobile_app/assets/models/Qwen2.5-3B-Instruct.Q4_K_M.gguf`: modelo empaquetado en el APK (1.93 GB, ignorado por git).
- `mobile_app/lib/data/llm/model_store.dart`: constante `modelAssetPath` con la ruta del asset dentro del APK.
- `mobile_app/test/widget_test.dart`: pruebas de `ProviderContainer` para copia del modelo (éxito y falla) usando `FakeInstaller`.

### Changed
- `mobile_app/lib/presentation/chat/chat_controller.dart`: al arrancar, si no hay GGUF en `files/models/`, copia el asset empaquetado mostrando barra de progreso (`EngineStatus.preparingModel`) antes de cargar el modelo.
- `mobile_app/lib/domain/chat/chat_state.dart`: `EngineStatus.preparingModel` y campo `progress` (0..1) en `ChatState`.
- `mobile_app/lib/presentation/chat/chat_screen.dart`: banner «Preparando el modelo» con `LinearProgressIndicator` y porcentaje durante la copia del asset.
- `mobile_app/android/app/build.gradle.kts`: `androidResources { noCompress += "gguf" }` para que el GGUF no se comprima dentro del APK.
- `mobile_app/pubspec.yaml`: asset `assets/models/Qwen2.5-3B-Instruct.Q4_K_M.gguf` registrado.
- `mobile_app/README.md`: documentado el flujo de empaquetado (APK ~2 GB, copia automática al primer arranque, sin necesidad de `adb push`).

- `mobile_app/web/`: plataforma web habilitada para probar la UI en Chrome mientras no hay SDK de Android (`flutter run -d chrome`).
- `mobile_app/`: proyecto Flutter base para Android/iOS con `flutter_riverpod` 3.4.3, `path_provider` 2.1.6 y `flutter_lints` 6.0.0; esqueleto con tema oscuro propio, `ChatMessage`, `ChatController` y pantalla de chat con estado vacío y burbujas.
- `mobile_app/test/widget_test.dart`: pruebas de la pantalla de chat (estado vacío, envío de mensaje) y del controlador (ignora mensajes vacíos).
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
- `.gitignore`: se deja de ignorar `mobile_app/pubspec.lock`; las apps Flutter versionan su lockfile.
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
- Reentrenamiento de Qwen2.5-3B-Instruct: QLoRA, 90 pasos, batch 1, `max_seq_length` 1024, solo `personality_es.jsonl`; 636 s, loss final 0.15.
- Export del GGUF `python_ai/outputs/Qwen2.5-3B-Instruct.Q4_K_M.gguf` (1.8 GB).
- `check_format.py`: 20/20 bloques `<think>` con JSON válido, 0 sin cerrar → PASS con Qwen2.5-3B.
- `eval_es.py`: 8/8 respuestas con formato válido; latencia 2.5–4.0 s por respuesta en RTX 3050.
- Español mejoró frente a MiniCPM5-2B (frases completas, respuestas coherentes); quedan errores de concordancia/ortografía y una respuesta que valida el pensamiento negativo, a corregir en el dataset (T11.7).
