# AGENTS.md

LAIN: asistente local con voz y personalidad en dispositivo (Edge AI). 100% offline, privacidad total.

## Stack

- Frontend/UI: Flutter (Dart) en `mobile_app/`.
- LLM: llama.cpp vía FFI (Qwen2.5-3B-Instruct + QLoRA, GGUF Q4_K_M, ~1.9–2.0 GB).
- Visión: dos pasos con MiniCPM-V 4 (GGUF + `mmproj`), que describe la imagen en texto para Qwen.
- Clasificador de decisión/emoción: Laya / BMP (~15 ms, ~100 MB RAM).
- STT: whisper.cpp. TTS: Kokoro/Piper o TTS nativo.
- Fine-tuning (PC): Python + PyTorch + Unsloth en `python_ai/` (SFT/CoT + DPO).
- Persistencia local: Hive/SQLite + `lain_experiences.jsonl` (trazas metacognitivas).
- Estado: BLoC o Riverpod.

## Estado actual

Repositorio con documentación base completa, estructura de carpetas (`mobile_app/`, `python_ai/`), `pubspec.yaml` de Flutter y scripts de fine-tuning/inferencia en Python: pipeline operativo en PC (`scripts/`, pruebas y evaluación en `python_ai/test/`), visión en dos pasos validada en PC (MiniCPM-V 4 → Qwen) y reentrenamiento de Qwen2.5-3B-Instruct en curso. La app Flutter aún no tiene código Dart funcional. Ver `STATE.md` y `TASKS.md` para el detalle.

## Convenciones

- Commits: Conventional Commits `<tipo>(<alcance>): <descripción breve en minúsculas>`. Tipos: `feat`, `fix`, `refactor`, `perf`, `docs`, `chore`.
- Antes de cada commit, ejecutar la prueba correspondiente y verificar que pase. No commitear si las pruebas fallan.
- Dart/Flutter: Effective Dart, tipado estricto, evitar `dynamic` salvo FFI.
- Python: PEP 8, tipado estricto (mypy), docstrings.
- C/C++ (puente FFI): manejo seguro de memoria, liberar punteros (evitar leaks en móvil).

## Notas

- Documento fuente de intención: `Proyecto LAIN..md`.
- Fundamentos de consciencia funcional: vault «Teoría y Arquitectura de Consciencia para LAIN».
- Principio cognitivo: consciencia funcional/metacognición (GWT, HOT, RPT), no consciencia fenomenológica.
- Núcleo axiomático invariante (inalterable): empatía, curiosidad infinita, fe en la humanidad, aceptación del error.
- Creencias dinámicas evolutivas (modificables) con ajuste bayesiano.
- Estructura prevista: `mobile_app/` (Flutter) y `python_ai/` (entrenamiento).
- No inventar comandos ni tooling hasta que existan manifiestos reales.
