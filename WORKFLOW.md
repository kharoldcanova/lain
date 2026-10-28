# WORKFLOW — Flujo completo de LAIN

Este documento explica cómo encajan las piezas: qué hace el entorno Python en la PC, cómo intervienen SFT, DPO y RAG, y qué hace la aplicación móvil en tiempo de ejecución.

---

## 1. Visión general

LAIN tiene **dos memorias** que no se mezclan:

| Memoria | Dónde vive | Qué guarda | Cómo se actualiza |
|---|---|---|---|
| **Pesos** (modelo) | `.gguf` en el celular | estilo, tono, personalidad, formato de `<think>` | reentrenamiento (SFT/DPO) en la PC |
| **Semántica** (RAG) | SQLite en el celular | hechos, documentos, conceptos descargados | indexar; sin reentrenar |
| **Vivencial** (memoria) | SQLite en el celular (`lain.db`) | creencias, preferencias, prompts previos | automático, con revisión |

Regla práctica:

- **Hechos nuevos** → RAG.
- **Cómo habla y piensa** → reentrenamiento.
- **Correcciones puntuales** → DPO.
- **Lo vivido con el usuario** (creencias, preferencias, temas) → memoria SQLite local.

```text
┌──────────────── CELULAR (runtime, offline) ────────────────┐
│ voz/texto/cámara → STT → Laya/BMP → RAG top-k → prompt     │
│      → Qwen2.5-3B (llama.cpp) → <think> JSON + respuesta   │
│      → TTS → registro lain_experiences.jsonl               │
└───────────────────────────┬────────────────────────────────┘
                            │ exportar JSONL
                            ▼
┌──────────────── PC (Python, offline) ──────────────────────┐
│ importar experiencias → dataset → SFT/DPO → export GGUF    │
│ RAG: URL/archivo → chunks → embeddings → SQLite            │
└───────────────────────────┬────────────────────────────────┘
                            │ copiar GGUF / DB
                            ▼
                       vuelve al celular
```

---

## 2. Qué hace el entorno Python (PC)

Ubicación: `python_ai/`.

### 2.1 Fine-tuning — `scripts/finetune.py`

Entrena un adaptador QLoRA sobre Qwen2.5-3B-Instruct con Unsloth:

1. Carga el modelo base en 4 bits.
2. Aplica LoRA solo a las capas de atención/MLP (~1 % de parámetros entrenables).
3. Construye el dataset solo con los ejemplos locales de `personality_es.jsonl` (sin corpus general).
4. Entrena con SFT.
5. Fusiona el adaptador, convierte a GGUF y cuantiza a `Q4_K_M` en `outputs/`.

Comandos:

```bash
python scripts/finetune.py --max-steps 1 --no-export            # smoke test
python scripts/finetune.py --max-steps 60 --batch-size 1 --max-seq-length 1024
```

### 2.2 SFT (Supervised Fine-Tuning)

Es el entrenamiento principal. Le muestra al modelo pares **entrada → salida correcta**:

```json
{"instruction": "¿Qué opinas de la IA y los sentimientos?",
 "response": "<think>\n{...JSON...}\n</think>\nYo no tengo un cuerpo que sienta..."}
```

Qué aprende:

- El **formato** de `<think>` con JSON.
- El **tono y estilo** de LAIN.
- Cómo estructurar una respuesta empática.

Qué **no** aprende de forma fiable: hechos nuevos. El conocimiento queda congelado al momento del entrenamiento.

> El vault conceptual lo llama `<thought>`; LAIN usa `<think>`. MiniCPM5 lo traía como tag nativo; Qwen2.5 usa ChatML y el bloque se aprende del system prompt y del dataset. El parser de `chat.py` acepta ambos.

### 2.3 DPO (Direct Preference Optimization)

Se usa cuando el usuario corrige una respuesta. En vez de "esta es la respuesta correcta", se le dan pares **preferida vs rechazada**:

- `response.model_output` = lo que dijo el modelo.
- `training_metadata.rejected_alternative` = la versión que el usuario prefirió.

DPO ajusta al modelo para elegir el estilo preferido. Está planificado en T7.4 / T13.3.

