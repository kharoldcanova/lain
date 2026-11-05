import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/domain/voice/sentence_streamer.dart';

void main() {
  test('entrega oraciones completas en fragmentos arbitrarios', () {
    final streamer = SentenceStreamer();

    expect(streamer.add('Hola mun'), isEmpty);
    expect(streamer.add('do. ¿Cómo'), <String>['Hola mundo.']);
    expect(streamer.add(' estás?'), <String>['¿Cómo estás?']);
  });

  test('mantiene la cola incompleta hasta flush', () {
    final streamer = SentenceStreamer();
    streamer.add('Una frase sin punto final');

    expect(streamer.flush(), <String>['Una frase sin punto final']);
    expect(streamer.flush(), isEmpty);
  });

  test('no parte decimales', () {
    final streamer = SentenceStreamer();

    expect(streamer.add('El valor es 3.'), isEmpty);
    expect(streamer.add('14 exactos. '), <String>['El valor es 3.14 exactos.']);
  });

  test('corta también por salto de línea', () {
    final streamer = SentenceStreamer();

    expect(streamer.add('Primera línea\nSegunda'), <String>['Primera línea']);
  });

  test('reset descarta el resto pendiente', () {
    final streamer = SentenceStreamer();
    streamer.add('texto a medias');

    streamer.reset();

    expect(streamer.flush(), isEmpty);
  });
}
