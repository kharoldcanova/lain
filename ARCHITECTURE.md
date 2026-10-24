# Documento de Diseño Arquitectónico (ARCHITECTURE.md)

## Principios de Diseño

1. **Local-First & Privacy-Centric:** Ningún dato personal o de conversación sale del dispositivo móvil.
2. **Desacoplamiento de Componentes:** La UI (Flutter) está completamente aislada de la lógica de procesamiento pesado mediante capas de abstracción y FFI.
3. **Optimización de Recursos (Edge AI):** Uso intensivo de modelos cuantizados (GGUF) y liberación proactiva de memoria RAM tras finalizar los ciclos de inferencia.

## Arquitectura de Capas

- **Capa de Presentación (Dart/Flutter):** Pantallas de chat, ajustes, gestión de estado con BLoC o Riverpod.
- **Capa de Negocio / Dominio:** Casos de uso para historiales locales (Hive/SQLite) y orquestación de prompts.
- **Capa de Infraestructura / Nativos (C/C++ / FFI):** Enlaces directos a llama.cpp y whisper.cpp compilados como bibliotecas nativas (.so para Android).
- **Capa de Apoyo Externo (Python - PC):** Scripts en Unsloth/PyTorch para adaptaciones y pruebas de modelos antes de exportar a GGUF.

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
├── STRUCTURE.md
├── STATE.md
├── CHANGELOG.md
└── README.md
```