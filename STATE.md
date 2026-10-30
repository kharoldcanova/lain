# STATE.md

## Tarea en curso
MVP funcional de LAIN en Android: APK release compilado y verificado (30.8 MB, sin modelos, con pantalla «Modelos» e importación SAF). **Pendiente: validación del usuario en el Samsung Galaxy A14** (instalar, importar Qwen3-1.7B, conversar, historial y offline). No se declara validado en Android físico hasta que el usuario realice las pruebas.

## Objetivo actual
Validar el MVP en un dispositivo Android real con Qwen3-1.7B y el prompt de identidad (sin JSON de metacognición), y presentar el contrato de salida propuesto (Fase C.1) para su revisión antes del SFT de LAIN-ES MVP.


## Objetivo anterior
Validar Qwen2.5-3B-Instruct como base de LAIN (español correcto + bloque `<think>` estable) y luego iniciar la Fase 2 (Flutter).

## Concepción vigente
LAIN = LOCAL ARTIFICIAL INTELIGENCE NEURONAL. Asistente Edge AI con consciencia funcional (no fenomenológica): GWT, HOT (`<think>`), RPT, percepción visual en dos pasos (MiniCPM-V 4 describe, Qwen razona) y ajuste bayesiano de creencias sobre un núcleo axiomático invariante.

