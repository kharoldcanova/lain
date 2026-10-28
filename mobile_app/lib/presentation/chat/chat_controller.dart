import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/diagnostics/startup_log.dart';
import '../../data/llm/lain_engine.dart';
import '../../data/llm/model_installer.dart';
import '../../data/llm/model_store.dart';
import '../../data/storage/chat_store.dart';
import '../../data/storage/lain_database.dart';
import '../../data/storage/memory_store.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_state.dart';
import '../../domain/chat/think_parser.dart';
import '../../domain/memory/belief_capture.dart';

/// Espacio mínimo para copiar el GGUF (1.93 GB) con margen.
const int minimumFreeBytes = 2400 * 1024 * 1024;

final lainEngineProvider = Provider<LainEngine>((ref) {
  final engine = NativeLainEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Solo Android: `dart:ffi` no existe en web.
final localInferenceProvider = Provider<bool>(
  (ref) => !kIsWeb && Platform.isAndroid,
);

final modelLocatorProvider = Provider<Future<ModelLocation> Function()>(
  (ref) => locateModel,
);

final modelInstallerProvider = Provider<ModelInstaller>(
  (ref) => AssetModelInstaller(),
);

/// Persistencia del historial. Si la base de datos no abre, el chat sigue
/// funcionando sin memoria (degradación explícita).
final chatStoreProvider = FutureProvider<ChatStore>((ref) async {
  final db = await LainDatabase.open();
  return SqliteChatStore(db);
});

/// Memoria persistente (observaciones, creencias y prompts).
final memoryStoreProvider = FutureProvider<MemoryStore>((ref) async {
  final db = await LainDatabase.open();
  return MemoryStore(db);
});


final systemPromptProvider = FutureProvider<String>((ref) async {
  return rootBundle.loadString('assets/system_prompt.txt');
});

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

class ChatController extends Notifier<ChatState> {
  ChatStore? _store;
  MemoryStore? _memory;

  @override
  ChatState build() {
    Future<void>.microtask(_init);
    return const ChatState();
  }

  Future<void> _init() async {
    await _restoreHistory();

    if (!ref.read(localInferenceProvider)) {
      state = state.copyWith(status: EngineStatus.unsupported);
      return;
    }

    state = state.copyWith(status: EngineStatus.loading);
    try {
      await StartupLog.write('init: buscando el modelo');
      final location = await ref.read(modelLocatorProvider)();
      var file = location.file;
      await StartupLog.write(
        'init: existe=${file != null} ruta=${location.expectedPath}',
      );

      if (file == null) {
        // Primer arranque: el GGUF viene dentro del APK y se copia aquí.
        state = state.copyWith(
          status: EngineStatus.preparingModel,
          modelPath: location.expectedPath,
          progress: 0,
        );
        final installer = ref.read(modelInstallerProvider);
        final free = await installer.freeBytes();
        await StartupLog.write('init: espacio libre=$free bytes');
        if (free > 0 && free < minimumFreeBytes) {
          await StartupLog.write('init: espacio insuficiente para el modelo');
          state = state.copyWith(
            status: EngineStatus.missingModel,
            modelPath: location.expectedPath,
            clearProgress: true,
            error: 'Quedan ${_gigabytes(free)} GB libres y hacen falta '
                '${_gigabytes(minimumFreeBytes)} GB para copiar el modelo.',
          );
          return;
        }

        await StartupLog.write('init: copiando el modelo desde los assets');
        await installer.install(
          assetPath: modelAssetPath,
          targetPath: location.expectedPath,
          onProgress: (progress) {
            state = state.copyWith(progress: progress);
          },
        );
        await StartupLog.write('init: copia terminada');
        file = File(location.expectedPath);
        if (!await file.exists()) {
          await StartupLog.write('init: el archivo no existe tras la copia');
          state = state.copyWith(
            status: EngineStatus.missingModel,
            modelPath: location.expectedPath,
            clearProgress: true,
          );
          return;
        }
      }

      state = state.copyWith(status: EngineStatus.loading, clearProgress: true);
      await StartupLog.write('init: cargando el modelo en llama.cpp');
      await ref.read(lainEngineProvider).loadModel(file.path);
      await StartupLog.write('init: modelo cargado');
      state = state.copyWith(status: EngineStatus.ready, modelPath: file.path);
    } on Object catch (error, stack) {
      await StartupLog.write('init: error $error\n$stack');
      state = state.copyWith(status: EngineStatus.error, error: '$error');
    }
  }

  /// Reintenta el arranque del motor tras un fallo.
  Future<void> retry() async {
    if (state.generating) return;
    state = state.copyWith(
      status: EngineStatus.starting,
      clearError: true,
      clearProgress: true,
    );
    await _init();
  }

  String _gigabytes(int bytes) =>
      (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);

  Future<void> _restoreHistory() async {
    try {
      final store = await ref.read(chatStoreProvider.future);
      _store = store;
      final history = store.loadRecent();
      if (history.isNotEmpty) {
        state = state.copyWith(messages: history);
      }
    } on Object catch (error) {
      debugPrint('Sin persistencia del historial: $error');
    }

    try {
      _memory = await ref.read(memoryStoreProvider.future);
    } on Object catch (error) {
      debugPrint('Sin memoria persistente: $error');
    }
  }

  /// Bloque de memoria recuperada que se inyecta antes de generar.
  String? _memoryContext(String query) {
    final memory = _memory;
    if (memory == null) return null;
    final items = memory.context(query: query, limit: 6, charBudget: 1200);
    if (items.isEmpty) return null;
    final buffer = StringBuffer('[MEMORIA]\n');
    for (final item in items) {
      buffer.writeln('- (${item.type}) ${item.title}: ${item.content}');
    }
    buffer.write('[FIN MEMORIA]');
    return buffer.toString();
  }

  void _captureBelief(String? thought) {
    final memory = _memory;
    if (memory == null) return;
    final belief = beliefFromThought(thought);
    if (belief == null) return;
    try {
      memory.save(
        type: MemoryType.belief,
        title: belief.title,
        content: belief.content,
        topicKey: belief.topicKey,
      );
    } on Object catch (error) {
      debugPrint('No se pudo guardar la creencia: $error');
    }
  }

  /// Borra el historial persistido y el de pantalla.
  Future<void> clearHistory() async {
    state = state.copyWith(messages: const <ChatMessage>[]);
    try {
      _store?.clear();
    } on Object catch (error) {
      debugPrint('No se pudo borrar el historial: $error');
    }
  }

  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || !state.canSend) return;

    final now = DateTime.now();
    state = state.copyWith(
      messages: <ChatMessage>[
        ...state.messages,
        ChatMessage(role: ChatRole.user, text: text, createdAt: now),
        ChatMessage(role: ChatRole.lain, text: '', createdAt: now),
      ],
      generating: true,
      clearError: true,
    );

    _memory?.savePrompt(text);
    final parser = ThinkParser();
    try {
      final system = await ref.read(systemPromptProvider.future);
      final memory = _memoryContext(text);
      final stream = ref.read(lainEngineProvider).generate(
            systemPrompt: memory == null ? system : '$system\n\n$memory',
            userMessage: text,
          );
      final clock = Stopwatch()..start();
      int? firstTokenMs;
      var chars = 0;
      await for (final piece in stream) {
        firstTokenMs ??= clock.elapsedMilliseconds;
        chars += piece.length;
        parser.add(piece);
        _setLastLain(parser.visible.trim(), thought: parser.thought);
      }
      parser.close();
      _captureBelief(parser.thought);
      final reply = parser.visible.trim();
      await StartupLog.write(
        'turno: ttft=${firstTokenMs ?? -1}ms total=${clock.elapsedMilliseconds}ms '
        'chars=$chars pensamiento=${parser.thought.length}',
      );
      _setLastLain(
        reply.isEmpty ? 'No supe qué responder. Intenta reformular la pregunta.' : reply,
        thought: parser.thought,
      );
    } on Object catch (error) {
      _setLastLain('No pude responder: $error');
    } finally {
      await _persistTurn();
      state = state.copyWith(generating: false);
    }
  }

  Future<void> _persistTurn() async {
    final store = _store;
    final messages = state.messages;
    if (store == null || messages.length < 2) return;
    final user = messages[messages.length - 2];
    final lain = messages.last;
    if (!user.isUser || lain.isUser) return;
    try {
      store.saveTurn(user: user, lain: lain);
    } on Object catch (error) {
      debugPrint('No se pudo guardar el turno: $error');
    }
  }

  void _setLastLain(String text, {String? thought}) {
    final messages = List<ChatMessage>.of(state.messages);
    if (messages.isEmpty || messages.last.isUser) return;
    messages[messages.length - 1] = ChatMessage(
      role: ChatRole.lain,
      text: text,
      createdAt: messages.last.createdAt,
      thought: thought,
    );
    state = state.copyWith(messages: messages);
  }
}