### 2.4 RAG — `scripts/rag.py`

No entrena. Prepara conocimiento para consultarlo en tiempo real:

1. Descarga una URL o lee un archivo.
2. Extrae el texto visible.
3. Corta en fragmentos (~1000 caracteres, solape 150).
4. Calcula embeddings con `multilingual-e5-small` (384 dimensiones).
5. Guarda en `rag/lain_rag.db`.

En consulta: vectoriza la pregunta, compara por coseno y devuelve los `top-k` fragmentos.

```bash
python scripts/rag.py ingest https://ejemplo.com/articulo
python scripts/rag.py ingest --file nota.md
python scripts/rag.py query "¿qué es Laya/BMP?" --top-k 4
```

### 2.5 Importar experiencias — `scripts/import_experiences.py`

Toma el JSONL exportado por la app y lo convierte en dataset de entrenamiento:

1. Valida el esquema del vault.
2. Descarta registros sin `thought_trace`, sin salida o marcados `suitable_for_sft: false`.
3. Evita instrucciones duplicadas.
4. Agrega los pares nuevos a `datasets/personality_es.jsonl`.

```bash
python scripts/import_experiences.py --input ~/Descargas/lain_experiences.jsonl --dry-run
python scripts/import_experiences.py --input ~/Descargas/lain_experiences.jsonl
```

### 2.6 Prueba — `scripts/chat.py` / `test/infer.py`

- `test/infer.py`: una pregunta, salida limpia (sin `<think>`).
- `scripts/validate_dataset.py`: verifica el contrato del dataset antes de entrenar.
- `test/check_format.py`: mide la tasa de `<think>` JSON válido en 20 prompts.
- `scripts/chat.py`: conversación interactiva, historial, `--rag`, `--hide-thought`, y registro automático en `experiences/lain_experiences.jsonl`.

---

## 3. Qué hace la aplicación móvil

Ubicación: `mobile_app/` (Flutter). **Estado actual: estructura creada, sin código Dart todavía (T1.1 pendiente).**

### 3.1 Flujo de una interacción

1. **Entrada**: texto, micrófono (`whisper.cpp`) o cámara (`mmproj` + modelo de visión).
2. **Laya/BMP (~15 ms)**: clasifica carga emocional e intención y elige la directriz de tono.
3. **Memoria**: recupera de `lain.db` las observaciones fijadas, las recientes y las que coinciden con la consulta (FTS5 trigram) e inyecta un bloque `[MEMORIA]` en el system prompt.
4. **RAG**: convierte la consulta en embedding, recupera los `top-k` fragmentos de SQLite e inyecta el contexto.
4. **Inferencia**: `llama.cpp` genera primero el bloque `<think>` (JSON de metacognición) y luego la respuesta.
5. **Salida**: texto en pantalla y voz por TTS, en streaming por oraciones.
6. **Registro**: guarda la experiencia en `lain_experiences.jsonl` desde un isolate en segundo plano.

### 3.2 Exportación

La app tendrá un botón **Exportar experiencias** que genera el JSONL para compartir o guardar (T12.1). Ese archivo es el que se lleva a la PC.

### 3.3 Gestión de modelos y conocimiento

- Importar/verificar `.gguf` y `mmproj.gguf` (T4.x).
- Listar, consultar y borrar fuentes del RAG (T10.7).
- Sin red, el RAG sigue respondiendo con lo ya indexado.

---

## 4. Ciclo de aprendizaje completo

```text
1. Usuario conversa en la app
        ↓
2. App registra experiencia (JSONL con <think>, creencias, respuesta)
        ↓
3. Usuario pulsa "Exportar experiencias"
        ↓
4. PC: import_experiences.py → personality_es.jsonl
        ↓
5. PC: finetune.py (SFT) → adaptador → GGUF Q4_K_M
        ↓
6. Copiar GGUF a mobile_app/assets/models/
        ↓
7. La app usa la nueva versión del modelo
```

Para hechos concretos, se salta el reentrenamiento:

```text
URL/archivo → rag.py ingest → SQLite → disponible al instante
```

