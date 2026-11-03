import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/model_manager.dart';
import 'package:lain_mobile/data/llm/model_metadata.dart';

void main() {
  late Directory root;
  late Directory sources;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lain-mm-');
    sources = await Directory.systemTemp.createTemp('lain-mm-src-');
  });

  tearDown(() async {
    for (final dir in [root, sources]) {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  });

  /// Archivo dentro de la carpeta de modelos (huérfanos, incompletos, …).
  File createFile(String name, String content) {
    return File('${root.path}/$name')..writeAsStringSync(content);
  }

  /// Archivo fuente de importación, FUERA de la carpeta de modelos.
  File createSource(String name, String content) {
    return File('${sources.path}/$name')..writeAsStringSync(content);
  }

  String sha256Of(String content) => sha256.convert(content.codeUnits).toString();

  test('importa un GGUF válido y lo registra con su SHA-256', () async {
    final source = createSource('qwen3-1.7b.Q4_K_M.gguf', 'contenido del modelo');
    final manager = ModelManager(root);

    final metadata = await manager.importModel(source: source);

    expect(metadata.id, 'qwen3-1.7b.q4_k_m');
    expect(metadata.format, 'gguf');
    expect(metadata.quantization, 'Q4_K_M');
    expect(metadata.family, 'language');
    expect(metadata.sizeBytes, 'contenido del modelo'.length);
    expect(metadata.sha256, sha256Of('contenido del modelo'));

    final inventory = await manager.inventory();
    expect(inventory, hasLength(1));
    expect(inventory.first.id, metadata.id);

    final installed = File('${root.path}/qwen3-1.7b.q4_k_m/qwen3-1.7b.Q4_K_M.gguf');
    expect(installed.existsSync(), isTrue);
    expect(
      File('${root.path}/qwen3-1.7b.q4_k_m/model.json').existsSync(),
      isTrue,
    );
  });

  test('rechaza un id duplicado', () async {
    final source = createSource('qwen3-1.7b.Q4_K_M.gguf', 'uno');
    final manager = ModelManager(root);
    await manager.importModel(source: source);

    await expectLater(
      manager.importModel(source: source),
      throwsA(
        isA<ModelManagerException>().having(
          (error) => error.message,
          'message',
          contains('ya existe'),
        ),
      ),
    );
  });

  test('rechaza un hash esperado incorrecto sin dejar residuos', () async {
    final source = createSource('qwen3-1.7b.Q4_K_M.gguf', 'contenido real');
    final manager = ModelManager(root);

    await expectLater(
      manager.importModel(source: source, expectedSha256: '00' * 32),
      throwsA(
        isA<ModelManagerException>().having(
          (error) => error.message,
          'message',
          contains('SHA-256'),
        ),
      ),
    );

    expect(await manager.inventory(), isEmpty);
    expect(await manager.incompleteInstallations(), isEmpty);
    expect(root.listSync().whereType<Directory>(), isEmpty);
  });

  test('rechaza extensiones que no son .gguf', () async {
    final manager = ModelManager(root);
    final source = createSource('modelo.onnx', 'pesos');

    await expectLater(
      manager.importModel(source: source),
      throwsA(
        isA<ModelManagerException>().having(
          (error) => error.message,
          'message',
          contains('.gguf'),
        ),
      ),
    );
  });

  test('rechaza archivos vacíos', () async {
    final manager = ModelManager(root);
    final source = createSource('vacio.gguf', '');

    await expectLater(
      manager.importModel(source: source),
      throwsA(isA<ModelManagerException>()),
    );
  });

  test('rechaza la importación sin espacio suficiente', () async {
    final source = createSource('grande.Q4_K_M.gguf', 'x' * 1024);
    final manager = ModelManager(root);

    await expectLater(
      manager.importModel(
        source: source,
        freeBytes: () async => 10,
      ),
      throwsA(
        isA<ModelManagerException>().having(
          (error) => error.message,
          'message',
          contains('espacio'),
        ),
      ),
    );
  });

  test('detecta instalaciones incompletas y las excluye del inventario', () async {
    final manager = ModelManager(root);
    await root.create(recursive: true);
    final partialDir = Directory('${root.path}/a-medio')
      ..createSync(recursive: true);
    File('${partialDir.path}/modelo.gguf.part').writeAsStringSync('incompleto');

    expect(await manager.inventory(), isEmpty);
    expect(await manager.incompleteInstallations(), contains('a-medio'));
  });

  test('ignora manifiestos corruptos y reporta la carpeta como incompleta', () async {
    final manager = ModelManager(root);
    final dir = Directory('${root.path}/roto')..createSync(recursive: true);
    File('${dir.path}/model.json').writeAsStringSync('{no es json');

    expect(await manager.inventory(), isEmpty);
    expect(await manager.incompleteInstallations(), contains('roto'));
  });

  test('lista los GGUF sueltos de la raíz (modelos legados)', () async {
    final manager = ModelManager(root);
    createFile('MiniCPM5-2B.Q4_K_M.gguf', 'modelo viejo');
    createFile('notas.txt', 'no es modelo');

    final orphans = await manager.orphanGgufs();

    expect(orphans, hasLength(1));
    expect(orphans.first.path, endsWith('MiniCPM5-2B.Q4_K_M.gguf'));
  });

  test('elimina solo la carpeta del modelo indicado', () async {
    final manager = ModelManager(root);
    final a = await manager.importModel(
      source: createSource('modelo-a.Q4_K_M.gguf', 'a'),
    );
    final b = await manager.importModel(
      source: createSource('modelo-b.Q4_K_M.gguf', 'b'),
    );
    final external = File('${root.path}/lain.db')..writeAsStringSync('recuerdos');

    await manager.removeModel(a.id);

    expect(Directory('${root.path}/modelo-a.q4_k_m').existsSync(), isFalse);
    expect(Directory('${root.path}/modelo-b.q4_k_m').existsSync(), isTrue);
    expect(external.readAsStringSync(), 'recuerdos');
    expect((await manager.inventory()).map((m) => m.id), contains(b.id));
  });

  test('rechaza eliminar un modelo inexistente', () async {
    final manager = ModelManager(root);

    await expectLater(
      manager.removeModel('no-existe'),
      throwsA(isA<ModelManagerException>()),
    );
  });

  test('selecciona el modelo activo y lo persiste', () async {
    final manager = ModelManager(root);
    final a = await manager.importModel(
      source: createSource('modelo-a.Q4_K_M.gguf', 'a'),
    );
    await manager.importModel(source: createSource('modelo-b.Q4_K_M.gguf', 'b'));

    await manager.setActiveModel(a.id);

    expect(await manager.activeModelId(), a.id);
    final reopened = ModelManager(root);
    expect(await reopened.activeModelId(), a.id);
    expect((await reopened.activeModel())?.id, a.id);
  });

  test('rechaza activar un modelo no instalado', () async {
    final manager = ModelManager(root);

    await expectLater(
      manager.setActiveModel('fantasma'),
      throwsA(isA<ModelManagerException>()),
    );
  });

  test('usageBytes suma modelos, sueltos e incompletos', () async {
    final manager = ModelManager(root);
    await manager.importModel(
      source: createSource('modelo-a.Q4_K_M.gguf', '12345'),
    );
    createFile('viejo.Q4_K_M.gguf', '123');
    final partial = Directory('${root.path}/.importing-x')
      ..createSync(recursive: true);
    File('${partial.path}/model.gguf.part').writeAsStringSync('12');

    var expected = 0;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is File) expected += entity.lengthSync();
    }

    expect(await manager.usageBytes(), expected);
    // Incluye el GGUF, el suelto, el .part y los manifiestos model.json.
    expect(expected, greaterThan(5 + 3 + 2));
  });

  test('removeOrphan borra solo un GGUF suelto de la raíz', () async {
    final manager = ModelManager(root);
    final orphan = createFile('viejo.Q4_K_M.gguf', 'pesos');
    final keep = createFile('notas.txt', 'no es modelo');
    final nested = Directory('${root.path}/carpeta')..createSync(recursive: true);
    final nestedGguf = File('${nested.path}/dentro.gguf')..writeAsStringSync('x');

    await manager.removeOrphan(orphan);

    expect(orphan.existsSync(), isFalse);
    expect(keep.existsSync(), isTrue);
    await expectLater(
      manager.removeOrphan(nestedGguf),
      throwsA(isA<ModelManagerException>()),
    );
    await expectLater(
      manager.removeOrphan(keep),
      throwsA(isA<ModelManagerException>()),
    );
    expect(nestedGguf.existsSync(), isTrue);
  });

  test('purgeIncomplete borra staging y .part, y conserva los registrados', () async {
    final manager = ModelManager(root);
    final model = await manager.importModel(
      source: createSource('modelo-a.Q4_K_M.gguf', 'abcd'),
    );
    Directory('${root.path}/.importing-x').createSync(recursive: true);
    Directory('${root.path}/.download-y').createSync(recursive: true);
    final noManifest = Directory('${root.path}/sin-manifiesto')
      ..createSync(recursive: true);
    File('${noManifest.path}/algo.gguf').writeAsStringSync('123');
    File('${root.path}/suelto.gguf.part').writeAsStringSync('12');

    final freed = await manager.purgeIncomplete();

    expect(freed, 3 + 2);
    expect(Directory('${root.path}/.importing-x').existsSync(), isFalse);
    expect(Directory('${root.path}/.download-y').existsSync(), isFalse);
    expect(noManifest.existsSync(), isFalse);
    expect(File('${root.path}/suelto.gguf.part').existsSync(), isFalse);
    expect((await manager.inventory()).map((m) => m.id), [model.id]);
  });

  test('removeAllModels borra modelos y sueltos, y respeta los datos de LAIN',
      () async {
    final manager = ModelManager(root);
    await manager.importModel(
      source: createSource('modelo-a.Q4_K_M.gguf', 'abcd'),
    );
    await manager.setActiveModel('modelo-a.q4_k_m');
    final orphan = createFile('viejo.Q4_K_M.gguf', '123');
    final database = File('${root.path}/lain.db')..writeAsStringSync('recuerdos');
    final notes = createFile('notas.txt', 'config');

    final freed = await manager.removeAllModels();

    expect(freed, greaterThan(0));
    expect(await manager.inventory(), isEmpty);
    expect(await manager.activeModelId(), isNull);
    expect(orphan.existsSync(), isFalse);
    expect(database.readAsStringSync(), 'recuerdos');
    expect(notes.existsSync(), isTrue);
  });

  test('eliminar el modelo activo desactiva antes de borrar', () async {
    final manager = ModelManager(root);
    final model = await manager.importModel(
      source: createSource('modelo-a.Q4_K_M.gguf', 'abcd'),
    );
    await manager.setActiveModel(model.id);

    await manager.removeModel(model.id);

    expect(await manager.activeModelId(), isNull);
    expect(Directory('${root.path}/modelo-a.q4_k_m').existsSync(), isFalse);
  });
}
