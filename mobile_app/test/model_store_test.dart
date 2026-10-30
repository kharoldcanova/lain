import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/model_manager.dart';
import 'package:lain_mobile/data/llm/model_store.dart';

void main() {
  late Directory dir;
  late Directory sources;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lain-modelos-');
    sources = await Directory.systemTemp.createTemp('lain-modelos-src-');
  });

  tearDown(() async {
    for (final entry in [dir, sources]) {
      if (await entry.exists()) {
        await entry.delete(recursive: true);
      }
    }
  });

  File crear(String nombre, DateTime hora) {
    final file = File('${dir.path}/$nombre')..writeAsStringSync('x');
    file.setLastModifiedSync(hora);
    return file;
  }

  File source(String nombre, String contenido) {
    return File('${sources.path}/$nombre')..writeAsStringSync(contenido);
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

  test('locateModelIn sin nada instalado devuelve la carpeta sin archivo', () async {
    final location = await locateModelIn(dir);

    expect(location.file, isNull);
    expect(location.expectedPath, dir.path);
  });

  test('locateModelIn usa el GGUF suelto como fallback legado', () async {
    final legacy = crear('MiniCPM5-2B.Q4_K_M.gguf', DateTime(2026, 10, 29, 20));

    final location = await locateModelIn(dir);

    expect(location.file?.path, legacy.path);
  });

  test('locateModelIn prefiere el modelo activo registrado', () async {
    final manager = ModelManager(dir);
    final a = await manager.importModel(
      source: source('modelo-a.Q4_K_M.gguf', 'a'),
    );
    final b = await manager.importModel(
      source: source('modelo-b.Q4_K_M.gguf', 'b'),
    );
    crear('MiniCPM5-2B.Q4_K_M.gguf', DateTime(2026, 10, 29, 20));
    await manager.setActiveModel(b.id);

    final location = await locateModelIn(dir);

    expect(location.file?.path, contains('modelo-b'));
    expect(location.file?.path, isNot(contains('MiniCPM5')));
    expect((await manager.activeModel())?.id, isNot(a.id));
  });

  test('locateModelIn cae al fallback si el activo perdió su archivo', () async {
    final manager = ModelManager(dir);
    final a = await manager.importModel(
      source: source('modelo-a.Q4_K_M.gguf', 'a'),
    );
    await manager.setActiveModel(a.id);
    File(a.filePath(dir.path)).deleteSync();
    final legacy = crear('MiniCPM5-2B.Q4_K_M.gguf', DateTime(2026, 10, 29, 20));

    final location = await locateModelIn(dir);

    expect(location.file?.path, legacy.path);
  });
}
