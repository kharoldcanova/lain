import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lain_mobile/data/llm/lain_engine.dart';
import 'package:lain_mobile/data/llm/model_store.dart';

/// Prueba de humo real: carga el GGUF del almacenamiento externo y genera una
/// respuesta con llama.cpp. Requiere el modelo copiado por adb:
///
///   adb push Qwen2.5-3B-Instruct.Q4_K_M.gguf \
///     /sdcard/Android/data/com.lain.lain_mobile/files/models/
///
/// Ejecutar en un dispositivo/emulador:
///   flutter test integration_test/model_smoke_test.dart -d DEVICE_ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('genera texto con el GGUF local', (tester) async {
    final location = await locateModel();
    expect(location.exists, isTrue,
        reason: 'falta el GGUF en ${location.expectedPath}');

    final engine = NativeLainEngine();
    addTearDown(engine.dispose);

    await engine.loadModel(location.file!.path, contextSize: 2048, threads: 4);
    expect(engine.isReady, isTrue);

    final buffer = StringBuffer();
    await for (final piece in engine.generate(
      systemPrompt: 'Eres LAIN. Responde en español, en una sola frase.',
      userMessage: 'Preséntate en una frase.',
      maxTokens: 48,
      temperature: 0.7,
    )) {
      buffer.write(piece);
    }

    // ignore: avoid_print
    print('RESPUESTA: ${buffer.toString().trim()}');
    expect(buffer.toString().trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
