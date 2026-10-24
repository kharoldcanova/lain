# AGENTS.md

LAIN: asistente local con voz y personalidad en dispositivo (Edge AI). 100% offline, privacidad total.

## Stack

- Frontend/UI: Flutter (Dart) en `mobile_app/`.
- LLM: llama.cpp vía FFI (modelos MiniCPM cuantizados GGUF).
- STT: whisper.cpp. TTS: Kokoro/Piper o TTS nativo.
- Fine-tuning (PC): Python + PyTorch + Unsloth en `python_ai/`.
- Persistencia local: Hive/SQLite.
- Estado: BLoC o Riverpod.

## Estado actual

Repositorio en inicialización: documentación base creada, sin código ni manifiestos aún. No hay comandos de build/test/lint. Cuando existan manifiestos reales, regenerar este archivo desde ellos.

## Convenciones

- Commits: Conventional Commits `<tipo>(<alcance>): <descripción breve en minúsculas>`. Tipos: `feat`, `fix`, `refactor`, `perf`, `docs`, `chore`.
- Dart/Flutter: Effective Dart, tipado estricto, evitar `dynamic` salvo FFI.
- Python: PEP 8, tipado estricto (mypy), docstrings.
- C/C++ (puente FFI): manejo seguro de memoria, liberar punteros (evitar leaks en móvil).

## Notas

- Documento fuente de intención: vault de Obsidian `Proyecto LAIN..md` (Boveda/AI/IA).
- Estructura prevista: `mobile_app/` (Flutter) y `python_ai/` (entrenamiento).
- No inventar comandos ni tooling hasta que existan manifiestos reales.
