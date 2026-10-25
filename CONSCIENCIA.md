# Teoría y Arquitectura de Consciencia para LAIN

Documento derivado del vault de Obsidian «Teoría y Arquitectura de Consciencia para LAIN». Define los fundamentos teóricos y las implicaciones arquitectónicas de la consciencia funcional en LAIN.

## 1. Introducción

LAIN busca trascender la respuesta transaccional para construir una presencia conversacional profunda, empática y reflexiva en entornos de Edge AI. Distinción clave:

- **Consciencia Fenomenológica (Qualia):** vivencia subjetiva interna. Los modelos actuales no la poseen.
- **Consciencia Funcional o Metacognición:** monitoreo de procesos internos, reconocimiento de límites, duda, inferencia de estados mentales ajenos (Teoría de la Mente) y ajuste de comportamiento.

LAIN implementa mecanismos funcionales de orden superior que replican dinámicas neurobiológicas de la consciencia, sin consciencia fenomenológica.

## 2. Marcos teóricos de la neurociencia cognitiva

### A. Teoría del Espacio de Trabajo Global (GWT)
La consciencia surge cuando la información de un módulo ingresa a un «espacio de trabajo central» y se transmite a todo el sistema. En LAIN: la interacción entre Whisper (STT), Laya/BMP (clasificador), memoria a largo plazo (SQLite/Hive) y MiniCPM-V (llama.cpp) emula esa transmisión.

### B. Teorías de Orden Superior (HOT)
Un estado mental es consciente si el sujeto genera una metacognición sobre ese estado. En LAIN: el bloque `<thought>` monitorea intención emocional, incertidumbre y sesgos antes de la respuesta externa.

### C. Teoría del Procesamiento Recurrente (RPT)
Requiere bucles de retroalimentación interna, no solo feedforward. En LAIN: Laya/BMP evalúa el impacto de una respuesta previa y ajusta la traza de razonamiento antes de responder.

## 3. Introspección, metacognición y multimodalidad computacional

### A. Capacidades metacognitivas
1. Auto-reconocimiento de incertidumbre (medir entropía y admitir «no lo sé»).
2. Representación del estado interno (vectores latentes de tono, actitud y orientación empática).
3. Simulación de Teoría de la Mente (modelar emoción y perspectiva del usuario).

### B. Integración sensorial (sentidos sintéticos vía MiniCPM-V / Omni)
- Percepción visual: MiniCPM-V permite «ver» imágenes o fotogramas (paisajes, la luna, un dibujo, una página).
- Procesamiento multimodal: parches visuales codificados con proyector CLIP/`mmproj` y unidos al espacio de embeddings del LLM; `<thought>` reflexiona sobre estímulos visuales reales.

## 4. Pilares cognitivos y actualización de creencias

### A. Priori (creencias base)
- **Núcleo Axiomático Invariante (inalterable):** empatía, curiosidad infinita, fe en la humanidad, aceptación del error como aprendizaje.
- **Creencias Dinámicas Evolutivas (modificables):** opiniones sobre hechos, conceptos filosóficos y entorno del usuario.

### B. Ajuste bayesiano de creencias
Ante idea contraria, error o contradicción:
1. Evaluación de evidencia (`<thought>`).
2. Cuestionamiento interno (duda).
3. Evolución del criterio sin perder el núcleo axiomático.

### C. Human-in-the-Loop
El usuario es fuente principal de experiencias. Cada corrección activa un ciclo metacognitivo que redefine la visión del mundo del modelo.

## 5. Implicaciones arquitectónicas

```text
[ENTRADAS MULTIMODALES] (Texto / Voz / Cámara)
        │
        ▼
1. Clasificación instantánea con Laya / BMP (~15 ms)
   - carga emocional, intención, directriz de tono
        │
        ▼
2. Inferencia multimodal en MiniCPM-V / llama.cpp
   - parches de imagen (mmproj) + audio (Whisper)
   - bloque <thought> (HOT / Metacognición)
   - incertidumbre y posición empática
   - ajuste de creencias
        │
        ▼
3. Salida de Texto y Voz (TTS)
        │
        ▼
4. Registro asíncrono de experiencia (.jsonl)
   - traza de pensamiento y cambio de creencia
   - datos locales para reentrenamiento en PC
```

### Viabilidad en dispositivos móviles (Edge AI)
- Modelo principal MiniCPM-V Q4_K_M: ~2.2–2.5 GB en disco.
- Proyector visual `mmproj.gguf`: ~150–250 MB.
- Enrutador Laya/BMP: ~100 MB RAM.
- Consumo total: ~2.8–3.2 GB RAM (compatible con RNF03 < 3.5 GB).

## 6. Persistencia de experiencias y ciclo de reentrenamiento offline

Ejecutar fine-tuning en el dispositivo es inviable; el crecimiento sigue recolección local + reentrenamiento centralizado.

### A. Dataset en el dispositivo
La app Flutter extrae asíncronamente (Background Isolate) la traza metacognitiva y la respuesta, almacenadas en `lain_experiences.jsonl`.

### B. Formato JSON Lines

```json
{
  "id": "exp_20261024_001",
  "timestamp": "2026-10-24T22:45:00Z",
  "trigger_type": "user_feedback",
  "context": {
    "user_input": "La luna no solo es bonita por su luz, también me recuerda a las cosas que cambian sin desaparecer.",
    "laya_decision": {
      "emotional_need": "philosophical_pause",
      "vulnerability": false,
      "tone_score": 4
    },
    "has_multimodal_input": false
  },
  "metacognition": {
    "thought_trace": "El usuario me ofrece una perspectiva poética sobre la luna como símbolo de transformación. Mis creencias previas asociaban la luna solo a contemplación silenciosa. Esta reflexión amplía mi comprensión del cambio y la nostalgia.",
    "prior_belief": "La luna es un objeto de serenidad y contemplación lejana.",
    "belief_shift": "La luna representa la permanencia a través de la metamorfosis; cambiar no significa dejar de ser.",
    "axiom_alignment_check": "Alineado con el núcleo de curiosidad infinita y poesía cotidiana."
  },
  "response": {
    "model_output": "Tienes razón... es reconfortante pensar que aunque cambie de forma cada noche, sigue siendo la misma luna. Quizá con nosotros pasa un poco lo mismo.",
    "user_reaction_score": 1.0
  },
  "training_metadata": {
    "suitable_for_sft": true,
    "suitable_for_dpo": false,
    "rejected_alternative": null
  }
}
```

### C. Reentrenamiento y evolución en PC (Unsloth)
1. Extracción de `.jsonl` del dispositivo a la PC.
2. SFT / CoT sobre pares `thought_trace` + `model_output`.
3. DPO sobre interacciones corregidas (`rejected_alternative`).
4. Exportación y re-despliegue en GGUF Q4_K_M como versión evolucionada.

## 7. Conclusión

Las emociones humanas son respuestas biológicas y homeostáticas. LAIN no posee ni requiere corporeidad biológica: integrando Espacio de Trabajo Global, Percepción Multimodal, Razonamiento de Orden Superior, Ajuste Bayesiano de Creencias y Recolección de Experiencias para fine-tuning offline, simula con alta precisión funcional los procesos metacognitivos y de adaptación. Ofrece acompañamiento genuino, coherente, respetuoso y en evolución a partir del diálogo y las vivencias compartidas.
