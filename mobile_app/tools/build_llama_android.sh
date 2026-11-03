#!/usr/bin/env bash
# Compila llama.cpp + el puente C para Android y copia las .so al destino.
#
# Requisitos: Android SDK con NDK 28.2.13676358 y cmake 3.22.1.
#
# Uso:
#   ./tools/build_llama_android.sh [abi...]     (por defecto arm64-v8a x86_64)
#
# Variables de entorno:
#   LLAMA_COMMIT       commit de llama.cpp (por defecto caa8191)
#   LLAMA_SRC          checkout de llama.cpp (por defecto ~/.cache/lain/llama.cpp)
#   LAIN_JNI_OUT       carpeta de salida (por defecto android/app/src/prod/jniLibs)
#   LAIN_ARM_VARIANTS  1 = arm64 con GGML_BACKEND_DL + GGML_CPU_ALL_VARIANTS
#                      (variantes android_* con dispatch en runtime)
#   LAIN_ARM_ARCH      -march alternativo para arm64 cuando no se usan variantes
#                      (p. ej. armv8.2-a+dotprod+fp16)
#   LAIN_STRIP         1 = quitar símbolos/debug de las .so copiadas (por defecto)
#   LAIN_BRIDGE_SRC    fuente del puente C (por defecto main/cpp/lain_llm.c);
#                      el puente experimental vive en experimental/cpp/
#   LAIN_BUILD_TAG     sufijo del directorio de build (evita mezclar configuraciones)
#
# Producción (bibliotecas originales del flavor prod):
#   ./tools/build_llama_android.sh
#
# Experimental arm64 (no toca las .so de producción):
#   LAIN_JNI_OUT=android/app/src/experimental/jniLibs LAIN_ARM_VARIANTS=1 \
#     ./tools/build_llama_android.sh arm64-v8a
set -euo pipefail

LLAMA_COMMIT="${LLAMA_COMMIT:-caa8191}"
LLAMA_SRC="${LLAMA_SRC:-${XDG_CACHE_HOME:-$HOME/.cache}/lain/llama.cpp}"
# `git fetch` de un SHA corto falla en GitHub: se resuelve al SHA completo.
if [ "${#LLAMA_COMMIT}" -lt 40 ]; then
  full_sha=$(curl -fsSL "https://api.github.com/repos/ggml-org/llama.cpp/commits/$LLAMA_COMMIT" 2>/dev/null \
    | grep -m1 -oE '"sha"[[:space:]]*:[[:space:]]*"[0-9a-f]{40}"' \
    | grep -oE '[0-9a-f]{40}' || true)
  if [ -z "$full_sha" ]; then
    echo "No se pudo resolver el commit $LLAMA_COMMIT"; exit 1
  fi
  echo "Commit $LLAMA_COMMIT -> $full_sha"
  LLAMA_COMMIT="$full_sha"
fi
SDK="${ANDROID_HOME:-$HOME/Android/Sdk}"
NDK="${ANDROID_NDK_HOME:-$SDK/ndk/28.2.13676358}"
CMAKE="${CMAKE:-$SDK/cmake/3.22.1/bin/cmake}"
OBJDUMP="${OBJDUMP:-$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump}"
STRIP="${STRIP:-$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip}"
ABIS=("${@:-}")
if [ -z "${ABIS[0]:-}" ]; then
  ABIS=(arm64-v8a x86_64)
fi

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CPP_DIR="$APP_DIR/android/app/src/main/cpp"
BRIDGE_SRC="${LAIN_BRIDGE_SRC:-$CPP_DIR/lain_llm.c}"
OUT_DIR="${LAIN_JNI_OUT:-$APP_DIR/android/app/src/prod/jniLibs}"
ARM_VARIANTS="${LAIN_ARM_VARIANTS:-0}"
ARM_ARCH="${LAIN_ARM_ARCH:-}"
LAIN_STRIP="${LAIN_STRIP:-1}"
LAIN_BUILD_TAG="${LAIN_BUILD_TAG:-}"

for tool in "$CMAKE" "$NDK/build/cmake/android.toolchain.cmake" "$OBJDUMP" "$STRIP" "$BRIDGE_SRC"; do
  [ -e "$tool" ] || { echo "Falta $tool"; exit 1; }
done

if [ "$ARM_VARIANTS" = "1" ] && [ -n "$ARM_ARCH" ]; then
  echo "LAIN_ARM_VARIANTS y LAIN_ARM_ARCH son mutuamente excluyentes"; exit 1
fi

