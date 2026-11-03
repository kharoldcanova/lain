import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/hf_client.dart';
import 'package:lain_mobile/data/llm/hf_url.dart';

void main() {
  late HttpServer server;
  late HfClient client;

  const repo = 'LiquidAI/LFM2.5-1.2B-Instruct-GGUF';

  Future<void> start(Future<void> Function(HttpRequest request) handler) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      handler(request);
    });
    client = HfClient(
      apiBase: Uri.parse('http://127.0.0.1:${server.port}/'),
      policy: const HfUrlPolicy(
        allowedHosts: <String>{'127.0.0.1'},
        requireHttps: false,
      ),
      timeout: const Duration(seconds: 5),
    );
  }

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  Future<void> json(HttpRequest request, Object? body, [int status = 200]) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  test('lista solo los .gguf con tamaño y sha256 de LFS', () async {
    await start((request) async {
      expect(request.uri.path, '/api/models/$repo');
      expect(request.uri.queryParameters['blobs'], 'true');
      await json(request, {
        'siblings': [
          {'rfilename': 'model.safetensors', 'size': 10},
          {
            'rfilename': 'modelo-Q4_K_M.gguf',
            'size': 700,
            'lfs': {'sha256': 'a' * 64, 'size': 700},
          },
          {'rfilename': 'modelo-Q8_0.gguf', 'size': 900},
        ],
      });
    });

    final files = await client.listGgufFiles(repo);

    expect(files, hasLength(2));
    expect(files.first.name, 'modelo-Q4_K_M.gguf');
    expect(files.first.sizeBytes, 700);
    expect(files.first.sha256, 'a' * 64);
    expect(files.last.sha256, isNull);
  });

  test('resuelve un enlace a archivo concreto', () async {
    await start((request) async {
      await json(request, {
        'siblings': [
          {
            'rfilename': 'modelo-Q4_K_M.gguf',
            'lfs': {'oid': 'b' * 64, 'size': 731},
          },
          {'rfilename': 'modelo-Q8_0.gguf', 'size': 900},
        ],
      });
    });

    final files = await client.resolve(HfReference(
      repo: repo,
      file: 'modelo-Q4_K_M.gguf',
    ));

    expect(files, hasLength(1));
    expect(files.single.sizeBytes, 731);
    expect(files.single.downloadUri.host, 'huggingface.co');
  });

  test('un archivo no listado se intenta igual sin tamaño', () async {
    await start((request) async {
      await json(request, {'siblings': <Object>[]});
    });

    final files = await client.resolve(HfReference(
      repo: repo,
      file: 'raro/modelo.gguf',
    ));

    expect(files.single.name, 'raro/modelo.gguf');
    expect(files.single.sizeBytes, 0);
  });

  test('error 404 del repositorio', () async {
    await start((request) async => json(request, {'error': 'not found'}, 404));

    await expectLater(
      client.listGgufFiles(repo),
      throwsA(isA<HfClientException>().having(
        (error) => error.message,
        'message',
        contains('no existe'),
      )),
    );
  });

  test('error 401 de repositorio privado', () async {
    await start((request) async => json(request, {'error': 'auth'}, 401));

    await expectLater(
      client.listGgufFiles(repo),
      throwsA(isA<HfClientException>().having(
        (error) => error.message,
        'message',
        contains('privado'),
      )),
    );
  });

  test('respuesta inválida', () async {
    await start((request) async {
      request.response.write('no es json');
      await request.response.close();
    });

    await expectLater(
      client.listGgufFiles(repo),
      throwsA(isA<HfClientException>()),
    );
  });

  test('sin conexión', () async {
    await start((request) async => json(request, {'siblings': <Object>[]}));
    final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close(force: true);
    client.close();
    client = HfClient(
      apiBase: Uri.parse('http://127.0.0.1:$port/'),
      policy: const HfUrlPolicy(
        allowedHosts: <String>{'127.0.0.1'},
        requireHttps: false,
      ),
      timeout: const Duration(seconds: 2),
    );

    await expectLater(
      client.listGgufFiles(repo),
      throwsA(isA<HfClientException>().having(
        (error) => error.message,
        'message',
        contains('sin conexión'),
      )),
    );
  });

  test('rechaza la API fuera de la política de hosts', () async {
    await start((request) async => json(request, {'siblings': <Object>[]}));
    client.close();
    client = HfClient(
      apiBase: Uri.parse('http://127.0.0.1:${server.port}/'),
      policy: const HfUrlPolicy(), // solo huggingface.co
    );

    await expectLater(
      client.listGgufFiles(repo),
      throwsA(isA<HfClientException>()),
    );
  });
}
