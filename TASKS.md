# TASKS.md — Desglose por funcionalidad

Basado en el documento fuente del proyecto y en el vault «Teoría y Arquitectura de Consciencia para LAIN». Orden: primero modelo, luego conexión con la app.

## Fase 1: Modelo (Fine-tuning en Python — PC)

### Funcionalidad 5: Fine-tuning
- [x] T5.1 Crear entorno Python en `python_ai/` con dependencias (torch, unsloth, transformers).
- [x] T5.2 Preparar dataset de personalidad en español (`personality_es.jsonl`).
- [x] T5.3 Script de fine-tuning con Unsloth (`scripts/finetune.py`).
- [x] T5.4 Ejecutar fine-tuning completo en PC (GPU) y exportar GGUF.
  - [x] Pipeline validado con smoke test (1 paso + export GGUF Q4_K_M).
  - [x] Corrida completa: 60 pasos (loss 2.30 → 0.68) + GGUF Q4_K_M.
- [x] T5.5 Probar inferencia con `test/infer.py` (validar personalidad).
  - [x] Inferencia funcional verificada sobre el GGUF exportado.
- [ ] T5.6 Preparar dataset de trazas metacognitivas (`thought_trace`) para SFT/CoT.
- [ ] T5.7 Preparar pares de preferencia para DPO (`rejected_alternative`).
- [x] T5.8 Reentrenar con Qwen2.5-3B-Instruct (solo `personality_es.jsonl`) y exportar GGUF Q4_K_M.
  - Corrida completa: 90 pasos, batch 1, `max_seq_length` 1024, 636 s, loss final 0.15 + GGUF `Qwen2.5-3B-Instruct.Q4_K_M.gguf` (1.8 GB).

### Funcionalidad 7: Ciclo de reentrenamiento offline
- [ ] T7.1 Definir y documentar el esquema `lain_experiences.jsonl`.
- [ ] T7.2 Script de extracción/validación de experiencias desde el dispositivo a la PC.
- [ ] T7.3 Pipeline SFT/CoT sobre pares `thought_trace` + `model_output`.
- [ ] T7.4 Pipeline DPO sobre interacciones corregidas por el usuario.
- [ ] T7.5 Cuantizar a GGUF Q4_K_M y re-desplegar la versión evolucionada.

## Fase 2: Conexión con la app (Flutter)

### Funcionalidad 1: Inferencia de texto local
- [x] T1.1 Configurar proyecto Flutter en `mobile_app/` con dependencias base.
  - `flutter create` (android/ios), `flutter_riverpod`, `path_provider` y `flutter_lints`; esqueleto con `main.dart`, `app.dart`, `core/theme.dart`, `domain/chat/chat_message.dart` y `presentation/chat/`; `flutter analyze` limpio y 3 pruebas en verde.
- [x] T1.2 Integrar puente FFI para llama.cpp (bindings Dart ↔ C++).
  - `android/app/src/main/cpp/lain_llm.c` (C ABI: `lain_load`, `lain_free`, `lain_context_size`, `lain_format_prompt`, `lain_generate`), bindings en `lib/data/llm/lain_native.dart`, `tools/build_llama_android.sh` compila llama.cpp (`caa8191`) para `arm64-v8a` y `x86_64`. Verificado en emulador x86_64: `dlopen` correcto y generación real.
- [x] T1.3 Cargar el GGUF de Qwen2.5-3B-Instruct desde almacenamiento local.
  - `lib/data/llm/model_store.dart` busca el GGUF en `files/models/` del almacenamiento externo; la pantalla avisa con el comando `adb push` si falta.
- [x] T1.4 Inyectar System Prompt dinámico para personalidad en español.
  - `assets/system_prompt.txt` (copia de `python_ai/datasets/system_prompt.txt`) se aplica con la plantilla ChatML del GGUF vía `llama_chat_apply_template`.
- [x] T1.5 Implementar streaming de tokens (Time to First Token < 2s).
  - Tokens emitidos por callback C → `NativeCallable.isolateLocal` → `SendPort` → `Stream<String>` en un isolate dedicado. Implementado; el TTFT de 2 s no se cumple en emulador x86_64 sin aceleración (pendiente medir en teléfono arm64).
