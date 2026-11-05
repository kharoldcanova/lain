import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/voice/progressive_speech.dart';
import 'package:lain_mobile/data/voice/tts_engine.dart';

class _FakeTts extends TtsEngine {
  final List<String> spoken = <String>[];
  bool ready = true;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<bool> speak(
    String text, {
    required String id,
    bool flush = false,
  }) async {
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stop() async {
    spoken.clear();
  }
}

void main() {
  test('habla solo oraciones cerradas mientras llega el stream', () async {
    final tts = _FakeTts();
    final speech = ProgressiveSpeech(engine: tts);

    await speech.beginTurn();
    speech.add('Hola mu');
    expect(tts.spoken, isEmpty);
    speech.add('ndo. ¿Cómo');
    expect(tts.spoken, <String>['Hola mundo.']);
    speech.add(' estás?');
    expect(tts.spoken, <String>['Hola mundo.', '¿Cómo estás?']);
    await speech.endTurn();
  });

  test('flush final dice la última oración sin puntuación', () async {
    final tts = _FakeTts();
    final speech = ProgressiveSpeech(engine: tts);

    await speech.beginTurn();
    speech.add('Quedó sin cerrar');
    expect(tts.spoken, isEmpty);
    await speech.endTurn();

    expect(tts.spoken, <String>['Quedó sin cerrar']);
  });

  test('stop corta la voz y descarta lo pendiente', () async {
    final tts = _FakeTts();
    final speech = ProgressiveSpeech(engine: tts);

    await speech.beginTurn();
    speech.add('Hola mundo. ');
    expect(tts.spoken, isNotEmpty);
    await speech.stop();
    speech.add('Esto no debe sonar.');

    expect(tts.spoken, isEmpty);
  });

  test('sin TTS disponible no habla', () async {
    final tts = _FakeTts()..ready = false;
    final speech = ProgressiveSpeech(engine: tts);

    await speech.beginTurn();
    speech.add('Hola mundo.');
    await speech.endTurn();

    expect(tts.spoken, isEmpty);
    expect(await speech.isAvailable(), isFalse);
  });
}
