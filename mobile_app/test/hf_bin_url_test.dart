import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/hf_url.dart';

void main() {
  test('acepta .bin cuando se habilita para modelos de voz', () {
    final ref = parseHuggingFaceUrl(
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
      extensions: const <String>{'.bin'},
    );

    expect(ref.repo, 'ggerganov/whisper.cpp');
    expect(ref.file, 'ggml-base.bin');
  });

  test('el parser del LLM sigue rechazando .bin', () {
    expect(
      () => parseHuggingFaceUrl(
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
      ),
      throwsA(isA<HfUrlException>()),
    );
  });
}
