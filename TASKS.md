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
- [x] T5.5 Probar inferencia con `scripts/infer.py` (validar personalidad).
  - [x] Inferencia funcional verificada sobre el GGUF exportado.
- [ ] T5.6 Preparar dataset de trazas metacognitivas (`thought_trace`) para SFT/CoT.
- [ ] T5.7 Preparar pares de preferencia para DPO (`rejected_alternative`).
- [ ] T5.8 Reentrenar con Qwen2.5-3B-Instruct (solo `personality_es.jsonl`) y exportar GGUF Q4_K_M.

### Funcionalidad 7: Ciclo de reentrenamiento offline
- [ ] T7.1 Definir y documentar el esquema `lain_experiences.jsonl`.
- [ ] T7.2 Script de extracción/validación de experiencias desde el dispositivo a la PC.
- [ ] T7.3 Pipeline SFT/CoT sobre pares `thought_trace` + `model_output`.
- [ ] T7.4 Pipeline DPO sobre interacciones corregidas por el usuario.
- [ ] T7.5 Cuantizar a GGUF Q4_K_M y re-desplegar la versión evolucionada.

## Fase 2: Conexión con la app (Flutter)

### Funcionalidad 1: Inferencia de texto local
- [ ] T1.1 Configurar proyecto Flutter en `mobile_app/` con dependencias base.
- [ ] T1.2 Integrar puente FFI para llama.cpp (bindings Dart ↔ C++).
- [ ] T1.3 Cargar el GGUF de Qwen2.5-3B-Instruct desde almacenamiento local.
- [ ] T1.4 Inyectar System Prompt dinámico para personalidad en español.
- [ ] T1.5 Implementar streaming de tokens (Time to First Token < 2s).
- [ ] T1.6 Generar y procesar el bloque de pensamiento `<think>` antes de la respuesta externa.

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

### Funcionalidad 9: Percepción multimodal
- [ ] T9.1 Elegir la base de visión (previsto Qwen2.5-VL-3B-Instruct) y cargar su `mmproj.gguf` en llama.cpp.
- [ ] T9.2 Capturar imágenes/fotogramas de la cámara en Flutter.
- [ ] T9.3 Codificar parches visuales e integrarlos al espacio de embeddings del LLM.
- [ ] T9.4 Permitir que `<think>` reflexione sobre estímulos visuales.
- [ ] T9.5 Medir RAM del modelo de visión y confirmar RNF03 (< 3.5 GB).

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
- [ ] T11.2 Construir un set corto de evaluación en español: fluidez, coherencia, seguimiento de instrucciones y `<think>` JSON válido.
- [ ] T11.3 Medir el modelo actual contra los candidatos y registrar resultados.
  - Medición informal del 2026-10-26: MiniCPM5-2B estable en formato (6/6) pero con errores de español (léxico inventado, concordancia, definiciones erróneas).
- [x] T11.4 Elegir el modelo base y adaptar `finetune.py` / `infer.py`. Decisión: Qwen2.5-3B-Instruct (texto).
- [x] T11.5 Documentar la decisión, licencia y tamaño en RAM/GGUF. Licencia Qwen Research (no comercial); ~1.9–2.0 GB Q4_K_M.
- [ ] T11.6 Reentrenar y medir Qwen2.5-3B-Instruct (formato `<think>` + calidad de español) y decidir si se mantiene.

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
- [x] T13.5 `scripts/check_format.py`: mide la tasa de `<think>` JSON válido (20/20 tras ampliar el dataset).

## Fase 3: Requisitos no funcionales (transversal)

### Funcionalidad 6: RNF
- [ ] T6.1 Garantizar modo 100% offline (sin llamadas de red).
- [ ] T6.2 Validar consumo de RAM < 3.5 GB (Qwen2.5-3B-Instruct + proyector de visión + Laya/BMP).
- [ ] T6.3 Compilar correctamente en ARM64 (Android).
- [ ] T6.4 Asegurar privacidad total de datos.
- [ ] T6.5 Validar el flujo metacognitivo completo (entrada → Laya/BMP → `<think>` → salida → `.jsonl`) sin superar latencia objetivo.
