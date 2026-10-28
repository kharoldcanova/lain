import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/domain/chat/think_parser.dart';

/// Tags construidos con escapes para no depender del escapado del editor.
const String open = '\u003Cthink>';
const String close = '\u003C/think>';

void main() {
  test('separa el bloque think del texto visible', () {
    final parser = ThinkParser()
      ..add('$open{"tono":"calido"}$close')
      ..add(' Hola, soy LAIN.')
      ..close();

    expect(parser.thought, '{"tono":"calido"}');
    expect(parser.visible, ' Hola, soy LAIN.');
  });

  test('tolera el bloque partido en fragmentos arbitrarios', () {
    final parser = ThinkParser();
    for (final piece in <String>[
      '\u003Cth',
      'ink>',
      '{"a":',
      '1}\u003C/th',
      'ink>',
      '\n',
      'Respuesta',
    ]) {
      parser.add(piece);
    }
    parser.close();

    expect(parser.thought, '{"a":1}');
    expect(parser.visible, '\nRespuesta');
  });

  test('no filtra texto que solo se parece al tag', () {
    final parser = ThinkParser()
      ..add('Pienso que el \u003Cth')
      ..add('ema es claro.')
      ..close();

    expect(parser.thought, '');
    expect(parser.visible, 'Pienso que el \u003Cthema es claro.');
  });

  test('conserva varios bloques consecutivos en el pensamiento', () {
    final parser = ThinkParser()
      ..add('${open}uno$close')
      ..add('${open}dos$close')
      ..add('Texto final.')
      ..close();

    expect(parser.thought, 'unodos');
    expect(parser.visible, 'Texto final.');
  });

  test('si el bloque no cierra, el texto se muestra en lugar de perderse', () {
    final parser = ThinkParser()
      ..add('$open{"a":1} sin cierre')
      ..close();

    expect(parser.thought, '');
    expect(parser.visible, '{"a":1} sin cierre');
  });

  test('sin bloque think todo el stream es texto visible', () {
    final parser = ThinkParser()
      ..add('Hola ')
      ..add('mundo')
      ..close();

    expect(parser.thought, '');
    expect(parser.visible, 'Hola mundo');
  });
}
