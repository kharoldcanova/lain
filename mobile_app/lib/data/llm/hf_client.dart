import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'hf_url.dart';

/// Archivo GGUF publicado en un repositorio de Hugging Face.
class HfFile {
  const HfFile({
    required this.repo,
    required this.name,
    required this.sizeBytes,
    this.sha256,
    this.revision = 'main',
  });

  final String repo;

  /// Ruta dentro del repositorio (puede incluir subcarpetas).
  final String name;

  /// Tamaño en bytes, o `0` si la API no lo informa.
  final int sizeBytes;

  /// SHA-256 publicado por el almacenamiento LFS, o `null`.
  final String? sha256;

  final String revision;

  /// Nombre del archivo sin carpetas, para usarlo en disco.
  String get fileName => name.split('/').last;

  /// URL de descarga del archivo.
  Uri get downloadUri =>
      HfReference(repo: repo, file: name, revision: revision).resolveUri();
}

/// Error de comunicación con Hugging Face, con mensaje para el usuario.
class HfClientException implements Exception {
  const HfClientException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cliente mínimo de la API pública de Hugging Face.
///
/// Solo usa `dart:io`: no agrega dependencias al APK. La app consume el
/// listado de GGUFs (tamaño y SHA-256 de LFS) y construye la URL de descarga.
/// La validación de host y esquema es la misma que la del parser de URLs.
class HfClient {
  HfClient({
    Uri? apiBase,
    HttpClient? httpClient,
    HfUrlPolicy policy = const HfUrlPolicy(),
    Duration timeout = const Duration(seconds: 20),
  })  : _apiBase = apiBase ?? Uri.https('huggingface.co', '/'),
        _http = httpClient ?? HttpClient(),
        _ownsClient = httpClient == null,
        _policy = policy,
        _timeout = timeout;

  final Uri _apiBase;
  final HttpClient _http;
  final bool _ownsClient;
  final HfUrlPolicy _policy;
  final Duration _timeout;

  static final RegExp _repoPattern =
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$');

  Uri _modelUri(String repo) {
    final basePath = _apiBase.path.endsWith('/')
        ? _apiBase.path.substring(0, _apiBase.path.length - 1)
        : _apiBase.path;
    return _apiBase.replace(
      path: '$basePath/api/models/$repo',
      queryParameters: const <String, String>{'blobs': 'true'},
    );
  }

  /// Archivos que corresponden a [reference].
  ///
  /// Con un enlace a repositorio devuelve todos los `.gguf`; con un enlace a
  /// archivo devuelve ese archivo con su tamaño y SHA-256 cuando la API los
  /// informa. Si la API no responde se propaga [HfClientException].
  Future<List<HfFile>> resolve(HfReference reference) async {
    final repo = reference.repo;
    if (!_repoPattern.hasMatch(repo)) {
      throw const HfClientException('el nombre del repositorio no es válido');
    }
    final files = await listGgufFiles(repo);
    final wanted = reference.file;
    if (wanted == null) {
      if (files.isEmpty) {
        throw const HfClientException(
          'el repositorio no tiene archivos .gguf para descargar',
        );
      }
      return files;
    }
    for (final file in files) {
      if (file.name == wanted) return <HfFile>[file];
    }
    // La API puede no listar el archivo (repo con subcarpetas raras):
    // se permite intentar la descarga directa sin tamaño conocido.
    return <HfFile>[
      HfFile(
        repo: repo,
        name: wanted,
        sizeBytes: 0,
        revision: reference.revision,
      ),
    ];
  }

  /// Lista los `.gguf` de [repo], ordenados por nombre.
  Future<List<HfFile>> listGgufFiles(String repo) async {
    if (!_repoPattern.hasMatch(repo)) {
      throw const HfClientException('el nombre del repositorio no es válido');
    }
    final uri = _modelUri(repo);
    if (!_policy.allows(uri)) {
      throw const HfClientException('la API de Hugging Face no es accesible');
    }
    final json = await _getJson(uri);
    final siblings = json['siblings'];
    if (siblings is! List) {
      throw const HfClientException(
        'la respuesta de Hugging Face no incluye archivos',
      );
    }
    final files = <HfFile>[];
    for (final item in siblings) {
      if (item is! Map) continue;
      final name = item['rfilename'];
      if (name is! String || !name.toLowerCase().endsWith('.gguf')) continue;
      final lfs = item['lfs'];
      final int size;
      final String? sha;
      if (lfs is Map) {
        size = (lfs['size'] as num?)?.toInt() ?? 0;
        // Hugging Face publica el SHA-256 como `sha256` en el almacenamiento
        // Xet actual y como `oid` en repos LFS anteriores.
        sha = (lfs['sha256'] as String?) ?? (lfs['oid'] as String?);
      } else {
        size = (item['size'] as num?)?.toInt() ?? 0;
        sha = null;
      }
      files.add(HfFile(
        repo: repo,
        name: name,
        sizeBytes: size,
        sha256: sha,
      ));
    }
    files.sort((a, b) => a.name.compareTo(b.name));
    return files;
  }

  Future<Map<String, Object?>> _getJson(Uri uri) async {
    try {
      final request = await _http.getUrl(uri).timeout(_timeout);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'LAIN-Android/0.1 (model-manager)',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_timeout);
      final body =
          await response.transform(utf8.decoder).join().timeout(_timeout);
      switch (response.statusCode) {
        case 200:
          break;
        case 401:
        case 403:
          throw const HfClientException(
            'el repositorio es privado o requiere iniciar sesión en Hugging Face',
          );
        case 404:
          throw const HfClientException(
            'el repositorio no existe en Hugging Face',
          );
        case 429:
          throw const HfClientException(
            'Hugging Face limitó las solicitudes; esperá un momento y reintentá',
          );
        default:
          throw HfClientException(
            'Hugging Face respondió ${response.statusCode}',
          );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) {
        throw const HfClientException(
          'la respuesta de Hugging Face no es válida',
        );
      }
      return decoded;
    } on SocketException {
      throw const HfClientException(
        'sin conexión a internet: revisá la red y reintentá',
      );
    } on TimeoutException {
      throw const HfClientException(
        'la conexión con Hugging Face tardó demasiado; reintentá',
      );
    } on HandshakeException {
      throw const HfClientException(
        'no se pudo establecer una conexión segura con Hugging Face',
      );
    } on FormatException {
      throw const HfClientException(
        'la respuesta de Hugging Face no es válida',
      );
    }
  }

  /// Cierra el cliente HTTP propio (no hace nada si fue inyectado).
  void close() {
    if (_ownsClient) _http.close(force: true);
  }
}
