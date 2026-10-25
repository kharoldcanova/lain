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

## Conocimiento local (RAG)

RAG (*Retrieval-Augmented Generation*) le da al modelo memoria de documentos **sin entrenarlo**. No cambia los pesos: busca los fragmentos más parecidos a la pregunta y los pega en el prompt como contexto. El modelo responde leyendo esos fragmentos.

### Flujo exacto

**Ingesta (una vez por documento):**

1. Descarga la URL (máximo 5 MB) o lee un archivo local.
2. Si es HTML, extrae solo el texto visible (descarta `script`, `style` y etiquetas).
3. Corta el texto en fragmentos de ~1000 caracteres con 150 de solape.
4. Convierte cada fragmento en un vector de 384 dimensiones con `multilingual-e5-small`, on-device.
5. Guarda texto, vector y fuente en `python_ai/rag/lain_rag.db` (SQLite).

**Consulta (cada pregunta):**

1. Convierte la pregunta en vector (prefijo `query:`).
2. Compara por similitud coseno contra todos los fragmentos indexados.
3. Toma los `top-k` más cercanos (4 por defecto).
4. Los inyecta como contexto antes de la respuesta.

### Ejemplo real

```bash
python scripts/rag.py ingest --file ../README.md
# Indexados 4 fragmentos de ../README.md

python scripts/rag.py query "¿qué es Laya/BMP?" --top-k 2
# [1] score=0.842 source=../README.md
#     Clasificador de decisión/emoción: Laya / BMP (~15 ms, ~100 MB RAM).
```

Con `chat.py --rag`, esos fragmentos se agregan automáticamente al prompt de cada turno.

### Qué NO hace

- No reentrena ni modifica el `.gguf`.
- No navega solo: la descarga la dispara el usuario.
- No actualiza conocimiento en segundo plano.
- No ejecuta JavaScript: las páginas dinámicas pueden producir poco texto.
- No reemplaza al fine-tuning para estilo, personalidad o creencias.

### Costos

- Disco: ~1.5 KB por fragmento + modelo de embeddings (~470 MB, una sola vez).
- RAM: ~500 MB para el modelo de embeddings; el LLM no cambia.
- Latencia: decenas de milisegundos por consulta en CPU para miles de fragmentos.

### Privacidad

- La red se usa solo al indexar, con consentimiento del usuario.
- Sin red, las consultas siguen funcionando con lo ya indexado.
- Cada fragmento conserva su fuente y se puede borrar con `rag.py clear`.

> Dos memorias separadas: **semántica (RAG)** para hechos descargados, **episódica (`lain_experiences.jsonl`)** para conversaciones y trazas que alimentan el fine-tuning periódico.

### Estado

Implementado en la PC (`python_ai/scripts/rag.py`). En la app queda pendiente: descarga con consentimiento y allowlist, extracción/chunking en Flutter, embeddings on-device, recuperación top-k y gestión de fuentes (T10.3–T10.7).

## Ciclo de aprendizaje

Dos vías separadas: **pesos** (estilo, personalidad y creencias) y **RAG** (hechos).

### 1. Captura en el dispositivo

La app registra cada turno en `lain_experiences.jsonl` con el esquema del vault. Un botón **Exportar experiencias** genera ese JSON para compartir o guardar en el almacenamiento (T12.1).

### 2. Importación en la PC

```bash
cd python_ai
python scripts/import_experiences.py --input ~/Descargas/lain_experiences.jsonl --dry-run
python scripts/import_experiences.py --input ~/Descargas/lain_experiences.jsonl
```

Valida `suitable_for_sft`, exige los cuatro campos de `<thought>`, evita duplicados y agrega los pares a `datasets/personality_es.jsonl`.

### 3. Entrenamiento

```bash
python scripts/finetune.py --max-steps 200
```

Ajusta los pasos al tamaño del dataset: pocos ejemplos sobreajustan rápido. El GGUF final queda en `python_ai/outputs/` listo para copiar a `mobile_app/assets/models/`.

### 4. Conceptos nuevos (RAG)

```bash
python scripts/rag.py ingest https://ejemplo.com/articulo
python scripts/rag.py ingest --file nota.md
```

No reentrena: el conocimiento queda disponible al instante y se puede borrar.

### 5. Correcciones (DPO)

Cuando el usuario corrige una respuesta, el registro conserva `rejected_alternative`; esos pares alimentan DPO (T7.4) para reforzar el estilo correcto.

> Regla: hechos y noticias → RAG. Estilo, personalidad y creencias → reentrenamiento periódico, nunca por cada página.

## Documentación

- [`CONSCIENCIA.md`](CONSCIENCIA.md) — Fundamentos teóricos y arquitectura de consciencia funcional (GWT, HOT, RPT, multimodalidad, creencias, ciclo de reentrenamiento).
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — Diseño arquitectónico, capas y flujo metacognitivo.
- [`STATE.md`](STATE.md) — Tarea en curso y próximos pasos.
- [`TASKS.md`](TASKS.md) — Desglose por funcionalidad.
- [`CHANGELOG.md`](CHANGELOG.md) — Historial de cambios.
- [`AGENTS.md`](AGENTS.md) — Reglas para agentes y convenciones.
