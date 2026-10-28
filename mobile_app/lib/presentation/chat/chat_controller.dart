import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/llm/lain_engine.dart';
import '../../data/llm/model_installer.dart';
import '../../data/llm/model_store.dart';
import '../../data/storage/chat_store.dart';
import '../../data/storage/lain_database.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_state.dart';
import '../../domain/chat/think_parser.dart';

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


final systemPromptProvider = FutureProvider<String>((ref) async {
  return rootBundle.loadString('assets/system_prompt.txt');
});

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

class ChatController extends Notifier<ChatState> {
  ChatStore? _store;

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
      final location = await ref.read(modelLocatorProvider)();
      var file = location.file;

      if (file == null) {
        // Primer arranque: el GGUF viene dentro del APK y se copia aquí.
        state = state.copyWith(
          status: EngineStatus.preparingModel,
          modelPath: location.expectedPath,
          progress: 0,
        );
        await ref.read(modelInstallerProvider).install(
          assetPath: modelAssetPath,
          targetPath: location.expectedPath,
          onProgress: (progress) {
            state = state.copyWith(progress: progress);
          },
        );
        file = File(location.expectedPath);
        if (!await file.exists()) {
          state = state.copyWith(
            status: EngineStatus.missingModel,
            modelPath: location.expectedPath,
            clearProgress: true,
          );
          return;
        }
      }

      state = state.copyWith(status: EngineStatus.loading, clearProgress: true);
      await ref.read(lainEngineProvider).loadModel(file.path);
      state = state.copyWith(status: EngineStatus.ready, modelPath: file.path);
    } on Object catch (error) {
      state = state.copyWith(status: EngineStatus.error, error: '$error');
    }
  }

  Future<void> _restoreHistory() async {
    try {
      final store = await ref.read(chatStoreProvider.future);
      _store = store;
      final history = await store.loadRecent();
      if (history.isNotEmpty) {
        state = state.copyWith(messages: history);
      }
    } on Object catch (error) {
      debugPrint('Sin persistencia del historial: $error');
    }
  }

  /// Borra el historial persistido y el de pantalla.
  Future<void> clearHistory() async {
    state = state.copyWith(messages: const <ChatMessage>[]);
    try {
      await _store?.clear();
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

    final parser = ThinkParser();
    try {
      final system = await ref.read(systemPromptProvider.future);
      final stream = ref.read(lainEngineProvider).generate(
            systemPrompt: system,
            userMessage: text,
          );
      await for (final piece in stream) {
        parser.add(piece);
        _setLastLain(parser.visible.trim(), thought: parser.thought);
      }
      parser.close();
      final reply = parser.visible.trim();
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
      await store.saveTurn(user: user, lain: lain);
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