## Zonas frágiles
- Las `.so` de llama.cpp no se versionan (`jniLibs/` está ignorado): hay que ejecutar `mobile_app/tools/build_llama_android.sh` antes de compilar el APK.
- El puente debe llamarse `liblain_llm.so` (prefijo `lib`): `dlopen` resuelve por nombre y sin el prefijo falla aunque el archivo exista.
- El APK necesita `useLegacyPackaging = true`; con `extractNativeLibs=false` las `.so` quedan dentro del APK y `dlopen("liblain_llm.so")` devuelve «library not found».
- La carpeta `files/models` la debe crear la app: si se crea con `adb shell mkdir` queda propiedad de `shell` y la app no puede leer el GGUF.
- `flutter test integration_test/...` desinstala la app al terminar y Android borra `files/models`: hay que volver a copiar el modelo antes de cada corrida.
- Consumo de RAM: Qwen2.5-3B-Instruct Q4_K_M (~1.9–2.0 GB) o VLM MiniCPM-V 4 (~3.0 GB, solo con imagen) + Laya/BMP (~100 MB) debe mantenerse < 3.5 GB (RNF03).
- La visión es en dos pasos: MiniCPM-V 4 describe la imagen en texto y Qwen razona sobre esa descripción; no se comparten embeddings.
- La plantilla de chat de MiniCPM-V 4 concatena `content` como texto: `vision.py` aplana la lista de partes (`MiniCPMVHandler`).
- Qwen2.5 usa ChatML y no trae tag nativo de pensamiento: el bloque `<think>` depende del system prompt y del dataset, hay que re-verificarlo con `test/check_format.py`.
- `outputs/` puede contener varios `.gguf` (MiniCPM y Qwen); los scripts eligen el más reciente por fecha.
- VLM y LLM no deben convivir en VRAM: el VLM se libera antes de cargar Qwen (~3.0 GB + ~1.9 GB no caben juntos en 6 GB).
- Entorno Python: requiere Python 3.12 (Unsloth no soporta 3.13+); `torch`/`torchvision` deben ser de la misma build CUDA (cu126).
- Latencia inaceptable en móvil: Qwen2.5-3B Q4_K_M en CPU responde con una demora muy alta para conversación (reportado al probar el APK arm64). El prompt de sistema (~1.5k tokens) más el bloque `[MEMORIA]` agravan el TTFT; es el argumento principal de T15 (modelo pequeño o propio).
- `--split-per-abi` **no** se puede usar con `abiFilters` en `defaultConfig`: AGP aborta con «Conflicting configuration: 'arm64-v8a,x86_64' in ndk abiFilters cannot be present when splits abi filters are set». El build documentado es universal: `flutter build apk --release` (el `abiFilters` ya limita a arm64-v8a y x86_64). Tampoco usar `--target-platform android-arm64` con `jniLibs` de dos ABIs: ese APK crashea en x86_64 (`libflutter.so is for EM_AARCH64`).
- Qué modelo carga la app: el activo registrado en `models/active.json` (ModelManager); si no hay, el `.gguf` suelto más reciente en `files/models/` (modelos por `adb push`). El arranque escribe `init: modelo=<nombre>` en `lain_startup.log`. Sin modelo, la app arranca igual y pide importar uno (estado «Falta el modelo»).
- El emulador `lain` del AVD tiene 8 GB de `/data`: no alcanza para el APK (~1.6 GB) más la copia del GGUF (~1.5 GB). Para pruebas en emulador hace falta un AVD con `disk.dataPartition.size=16G` (se creó `lain16` en `~/.android/avd/`).
- SQLite propio: `package:sqlite3` empaqueta SQLite con FTS5 (no el del sistema); el tokenizer `trigram` exige SQLite ≥ 3.34, por eso no se usa `sqflite`.
- La memoria se guarda en `getApplicationSupportDirectory()/lain.db`; el historial del chat anterior (vía `sqflite`) no se migra.
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
- Reentrenamiento de Qwen2.5-3B-Instruct: QLoRA, 90 pasos, batch 1, `max_seq_length` 1024, solo `personality_es.jsonl`; 636 s, loss final 0.15.
- Export del GGUF `python_ai/outputs/Qwen2.5-3B-Instruct.Q4_K_M.gguf` (1.8 GB).
- Verificación del modelo (T11.6): `check_format.py` 20/20 bloques `<think>` con JSON válido, 0 sin cerrar (PASS); `eval_es.py` 8/8 respuestas con formato válido, latencia 2.5–4.0 s por respuesta en RTX 3050.
- App Flutter (T1.1): proyecto creado con plataformas Android/iOS, `flutter_riverpod` 3.4.3, `path_provider` 2.1.6 y `flutter_lints` 6.0.0; esqueleto con tema oscuro propio, modelo `ChatMessage`, `ChatController` (Riverpod) y pantalla de chat; `flutter analyze` sin issues y 3 pruebas en verde.
- Inferencia local en Android (T1.2–T1.5): llama.cpp `caa8191` compilado para `arm64-v8a` y `x86_64`, puente C `lain_llm.c` → bindings `dart:ffi` → motor en isolate con streaming por `SendPort`; GGUF cargado desde `files/models/` y respuesta real con bloque `think` en emulador x86_64 (APK release 27.4 MB). `flutter analyze` limpio, 4 pruebas de widget en verde y 2 pruebas de integración en dispositivo.
- Bug cerrado y verificado: el GGUF nunca se copiaba desde T1.6 (`modelAssetPath` sin `flutter_assets/`); en emulador x86_64 la copia tarda 18 s y la carga 7–11 s.
- Bug cerrado: el GGUF nunca se copiaba porque `modelAssetPath` omitía el prefijo `flutter_assets/`; verificado en emulador x86_64 (copia 18 s, carga 11 s, respuesta con `think` oculto).
- T14: memoria persistente local estilo Engram sobre `package:sqlite3` (FTS5 trigram): `observations`, `user_prompts`, `memory_relations`; deduplicación por hash, revisión por `topic_key`, recall inyectado en el system prompt y pantalla «Memoria». 44 pruebas en verde.
- T1.9: historial persistido en SQLite (`lain.db`, tabla `messages`); `SqliteChatStore` con `loadRecent`/`saveTurn`/`clear`, restauración al abrir y botón de limpiar con confirmación. 4 pruebas con SQLite real (ffi) y 19 en total.
- T1.7: `ThinkParser` separa el bloque `think` del texto visible (fragmentos partidos, bloques consecutivos, sin cierre) y la UI lo muestra en un panel colapsable; 6 pruebas del parser y 12 en total en verde.
- Prueba de MiniCPM5-2B en CPU del PC (4 hilos, `n_gpu_layers=0`, mismos 5 prompts y 180 tokens): media 11.8 s/turno (~11.4 tok/s) frente a 16.0 s de Qwen2.5-3B (~8.2 tok/s), es decir ~26 % menos latencia; formato `<think>` 5/5 válido en ambos. El español es peor: se cuelan caracteres chinos («tamaño del `向量` de salida») y léxico inventado, pero el caso emocional («no sirvo para nada») lo trató mejor que Qwen.
- App móvil con MiniCPM5-2B: asset empaquetado y copiado al primer arranque, carga y generación reales verificadas en emulador x86_64 (respuesta `<think>` JSON válido + texto visible). `locateModel()` elige el GGUF más reciente de `files/models/` y `modelFileName` pasó a `MiniCPM5-2B.Q4_K_M.gguf`; APK release universal de 1.59 GB. `flutter analyze` limpio y 48 pruebas en verde.
- APK de release documentado como universal: el `--split-per-abi` del README chocaba con el `abiFilters` añadido el 2026-10-28.
- Calidad del español mejoró frente a MiniCPM5-2B (frases completas, respuestas coherentes), pero siguen errores («Soyo soy es un modelo…», «los grupos más avances», corrección ortográfica equivocada en «Haber si mañana…») y una respuesta que valida el pensamiento negativo («No sirves para nada») en vez de acompañarlo → dataset a revisar en T11.7.
- Decisión de producto: sustituir MiniCPM5-2B como modelo conversacional principal (español deficiente); Qwen2.5-3B queda en PC (latencia inaceptable en móvil). Evaluación comparativa autorizada de Qwen3-1.7B, Qwen3-0.6B y Llama 3.2 1B Instruct (benchmark de 60 escenarios en español en curso en el PC).
- Fase B externalización (commit `8034c39`): el APK ya no empaqueta GGUF (asset quitado de `pubspec.yaml`, `noCompress` eliminado de gradle); arranque sin modelo con instrucciones claras; `ModelManager` (`lib/data/llm/model_manager.dart` + `model_metadata.dart`) con inventario `models/<id>/model.json`, importación con SHA-256 en un solo pase, verificación de espacio, copia temporal + renombrado atómico, detección de instalaciones incompletas, modelo activo (`active.json`) y eliminación que solo toca la carpeta del modelo; `locateModel()` conserva el fallback de GGUF sueltos (`adb push`). 65 pruebas en verde y `flutter analyze` limpio.
- APK release verificado (5.6 parcial): 30.4 MB, sin GGUF/ONNX/pesos (solo `AssetManifest.bin` y `DebugProbesKt.bin`). Falta: instalación en dispositivo, persistencia al actualizar y offline.
- Benchmark comparativo completado (PC, llama.cpp `caa8191`, CPU 12 hilos, `-ngl 0`, 60 escenarios / 82 turnos, muestreo no-thinking temp 0.7): Qwen3-1.7B TTFT medio 477 ms, 11.06 tok/s, ~2.32 GB VmHWM; Qwen3-0.6B 187 ms / 26.72 tok/s / ~1.24 GB; Llama 3.2 1B 194 ms / 15.37 tok/s / ~1.67 GB. Calidad: Qwen3-1.7B español limpio y JSON de metacognición impecable, pero emite SOLO el JSON (0/82 con `<think>`, sin respuesta visible) en modo no-thinking → el formato LAIN hay que fijarlo con SFT o plantilla; Qwen3-0.6B descartada (ecos del usuario, fuga de instrucciones `</tool_call>`, sin respuestas); Llama 3.2 1B coherente pero rompe personaje («como modelo de lenguaje»), confabula y contamina el formato (`<p>`, `**Think**`). Recomendación: Qwen3-1.7B como base (pendiente de revisión del usuario).
- Fase C.1 (contrato de salida) — causa raíz del JSON-only encontrada en el TEMPLATE del GGUF: con `enable_thinking=false` la plantilla pre-siembra `<think>\n\n</think>\n\n` vacío y, combinada con el prompt que obliga a empezar con `<think>JSON</think>`, el modelo emite solo el JSON y se detiene (además el JSON se parece a un tool call). En modo por defecto el comportamiento es mixto (52/82 solo-JSON, 0/82 con `<think>`, resto respuestas directas limpias). Con prompt de personalidad pura (sin JSON) el modelo responde directo, empático y limpio (sonda s27/s41). Contrato propuesto: `<think>…</think>` como único marcador estructural (compatible con llama.cpp, ThinkParser y el dataset SFT); dentro del bloque, JSON de metacognición OPCIONAL (belief_capture ya tolera su ausencia) o razonamiento libre; respuesta visible = texto tras `</think>`. MVP: prompt de identidad sin JSON + modo por defecto; la metacognición JSON vuelve con el SFT (LAIN-ES MVP).