if [ -n "$OUT_DIR" ] && [ "$OUT_DIR" != "$APP_DIR/android/app/src/prod/jniLibs" ]; then
  echo "Salida: $OUT_DIR"
fi

# Checkout superficial del commit exacto: no arrastra el historial completo.
if [ ! -d "$LLAMA_SRC/.git" ]; then
  echo "Inicializando llama.cpp en $LLAMA_SRC"
  mkdir -p "$LLAMA_SRC"
  git -C "$LLAMA_SRC" init -q
  git -C "$LLAMA_SRC" remote add origin https://github.com/ggml-org/llama.cpp.git
fi
if ! git -C "$LLAMA_SRC" cat-file -e "$LLAMA_COMMIT^{commit}" 2>/dev/null; then
  git -C "$LLAMA_SRC" fetch --depth 1 origin "$LLAMA_COMMIT"
fi
git -C "$LLAMA_SRC" checkout --detach -q "$LLAMA_COMMIT"

for abi in "${ABIS[@]}"; do
  build="$LLAMA_SRC/build-android-$abi${LAIN_BUILD_TAG:+-$LAIN_BUILD_TAG}"
  dl_mode=0
  cmake_args=(
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake"
    -DANDROID_ABI="$abi" -DANDROID_PLATFORM=android-24
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=OFF
    -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_COMMON=OFF
    -DLLAMA_CURL=OFF -DGGML_OPENMP=OFF
  )
  if [ "$abi" = "arm64-v8a" ] && [ "$ARM_VARIANTS" = "1" ]; then
    # Variantes android_* + carga dinámica: el backend se elige en runtime con
    # ggml_backend_load_all_from_path() y la mejor variante compatible.
    cmake_args+=(-DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON)
    dl_mode=1
  elif [ "$abi" = "arm64-v8a" ] && [ -n "$ARM_ARCH" ]; then
    cmake_args+=(-DGGML_CPU_ARM_ARCH="$ARM_ARCH")
  fi

  echo "=== llama.cpp $abi (DL=$dl_mode)"
  "$CMAKE" -B "$build" -S "$LLAMA_SRC" "${cmake_args[@]}" >/dev/null
  "$CMAKE" --build "$build" -j"$(nproc)" >/dev/null

  echo "=== puente lain_llm.so $abi"
  CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/${abi/arm64-v8a/aarch64}-linux-android24-clang"
  [ "$abi" = "x86_64" ] && CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android24-clang"

  link_libs=(-lllama -lggml -lggml-base)
  # En modo DL libggml-cpu es un MODULE (no linkeable) y se carga en runtime.
  [ "$dl_mode" = "0" ] && link_libs+=(-lggml-cpu)

  mkdir -p "$OUT_DIR/$abi"
  "$CC" -shared -fPIC -O2 -o "$OUT_DIR/$abi/liblain_llm.so" "$BRIDGE_SRC" \
    -I"$LLAMA_SRC/include" -I"$LLAMA_SRC/ggml/include" \
    -L"$build/bin" "${link_libs[@]}" \
    -Wl,-rpath,'$ORIGIN' -Wl,--no-undefined

  for lib in "$build"/bin/*.so; do
    cp "$lib" "$OUT_DIR/$abi/"
  done
  if [ "$LAIN_STRIP" = "1" ]; then
    "$STRIP" --strip-unneeded "$OUT_DIR/$abi"/lib*.so
  fi
  echo "=== $abi listo: $(ls "$OUT_DIR/$abi" | tr '\n' ' ')"

  if [ "$dl_mode" = "1" ]; then
    dotprod_lib=$(ls "$OUT_DIR/$abi"/libggml-cpu-android_armv8.2_*.so 2>/dev/null | head -1 || true)
    if [ -z "$dotprod_lib" ]; then
      echo "ERROR: no se generó ninguna variante android_armv8.2_*"; exit 1
    fi
    if [ "$("$OBJDUMP" -d "$dotprod_lib" | grep -cE '\bsdot\b' || true)" -eq 0 ]; then
      echo "ERROR: $dotprod_lib no tiene instrucciones dotprod"; exit 1
    fi
    i8mm_lib=$(ls "$OUT_DIR/$abi"/libggml-cpu-android_armv8.6_*.so 2>/dev/null | head -1 || true)
    if [ -n "$i8mm_lib" ] && [ "$("$OBJDUMP" -d "$i8mm_lib" | grep -cE '\bsmmla\b' || true)" -eq 0 ]; then
      echo "ERROR: $i8mm_lib no tiene instrucciones i8mm"; exit 1
    fi
    echo "=== verificado: dotprod en $(basename "$dotprod_lib")"
  fi
done
