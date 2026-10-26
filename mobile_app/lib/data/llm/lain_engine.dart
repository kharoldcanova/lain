import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:convert';

import 'lain_native.dart';

/// Motor de inferencia. Implementación nativa en un isolate aparte para no
/// bloquear la UI: el isolate queda dentro de `lain_generate` y reenvía cada
/// pieza de texto por un puerto.
abstract interface class LainEngine {
  bool get isReady;

  Future<void> loadModel(String path, {int contextSize, int threads});

  Stream<String> generate({
    required String systemPrompt,
    required String userMessage,
    int maxTokens,
    double temperature,
    double topP,
    int seed,
  });

  Future<void> dispose();
}

class NativeLainEngine implements LainEngine {
  SendPort? _commands;
  ReceivePort? _events;
  Isolate? _isolate;
  Completer<void>? _loadCompleter;
  StreamController<String>? _generation;
  bool _ready = false;

  @override
  bool get isReady => _ready;

  Future<void> _ensureStarted() async {
    if (_isolate != null) return;

    final readyPort = ReceivePort();
    _events = ReceivePort();
    _isolate = await Isolate.spawn(
      _engineWorker,
      <Object>[readyPort.sendPort, _events!.sendPort],
      debugName: 'lain-engine',
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
      case 'token':
        _generation?.add(event[1] as String);
      case 'done':
        _generation?.close();
        _generation = null;
      case 'error':
        final error = LainException(event[1] as String);
        _loadCompleter?.completeError(error);
        _loadCompleter = null;
        _generation?.addError(error);
        _generation?.close();
        _generation = null;
    }
  }

  @override
  Future<void> loadModel(String path, {int contextSize = 2048, int threads = 4}) async {
    await _ensureStarted();
    final completer = Completer<void>();
    _loadCompleter = completer;
    _commands!.send(<Object>['load', path, contextSize, threads]);
    return completer.future;
  }

  @override
  Stream<String> generate({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 512,
    double temperature = 0.7,
    double topP = 0.9,
    int seed = 42,
  }) {
    if (!_ready) {
      return Stream<String>.error(const LainException('el modelo no está cargado'));
    }

    final controller = StreamController<String>();
    _generation = controller;
    _commands!.send(<Object>[
      'generate',
      systemPrompt,
      userMessage,
      maxTokens,
      temperature,
      topP,
      seed,
    ]);
    return controller.stream;
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

void _engineWorker(List<Object> args) {
  final commands = ReceivePort();
  (args[0] as SendPort).send(commands.sendPort);
  final events = args[1] as SendPort;

  final native = LainNative();
  final chunker = Utf8Chunker();
  var handle = 0;

  late final NativeCallable<PieceCallbackNative> callable =
      NativeCallable<PieceCallbackNative>.isolateLocal(
    (Pointer<Char> piece, int len, Pointer<Void> _) {
      if (len <= 0) return;
      final bytes = piece.cast<Uint8>().asTypedList(len);
      final text = chunker.add(bytes);
      if (text.isNotEmpty) events.send(<Object>['token', text]);
    },
  );

  commands.listen((Object? message) {
    final command = message as List<Object?>;
    switch (command[0]) {
      case 'load':
        try {
          handle = native.load(
            command[1] as String,
            command[2] as int,
            command[3] as int,
          );
          events.send(<Object>['loaded']);
        } on Object catch (error) {
          events.send(<Object>['error', '$error']);
        }
      case 'generate':
        if (handle == 0) {
          events.send(<Object>['error', 'el modelo no está cargado']);
          return;
        }
        chunker.reset();
        try {
          final prompt = native.formatPrompt(
            handle,
            command[1] as String,
            command[2] as String,
          );
          native.generate(
            handle,
            prompt,
            command[3] as int,
            command[4] as double,
            command[5] as double,
            command[6] as int,
            callable.nativeFunction,
          );
          final tail = chunker.flush();
          if (tail.isNotEmpty) events.send(<Object>['token', tail]);
          events.send(<Object>['done']);
        } on Object catch (error) {
          events.send(<Object>['error', '$error']);
        }
      case 'dispose':
        if (handle != 0) native.free(handle);
        handle = 0;
        callable.close();
        events.send(<Object>['disposed']);
    }
  });
}

/// Junta bytes hasta tener una secuencia UTF-8 completa: un token puede cortar
/// una letra acentuada por la mitad.
class Utf8Chunker {
  final List<int> _buffer = <int>[];

  String add(List<int> bytes) {
    _buffer.addAll(bytes);
    try {
      final text = utf8.decode(_buffer);
      _buffer.clear();
      return text;
    } on FormatException {
      if (_buffer.length > 16) {
        final text = utf8.decode(_buffer, allowMalformed: true);
        _buffer.clear();
        return text;
      }
      return '';
    }
  }

  String flush() {
    if (_buffer.isEmpty) return '';
    final text = utf8.decode(_buffer, allowMalformed: true);
    _buffer.clear();
    return text;
  }

  void reset() => _buffer.clear();
}
