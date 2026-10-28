import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/domain/memory/belief_capture.dart';

void main() {
  const validJson = '{"thought_trace": "El usuario comparte una foto de la luna '
      'y una frase melancólica; detecto necesidad de contemplación.", '
      '"prior_belief": "La luna solo se asocia a belleza y distancia.", '
      '"belief_shift": "La luna también puede simbolizar permanencia.", '
      '"axiom_alignment_check": "Alineado con empatía."}';

  test('extrae la creencia de un JSON válido', () {
    final belief = beliefFromThought(validJson);

    expect(belief, isNotNull);
    expect(belief!.title, 'La luna solo se asocia a belleza y distancia.');
    expect(belief.content, contains('permanencia'));
    expect(belief.topicKey, startsWith('belief/'));
    expect(belief.topicKey, contains('usuario'));
  });

  test('ignora el JSON envuelto en texto o saltos de línea', () {
    final belief = beliefFromThought('\n  $validJson  \n');

    expect(belief, isNotNull);
  });

  test('devuelve null si falta alguna clave obligatoria', () {
    expect(beliefFromThought('{"thought_trace": "solo esto"}'), isNull);
    expect(
      beliefFromThought('{"prior_belief": "algo", "belief_shift": "  "}'),
      isNull,
    );
  });

  test('devuelve null si el bloque no es JSON', () {
    expect(beliefFromThought('esto no es json'), isNull);
    expect(beliefFromThought(''), isNull);
    expect(beliefFromThought(null), isNull);
  });

  test('el mismo tema produce el mismo topic_key', () {
    final a = beliefFromThought(validJson)!;
    final b = beliefFromThought(validJson)!;

    expect(a.topicKey, b.topicKey);
  });
}
