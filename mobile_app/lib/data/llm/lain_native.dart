import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Bindings mínimos a `liblain_llm.so` (puente C sobre llama.cpp).
class LainException implements Exception {
  const LainException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef _LoadNative = IntPtr Function(
    Pointer<Utf8> path, Int32 nCtx, Int32 threads, Pointer<Utf8> err, Int32 errLen);
typedef _LoadDart = int Function(
    Pointer<Utf8> path, int nCtx, int threads, Pointer<Utf8> err, int errLen);

typedef _FreeNative = Void Function(IntPtr handle);
typedef _FreeDart = void Function(int handle);

typedef _FormatNative = Int32 Function(
    IntPtr handle, Pointer<Utf8> system, Pointer<Utf8> user, Pointer<Char> out, Int32 outLen);
typedef _FormatDart = int Function(
    int handle, Pointer<Utf8> system, Pointer<Utf8> user, Pointer<Char> out, int outLen);

typedef _GenerateNative = Int32 Function(
    IntPtr handle,
    Pointer<Utf8> prompt,
    Int32 maxTokens,
    Float temp,
    Float topP,
    Int32 seed,
    Pointer<NativeFunction<PieceCallbackNative>> callback,
    Pointer<Void> userData,
    Pointer<Utf8> err,
    Int32 errLen);
typedef _GenerateDart = int Function(
    int handle,
    Pointer<Utf8> prompt,
    int maxTokens,
    double temp,
    double topP,
    int seed,
    Pointer<NativeFunction<PieceCallbackNative>> callback,
    Pointer<Void> userData,
    Pointer<Utf8> err,
    int errLen);

typedef PieceCallbackNative = Void Function(Pointer<Char> piece, Int32 len, Pointer<Void> userData);
typedef PieceCallbackDart = void Function(Pointer<Char> piece, int len, Pointer<Void> userData);

class LainNative {
  LainNative() : _lib = DynamicLibrary.open('liblain_llm.so') {
    _load = _lib.lookupFunction<_LoadNative, _LoadDart>('lain_load');
    _free = _lib.lookupFunction<_FreeNative, _FreeDart>('lain_free');
    _formatPrompt = _lib.lookupFunction<_FormatNative, _FormatDart>('lain_format_prompt');
    _generate = _lib.lookupFunction<_GenerateNative, _GenerateDart>('lain_generate');
  }

  static const int _errLen = 512;

  final DynamicLibrary _lib;
  late final _LoadDart _load;
  late final _FreeDart _free;
  late final _FormatDart _formatPrompt;
  late final _GenerateDart _generate;

  int load(String path, int nCtx, int threads) {
    final pathPtr = path.toNativeUtf8();
    final err = calloc<Uint8>(_errLen);
    try {
      final handle = _load(pathPtr, nCtx, threads, err.cast<Utf8>(), _errLen);
      if (handle == 0) {
        throw LainException(err.cast<Utf8>().toDartString());
      }
      return handle;
    } finally {
      calloc.free(pathPtr);
      calloc.free(err);
    }
  }

  void free(int handle) => _free(handle);

  String formatPrompt(int handle, String system, String user) {
    final systemPtr = system.toNativeUtf8();
    final userPtr = user.toNativeUtf8();
    try {
      final needed = _formatPrompt(handle, systemPtr, userPtr, nullptr, 0);
      if (needed <= 0) {
        throw const LainException('la plantilla del modelo no pudo formatear el turno');
      }
      final buffer = calloc<Uint8>(needed + 1);
      try {
        final written = _formatPrompt(
            handle, systemPtr, userPtr, buffer.cast<Char>(), needed + 1);
        return buffer.cast<Utf8>().toDartString(length: written);
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(systemPtr);
      calloc.free(userPtr);
    }
  }

  int generate(
    int handle,
    String prompt,
    int maxTokens,
    double temp,
    double topP,
    int seed,
    Pointer<NativeFunction<PieceCallbackNative>> callback,
  ) {
    final promptPtr = prompt.toNativeUtf8();
    final err = calloc<Uint8>(_errLen);
    try {
      final produced = _generate(handle, promptPtr, maxTokens, temp, topP, seed,
          callback, nullptr, err.cast<Utf8>(), _errLen);
      if (produced < 0) {
        throw LainException(err.cast<Utf8>().toDartString());
      }
      return produced;
    } finally {
      calloc.free(promptPtr);
      calloc.free(err);
    }
  }
}
