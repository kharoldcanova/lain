import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/model_store.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lain-modelos-');
  });

  tearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  File crear(String nombre, DateTime hora) {
    final file = File('${dir.path}/$nombre')..writeAsStringSync('x');
    file.setLastModifiedSync(hora);
    return file;
  }

  test('sin GGUF no hay modelo', () {
    expect(pickModelFile(dir.listSync().whereType<File>().toList()), isNull);
  });

  test('elige el GGUF modificado más recientemente', () {
    crear('Qwen2.5-3B-Instruct.Q4_K_M.gguf', DateTime(2026, 10, 26, 11));
    final minicpm = crear(
      'MiniCPM5-2B.Q4_K_M.gguf',
      DateTime(2026, 10, 29, 20),
    );

    final picked = pickModelFile(dir.listSync().whereType<File>().toList());

    expect(picked?.path, minicpm.path);
  });

  test('ignora archivos que no son .gguf', () {
    crear('lain_startup.log', DateTime(2026, 10, 29, 21));
    final modelo = crear('MiniCPM5-2B.Q4_K_M.gguf', DateTime(2026, 10, 20));

    final picked = pickModelFile(dir.listSync().whereType<File>().toList());

    expect(picked?.path, modelo.path);
  });
}