- [x] T1.6 Empaquetar el GGUF en el APK y copiarlo automáticamente al primer arranque.
  - `assets/models/Qwen2.5-3B-Instruct.Q4_K_M.gguf` incluido en el APK (`androidResources { noCompress += "gguf" }`). `AssetModelInstaller` copia el asset vía `MethodChannel` + `AssetManager` en streaming con barra de progreso (`EngineStatus.preparingModel`). Verificado: APK release 1.96 GB, compilado y empaquetado correctamente.
- [x] T1.7 Procesar/ocultar el bloque `think` en la UI antes de mostrarlo.
  - `lib/domain/chat/think_parser.dart` separa el bloque del texto visible con tolerancia a fragmentos partidos, bloques consecutivos y bloques sin cerrar; `ChatMessage.thought` lo guarda y la burbuja lo muestra en un panel colapsable «Razonamiento». `flutter analyze` limpio y 12 pruebas en verde (6 del parser).
- [x] T1.9 Persistir el historial del chat en SQLite (`sqflite`).
  - `lib/data/storage/lain_database.dart` (esquema v1, tabla `messages` con `role`, `text`, `thought`, `created_at`) y `lib/data/storage/chat_store.dart` (`loadRecent`, `saveTurn` transaccional, `clear`). El controlador restaura el historial al abrir, guarda cada turno y permite borrarlo con confirmación. Degradación explícita: si la base no abre, el chat funciona sin memoria. 4 pruebas del store con SQLite real (`sqflite_common_ffi`) y 19 en total.
- [ ] T1.8 Medir latencia en hardware arm64 real (emulador x86_64 es referencia pesimista).

### Funcionalidad 2: Reconocimiento de voz a texto (STT)
- [ ] T2.1 Capturar audio del micrófono en Flutter.
- [ ] T2.2 Integrar whisper.cpp vía FFI para STT.
- [ ] T2.3 Convertir audio a texto editable en el chat.

### Funcionalidad 3: Síntesis de texto a voz (TTS)
- [ ] T3.1 Integrar motor TTS (Kokoro/Piper o nativo).
- [ ] T3.2 Reproducir respuesta en voz de forma progresiva (por oraciones).
- [ ] T3.3 Liberar recursos de GPU/NPU al salir del chat.

### Funcionalidad 4: Gestión de modelos locales
- [ ] T4.1 Verificar disponibilidad de archivos `.gguf`, `.gguf` (mmproj) y `.bin` en almacenamiento interno.
- [ ] T4.2 Permitir importar modelos desde el sistema de archivos.
- [ ] T4.3 Manejar errores de modelo no encontrado / corrupto.
- [ ] T4.4 Validar compatibilidad modelo base ↔ proyector `mmproj.gguf`.

### Funcionalidad 8: Consciencia funcional y metacognición
- [ ] T8.1 Integrar enrutador Laya/BMP (~15 ms) para clasificar emoción e intención.
- [ ] T8.2 Definir directrices de tono (`score` / `choice`) a partir de Laya/BMP.
- [ ] T8.3 Definir el Núcleo Axiomático Invariante (empatía, curiosidad, fe en la humanidad, aceptación del error).
- [ ] T8.4 Implementar evaluación de incertidumbre y auto-reconocimiento de "no lo sé".
- [ ] T8.5 Implementar actualización de creencias dinámicas (ajuste bayesiano).
- [ ] T8.6 Implementar bucle recurrente Laya/BMP (RPT) sobre respuestas previas.
- [ ] T8.7 Registrar asíncronamente la experiencia en `lain_experiences.jsonl` (Background Isolate).

