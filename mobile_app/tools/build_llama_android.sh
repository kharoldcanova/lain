#!/usr/bin/env bash
# Compila llama.cpp + el puente C para Android y copia las .so a jniLibs.
#
# Requisitos: Android SDK con NDK 28.2.13676358 y cmake 3.22.1.
# Uso: ./tools/build_llama_android.sh [abi...]   (por defecto arm64-v8a x86_64)
set -euo pipefail

LLAMA_COMMIT="${LLAMA_COMMIT:-caa8191}"
LLAMA_SRC="${LLAMA_SRC:-${XDG_CACHE_HOME:-$HOME/.cache}/lain/llama.cpp}"
SDK="${ANDROID_HOME:-$HOME/Android/Sdk}"
NDK="${ANDROID_NDK_HOME:-$SDK/ndk/28.2.13676358}"
CMAKE="${CMAKE:-$SDK/cmake/3.22.1/bin/cmake}"
ABIS=("${@:-}")
if [ -z "${ABIS[0]:-}" ]; then
  ABIS=(arm64-v8a x86_64)
fi

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CPP_DIR="$APP_DIR/android/app/src/main/cpp"
JNI_DIR="$APP_DIR/android/app/src/main/jniLibs"

for tool in "$CMAKE" "$NDK/build/cmake/android.toolchain.cmake"; do
  [ -e "$tool" ] || { echo "Falta $tool"; exit 1; }
done

if [ ! -d "$LLAMA_SRC/.git" ]; then
  echo "Clonando llama.cpp en $LLAMA_SRC"
  git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_SRC"
fi
git -C "$LLAMA_SRC" fetch --depth 1 origin "$LLAMA_COMMIT"
git -C "$LLAMA_SRC" checkout --detach "$LLAMA_COMMIT"

for abi in "${ABIS[@]}"; do
  build="$LLAMA_SRC/build-android-$abi"
  echo "=== llama.cpp $abi"
  "$CMAKE" -B "$build" -S "$LLAMA_SRC" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" -DANDROID_PLATFORM=android-24 \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=OFF \
    -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_COMMON=OFF \
    -DLLAMA_CURL=OFF -DGGML_OPENMP=OFF >/dev/null
  "$CMAKE" --build "$build" -j"$(nproc)" >/dev/null

  echo "=== puente lain_llm.so $abi"
  CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/${abi/arm64-v8a/aarch64}-linux-android24-clang"
  [ "$abi" = "x86_64" ] && CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android24-clang"

  mkdir -p "$JNI_DIR/$abi"
  "$CC" -shared -fPIC -O2 -o "$JNI_DIR/$abi/liblain_llm.so" "$CPP_DIR/lain_llm.c" \
    -I"$LLAMA_SRC/include" -I"$LLAMA_SRC/ggml/include" \
    -L"$build/bin" -lllama -lggml -lggml-base -lggml-cpu \
    -Wl,-rpath,'$ORIGIN' -Wl,--no-undefined

  for lib in "$build"/bin/*.so; do
    cp "$lib" "$JNI_DIR/$abi/"
  done
  echo "=== $abi listo: $(ls "$JNI_DIR/$abi" | tr '\n' ' ')"
done
