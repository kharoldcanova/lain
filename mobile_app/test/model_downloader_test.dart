import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/hf_client.dart';
import 'package:lain_mobile/data/llm/hf_url.dart';
import 'package:lain_mobile/data/llm/model_downloader.dart';

void main() {
  late Directory root;
  late HttpServer server;
  late int port;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lain-dl-');
  });

  tearDown(() async {
    await server.close(force: true);
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Arranca un servidor local que delega en [handler].
  Future<void> start(void Function(HttpRequest request) handler) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen(handler);
  }

  ModelDownloader downloader() => ModelDownloader(
        rootDir: root,
        policy: const HfUrlPolicy(
          allowedHosts: <String>{'127.0.0.1'},
          requireHttps: false,
        ),
        uriFor: (file) => Uri.parse(
          'http://127.0.0.1:$port/files/${file.fileName}',
        ),
      );

  HfFile fileFor(List<int> bytes, {String? sha}) => HfFile(
        repo: 'org/repo',
        name: 'modelo-Q4_K_M.gguf',
        sizeBytes: bytes.length,
        sha256: sha ?? sha256.convert(bytes).toString(),
      );

  Future<void> serveBytes(
    HttpRequest request,
    List<int> bytes, {
    bool honourRange = true,
    int? declaredLength,
  }) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    if (honourRange && range != null && range.startsWith('bytes=')) {
      start = int.tryParse(range.substring(6).split('-').first) ?? 0;
    }
    final body = bytes.sublist(start);
    request.response.statusCode =
        start > 0 ? HttpStatus.partialContent : HttpStatus.ok;
    if (start > 0) {
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${bytes.length - 1}/${bytes.length}',
      );
    }
    request.response.contentLength = declaredLength ?? body.length;
    request.response.add(body);
    await request.response.close();
  }

  test('descarga completa, verifica SHA y reporta progreso', () async {
    final bytes = List<int>.generate(300000, (index) => index % 251);
    await start((request) => serveBytes(request, bytes));
    final progress = <DownloadProgress>[];

    final result = await downloader().download(
      file: fileFor(bytes),
      onProgress: progress.add,
    );

    expect(result.file.existsSync(), isTrue);
    expect(result.sizeBytes, bytes.length);
    expect(result.sha256, sha256.convert(bytes).toString());
    expect(result.file.readAsBytesSync(), bytes);
    expect(progress, isNotEmpty);
    expect(progress.last.receivedBytes, bytes.length);
    expect(progress.last.fraction, 1.0);
    expect(result.staging.path, endsWith('.download-modelo-q4_k_m'));
  });

  test('reanuda una descarga interrumpida con Range', () async {
    final bytes = List<int>.generate(200000, (index) => (index * 7) % 251);
    const resumeAt = 120000;
    String? receivedRange;
    await start((request) async {
      receivedRange = request.headers.value(HttpHeaders.rangeHeader);
      await serveBytes(request, bytes);
    });

    final staging =
        Directory('${root.path}/.download-modelo-q4_k_m')..createSync();
    File('${staging.path}/modelo-Q4_K_M.gguf.part')
        .writeAsBytesSync(bytes.sublist(0, resumeAt));

    final result = await downloader().download(file: fileFor(bytes));

    expect(receivedRange, 'bytes=$resumeAt-');
    expect(result.file.readAsBytesSync(), bytes);
    expect(result.sha256, sha256.convert(bytes).toString());
  });

  test('si el servidor ignora el Range reinicia desde cero', () async {
    final bytes = List<int>.generate(120000, (index) => (index * 3) % 251);
    await start((request) => serveBytes(request, bytes, honourRange: false));

    final staging =
        Directory('${root.path}/.download-modelo-q4_k_m')..createSync();
    File('${staging.path}/modelo-Q4_K_M.gguf.part')
        .writeAsBytesSync(bytes.sublist(0, 60000));

    final result = await downloader().download(file: fileFor(bytes));

    expect(result.file.readAsBytesSync(), bytes);
    expect(result.sizeBytes, bytes.length);
  });

  test('cancelar conserva el .part para reanudar', () async {
    final bytes = List<int>.generate(400000, (index) => index % 251);
    await start((request) async {
      request.response.contentLength = bytes.length;
      request.response.add(bytes.sublist(0, 100000));
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      request.response.add(bytes.sublist(100000));
      await request.response.close();
    });

    var cancelled = false;
    await expectLater(
      downloader().download(
        file: fileFor(bytes),
        onProgress: (progress) {
          if (progress.receivedBytes > 0) cancelled = true;
        },
        isCancelled: () => cancelled,
      ),
      throwsA(isA<DownloadCancelled>()),
    );

    final part = File(
      '${root.path}/.download-modelo-q4_k_m/modelo-Q4_K_M.gguf.part',
    );
    expect(part.existsSync(), isTrue);
    expect(part.lengthSync(), lessThan(bytes.length));
  });

  test('un SHA-256 distinto descarta la descarga', () async {
    final bytes = List<int>.generate(50000, (index) => index % 251);
    await start((request) => serveBytes(request, bytes));

    await expectLater(
      downloader().download(file: fileFor(bytes, sha: 'f' * 64)),
      throwsA(isA<DownloadException>().having(
        (error) => error.message,
        'message',
        contains('SHA-256'),
      )),
    );

    final staging = Directory('${root.path}/.download-modelo-q4_k_m');
    expect(
      File('${staging.path}/modelo-Q4_K_M.gguf.part').existsSync(),
      isFalse,
    );
    expect(File('${staging.path}/modelo-Q4_K_M.gguf').existsSync(), isFalse);
  });

  test('no descarga si no hay espacio suficiente', () async {
    final bytes = List<int>.generate(50000, (index) => index % 251);
    var requests = 0;
    await start((request) {
      requests++;
      serveBytes(request, bytes);
    });

    await expectLater(
      downloader().download(
        file: fileFor(bytes),
        freeBytes: () async => 1024,
      ),
      throwsA(isA<DownloadException>().having(
        (error) => error.message,
        'message',
        contains('espacio'),
      )),
    );
    expect(requests, 0);
  });

  test('rechaza una redirección a un host no permitido', () async {
    await start((request) async {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'http://evil.example/modelo.gguf',
      );
      await request.response.close();
    });

    await expectLater(
      downloader().download(file: fileFor(List<int>.filled(10, 1))),
      throwsA(isA<DownloadException>().having(
        (error) => error.message,
        'message',
        contains('no permitido'),
      )),
    );
  });

  test('sigue una redirección permitida', () async {
    final bytes = List<int>.generate(40000, (index) => index % 251);
    await start((request) async {
      if (request.uri.path == '/files/modelo-Q4_K_M.gguf') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:$port/espejo/modelo-Q4_K_M.gguf',
        );
        await request.response.close();
        return;
      }
      await serveBytes(request, bytes);
    });

    final result = await downloader().download(file: fileFor(bytes));

    expect(result.file.readAsBytesSync(), bytes);
  });

  test('detecta una descarga truncada', () async {
    final bytes = List<int>.generate(100000, (index) => index % 251);
    await start((request) async {
      request.response.contentLength = -1; // chunked
      final socket = await request.response.detachSocket(writeHeaders: true);
      socket.add(bytes.sublist(0, 40000));
      await socket.flush();
      socket.destroy();
    });

    await expectLater(
      downloader().download(file: fileFor(bytes)),
      throwsA(isA<DownloadException>()),
    );
  });

  test('discard borra solo el staging de la descarga', () async {
    final staging = Directory('${root.path}/.download-x')..createSync();
    File('${staging.path}/a.part').writeAsStringSync('parcial');
    final keep = File('${root.path}/otro.gguf')..writeAsStringSync('modelo');

    await downloader().discard(staging);

    expect(staging.existsSync(), isFalse);
    expect(keep.existsSync(), isTrue);
  });
}
