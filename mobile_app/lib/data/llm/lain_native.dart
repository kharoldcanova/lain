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

typedef _GenerateExNative = Int32 Function(
    IntPtr handle,
    Pointer<Utf8> prompt,
    Int32 maxTokens,
    Float temp,
    Float topP,
    Int32 topK,
    Float repeatPenalty,
    Int32 seed,
    Pointer<NativeFunction<PieceCallbackNative>> callback,
    Pointer<Void> userData,
    Pointer<Utf8> err,
    Int32 errLen);
typedef _GenerateExDart = int Function(
    int handle,
    Pointer<Utf8> prompt,
    int maxTokens,
    double temp,
    double topP,
    int topK,
    double repeatPenalty,
    int seed,
    Pointer<NativeFunction<PieceCallbackNative>> callback,
    Pointer<Void> userData,
    Pointer<Utf8> err,
    int errLen);

typedef _LastMetricsNative = Int32 Function(IntPtr handle, Pointer<LainMetrics> out);
typedef _LastMetricsDart = int Function(int handle, Pointer<LainMetrics> out);

typedef _BackendNameNative = Int32 Function(Pointer<Char> out, Int32 outLen);
typedef _BackendNameDart = int Function(Pointer<Char> out, int outLen);

typedef PieceCallbackNative = Void Function(Pointer<Char> piece, Int32 len, Pointer<Void> userData);
typedef PieceCallbackDart = void Function(Pointer<Char> piece, int len, Pointer<Void> userData);

/// Métricas del último turno. El layout debe coincidir exactamente con
/// `lain_metrics` del puente experimental (4 int64 + 8 int32 = 64 bytes).
final class LainMetrics extends Struct {
  @Int64()
  external int loadMs;

  @Int64()
  external int prefillMs;

  @Int64()
  external int decodeMs;

  @Int64()
  external int ttftMs;

  @Int32()
  external int nPromptTokens;

  @Int32()
  external int nGeneratedTokens;

  @Int32()
  external int nThreads;

  @Int32()
  external int nBatchThreads;

  @Int32()
  external int nCtx;

  /// `llama_load_mode`: -1 auto, 0 none, 1 mmap, 2 mlock, 3 mmap+mlock, 4 direct.
  @Int32()
  external int loadMode;

  @Int32()
  external int nBackend;

  @Int32()
  external int instrumented;
}

/// Vista Dart de [LainMetrics] con valores listos para el registro de turnos.
class LainTurnMetrics {
  const LainTurnMetrics({
    required this.loadMs,
    required this.prefillMs,
    required this.decodeMs,
    required this.ttftMs,
    required this.nPromptTokens,
    required this.nGeneratedTokens,
    required this.nThreads,
    required this.nBatchThreads,
    required this.nCtx,
    required this.loadMode,
    required this.nBackend,
    required this.instrumented,
  });

  factory LainTurnMetrics.fromNative(LainMetrics metrics) => LainTurnMetrics(
        loadMs: metrics.loadMs,
        prefillMs: metrics.prefillMs,
        decodeMs: metrics.decodeMs,
        ttftMs: metrics.ttftMs,
        nPromptTokens: metrics.nPromptTokens,
        nGeneratedTokens: metrics.nGeneratedTokens,
        nThreads: metrics.nThreads,
        nBatchThreads: metrics.nBatchThreads,
        nCtx: metrics.nCtx,
        loadMode: metrics.loadMode,
        nBackend: metrics.nBackend,
        instrumented: metrics.instrumented != 0,
      );

  factory LainTurnMetrics.fromJson(Map<String, Object?> json) => LainTurnMetrics(
        loadMs: (json['load_ms'] as num?)?.toInt() ?? 0,
        prefillMs: (json['prefill_ms'] as num?)?.toInt() ?? 0,
        decodeMs: (json['decode_ms'] as num?)?.toInt() ?? 0,
        ttftMs: (json['ttft_ms'] as num?)?.toInt() ?? 0,
        nPromptTokens: (json['n_prompt'] as num?)?.toInt() ?? 0,
        nGeneratedTokens: (json['n_generated'] as num?)?.toInt() ?? 0,
        nThreads: (json['n_threads'] as num?)?.toInt() ?? 0,
        nBatchThreads: (json['n_batch_threads'] as num?)?.toInt() ?? 0,
        nCtx: (json['n_ctx'] as num?)?.toInt() ?? 0,
        loadMode: (json['load_mode'] as num?)?.toInt() ?? -1,
        nBackend: (json['n_backend'] as num?)?.toInt() ?? 0,
        instrumented: json['instrumented'] == true,
      );

  final int loadMs;
  final int prefillMs;
  final int decodeMs;
  final int ttftMs;
  final int nPromptTokens;
  final int nGeneratedTokens;
  final int nThreads;
  final int nBatchThreads;
  final int nCtx;
  final int loadMode;
  final int nBackend;
  final bool instrumented;

