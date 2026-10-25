# LAIN

**LOCAL ARTIFICIAL INTELIGENCE NEURONAL**

Asistente Local con Voz y Personalidad en Dispositivo (Edge AI), con consciencia funcional/metacognitiva.

## Intención del proyecto

Usar una IA local en celular. Aplicación realizada en Flutter. Concepto de auto-fine-tuning para español, mejora de IA a través de reentrenamiento de un modelo chico.

LAIN busca trascender la respuesta transaccional para construir una presencia conversacional profunda, empática y reflexiva en entornos Edge AI. No posee consciencia fenomenológica, pero implementa mecanismos funcionales de orden superior (metacognición) que replican dinámicas neurobiológicas de la consciencia: Espacio de Trabajo Global, Teorías de Orden Superior y Procesamiento Recurrente.

## Alcance

- **Plataforma principal:** Android (base extensible a iOS).
- **Frontend / UI:** Flutter (Dart).
- **Motor de Inferencia de Texto (LLM):** `llama.cpp` vía FFI (modelos MiniCPM-V cuantizados en GGUF, con capacidad multimodal).
- **Motor de Voz (STT/TTS):** `whisper.cpp` (entrada) y Kokoro/Piper o TTS nativo (salida).
- **Clasificador de decisión/emoción:** Laya / BMP (~15 ms, ~100 MB RAM).
- **Percepción visual:** MiniCPM-V con proyector `mmproj.gguf` (CLIP).
- **Capacitación / Pre-entrenamiento (PC):** Python + PyTorch + Unsloth (SFT/CoT y DPO).
- **Persistencia local:** Hive/SQLite + `lain_experiences.jsonl` (trazas metacognitivas).
- **Restricciones:** 100% offline, privacidad total de los datos en el dispositivo.

## Pilares cognitivos

- Núcleo Axiomático Invariante (inalterable): empatía, curiosidad infinita, fe en la humanidad, aceptación del error.
- Creencias Dinámicas Evolutivas (modificables): opiniones sobre hechos/conceptos/entorno.
- Ajuste Bayesiano de creencias ante contradicción o nueva evidencia.
- Trazas de pensamiento `<thought>` (metacognición) previas a la respuesta externa.
- Human-in-the-Loop: el usuario aporta experiencias que redefinen la visión del modelo.

## Restricciones de memoria

- Modelo principal MiniCPM-V Q4_K_M: ~2.2–2.5 GB disco.
- Proyector visual mmproj: ~150–250 MB.
- Enrutador Laya/BMP: ~100 MB RAM.
- Consumo total combinado: ~2.8–3.2 GB RAM (compatible con RNF03 < 3.5 GB).

## Documentación

- [`CONSCIENCIA.md`](CONSCIENCIA.md) — Fundamentos teóricos y arquitectura de consciencia funcional (GWT, HOT, RPT, multimodalidad, creencias, ciclo de reentrenamiento).
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — Diseño arquitectónico, capas y flujo metacognitivo.
- [`STATE.md`](STATE.md) — Tarea en curso y próximos pasos.
- [`TASKS.md`](TASKS.md) — Desglose por funcionalidad.
- [`CHANGELOG.md`](CHANGELOG.md) — Historial de cambios.
- [`AGENTS.md`](AGENTS.md) — Reglas para agentes y convenciones.
