# STATE.md

## Tarea en curso
Fase 2 avanzada: la app Flutter ya hace inferencia real en Android con el GGUF de Qwen2.5-3B-Instruct empaquetado en el APK (T1.2–T1.6), verificado: APK release 1.96 GB con el GGUF y las `.so` para arm64-v8a y x86_64, `flutter analyze` limpio, 5 pruebas en verde. T1.7 cerrado (bloque `think` separado y colapsable), T1.9 cerrado (historial en SQLite) y T14 cerrada (memoria persistente estilo Engram: observaciones con FTS5 trigram, deduplicación, creencias del bloque `think`, recall en el prompt y pantalla de revisión). Sigue pendiente medir latencia en un teléfono arm64 real (T1.8). En paralelo, la calidad del modelo sigue abierta (T11.7).

## Objetivo actual
Probar el APK en el teléfono (T1.8: latencia real y memoria en uso); después, dar contexto multi-turno al modelo (el puente C solo acepta system+user) y seguir con STT (Fase 2, Funcionalidad 2).


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
- T14: memoria persistente local estilo Engram sobre `package:sqlite3` (FTS5 trigram): `observations`, `user_prompts`, `memory_relations`; deduplicación por hash, revisión por `topic_key`, recall inyectado en el system prompt y pantalla «Memoria». 44 pruebas en verde.
- T1.9: historial persistido en SQLite (`lain.db`, tabla `messages`); `SqliteChatStore` con `loadRecent`/`saveTurn`/`clear`, restauración al abrir y botón de limpiar con confirmación. 4 pruebas con SQLite real (ffi) y 19 en total.
- T1.7: `ThinkParser` separa el bloque `think` del texto visible (fragmentos partidos, bloques consecutivos, sin cierre) y la UI lo muestra en un panel colapsable; 6 pruebas del parser y 12 en total en verde.
- Calidad del español mejoró frente a MiniCPM5-2B (frases completas, respuestas coherentes), pero siguen errores («Soyo soy es un modelo…», «los grupos más avances», corrección ortográfica equivocada en «Haber si mañana…») y una respuesta que valida el pensamiento negativo («No sirves para nada») en vez de acompañarlo → dataset a revisar en T11.7.

## Próximos pasos
- T11.7: revisar el dataset (respuestas que validan pensamientos negativos, concordancia y ortografía) y medir de nuevo con `test/check_format.py` + `test/eval_es.py` tras corregirlo.
- T9: portar la visión en dos pasos a la app (cámara, liberar VLM antes del LLM).
- T9.7: pedir el caption del VLM en inglés (más preciso) y que Qwen lo traduzca; hoy arrastra «conductor's» y «un blusa».
- T11.3 (resto): comparar Qwen2.5-3B contra los candidatos restantes (Salamandra-2B, EuroLLM-1.7B, Qwen3-1.7B, Gemma-3-1B) con `test/eval_es.py` y registrar resultados.
- Fase 2: medir latencia en un teléfono arm64 real (T1.8); historial multi-turno en el prompt (requiere extender `lain_format_prompt` a N mensajes y recompilar las `.so`); después STT (T2.x).
- Interalimentación (T13.6–T13.9): cerrar el bucle de mejora LLM ↔ VLM ↔ experiencias — el LLM re-consulta al VLM cuando la descripción visual no alcanza, cada turno deja una experiencia en `lain_experiences.jsonl` que alimenta SFT/DPO, con filtro de calidad, revisión humana y evaluación de regresión por versión.
- Modelo propio pequeño (Pixys, T15): el 3B Q4 de 1.9 GB condiciona el APK, la RAM y el primer arranque; se evalúan modelos de 300M–1B y, en paralelo, la ruta de aprendizaje Pixys (vault `Boveda/AI/IA/Proyecto Pixys.md`) para construir uno propio con tokenizer español.
- Nuevas líneas (ver TASKS.md): enrutador Laya/BMP, visión en dos pasos con MiniCPM-V 4, trazas `<think>`, persistencia `lain_experiences.jsonl` y ciclo SFT/CoT + DPO.