### Funcionalidad 9: Percepción multimodal (visión en dos pasos)
- [x] T9.1 Elegir la base de visión y cargarla en llama.cpp: MiniCPM-V 4 GGUF Q4_K_M + `mmproj` vía `MTMDChatHandler`.
- [ ] T9.2 Capturar imágenes/fotogramas de la cámara en Flutter.
- [x] T9.3 Convertir la imagen en descripción textual (descripción + OCR) y pasarla al LLM de texto (`scripts/vision.py`).
- [x] T9.4 Permitir que `<think>` reflexione sobre la descripción visual (validado en PC).
- [ ] T9.5 Medir RAM del VLM y confirmar RNF03 (< 3.5 GB).
- [ ] T9.6 Liberar el VLM antes de cargar el LLM en el celular (carga secuencial).
- [ ] T9.7 Pedir la descripción del VLM en inglés y dejar que Qwen la traduzca: MiniCPM-V 4 arrastra errores en español («conductor's», «un blusa»).

### Funcionalidad 10: Conocimiento local (RAG)
- [x] T10.1 Script RAG en PC: ingesta, chunking, embeddings y SQLite (`scripts/rag.py`).
- [x] T10.2 Consulta semántica e inyección de contexto en `chat.py --rag`.
- [ ] T10.3 Descarga de URLs en la app con consentimiento y allowlist.
- [ ] T10.4 Extracción de texto y chunking on-device en Flutter.
- [ ] T10.5 Embeddings on-device (e5-small / llama.cpp) y almacenamiento SQLite.
- [ ] T10.6 Recuperación top-k e inyección en el prompt en el dispositivo.
- [ ] T10.7 Gestión de fuentes: listar, ver y borrar conocimiento descargado.

### Funcionalidad 11: Modelo local pequeño con buen español (investigación)
- [ ] T11.1 Evaluar candidatos pequeños con español fuerte (Salamandra-2B-Instruct, EuroLLM-1.7B, Qwen3-1.7B, Gemma-3-1B) verificando soporte en Unsloth y licencia.
- [x] T11.2 Construir un set corto de evaluación en español: `test/eval_es.py` (8 casos, formato, latencia y JSON de salida).
- [ ] T11.3 Medir el modelo actual contra los candidatos y registrar resultados.
  - Medición informal del 2026-10-26: MiniCPM5-2B estable en formato (6/6) pero con errores de español (léxico inventado, concordancia, definiciones erróneas).
- [x] T11.4 Elegir el modelo base y adaptar `finetune.py` / `infer.py`. Decisión: Qwen2.5-3B-Instruct (texto).
- [x] T11.5 Documentar la decisión, licencia y tamaño en RAM/GGUF. Licencia Qwen Research (no comercial); ~1.9–2.0 GB Q4_K_M.
- [x] T11.6 Reentrenar y medir Qwen2.5-3B-Instruct (formato `<think>` + calidad de español) y decidir si se mantiene.
  - Se mantiene: `check_format.py` 20/20 bloques `<think>` con JSON válido, 0 sin cerrar (PASS); `eval_es.py` 8/8 respuestas con formato válido, latencia 2.5–4.0 s por respuesta (RTX 3050). Español mejoró frente a MiniCPM5-2B; errores residuales pasan a T11.7.
- [ ] T11.7 Revisar el dataset para corregir respuestas que validan pensamientos negativos y errores de concordancia.

### Funcionalidad 15: Modelo propio pequeño y eficiente (Pixys)
Contexto: Qwen2.5-3B-Instruct Q4_K_M pesa 1.9 GB, lo que obliga a un APK de 1.9 GB, ~2 GB de RAM en uso y una copia inicial de 1.9 GB en el dispositivo. Un modelo de 300M–1B con tokenizer y personalidad propios bajaría el APK por debajo de 700 MB y reduciría el tiempo de arranque y la presión de memoria.

Pixys es la ruta de aprendizaje para construirlo (vault Obsidian: `Boveda/AI/IA/Proyecto Pixys.md`): MLP en NumPy → self-attention y multi-head → tokenizer BPE → KV cache → cuantización → servidor local con RAG y MCP. Aún no ha comenzado.

- [ ] T15.1 Medir el coste real del modelo actual en el teléfono (tamaño instalado, RAM pico, TTFT) para fijar el objetivo.
- [ ] T15.2 Evaluar modelos pequeños existentes (Qwen3-0.6B, Gemma-3-270M, SmolLM2-360M, Salamandra-2B) con `test/eval_es.py`.
- [ ] T15.3 Definir el criterio de aceptación: tamaño del GGUF, RAM, TTFT y calidad mínima en español.
- [ ] T15.4 Avanzar la ruta Pixys en paralelo (Fase 1: perceptrón multicapa en NumPy) sin bloquear LAIN.
- [ ] T15.5 Decidir entre destilar el 3B actual o entrenar desde cero un modelo propio con tokenizer español.

### Funcionalidad 14: Memoria persistente local (estilo Engram)
- [x] T14.1 Migrar el motor a `package:sqlite3` (SQLite empaquetado con FTS5 garantizado) y retirar `sqflite`.
- [x] T14.2 Esquema v2: `sessions`, `observations` + FTS5 trigram, `user_prompts` + FTS5 y `memory_relations`, con migración desde la v1.
- [x] T14.3 Guardado con deduplicación por `normalized_hash` (`duplicate_count`) y revisión por `topic_key` (`revision_count`).
- [x] T14.4 Búsqueda léxica FTS5 por términos (OR) con respaldo `LIKE` y tolerancia a sintaxis inválida.
- [x] T14.5 Contexto para el prompt: fijadas + coincidencias + recientes, sin repetir y con presupuesto de caracteres.
- [x] T14.6 Captura desde el chat: prompts del usuario y creencias (`prior_belief` → `belief_shift`) del bloque `think`.
- [x] T14.7 Relaciones `supersedes` con `judgment_status='pending'` cuando cambia una creencia del mismo `topic_key`.
- [x] T14.8 Pantalla «Memoria»: buscar, fijar, olvidar y resolver creencias que cambiaron.

### Funcionalidad 12: Exportación de experiencias desde la app
- [ ] T12.1 Botón «Exportar experiencias» que genere JSONL con el esquema del vault.
- [ ] T12.2 Compartir/guardar con el selector del sistema y nombre con fecha.
- [ ] T12.3 Validar el esquema antes de exportar y avisar registros incompletos.
- [ ] T12.4 Consentimiento y aviso de privacidad antes de exportar.
- [ ] T12.5 Particionar o comprimir si el archivo supera el tamaño acordado.

### Funcionalidad 13: Ciclo de aprendizaje (importar → entrenar → desplegar)
- [x] T13.1 `scripts/import_experiences.py` para convertir experiencias en dataset SFT.
- [ ] T13.2 Versionar datasets y GGUF (fecha/hash) para poder revertir.
- [ ] T13.3 Pipeline DPO con `rejected_alternative`.
- [ ] T13.4 Prueba de regresión de personalidad tras cada reentrenamiento.
- [x] T13.5 `test/check_format.py`: mide la tasa de `<think>` JSON válido (20/20 tras ampliar el dataset).

### Interalimentación
- [ ] T13.6 Registrar pares de interalimentación (imagen → descripción → respuesta → corrección) en `lain_experiences.jsonl`.
- [ ] T13.7 Re-consulta al VLM desde el LLM cuando la descripción visual es insuficiente.
- [ ] T13.8 Filtro de calidad y revisión humana antes de incorporar experiencias al dataset.
- [ ] T13.9 Evaluación de regresión por versión con `test/check_format.py` y `test/eval_es.py`.

## Fase 3: Requisitos no funcionales (transversal)

### Funcionalidad 6: RNF
- [ ] T6.1 Garantizar modo 100% offline (sin llamadas de red).
- [ ] T6.2 Validar consumo de RAM < 3.5 GB (Qwen2.5-3B-Instruct + proyector de visión + Laya/BMP).
- [ ] T6.3 Compilar correctamente en ARM64 (Android).
- [ ] T6.4 Asegurar privacidad total de datos.
- [ ] T6.5 Validar el flujo metacognitivo completo (entrada → Laya/BMP → `<think>` → salida → `.jsonl`) sin superar latencia objetivo.
