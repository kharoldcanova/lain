enum ChatRole { user, lain }

/// Un turno de la conversación. `text` ya viene limpio del bloque `think`.
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final ChatRole role;
  final String text;
  final DateTime createdAt;

  bool get isUser => role == ChatRole.user;
}
