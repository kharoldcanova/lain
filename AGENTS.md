# AGENTS.md

LAIN: asistente local con voz y personalidad en dispositivo (Edge AI). 100% offline, privacidad total.

## Stack

- Frontend/UI: Flutter (Dart) en `mobile_app/`.
- LLM: llama.cpp vía FFI. Móvil: LFM2.5-1.2B-Instruct (GGUF Q4_K_M, ~0.7 GB). PC: Qwen2.5-3B-Instruct + QLoRA (GGUF Q4_K_M, ~1.9–2.0 GB) para fine-tuning.
- Visión: dos pasos con MiniCPM-V 4 (GGUF + `mmproj`), que describe la imagen en texto para el LLM.
- Clasificador de decisión/emoción: Laya / BMP (~15 ms, ~100 MB RAM).
- STT: whisper.cpp (`ggml-base.bin`, ~148 MB, multilingüe). TTS: TTS nativo de Android (voz es-ES del sistema).
- Fine-tuning (PC): Python + PyTorch + Unsloth en `python_ai/` (SFT/CoT + DPO).
- Persistencia local: SQLite (`package:sqlite3`, FTS5 trigram) + `lain_experiences.jsonl` (trazas metacognitivas).
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

## Transparencia de ejecución de agentes

Durante tareas prolongadas o ejecutadas en background:

1. Mantener un registro actualizado de cada tarea activa.
2. Informar qué está haciendo cada worker y cuál es su objetivo.
3. Registrar los comandos importantes ejecutados y sus resultados.
4. Identificar archivos leídos y modificados.
5. Registrar el estado de cada etapa: pendiente, ejecutando, completada o bloqueada.
6. Informar cuando un worker termina, falla o necesita intervención.
7. No presentar estimaciones como resultados verificados.
8. No modificar archivos del repositorio sin respetar las aprobaciones y el flujo de trabajo establecido.

Al solicitar el estado de ejecución, proporcionar un resumen de todos los procesos y subagentes activos, incluyendo sus últimas operaciones verificables.
