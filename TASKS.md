# TASKS.md — Desglose por funcionalidad

Basado en el documento fuente del proyecto y en el vault «Teoría y Arquitectura de Consciencia para LAIN». Orden: primero modelo, luego conexión con la app.

## Fase 1: Modelo (Fine-tuning en Python — PC)

### Funcionalidad 5: Fine-tuning
- [x] T5.1 Crear entorno Python en `python_ai/` con dependencias (torch, unsloth, transformers).
- [x] T5.2 Preparar dataset de personalidad en español (`personality_es.jsonl`).
- [x] T5.3 Script de fine-tuning con Unsloth (`scripts/finetune.py`).
- [ ] T5.4 Ejecutar fine-tuning en PC (GPU) y exportar GGUF.
- [ ] T5.5 Probar inferencia con `scripts/infer.py` (validar personalidad).
- [ ] T5.6 Preparar dataset de trazas metacognitivas (`thought_trace`) para SFT/CoT.
- [ ] T5.7 Preparar pares de preferencia para DPO (`rejected_alternative`).

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
- [ ] T1.3 Cargar modelo MiniCPM-V GGUF desde almacenamiento local.
- [ ] T1.4 Inyectar System Prompt dinámico para personalidad en español.
- [ ] T1.5 Implementar streaming de tokens (Time to First Token < 2s).
- [ ] T1.6 Generar y procesar el bloque de pensamiento `<thought>` antes de la respuesta externa.

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
- [ ] T9.1 Cargar el proyector visual `mmproj.gguf` en llama.cpp.
- [ ] T9.2 Capturar imágenes/fotogramas de la cámara en Flutter.
- [ ] T9.3 Codificar parches visuales e integrarlos al espacio de embeddings del LLM.
- [ ] T9.4 Permitir que `<thought>` reflexione sobre estímulos visuales.

## Fase 3: Requisitos no funcionales (transversal)

### Funcionalidad 6: RNF
- [ ] T6.1 Garantizar modo 100% offline (sin llamadas de red).
- [ ] T6.2 Validar consumo de RAM < 3.5 GB (incluyendo MiniCPM-V + mmproj + Laya/BMP).
- [ ] T6.3 Compilar correctamente en ARM64 (Android).
- [ ] T6.4 Asegurar privacidad total de datos.
- [ ] T6.5 Validar el flujo metacognitivo completo (entrada → Laya/BMP → `<thought>` → salida → `.jsonl`) sin superar latencia objetivo.
