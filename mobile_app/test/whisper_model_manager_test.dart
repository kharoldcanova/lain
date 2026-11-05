import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/voice/stt_native.dart';
import 'package:lain_mobile/data/voice/stt_service.dart';
import 'package:lain_mobile/data/voice/whisper_model_manager.dart';

class _FakeStt implements SttEngine {
  final List<String> loaded = <String>[];
  bool _ready = false;

  @override
  bool get isReady => _ready;

  @override
  Future<void> loadModel(String path, {int threads = 4}) async {
    loaded.add(path);
    _ready = true;
  }

  @override
  Future<String> transcribe(Uint8List pcm16, {String language = 'es'}) async {
    return 'hola desde whisper';
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('localiza el .bin más reciente, mide y borra', () async {
    final dir = Directory.systemTemp.createTempSync('lain_whisper_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final oldFile = File('${dir.path}/ggml-small.bin')
      ..writeAsBytesSync(<int>[1]);
    final newFile = File('${dir.path}/ggml-base.bin')
      ..writeAsBytesSync(<int>[2, 3]);
    oldFile.setLastModifiedSync(DateTime(2026, 1, 1));
    newFile.setLastModifiedSync(DateTime(2026, 6, 1));
    final manager = WhisperModelManager(dir);

    final found = await manager.locate();

    expect(found?.path, newFile.path);
    expect(await manager.usageBytes(), 3);
    expect(await manager.delete(), 3);
    expect(await manager.locate(), isNull);
  });

  test('sin carpeta de voz devuelve null', () async {
    final dir = Directory.systemTemp.createTempSync('lain_whisper_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final manager = WhisperModelManager(Directory('${dir.path}/missing'));

    expect(await manager.locate(), isNull);
    expect(await manager.delete(), 0);
  });

  test('SttService carga el modelo una sola vez y transcribe', () async {
    final dir = Directory.systemTemp.createTempSync('lain_whisper_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final model = File('${dir.path}/ggml-base.bin')
      ..writeAsBytesSync(<int>[1, 2]);
    final engine = _FakeStt();
    final service =
        SttService(engine: engine, manager: WhisperModelManager(dir));
    final pcm = Uint8List.fromList(<int>[0, 0, 0, 0]);

    expect(await service.transcribe(pcm), 'hola desde whisper');
    expect(await service.transcribe(pcm), 'hola desde whisper');

    expect(engine.loaded, <String>[model.path]);
  });

  test('SttService explica que falta el modelo de voz', () async {
    final dir = Directory.systemTemp.createTempSync('lain_whisper_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = SttService(
      engine: _FakeStt(),
      manager: WhisperModelManager(dir),
    );

    expect(
      () => service.transcribe(Uint8List.fromList(<int>[0, 0])),
      throwsA(isA<SttException>()),
    );
  });
}
