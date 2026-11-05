# Voz en LAIN: Whisper (STT) + TTS progresivo

Objetivo: dictado por voz con whisper.cpp y lectura progresiva de la respuesta del modelo por oraciones, 100% offline.
Rama: `main` (los commits se harán en una rama de trabajo si el usuario lo pide). Runner: `flutter test`.
Estrategia de entrega: `ask-on-risk`.

## Specs

- S1. La prueba con el APK experimental se considera viable por ahora; no se invalida F5 ni se inicia F6.
- S2. Implementar Whisper (STT) y el stream de voz de la respuesta del modelo.
- S3. Alcance confirmado por el usuario: «Whisper + TTS progresivo».
- S4. Modelo Whisper predeterminado: base multilingüe (~148 MB), archivo `ggml-base.bin` de `ggerganov/whisper.cpp`.
- S5. TTS mediante el motor nativo de Android (`TextToSpeech`), sin dependencias nuevas.
- S6. La transcripción de Whisper cae en el campo de texto como contenido editable; no se envía automáticamente.
- S7. El TTS solo lee el texto visible (nunca el bloque `<think>`) y lo hace por oraciones completas a medida que llegan los tokens.
- S8. El TTS está apagado por defecto y su preferencia persiste entre arranques.

## Tareas

| ID | Specs | Ruta | Estado |
|---|---|---|---|
| T1 | S2, S3, S6 | inline | ✅ Captura de audio nativa (16 kHz mono) + permiso RECORD_AUDIO + botón de micrófono. |
| T2 | S2, S3, S6 | inline | ✅ Puente C + bindings FFI de whisper.cpp + isolate de transcripción (`liblain_stt.so`, arm64-v8a y x86_64). |
| T3 | S2, S4 | inline | ✅ Gestión del modelo Whisper base (descarga HF, ubicación, borrado). |
| T4 | S3, S5, S7, S8 | inline | ✅ TTS nativo + cortador de oraciones + integración con el stream del modelo + toggle persistido. |
| T5 | — | inline | ✅ `flutter analyze` limpio, 178 pruebas en verde, APK debug compilado y documentación actualizada. |

## Log

### L1 — Pedido original (2026-11-05)
> Digamos que la prueba con el apk experimental por ahora es viable, nos quedaremos con eso por el momento.
>
> Avanza con la implementacion de whisper y el stream para la respuesta del modelo.

### L2 — Alcance confirmado
> Whisper + TTS progresivo (Recomendado)

Modelo: Base multilingüe (~148 MB). TTS: nativo de Android.

### L3 — Evidencia de cierre (2026-11-05)
- `flutter analyze`: sin issues.
- `flutter test`: 178 pruebas en verde.
- `tools/build_whisper_android.sh`: `liblain_stt.so` compilado para arm64-v8a y x86_64; solo exporta `lain_stt_load`, `lain_stt_free`, `lain_stt_transcribe`.
- `flutter build apk --debug --flavor prod`: APK generado con `liblain_stt.so` en ambas ABIs.
- Pendiente de validación en dispositivo: calidad de transcripción, latencia y voz es-ES offline.
