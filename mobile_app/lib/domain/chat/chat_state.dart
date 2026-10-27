import '../../domain/chat/chat_message.dart';

enum EngineStatus {
  starting,
  preparingModel,
  loading,
  ready,
  missingModel,
  unsupported,
  error,
}

class ChatState {
  const ChatState({
    this.messages = const <ChatMessage>[],
    this.status = EngineStatus.starting,
    this.error,
    this.modelPath,
    this.progress,
    this.generating = false,
  });

  final List<ChatMessage> messages;
  final EngineStatus status;
  final String? error;
  final String? modelPath;

  /// Avance de la copia del modelo empaquetado (0..1).
  final double? progress;
  final bool generating;

  bool get canSend => status == EngineStatus.ready && !generating;

  ChatState copyWith({
    List<ChatMessage>? messages,
    EngineStatus? status,
    String? error,
    String? modelPath,
    double? progress,
    bool? generating,
    bool clearError = false,
    bool clearProgress = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      modelPath: modelPath ?? this.modelPath,
      progress: clearProgress ? null : (progress ?? this.progress),
      generating: generating ?? this.generating,
    );
  }
}
