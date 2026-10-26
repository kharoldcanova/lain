import '../../domain/chat/chat_message.dart';

enum EngineStatus { starting, loading, ready, missingModel, unsupported, error }

class ChatState {
  const ChatState({
    this.messages = const <ChatMessage>[],
    this.status = EngineStatus.starting,
    this.error,
    this.modelPath,
    this.generating = false,
  });

  final List<ChatMessage> messages;
  final EngineStatus status;
  final String? error;
  final String? modelPath;
  final bool generating;

  bool get canSend => status == EngineStatus.ready && !generating;

  ChatState copyWith({
    List<ChatMessage>? messages,
    EngineStatus? status,
    String? error,
    String? modelPath,
    bool? generating,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      modelPath: modelPath ?? this.modelPath,
      generating: generating ?? this.generating,
    );
  }
}
