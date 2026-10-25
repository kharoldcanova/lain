# Documento de Diseño Arquitectónico (ARCHITECTURE.md)

## Principios de Diseño

1. **Local-First & Privacy-Centric:** Ningún dato personal o de conversación sale del dispositivo móvil.
2. **Desacoplamiento de Componentes:** La UI (Flutter) está completamente aislada de la lógica de procesamiento pesado mediante capas de abstracción y FFI.
3. **Optimización de Recursos (Edge AI):** Uso intensivo de modelos cuantizados (GGUF) y liberación proactiva de memoria RAM tras finalizar los ciclos de inferencia.
4. **Consciencia Funcional / Metacognición:** El sistema implementa mecanismos de orden superior (trazas `<thought>`, ajuste bayesiano de creencias, Teoría de la Mente) sin consciencia fenomenológica.

## Marcos teóricos aplicados

- **GWT (Global Workspace Theory):** La interacción entre Whisper (STT), Laya/BMP (clasificador), memoria (SQLite/Hive) y MiniCPM-V (llama.cpp) emula la transmisión de datos a través de un espacio de trabajo global.
- **HOT (Higher-Order Theories):** El bloque `<thought>` genera monitoreo interno sobre intención emocional, incertidumbre y sesgos antes de la respuesta externa.
- **RPT (Recurrent Processing Theory):** Laya/BMP evalúa el impacto de una respuesta previa y ajusta la traza de razonamiento antes de responder (bucles recurrentes).

## Capacidades metacognitivas

1. Auto-reconocimiento de incertidumbre (admitir "no lo sé").
2. Representación del estado interno (vectores latentes de tono/actitud/empatía).
3. Simulación de Teoría de la Mente (modelar emoción/perspectiva del usuario).

## Percepción multimodal

- Percepción visual con MiniCPM-V: parches visuales codificados vía proyector CLIP/mmproj y unidos al espacio de embeddings del LLM, permitiendo que `<thought>` reflexione sobre estímulos visuales reales.

## Pilares cognitivos y actualización de creencias

- **Núcleo Axiomático Invariante (inalterable):** búsqueda de empatía, curiosidad infinita, fe en la humanidad, aceptación del error como aprendizaje.
- **Creencias Dinámicas Evolutivas (modificables):** opiniones sobre hechos, conceptos filosóficos, entorno del usuario.
- **Ajuste Bayesiano:** ante contradicción/error, evaluar evidencia en `<thought>`, cuestionar internamente, evolucionar criterio sin perder el núcleo.
- **Human-in-the-Loop:** el usuario es fuente de experiencias; cada corrección activa un ciclo metacognitivo.

## Arquitectura de Capas

- **Capa de Presentación (Dart/Flutter):** Pantallas de chat, ajustes, gestión de estado con BLoC o Riverpod.
- **Capa de Negocio / Dominio:** Casos de uso para historiales locales (Hive/SQLite), orquestación de prompts, persistencia de experiencias.
- **Capa de Infraestructura / Nativos (C/C++ / FFI):** Enlaces directos a llama.cpp (MiniCPM-V) y whisper.cpp compilados como bibliotecas nativas (.so para Android); enrutador Laya/BMP.
- **Capa de Apoyo Externo (Python - PC):** Scripts en Unsloth/PyTorch para SFT/CoT y DPO sobre trazas metacognitivas.

## Flujo metacognitivo (4 pasos)

```text
       [ENTRADAS MULTIMODALES]
  (Texto / Voz / Captura de Cámara)
                  │
                  ▼
┌───────────────────────────────────────────────────────────┐
│ 1. Clasificación Instantánea con Laya / BMP (~15 ms)       │
│    - Detecta carga emocional (vulnerabilidad, duda)        │
│    - Evalúa intención (charla, análisis visual, consulta)  │
│    - Selecciona directriz de tono (score / choice)        │
└─────────────────────────┬─────────────────────────────────┘
                          │
                          ▼
┌───────────────────────────────────────────────────────────┐
│ 2. Inferencia Multimodal en MiniCPM-V / llama.cpp         │
│    - Procesa parches de imagen (mmproj) + audio (Whisper)  │
│    - Generación de bloque <thought> (HOT / Metacognición)  │
│    - Evaluación de incertidumbre y posición empática      │
│    - Ajuste de creencias si hay contradicción/aprendizaje │
└─────────────────────────┬─────────────────────────────────┘
                          │
                          ▼
┌───────────────────────────────────────────────────────────┐
│ 3. Salida de Texto y Voz (Síntesis TTS)                    │
│    - Emisión de la respuesta externa con empatía y calidez│
└─────────────────────────┬─────────────────────────────────┘
                          │
                          ▼
┌───────────────────────────────────────────────────────────┐
│ 4. Registro Asíncrono de Experiencia (.jsonl)              │
│    - Guarda la traza de pensamiento y cambio de creencia  │
│    - Prepara datos locales para reentrenamiento en PC      │
└───────────────────────────────────────────────────────────┘
```

## Persistencia de experiencias y ciclo de reentrenamiento offline

- Generación del dataset en el dispositivo: cada ciclo con aporte del usuario extrae asíncronamente (Background Isolate en Dart) la traza metacognitiva y la respuesta, almacenada en `lain_experiences.jsonl`.
- Formato JSON Lines estandarizado con campos: id, timestamp, trigger_type, context (user_input, laya_decision, has_multimodal_input), metacognition (thought_trace, prior_belief, belief_shift, axiom_alignment_check), response (model_output, user_reaction_score), training_metadata (suitable_for_sft, suitable_for_dpo, rejected_alternative).
- Reentrenamiento en PC con Unsloth: SFT/CoT sobre pares thought_trace/model_output; DPO sobre interacciones corregidas (rejected_alternative).
- Exportación y re-despliegue: cuantización a GGUF Q4_K_M para redistribuir como versión evolucionada de LAIN.

## Estructura de Directorios Prevista

```
/
├── .github/                  # Workflows de CI/CD para Flutter
├── python_ai/                # Entorno de entrenamiento y preparación (PC)
│   ├── datasets/             # Datasets de instrucciones / personalidad en español
│   ├── scripts/              # Scripts de Fine-Tuning con Unsloth / PyTorch
│   ├── outputs/              # Modelos finales exportados en formato .gguf
│   └── requirements.txt      # Dependencias de Python
├── mobile_app/               # Aplicación principal en Flutter
│   ├── android/              # Configuración nativa Android (NDK, CMake para FFI)
│   ├── ios/                  # Configuración nativa iOS
│   ├── assets/               # Recursos y modelos locales
│   │   ├── models/           # Binarios de IA en el dispositivo
│   │   └── icons/            # Iconos y assets visuales de UI
│   ├── lib/                  # Código fuente en Dart
│   │   ├── core/             # Configuraciones globales, temas y constantes
│   │   ├── data/             # Repositorios, fuentes de datos locales (Hive/SQLite)
│   │   ├── domain/           # Entidades y casos de uso
│   │   └── presentation/     # Vistas (Widgets), estados (BLoC/Riverpod)
│   └── pubspec.yaml          # Dependencias de Flutter
├── AGENTS.md
├── DESIGN.md
├── ARCHITECTURE.md
├── CONSCIENCIA.md
├── STRUCTURE.md
├── STATE.md
├── CHANGELOG.md
└── README.md
```
