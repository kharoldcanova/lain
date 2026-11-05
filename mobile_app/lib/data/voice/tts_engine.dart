import 'package:flutter/services.dart';

/// Envoltorio del `TextToSpeech` nativo de Android.
class TtsEngine {
  static const MethodChannel _channel =
      MethodChannel('com.lain.lain_mobile/tts');

  Future<bool> isReady() async {
    try {
      return await _channel.invokeMethod<bool>('isReady') ?? false;
    } on Object {
      return false;
    }
  }

  /// Encola [text]. Con [flush] descarta lo que todavía no se dijo.
  Future<bool> speak(
    String text, {
    required String id,
    bool flush = false,
  }) async {
    if (text.trim().isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('speak', <String, Object?>{
            'text': text,
            'id': id,
            'flush': flush,
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on Object {
      // Detener la voz nunca debe romper el chat.
    }
  }
}
