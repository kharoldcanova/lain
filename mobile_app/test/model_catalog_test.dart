import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/engine_capabilities.dart';
import 'package:lain_mobile/data/llm/model_catalog.dart';
import 'package:lain_mobile/data/llm/model_metadata.dart';

void main() {
  test('el catálogo tiene ids y archivos únicos', () {
    final ids = modelCatalog.map((entry) => entry.id).toSet();
    final files = modelCatalog.map((entry) => entry.file).toSet();

    expect(ids.length, modelCatalog.length);
    expect(files.length, modelCatalog.length);
  });

  test('todos los archivos son GGUF y derivan un id de instalación', () {
    for (final entry in modelCatalog) {
      expect(entry.file.toLowerCase(), endsWith('.gguf'), reason: entry.name);
      expect(entry.installedId, isNotNull, reason: entry.name);
      expect(entry.quantization, isNotEmpty, reason: entry.name);
    }
  });

  test('incluye los cinco modelos acordados', () {
    final ids = modelCatalog.map((entry) => entry.id).toList();

    expect(ids, containsAll(<String>[
      'lfm2.5-1.2b-instruct',
      'lfm2.5-2.6b',
      'lfm3-1.7b',
      'qwen3-1.7b',
      'qwen2.5-3b-instruct',
    ]));
  });

  test('LFM3 se ofrece pero se marca como no soportada por el motor', () {
    final lfm3 = modelCatalog.firstWhere((entry) => entry.id == 'lfm3-1.7b');

    expect(lfm3.architecture, 'lfm3');
    expect(isArchitectureSupported(lfm3.architecture), isFalse);
    expect(lfm3.note, contains('Requiere'));
  });

  test('los modelos compatibles usan arquitecturas soportadas', () {
    for (final entry in modelCatalog) {
      if (entry.id == 'lfm3-1.7b') continue;
      expect(
        isArchitectureSupported(entry.architecture),
        isTrue,
        reason: entry.name,
      );
    }
  });

  test('detecta la cuantización en nombres en minúsculas', () {
    expect(
      ModelMetadata.quantizationFromName('qwen2.5-3b-instruct-q4_k_m.gguf'),
      'Q4_K_M',
    );
    expect(
      ModelMetadata.quantizationFromName('modelo-Q5_K_S.gguf'),
      'Q5_K_S',
    );
  });
}
