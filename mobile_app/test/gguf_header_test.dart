import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/gguf_header.dart';

import 'support/gguf_fixture.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('lain-gguf-'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File write(String name, List<int> bytes) {
    final file = File('${dir.path}/$name')..writeAsBytesSync(bytes);
    return file;
  }

  test('lee general.architecture del GGUF', () async {
    final file = write('lfm3.gguf', buildGguf(architecture: 'lfm3'));

    final info = await readGgufInfo(file);

    expect(info.architecture, 'lfm3');
  });

  test('normaliza a minúsculas', () async {
    final file = write('qwen.gguf', buildGguf(architecture: 'Qwen3'));

    expect((await readGgufInfo(file)).architecture, 'qwen3');
  });

  test('rechaza un archivo que no es GGUF', () async {
    final file = write('falso.gguf', 'no soy un gguf'.codeUnits);

    await expectLater(
      readGgufInfo(file),
      throwsA(isA<GgufHeaderException>().having(
        (error) => error.message,
        'message',
        contains('no es un GGUF'),
      )),
    );
  });

  test('rechaza un GGUF sin arquitectura declarada', () async {
    final file = write(
      'sin-arch.gguf',
      buildGguf(architecture: '', includeArchitecture: false),
    );

    await expectLater(
      readGgufInfo(file),
      throwsA(isA<GgufHeaderException>().having(
        (error) => error.message,
        'message',
        contains('arquitectura'),
      )),
    );
  });

  test('rechaza una versión de GGUF no soportada', () async {
    final file = write('v1.gguf', buildGguf(architecture: 'lfm2', version: 1));

    await expectLater(
      readGgufInfo(file),
      throwsA(isA<GgufHeaderException>().having(
        (error) => error.message,
        'message',
        contains('versión'),
      )),
    );
  });

  test('rechaza un archivo truncado', () async {
    final bytes = buildGguf(architecture: 'lfm2');
    final file = write('cortado.gguf', bytes.sublist(0, 20));

    await expectLater(
      readGgufInfo(file),
      throwsA(isA<GgufHeaderException>()),
    );
  });
}
