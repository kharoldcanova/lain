import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Error del motor de voz con mensaje para el usuario.
class SttException implements Exception {
  const SttException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Motor de transcripción local (whisper.cpp).
abstract interface class SttEngine {
  bool get isReady;

  Future<void> loadModel(String path, {int threads});

  /// Transcribe PCM16 mono a 16 kHz.
  Future<String> transcribe(Uint8List pcm16, {String language});

  Future<void> dispose();
}

typedef _SttLoadNative = IntPtr Function(
    Pointer<Utf8> path, Int32 threads, Pointer<Utf8> err, Int32 errLen);
typedef _SttLoadDart = int Function(
    Pointer<Utf8> path, int threads, Pointer<Utf8> err, int errLen);

typedef _SttFreeNative = Void Function(IntPtr handle);
typedef _SttFreeDart = void Function(int handle);

typedef _SttTranscribeNative = Int32 Function(
    IntPtr handle,
    Pointer<Float> samples,
    Int32 count,
    Pointer<Utf8> language,
    Pointer<Char> out,
    Int32 outLen,
    Pointer<Utf8> err,
    Int32 errLen);
typedef _SttTranscribeDart = int Function(
    int handle,
    Pointer<Float> samples,
    int count,
    Pointer<Utf8> language,
    Pointer<Char> out,
    int outLen,
    Pointer<Utf8> err,
    int errLen);

/// Bindings a `liblain_stt.so`.
class SttNative {
  SttNative() : _lib = DynamicLibrary.open('liblain_stt.so') {
    _load = _lib.lookupFunction<_SttLoadNative, _SttLoadDart>('lain_stt_load');
    _free = _lib.lookupFunction<_SttFreeNative, _SttFreeDart>('lain_stt_free');
    _transcribe = _lib.lookupFunction<_SttTranscribeNative, _SttTranscribeDart>(
      'lain_stt_transcribe',
    );
  }

  /// `true` si la biblioteca nativa está empaquetada en este APK.
  static bool get isAvailable {
    try {
      DynamicLibrary.open('liblain_stt.so');
      return true;
    } on Object {
      return false;
    }
  }

  static const int _errLen = 512;
  static const int _outputLen = 8192;

  final DynamicLibrary _lib;
  late final _SttLoadDart _load;
  late final _SttFreeDart _free;
  late final _SttTranscribeDart _transcribe;

  int load(String path, int threads) {
    final pathPtr = path.toNativeUtf8();
    final err = calloc<Uint8>(_errLen);
    try {
      final handle = _load(pathPtr, threads, err.cast<Utf8>(), _errLen);
      if (handle == 0) {
        throw SttException(err.cast<Utf8>().toDartString());
      }
      return handle;
    } finally {
      calloc.free(pathPtr);
      calloc.free(err);
    }
  }

  void free(int handle) => _free(handle);

  String transcribe(
    int handle,
    Float32List samples, {
    String language = 'es',
  }) {
    final samplePtr = calloc<Float>(samples.length);
    final languagePtr = language.toNativeUtf8();
    final out = calloc<Uint8>(_outputLen);
    final err = calloc<Uint8>(_errLen);
    try {
      samplePtr.asTypedList(samples.length).setAll(0, samples);
      final written = _transcribe(
        handle,
        samplePtr,
        samples.length,
        languagePtr,
        out.cast<Char>(),
        _outputLen,
        err.cast<Utf8>(),
        _errLen,
      );
      if (written < 0) {
        throw SttException(err.cast<Utf8>().toDartString());
      }
      return out.cast<Utf8>().toDartString(length: written);
    } finally {
      calloc.free(samplePtr);
      calloc.free(languagePtr);
      calloc.free(out);
      calloc.free(err);
    }
  }
}

/// Motor de voz nativo en un isolate propio: la transcripción no bloquea la UI.
class NativeSttEngine implements SttEngine {
  SendPort? _commands;
  ReceivePort? _events;
  Isolate? _isolate;
  Completer<void>? _loadCompleter;
  Completer<String>? _resultCompleter;
  bool _ready = false;

