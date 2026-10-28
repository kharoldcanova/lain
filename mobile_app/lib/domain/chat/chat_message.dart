enum ChatRole { user, lain }

/// Un turno de la conversación. `text` ya viene limpio del bloque `think`;
/// el razonamiento, si lo hubo, queda en [thought].
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.createdAt,
    this.thought,
  });

  final ChatRole role;
  final String text;
  final DateTime createdAt;

  /// Bloque `think` del modelo, sin los tags. `null` si no hubo.
  final String? thought;

  bool get isUser => role == ChatRole.user;

  bool get hasThought => thought != null && thought!.isNotEmpty;
}
