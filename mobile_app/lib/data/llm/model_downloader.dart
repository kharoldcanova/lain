import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'hf_client.dart';
import 'hf_url.dart';
import 'model_manager.dart';
import 'model_metadata.dart';

/// Avance de una descarga.
class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  /// Bytes presentes en disco (incluye lo reanudado).
  final int receivedBytes;

  /// Tamaño total esperado, o `0` si todavía no se conoce.
  final int totalBytes;

  /// Fracción 0..1, o `null` si el total es desconocido.
  double? get fraction {
    if (totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }
}

/// Archivo descargado y verificado, listo para registrar.
class DownloadedFile {
  const DownloadedFile({
    required this.staging,
    required this.file,
    required this.sha256,
    required this.sizeBytes,
  });

  /// Carpeta `.download-<id>/` donde quedó el archivo.
  final Directory staging;

  final File file;
  final String sha256;
  final int sizeBytes;
}

/// El usuario canceló la descarga; el `.part` queda para reanudar.
class DownloadCancelled implements Exception {
  const DownloadCancelled();

  @override
  String toString() => 'descarga cancelada';
}

/// Error de descarga con mensaje para el usuario.
class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Descarga GGUF de Hugging Face a `models/.download-<id>/`.
///
/// - escribe en un `.part` y lo reanuda con `Range` si ya existe;
/// - valida cada redirección contra [HfUrlPolicy] antes de seguirla;
/// - calcula el SHA-256 durante la escritura y lo compara con el publicado;
/// - nunca carga el archivo en memoria ni duplica su tamaño en disco.
///
/// El registro final (renombrar la carpeta) lo hace `ModelManager`.
class ModelDownloader {
  ModelDownloader({
    required this.rootDir,
    HfUrlPolicy policy = const HfUrlPolicy(),
    HttpClient? httpClient,
    Duration timeout = const Duration(seconds: 30),
    Uri Function(HfFile file)? uriFor,
  })  : _policy = policy,
        _http = httpClient ?? HttpClient(),
        _ownsClient = httpClient == null,
        _timeout = timeout,
        _uriFor = uriFor;

  final Directory rootDir;
  final HfUrlPolicy _policy;
  final HttpClient _http;
  final bool _ownsClient;
  final Duration _timeout;
  final Uri Function(HfFile file)? _uriFor;

  static const int maxRedirects = 5;