  /// Tokens por segundo del tramo de decode (0 si no hubo decode).
  double get tokensPerSecond =>
      decodeMs > 0 ? nGeneratedTokens * 1000 / decodeMs : 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'load_ms': loadMs,
        'prefill_ms': prefillMs,
        'decode_ms': decodeMs,
        'ttft_ms': ttftMs,
        'n_prompt': nPromptTokens,
        'n_generated': nGeneratedTokens,
        'n_threads': nThreads,
        'n_batch_threads': nBatchThreads,
        'n_ctx': nCtx,
        'load_mode': loadMode,
        'n_backend': nBackend,
        'instrumented': instrumented,
        'tok_per_s': double.parse(tokensPerSecond.toStringAsFixed(2)),
      };
}

class LainNative {
  LainNative() : _lib = DynamicLibrary.open('liblain_llm.so') {
    _load = _lib.lookupFunction<_LoadNative, _LoadDart>('lain_load');
    _free = _lib.lookupFunction<_FreeNative, _FreeDart>('lain_free');
    _formatPrompt = _lib.lookupFunction<_FormatNative, _FormatDart>('lain_format_prompt');
    _generate = _lib.lookupFunction<_GenerateNative, _GenerateDart>('lain_generate');
    // Instrumentación opcional: el puente de producción no la expone.
    _generateEx = _lookupGenerateEx();
    _lastMetrics = _lookupLastMetrics();
    _backendName = _lookupBackendName();
  }

  static const int _errLen = 512;

  final DynamicLibrary _lib;
  late final _LoadDart _load;
  late final _FreeDart _free;
  late final _FormatDart _formatPrompt;
  late final _GenerateDart _generate;
  _GenerateExDart? _generateEx;
  _LastMetricsDart? _lastMetrics;
  _BackendNameDart? _backendName;

  _GenerateExDart? _lookupGenerateEx() {
    try {
      return _lib.lookupFunction<_GenerateExNative, _GenerateExDart>(
        'lain_generate_ex',
      );
    } on Object {
      return null;
    }
  }

  _LastMetricsDart? _lookupLastMetrics() {
    try {
      return _lib.lookupFunction<_LastMetricsNative, _LastMetricsDart>(
        'lain_last_metrics',
      );
    } on Object {
      return null;
    }
  }

  _BackendNameDart? _lookupBackendName() {
    try {
      return _lib.lookupFunction<_BackendNameNative, _BackendNameDart>(
        'lain_backend_name',
      );
    } on Object {
      return null;
    }
  }

  /// `true` si el puente expone `lain_last_metrics` (experimental).
  bool get supportsInstrumentation => _lastMetrics != null;

  /// `true` si el puente permite sampling configurable (`lain_generate_ex`).
  bool get supportsCustomSampling => _generateEx != null;

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

  /// Igual que [generate] pero con top-k y repeat penalty configurables.
  ///
  /// Solo existe en el puente experimental; el llamador debe comprobar
  /// [supportsCustomSampling].
  int generateEx(
    int handle,
    String prompt,
    int maxTokens,
    double temp,
    double topP,
    int topK,
    double repeatPenalty,
    int seed,
    Pointer<NativeFunction<PieceCallbackNative>> callback,
  ) {
    final generateEx = _generateEx;
    if (generateEx == null) {
      throw const LainException('el motor no soporta sampling configurable');
    }
    final promptPtr = prompt.toNativeUtf8();
    final err = calloc<Uint8>(_errLen);
    try {
      final produced = generateEx(handle, promptPtr, maxTokens, temp, topP, topK,
          repeatPenalty, seed, callback, nullptr, err.cast<Utf8>(), _errLen);
      if (produced < 0) {
        throw LainException(err.cast<Utf8>().toDartString());
      }
      return produced;
    } finally {
      calloc.free(promptPtr);
      calloc.free(err);
    }
  }

  /// Métricas del último turno, o `null` si el motor no las expone.
  LainTurnMetrics? lastMetrics(int handle) {
    final read = _lastMetrics;
    if (read == null) return null;
    final out = calloc<LainMetrics>();
    try {
      if (read(handle, out) == 0) return null;
      return LainTurnMetrics.fromNative(out.ref);
    } finally {
      calloc.free(out);
    }
  }

  /// Archivo de la variante de backend realmente cargada, o `null`.
  String? backendName() {
    final read = _backendName;
    if (read == null) return null;
    final buffer = calloc<Uint8>(256);
    try {
      final written = read(buffer.cast<Char>(), 256);
      if (written <= 0) return null;
      return buffer.cast<Utf8>().toDartString(length: written);
    } finally {
      calloc.free(buffer);
    }
  }
}
