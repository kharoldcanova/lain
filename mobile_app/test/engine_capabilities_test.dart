import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/engine_capabilities.dart';

void main() {
  test('el motor incluido soporta las arquitecturas que usamos hoy', () {
    expect(isArchitectureSupported('lfm2'), isTrue);
    expect(isArchitectureSupported('qwen3'), isTrue);
    expect(isArchitectureSupported('qwen2'), isTrue);
    expect(isArchitectureSupported('gemma3'), isTrue);
  });

  test('lfm3 queda bloqueado hasta recompilar el motor', () {
    expect(isArchitectureSupported('lfm3'), isFalse);
    expect(knownUnsupportedArchitectures, contains('lfm3'));
  });

  test('arquitecturas desconocidas o vacías no se bloquean (legado)', () {
    expect(isArchitectureSupported(null), isTrue);
    expect(isArchitectureSupported(''), isTrue);
    expect(isArchitectureSupported('desconocida'), isTrue);
  });

  test('una arquitectura inventada sí se rechaza', () {
    expect(isArchitectureSupported('modelo-inventado'), isFalse);
  });
}
