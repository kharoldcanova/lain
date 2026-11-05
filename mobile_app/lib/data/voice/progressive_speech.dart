import 'dart:async';

import '../../domain/voice/sentence_streamer.dart';
import 'tts_engine.dart';

/// Motor de voz de la respuesta del modelo.
abstract interface class SpeechEngine {
  Future<bool> isAvailable();

  Future<void> beginTurn();

  void add(String visibleDelta);

  Future<void> endTurn();

  Future<void> stop();
}

/// Habla el texto visible a medida que llega, una oración por vez.
///
/// Nunca recibe el bloque `<think>`: el llamador solo le pasa
/// `ThinkParser.visible`.
class ProgressiveSpeech implements SpeechEngine {
  ProgressiveSpeech({TtsEngine? engine}) : _engine = engine ?? TtsEngine();

  final TtsEngine _engine;
  final SentenceStreamer _sentences = SentenceStreamer();
  var _counter = 0;
  var _active = false;

  @override
  Future<bool> isAvailable() => _engine.isReady();

  @override
  Future<void> beginTurn() async {
    _sentences.reset();
    _active = await _engine.isReady();
    if (_active) await _engine.stop();
  }

  @override
  void add(String visibleDelta) {
    if (!_active || visibleDelta.isEmpty) return;
    for (final sentence in _sentences.add(visibleDelta)) {
      unawaited(_speak(sentence));
    }
  }

  @override
  Future<void> endTurn() async {
    if (_active) {
      for (final sentence in _sentences.flush()) {
        await _speak(sentence);
      }
    }
    _active = false;
  }

  @override
  Future<void> stop() async {
    _sentences.reset();
    _active = false;
    await _engine.stop();
  }

  Future<void> _speak(String sentence) =>
      _engine.speak(sentence, id: 'lain-${_counter++}');
}
