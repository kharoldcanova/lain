import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/chat/chat_message.dart';

final chatControllerProvider =
    NotifierProvider<ChatController, List<ChatMessage>>(ChatController.new);

class ChatController extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() => const [];

  /// Añade el turno del usuario. El puente con llama.cpp llega en T1.2.
  void send(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    state = [
      ...state,
      ChatMessage(role: ChatRole.user, text: text, createdAt: now),
      ChatMessage(
        role: ChatRole.lain,
        text: 'Todavía no tengo el modelo cargado. Cuando exista el puente '
            'con llama.cpp podré responderte aquí mismo.',
        createdAt: now,
      ),
    ];
  }
}