**Interalimentación** (LLM ↔ VLM ↔ experiencias), el mecanismo que cierra el bucle: si la descripción visual que recibe el LLM de texto no alcanza para responder, este puede pedir al VLM una segunda descripción más específica; y cada turno (texto o `vision_input`) deja una experiencia en `lain_experiences.jsonl` que alimenta SFT/DPO, de modo que el modelo reentrenado produce mejores descripciones y respuestas, que a su vez generan mejores experiencias.

Salvaguardas: filtro de calidad y revisión humana antes de incorporar experiencias al dataset, y evaluación de regresión (`test/check_format.py` + `test/eval_es.py`) en cada versión para detectar degradación.

---

## 5. SFT vs DPO vs RAG

| | SFT | DPO | RAG |
|---|---|---|---|
| **Qué cambia** | los pesos | los pesos | nada (solo contexto) |
| **Qué enseña** | formato, estilo, tono | preferencia entre respuestas | hechos y documentos |
| **Datos** | pares instruction/response | pares preferida/rechazada | texto descargado |
| **Frecuencia** | periódica | cuando hay correcciones | por documento |
| **Riesgo** | olvido catastrófico | sobreajuste a pocos pares | contexto irrelevante si el chunk es malo |
| **Latencia** | ninguna en runtime | ninguna en runtime | decenas de ms por consulta |

Nota: "STD" no es un término del proyecto; el entrenamiento supervisado es **SFT**. El razonamiento previo (`<think>`) es estilo **CoT** (*Chain of Thought*) y va dentro del SFT.

---

## 6. Artefactos y rutas

| Ruta | Qué es | ¿Va a git? |
|---|---|---|
| `python_ai/datasets/personality_es.jsonl` | dataset SFT | sí |
| `python_ai/datasets/system_prompt.txt` | personalidad y contrato de `<think>` | sí |
| `python_ai/outputs/*.gguf` | modelo final | no |
| `python_ai/outputs/checkpoint-N/` | adaptador y estado | no |
| `python_ai/experiences/lain_experiences.jsonl` | experiencias de prueba en PC | no |
| `python_ai/rag/lain_rag.db` | índice semántico | no |
| `mobile_app/assets/models/` | GGUF en el celular | no |

---

## 7. Estado actual

| Pieza | Estado |
|---|---|
| Entorno Python + Unsloth | ✅ |
| Fine-tuning SFT + export GGUF | ✅ validado con MiniCPM5-2B (histórico) |
| Modelo base | ✅ Qwen2.5-3B-Instruct reentrenado (QLoRA, 90 pasos, loss 0.15, 636 s); GGUF Q4_K_M 1.8 GB |
| Inferencia (`infer.py`, `chat.py`) | ✅ sirven cualquier GGUF de `outputs/` |
| `<think>` en JSON | ✅ 20/20 bloques `<think>` con JSON válido, 0 sin cerrar con Qwen2.5-3B (T11.6); MiniCPM5 20/20 (histórico) |
| RAG local (PC) | ✅ |
| Importador de experiencias | ✅ |
| DPO | ⏳ T13.3 |
| App Flutter (UI, FFI, STT, TTS) | ⏳ Fase 2 |
| Laya/BMP | ⏳ T8.1 |
| Visión en dos pasos (PC, `vision.py`) | ✅ validada con MiniCPM-V 4 (descripción + OCR) |
| Multimodal en la app (`mmproj`) | ⏳ T9.x |
| Exportar experiencias desde la app | ⏳ T12.1 |

---

## 8. Glosario

- **GGUF**: formato de modelo cuantizado para llama.cpp.
- **QLoRA**: fine-tuning de bajo rango sobre un modelo base en 4 bits.
- **SFT**: entrenamiento supervisado con pares entrada/salida.
- **CoT**: cadena de pensamiento; aquí, el bloque `<think>`.
- **DPO**: ajuste por preferencias (preferida vs rechazada).
- **RAG**: recuperar fragmentos y añadirlos al prompt, sin reentrenar.
- **Embedding**: vector que representa el significado de un texto.
- **Chunk**: fragmento de documento indexado por separado.
- **Laya/BMP**: clasificador rápido de emoción e intención en el dispositivo.
