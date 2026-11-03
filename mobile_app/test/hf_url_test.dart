import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/hf_url.dart';

void main() {
  group('enlaces válidos', () {
    test('repositorio completo', () {
      final ref = parseHuggingFaceUrl(
        'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF',
      );

      expect(ref.repo, 'LiquidAI/LFM2.5-1.2B-Instruct-GGUF');
      expect(ref.isRepoOnly, isTrue);
    });

    test('archivo con resolve', () {
      final ref = parseHuggingFaceUrl(
        'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      );

      expect(ref.repo, 'LiquidAI/LFM2.5-1.2B-Instruct-GGUF');
      expect(ref.file, 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf');
      expect(ref.revision, 'main');
      expect(
        ref.resolveUri().toString(),
        'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      );
    });

    test('archivo con blob y revisión distinta', () {
      final ref = parseHuggingFaceUrl(
        'https://hf.co/org/repo/blob/v2/modelo.Q8_0.gguf',
      );

      expect(ref.revision, 'v2');
      expect(ref.file, 'modelo.Q8_0.gguf');
      expect(ref.resolveUri().host, 'huggingface.co');
    });

    test('archivo en subcarpeta', () {
      final ref = parseHuggingFaceUrl(
        'https://huggingface.co/org/repo/resolve/main/q4/modelo.gguf',
      );

      expect(ref.file, 'q4/modelo.gguf');
    });
  });

  group('política de hosts', () {
    test('acepta el CDN de Hugging Face y sus subdominios', () {
      const policy = HfUrlPolicy();

      expect(
        policy.allows(Uri.parse('https://us.aws.cdn.hf.co/xet-bridge-us/x')),
        isTrue,
      );
      expect(
        policy.allows(Uri.parse('https://cdn-lfs.huggingface.co/x')),
        isTrue,
      );
    });

    test('rechaza un dominio que solo parece de Hugging Face', () {
      const policy = HfUrlPolicy();

      expect(
        policy.allows(Uri.parse('https://hf.co.evil.com/x')),
        isFalse,
      );
      expect(
        policy.allows(Uri.parse('https://evil.com/x')),
        isFalse,
      );
    });
  });

  group('enlaces rechazados', () {
    test('http plano', () {
      expect(
        () => parseHuggingFaceUrl('http://huggingface.co/org/repo'),
        throwsA(isA<HfUrlException>().having(
          (error) => error.message,
          'message',
          contains('HTTPS'),
        )),
      );
    });

    test('host ajeno o con sufijo', () {
      for (final url in <String>[
        'https://evil.com/org/repo',
        'https://huggingface.co.evil.com/org/repo',
      ]) {
        expect(
          () => parseHuggingFaceUrl(url),
          throwsA(isA<HfUrlException>()),
          reason: url,
        );
      }
    });

    test('credenciales en la URL', () {
      expect(
        () => parseHuggingFaceUrl('https://user:pass@huggingface.co/org/repo'),
        throwsA(isA<HfUrlException>()),
      );
    });

    test('sin organización o repositorio', () {
      expect(
        () => parseHuggingFaceUrl('https://huggingface.co/solo-org'),
        throwsA(isA<HfUrlException>()),
      );
      expect(
        () => parseHuggingFaceUrl('https://huggingface.co/models/org/repo'),
        throwsA(isA<HfUrlException>()),
      );
    });

    test('archivo que no es .gguf', () {
      expect(
        () => parseHuggingFaceUrl(
          'https://huggingface.co/org/repo/resolve/main/model.safetensors',
        ),
        throwsA(isA<HfUrlException>().having(
          (error) => error.message,
          'message',
          contains('.gguf'),
        )),
      );
    });

    test('enlace incompleto a archivo', () {
      expect(
        () => parseHuggingFaceUrl('https://huggingface.co/org/repo/resolve/main'),
        throwsA(isA<HfUrlException>()),
      );
    });

    test('texto que no es una URL', () {
      expect(
        () => parseHuggingFaceUrl('LiquidAI/LFM2.5-1.2B-Instruct-GGUF'),
        throwsA(isA<HfUrlException>()),
      );
    });

    test('URL vacía', () {
      expect(() => parseHuggingFaceUrl('  '), throwsA(isA<HfUrlException>()));
    });
  });
}
