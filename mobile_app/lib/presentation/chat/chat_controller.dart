import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/llm/lain_engine.dart';
import '../../data/llm/model_store.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_state.dart';

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

final systemPromptProvider = FutureProvider<String>((ref) async {
  return rootBundle.loadString('assets/system_prompt.txt');
});

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() {
    Future<void>.microtask(_init);
    return const ChatState();
  }

  Future<void> _init() async {
    if (!ref.read(localInferenceProvider)) {
      state = state.copyWith(status: EngineStatus.unsupported);
      return;
    }

    state = state.copyWith(status: EngineStatus.loading);
    try {
      final location = await ref.read(modelLocatorProvider)();
      final file = location.file;
      if (file == null) {
        state = state.copyWith(
          status: EngineStatus.missingModel,
          modelPath: location.expectedPath,
        );
        return;
      }

      await ref.read(lainEngineProvider).loadModel(file.path);
      state = state.copyWith(status: EngineStatus.ready, modelPath: file.path);
    } on Object catch (error) {
      state = state.copyWith(status: EngineStatus.error, error: '$error');
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

    final buffer = StringBuffer();
    try {
      final system = await ref.read(systemPromptProvider.future);
      final stream = ref.read(lainEngineProvider).generate(
            systemPrompt: system,
            userMessage: text,
          );
      await for (final piece in stream) {
        buffer.write(piece);
        _setLastLain(buffer.toString());
      }
      if (buffer.isEmpty) {
        _setLastLain('No supe qué responder. Intenta reformular la pregunta.');
      }
    } on Object catch (error) {
      _setLastLain('No pude responder: $error');
    } finally {
      state = state.copyWith(generating: false);
    }
  }

  void _setLastLain(String text) {
    final messages = List<ChatMessage>.of(state.messages);
    if (messages.isEmpty || messages.last.isUser) return;
    messages[messages.length - 1] = ChatMessage(
      role: ChatRole.lain,
      text: text,
      createdAt: messages.last.createdAt,
    );
    state = state.copyWith(messages: messages);
  }
}