  /// Descarga [file] y devuelve el archivo verificado.
  ///
  /// [isCancelled] se consulta entre bloques: al cancelar se lanza
  /// [DownloadCancelled] y el `.part` queda en disco.
  Future<DownloadedFile> download({
    required HfFile file,
    void Function(DownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
    Future<int> Function()? freeBytes,
  }) async {
    final id = ModelMetadata.sanitizeId(p.basenameWithoutExtension(file.name));
    if (id == null) {
      throw const DownloadException(
        'el nombre del archivo no permite generar un id válido',
      );
    }
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }
    final staging =
        Directory(p.join(rootDir.path, '${ModelManager.downloadStage}-$id'));
    await staging.create(recursive: true);
    final partFile = File(p.join(staging.path, '${p.basename(file.name)}.part'));
    final finalFile = File(p.join(staging.path, p.basename(file.name)));

    var offset = await _lengthOf(partFile);
    final declaredTotal = file.sizeBytes;
    if (declaredTotal > 0 && offset > declaredTotal) {
      // Un .part más grande que el archivo esperado no sirve.
      await partFile.delete();
      offset = 0;
    }

    if (freeBytes != null && declaredTotal > 0) {
      final free = await freeBytes();
      final needed = declaredTotal - offset;
      if (free > 0 && free < needed + (needed ~/ 20)) {
        throw DownloadException(
          'no hay espacio suficiente: faltan ${_mib(needed)} y quedan ${_mib(free)}',
        );
      }
    }

    onProgress?.call(DownloadProgress(
      receivedBytes: offset,
      totalBytes: declaredTotal,
    ));

    var uri = _uriFor?.call(file) ?? file.downloadUri;
    if (!_policy.allows(uri)) {
      throw const DownloadException(
        'el enlace de descarga no pertenece a Hugging Face',
      );
    }

    final response = await _openWithRedirects(uri, offset);

    // El servidor pudo ignorar el Range: en ese caso se reinicia desde cero.
    if (offset > 0 && response.statusCode == HttpStatus.ok) {
      offset = 0;
      await partFile.writeAsBytes(const <int>[], flush: true);
    }
    final contentLength = response.contentLength;
    final expectedTotal = declaredTotal > 0
        ? declaredTotal
        : (response.statusCode == HttpStatus.ok && contentLength > 0
            ? contentLength
            : contentLength > 0
                ? offset + contentLength
                : 0);

    final digestSink = _DigestSink();
    final converter = sha256.startChunkedConversion(digestSink);
    if (offset > 0) {
      await for (final chunk in partFile.openRead()) {
        converter.add(chunk);
      }
    }

    var received = offset;
    final raf = await partFile.open(mode: FileMode.append);
    var lastPercent = -1;
    try {
      await for (final chunk in response.timeout(_timeout)) {
        if (isCancelled?.call() ?? false) {
          throw const DownloadCancelled();
        }
        converter.add(chunk);
        raf.writeFromSync(chunk);
        received += chunk.length;
        if (expectedTotal > 0) {
          final percent = ((received * 100) ~/ expectedTotal).clamp(0, 100);
          if (percent != lastPercent) {
            lastPercent = percent;
            onProgress?.call(DownloadProgress(
              receivedBytes: received,
              totalBytes: expectedTotal,
            ));
          }
        } else {
          onProgress?.call(DownloadProgress(
            receivedBytes: received,
            totalBytes: 0,
          ));
        }
      }
      await raf.flush();
    } on DownloadCancelled {
      rethrow;
    } on TimeoutException {
      throw const DownloadException(
        'la descarga se quedó sin datos; reintentá para reanudarla',
      );
    } on HttpException {
      throw const DownloadException(
        'la conexión se cortó durante la descarga; reintentá para reanudarla',
      );
    } on SocketException {
      throw const DownloadException(
        'se perdió la conexión durante la descarga; reintentá para reanudarla',
      );
    } finally {
      await raf.close();
    }

    converter.close();
    final digest = digestSink.value.toString();

    if (expectedTotal > 0 && received != expectedTotal) {
      throw DownloadException(
        'la descarga quedó incompleta ($received de $expectedTotal bytes); '
        'reintentá para reanudarla',
      );
    }
    final published = file.sha256?.toLowerCase();
    if (published != null && !digest.startsWith(published)) {
      await partFile.delete();
      throw const DownloadException(
        'el SHA-256 del archivo no coincide con el publicado; se descartó '
        'la descarga parcial',
      );
    }

    await partFile.rename(finalFile.path);
    return DownloadedFile(
      staging: staging,
      file: finalFile,
      sha256: digest,
      sizeBytes: received,
    );
  }

  /// Abre la descarga siguiendo redirecciones **solo** hacia hosts permitidos.
  Future<HttpClientResponse> _openWithRedirects(Uri start, int offset) async {
    var uri = start;
    var redirects = 0;
    while (true) {
      final request = await _http.openUrl('GET', uri).timeout(_timeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'LAIN-Android/0.1 (model-manager)',
      );
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final candidate = await request.close().timeout(_timeout);
      final status = candidate.statusCode;
      if (status == HttpStatus.movedPermanently ||
          status == HttpStatus.found ||
          status == HttpStatus.seeOther ||
          status == HttpStatus.temporaryRedirect ||
          status == HttpStatus.permanentRedirect) {
        final location = candidate.headers.value(HttpHeaders.locationHeader);
        await candidate.drain<void>();
        if (location == null) {
          throw const DownloadException(
            'Hugging Face devolvió una redirección sin destino',
          );
        }
        final next = uri.resolve(location);
        if (!_policy.allows(next)) {
          throw DownloadException(
            'la descarga redirige a un destino no permitido (${next.host})',
          );
        }
        redirects++;
        if (redirects > maxRedirects) {
          throw const DownloadException('demasiadas redirecciones al descargar');
        }
        uri = next;
        continue;
      }
      if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
        await candidate.drain<void>();
        if (status == HttpStatus.notFound) {
          throw const DownloadException('el archivo no existe en Hugging Face');
        }
        if (status == HttpStatus.unauthorized ||
            status == HttpStatus.forbidden) {
          throw const DownloadException(
            'el archivo es privado o requiere iniciar sesión en Hugging Face',
          );
        }
        throw DownloadException('la descarga falló (HTTP $status)');
      }
      return candidate;
    }
  }

  Future<int> _lengthOf(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      return 0;
    }
  }

  String _mib(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

  /// Borra el staging de una descarga cancelada o fallida.
  Future<void> discard(Directory staging) async {
    final root = p.canonicalize(rootDir.path);
    final target = p.canonicalize(staging.path);
    if (p.dirname(target) != root) {
      throw const DownloadException('carpeta de descarga inválida');
    }
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
  }

  /// Cierra el cliente HTTP propio (no hace nada si fue inyectado).
  void close() {
    if (_ownsClient) _http.close(force: true);
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
