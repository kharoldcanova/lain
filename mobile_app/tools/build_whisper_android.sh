#!/usr/bin/env bash
# Compila whisper.cpp + el puente C para Android y copia liblain_stt.so.
#
# Requisitos: Android SDK con NDK 28.2.13676358 y cmake 3.22.1.
#
# Uso:
#   ./tools/build_whisper_android.sh [abi...]   (por defecto arm64-v8a x86_64)
#
# Variables de entorno:
#   WHISPER_TAG        tag de whisper.cpp (por defecto v1.9.5)
#   WHISPER_SRC        checkout (por defecto ~/.cache/lain/whisper.cpp)
#   LAIN_STT_OUT       carpeta de salida (por defecto android/app/src/main/jniLibs)
#   LAIN_STRIP         1 = quitar símbolos/debug (por defecto)
#
# La salida va a src/main/jniLibs para que ambos flavors (prod y experimental)
# la incluyan. El resto de símbolos queda oculto con un version script: ggml y
# whisper no deben interponerse con las bibliotecas de llama.cpp.
set -euo pipefail

WHISPER_TAG="${WHISPER_TAG:-v1.9.5}"
WHISPER_SRC="${WHISPER_SRC:-${XDG_CACHE_HOME:-$HOME/.cache}/lain/whisper.cpp}"
SDK="${ANDROID_HOME:-$HOME/Android/Sdk}"
NDK="${ANDROID_NDK_HOME:-$SDK/ndk/28.2.13676358}"
CMAKE="${CMAKE:-$SDK/cmake/3.22.1/bin/cmake}"
STRIP="${STRIP:-$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip}"

ABIS=("${@:-}")
if [ -z "${ABIS[0]:-}" ]; then
  ABIS=(arm64-v8a x86_64)
fi

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CPP_DIR="$APP_DIR/android/app/src/main/cpp"
BRIDGE_SRC="$CPP_DIR/lain_stt.c"
OUT_DIR="${LAIN_STT_OUT:-$APP_DIR/android/app/src/main/jniLibs}"
LAIN_STRIP="${LAIN_STRIP:-1}"

for tool in "$CMAKE" "$NDK/build/cmake/android.toolchain.cmake" "$STRIP" "$BRIDGE_SRC"; do
  [ -e "$tool" ] || { echo "Falta $tool"; exit 1; }
done

if [ ! -d "$WHISPER_SRC/.git" ]; then
  echo "Inicializando whisper.cpp en $WHISPER_SRC"
  mkdir -p "$WHISPER_SRC"
  git -C "$WHISPER_SRC" init -q
  git -C "$WHISPER_SRC" remote add origin https://github.com/ggml-org/whisper.cpp.git
fi
if ! git -C "$WHISPER_SRC" rev-parse -q --verify "refs/tags/$WHISPER_TAG" >/dev/null; then
  git -C "$WHISPER_SRC" fetch --depth 1 origin "refs/tags/$WHISPER_TAG:refs/tags/$WHISPER_TAG"
fi
git -C "$WHISPER_SRC" checkout --detach -q "$WHISPER_TAG"

# Solo se exportan las funciones del puente; el resto queda local para no
# chocar con los símbolos ggml de liblain_llm.so.
VERSION_SCRIPT="$(mktemp)"
trap 'rm -f "$VERSION_SCRIPT"' EXIT
cat > "$VERSION_SCRIPT" <<'MAP'
{
  global:
    lain_stt_load;
    lain_stt_free;
    lain_stt_transcribe;
  local:
    *;
};
MAP

for abi in "${ABIS[@]}"; do
  build="$WHISPER_SRC/build-android-$abi"
  cmake_args=(
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake"
    -DANDROID_ABI="$abi" -DANDROID_PLATFORM=android-24
    -DCMAKE_BUILD_TYPE=Release
    -DBUILD_SHARED_LIBS=OFF
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DWHISPER_BUILD_TESTS=OFF
    -DWHISPER_BUILD_EXAMPLES=OFF
    -DWHISPER_BUILD_SERVER=OFF
    -DGGML_OPENMP=OFF
    -DGGML_BUILD_TESTS=OFF
    -DGGML_BUILD_EXAMPLES=OFF
  )

  echo "=== whisper.cpp $abi"
  "$CMAKE" -B "$build" -S "$WHISPER_SRC" "${cmake_args[@]}" >/dev/null
  "$CMAKE" --build "$build" -j"$(nproc)" >/dev/null

  # Todas las bibliotecas estáticas del build, en un grupo para resolver
  # dependencias circulares entre whisper y ggml.
  mapfile -t archives < <(find "$build" -name '*.a' -type f | sort)
  if [ "${#archives[@]}" -eq 0 ]; then
    echo "ERROR: no se generaron bibliotecas estáticas en $build"; exit 1
  fi

  case "$abi" in
    arm64-v8a) CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang" ;;
    x86_64)    CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android24-clang" ;;
    *) echo "ABI no soportada: $abi"; exit 1 ;;
  esac
  CXX="${CC}++"

  mkdir -p "$OUT_DIR/$abi"
  # El puente es C; whisper.cpp y ggml son C++, así que el enlace va con
  # clang++ y libc++ estática (el APK no empaqueta libc++_shared.so).
  "$CC" -c -fPIC -O2 -fvisibility=hidden \
    -o "$build/lain_stt.o" "$BRIDGE_SRC" \
    -I"$WHISPER_SRC/include" -I"$WHISPER_SRC/ggml/include"
  "$CXX" -shared -o "$OUT_DIR/$abi/liblain_stt.so" "$build/lain_stt.o" \
    -Wl,--start-group "${archives[@]}" -Wl,--end-group \
    -static-libstdc++ \
    -Wl,--exclude-libs,ALL -Wl,-Bsymbolic \
    -Wl,--version-script="$VERSION_SCRIPT" \
    -llog -lm -ldl -Wl,--no-undefined

  if [ "$LAIN_STRIP" = "1" ]; then
    "$STRIP" --strip-unneeded "$OUT_DIR/$abi/liblain_stt.so"
  fi
  echo "=== $abi listo: $(basename "$OUT_DIR/$abi/liblain_stt.so")"
done
