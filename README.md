# LAIN

**Asistente Local con Voz y Personalidad en Dispositivo (Edge AI)**

## Intención del proyecto

Usar una IA local en celular. Aplicación realizada en Flutter. Concepto de auto-fine-tuning para español, mejora de IA a través de reentrenamiento de un modelo chico.

## Alcance

- **Plataforma principal:** Android (base extensible a iOS).
- **Frontend / UI:** Flutter (Dart).
- **Motor de Inferencia de Texto (LLM):** `llama.cpp` vía FFI (modelos MiniCPM cuantizados en GGUF).
- **Motor de Voz (STT/TTS):** `whisper.cpp` (entrada) y Kokoro/Piper o TTS nativo (salida).
- **Capacitación / Pre-entrenamiento (PC):** Python + PyTorch + Unsloth (fine-tuning opcional de personalidad y español).
- **Restricciones:** 100% offline, privacidad total de los datos en el dispositivo.
