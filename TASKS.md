# TASKS.md — Desglose por funcionalidad

Basado en el documento fuente del vault (`Proyecto LAIN..md`). Orden: primero modelo, luego conexión con la app.

## Fase 1: Modelo (Fine-tuning en Python — PC)

### Funcionalidad 5: Fine-tuning
- [x] T5.1 Crear entorno Python en `python_ai/` con dependencias (torch, unsloth, transformers).
- [x] T5.2 Preparar dataset de personalidad en español (`personality_es.jsonl`).
- [x] T5.3 Script de fine-tuning con Unsloth (`scripts/finetune.py`).
- [ ] T5.4 Exportar modelo final a formato GGUF.
- [ ] T5.5 Validar modelo exportado (inferencia de prueba en PC).

## Fase 2: Conexión con la app (Flutter)

### Funcionalidad 1: Inferencia de texto local
- [ ] T1.1 Configurar proyecto Flutter en `mobile_app/` con dependencias base.
- [ ] T1.2 Integrar puente FFI para llama.cpp (bindings Dart ↔ C++).
- [ ] T1.3 Cargar modelo MiniCPM GGUF desde almacenamiento local.
- [ ] T1.4 Inyectar System Prompt dinámico para personalidad en español.
- [ ] T1.5 Implementar streaming de tokens (Time to First Token < 2s).

### Funcionalidad 2: Reconocimiento de voz a texto (STT)
- [ ] T2.1 Capturar audio del micrófono en Flutter.
- [ ] T2.2 Integrar whisper.cpp vía FFI para STT.
- [ ] T2.3 Convertir audio a texto editable en el chat.

### Funcionalidad 3: Síntesis de texto a voz (TTS)
- [ ] T3.1 Integrar motor TTS (Kokoro/Piper o nativo).
- [ ] T3.2 Reproducir respuesta en voz de forma progresiva (por oraciones).
- [ ] T3.3 Liberar recursos de GPU/NPU al salir del chat.

### Funcionalidad 4: Gestión de modelos locales
- [ ] T4.1 Verificar disponibilidad de archivos .gguf y .bin en almacenamiento interno.
- [ ] T4.2 Permitir importar modelos desde el sistema de archivos.
- [ ] T4.3 Manejar errores de modelo no encontrado / corrupto.

## Fase 3: Requisitos no funcionales (transversal)

### Funcionalidad 6: RNF
- [ ] T6.1 Garantizar modo 100% offline (sin llamadas de red).
- [ ] T6.2 Validar consumo de RAM < 3.5 GB.
- [ ] T6.3 Compilar correctamente en ARM64 (Android).
- [ ] T6.4 Asegurar privacidad total de datos.