## Próximos pasos
- Validar el MVP en el teléfono: instalar el APK release, importar `Qwen3-1.7B-Q4_K_M.gguf` desde la pantalla «Modelos» (o `adb push`), conversar en español, verificar historial y modo avión.
- Fase C.1: revisión del usuario del contrato de salida propuesto (JSON de metacognición opcional dentro de `<think>`, vuelve con SFT) antes de LAIN-ES MVP.
- LAIN-ES MVP (después de la revisión): SFT LoRA/QLoRA de Qwen3-1.7B con `personality_es.jsonl` para fijar el formato `<think>` + JSON + respuesta.
- Fase 5: decidir el filtro armeabi-v7a del APK universal (hoy instalaría en 32-bit sin `libllama`).
- Medir MiniCPM5-2B en el teléfono (T15.6/T1.8): instalar `mobile_app/build/app/outputs/flutter-apk/app-release.apk`, enviar 3 turnos y leer `ttft`/`total` en `lain_startup.log`; después `adb push` del Qwen y repetir para comparar.
- T11.7: revisar el dataset (respuestas que validan pensamientos negativos, concordancia y ortografía) y medir de nuevo con `test/check_format.py` + `test/eval_es.py` tras corregirlo.
- T9: portar la visión en dos pasos a la app (cámara, liberar VLM antes del LLM).
- T9.7: pedir el caption del VLM en inglés (más preciso) y que Qwen lo traduzca; hoy arrastra «conductor's» y «un blusa».
- T11.3 (resto): comparar Qwen2.5-3B contra los candidatos restantes (Salamandra-2B, EuroLLM-1.7B, Qwen3-1.7B, Gemma-3-1B) con `test/eval_es.py` y registrar resultados.
- Fase 2: medir latencia en un teléfono arm64 real (T1.8); historial multi-turno en el prompt (requiere extender `lain_format_prompt` a N mensajes y recompilar las `.so`); después STT (T2.x).
- Interalimentación (T13.6–T13.9): cerrar el bucle de mejora LLM ↔ VLM ↔ experiencias — el LLM re-consulta al VLM cuando la descripción visual no alcanza, cada turno deja una experiencia en `lain_experiences.jsonl` que alimenta SFT/DPO, con filtro de calidad, revisión humana y evaluación de regresión por versión.
- Modelo propio pequeño (Pixys, T15): el 3B Q4 de 1.9 GB condiciona el APK, la RAM y el primer arranque; se evalúan modelos de 300M–1B y, en paralelo, la ruta de aprendizaje Pixys (vault `Boveda/AI/IA/Proyecto Pixys.md`) para construir uno propio con tokenizer español.
- Nuevas líneas (ver TASKS.md): enrutador Laya/BMP, visión en dos pasos con MiniCPM-V 4, trazas `<think>`, persistencia `lain_experiences.jsonl` y ciclo SFT/CoT + DPO.