  @override
  bool get isReady => _ready;

  Future<void> _ensureStarted() async {
    if (_isolate != null) return;
    final readyPort = ReceivePort();
    _events = ReceivePort();
    _isolate = await Isolate.spawn(
      _sttWorker,
      <Object>[readyPort.sendPort, _events!.sendPort],
      debugName: 'lain-stt',
    );
    _commands = await readyPort.first as SendPort;
    readyPort.close();
    _events!.listen(_onEvent);
  }

  void _onEvent(Object? message) {
    final event = message as List<Object?>;
    switch (event[0]) {
      case 'loaded':
        _ready = true;
        _loadCompleter?.complete();
        _loadCompleter = null;
      case 'result':
        _resultCompleter?.complete(event[1] as String);
        _resultCompleter = null;
      case 'error':
        final error = SttException(event[1] as String);
        _loadCompleter?.completeError(error);
        _loadCompleter = null;
        _resultCompleter?.completeError(error);
        _resultCompleter = null;
    }
  }

  @override
  Future<void> loadModel(String path, {int threads = 4}) async {
    await _ensureStarted();
    final completer = Completer<void>();
    _loadCompleter = completer;
    _commands!.send(<Object>['load', path, threads]);
    return completer.future;
  }

  @override
  Future<String> transcribe(Uint8List pcm16, {String language = 'es'}) {
    if (!_ready) {
      return Future<String>.error(
        const SttException('el modelo de voz no está cargado'),
      );
    }
    if (pcm16.lengthInBytes < 2) {
      return Future<String>.value('');
    }
    final completer = Completer<String>();
    _resultCompleter = completer;
    _commands!.send(<Object>['transcribe', pcm16, language]);
    return completer.future;
  }

  /// PCM16 little-endian a float normalizado [-1, 1].
  static Float32List pcm16ToFloat(Uint8List pcm16) {
    final samples = pcm16.lengthInBytes ~/ 2;
    final result = Float32List(samples);
    final view = ByteData.sublistView(pcm16);
    for (var i = 0; i < samples; i++) {
      result[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return result;
  }

  @override
  Future<void> dispose() async {
    _commands?.send(<Object>['dispose']);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _events?.close();
    _events = null;
    _ready = false;
  }
}

void _sttWorker(List<Object> args) {
  final commands = ReceivePort();
  (args[0] as SendPort).send(commands.sendPort);
  final events = args[1] as SendPort;

  SttNative? native;
  Object? initError;
  try {
    native = SttNative();
  } on Object catch (error) {
    initError = error;
  }
  var handle = 0;

  commands.listen((Object? message) {
    final command = message as List<Object?>;
    switch (command[0]) {
      case 'load':
        final engine = native;
        if (engine == null) {
          events.send(<Object>[
            'error',
            'no se pudo cargar el motor de voz: $initError',
          ]);
          return;
        }
        try {
          if (handle != 0) {
            engine.free(handle);
            handle = 0;
          }
          handle = engine.load(command[1] as String, command[2] as int);
          events.send(<Object>['loaded']);
        } on Object catch (error) {
          events.send(<Object>['error', '$error']);
        }
      case 'transcribe':
        final engine = native;
        if (engine == null || handle == 0) {
          events.send(<Object>['error', 'el modelo de voz no está cargado']);
          return;
        }
        try {
          final samples = NativeSttEngine.pcm16ToFloat(command[1] as Uint8List);
          final text = engine.transcribe(
            handle,
            samples,
            language: command[2] as String,
          );
          events.send(<Object>['result', text.trim()]);
        } on Object catch (error) {
          events.send(<Object>['error', '$error']);
        }
      case 'dispose':
        if (handle != 0) native?.free(handle);
        handle = 0;
        events.send(<Object>['disposed']);
    }
  });
}
