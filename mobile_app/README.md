# LAIN Mobile (Flutter)

App Android con inferencia **100% local**: el GGUF de Qwen2.5-3B-Instruct corre
dentro del teléfono mediante `llama.cpp` compilado para Android y expuesto a
Dart por un puente C mínimo (`dart:ffi`). No hay red ni servicios externos.

## Cómo está conectado el modelo

```
ChatScreen ──► ChatController ──► LainEngine (Dart)
                                      │  Isolate.spawn (worker)
                                      ▼
                               lain_llm.c (C ABI)  ──►  llama.cpp
                                      │
                              tokens por SendPort
                                      ▼
                            burbuja de chat (streaming)
```

1. **Puente C** — `android/app/src/main/cpp/lain_llm.c`
   Expone solo cinco funciones con tipos simples, para no replicar structs de
   llama.cpp en Dart: `lain_load`, `lain_free`, `lain_context_size`,
   `lain_format_prompt` y `lain_generate`. La generación emite cada pieza de
   texto por un callback (`lain_piece_cb`).
2. **Bindings** — `lib/data/llm/lain_native.dart`
   `DynamicLibrary.open('liblain_llm.so')` + `lookupFunction` para cada símbolo.
   Los errores del lado C llegan como buffer de texto y se convierten en
   `LainException`.
3. **Motor** — `lib/data/llm/lain_engine.dart`
   `lain_generate` es bloqueante, así que corre en un `Isolate` propio: la UI
   nunca se congela. Los tokens viajan por `SendPort` y se emiten como
   `Stream<String>`. El callback nativo usa `NativeCallable.isolateLocal` y un
   `Utf8Chunker` que retiene bytes hasta completar una secuencia UTF-8 (un token
   puede partir una `á` en dos).
4. **Estado** — `lib/presentation/chat/chat_controller.dart`
   Riverpod expone el motor, localiza el GGUF y vuelca el stream dentro de la
   última burbuja del chat.
5. **Plantilla del chat** — `assets/system_prompt.txt` (copiado de
   `python_ai/datasets/system_prompt.txt`) se aplica con la plantilla ChatML que
   trae el propio GGUF (`llama_chat_apply_template`).

El modelo **no** viaja dentro del APK (1.93 GB). La app lo busca en:

```
/storage/emulated/0/Android/data/com.lain.lain_mobile/files/models/Qwen2.5-3B-Instruct.Q4_K_M.gguf
```

## Requisitos (todo en espacio de usuario)

| Pieza | Versión usada |
| --- | --- |
| JDK | Temurin 17 (`~/.local/opt/jdk-17.0.21+9`) |
| Android SDK | `~/Android/Sdk` (platform 36, build-tools 36.0.0) |
| NDK | `28.2.13676358` |
| CMake | `3.22.1` |
| llama.cpp | commit `caa8191` |

```bash
flutter config --jdk-dir ~/.local/opt/jdk-17.0.21+9
flutter config --android-sdk ~/Android/Sdk
```

## Compilar las librerías nativas

```bash
cd mobile_app
./tools/build_llama_android.sh            # arm64-v8a + x86_64
```

El script clona/fija llama.cpp en `~/.cache/lain/llama.cpp`, compila
`libllama.so`, `libggml*.so`, compila el puente y deja todo en
`android/app/src/main/jniLibs/<abi>/`. Esa carpeta está en `.gitignore`: las
`.so` se regeneran, no se versionan.

Detalle importante: el puente se genera como **`liblain_llm.so`** (con prefijo
`lib`). `dlopen` resuelve por nombre y el prefijo es obligatorio.

## Compilar e instalar el APK

```bash
# El modelo va empaquetado en el APK (~1.9 GB extra).
# El APK resultante pesa ~2 GB.
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

`android/app/build.gradle.kts` activa `packaging { jniLibs { useLegacyPackaging = true } }`
para que las `.so` se extraigan al instalar: con `extractNativeLibs=false`
`dlopen("liblain_llm.so")` falla aunque la librería esté dentro del APK.

También activa `androidResources { noCompress += "gguf" }` para que el GGUF
no se comprima dentro del APK y `AssetManager` pueda leerlo en streaming al
copiarlo al almacenamiento de la app.

## Primer arranque: el modelo ya está dentro

La app copia el GGUF de `assets/models/` a su almacenamiento externo
(`files/models/`) automáticamente al arrancar, mostrando una barra de progreso.
Eso ocurre solo la primera vez; después el modelo ya está en el dispositivo y
la app arranca directo al chat.

No hace falta `adb push` ni conectar el celular por USB. El usuario solo
instala el APK y usa la app.

```bash
# Solo si necesitas forzar una recopia (ej. para actualizar el modelo):
adb shell rm -rf /sdcard/Android/data/com.lain.lain_mobile/files/models
adb shell am start -n com.lain.lain_mobile/.MainActivity
```

## Pruebas

```bash
flutter analyze
flutter test                                   # UI con motor falso, sin dispositivo

# En dispositivo/emulador, con el GGUF ya copiado:
flutter test integration_test/model_smoke_test.dart -d <device-id>
```

`integration_test/model_smoke_test.dart` carga el GGUF real y verifica que
`llama.cpp` produce texto. Ojo: al terminar, `flutter test` desinstala la app y
Android borra `files/models` — hay que volver a copiar el modelo antes de cada
corrida.

## Rendimiento observado

Emulador x86_64 sin aceleración (referencia pesimista): carga del GGUF ~30 s,
~2 tokens/s de generación. En un teléfono arm64 con NEON el prefill y la
generación son sensiblemente más rápidos; la app usa 4 hilos y contexto de 2048.

## Limitaciones actuales

- Solo Android: `dart:ffi` no existe en web; la UI web muestra "Solo Android".
- Sin memoria conversacional: cada turno se formatea desde cero (system + user).
- Sin GPU: `n_gpu_layers = 0`, todo en CPU.
- El APK no incluye el GGUF; el primer arranque sin modelo muestra la ruta y el
  comando `adb push`.
