import 'dart:io';

import 'package:path/path.dart' as p;

import '../llm/hf_client.dart';
import '../llm/hf_url.dart';
import '../llm/model_downloader.dart';
import '../llm/model_store.dart';

/// Gestiona el modelo de voz `ggml-*.bin` de whisper.cpp.
///
/// Vive en `<modelos>/whisper/`, separado de los GGUF del LLM para que el
/// inventario de `ModelManager` no lo confunda con un modelo de lenguaje.
class WhisperModelManager {
  WhisperModelManager(this.rootDir);

  final Directory rootDir;

  static const String defaultRepo = 'ggerganov/whisper.cpp';
  static const String defaultFileName = 'ggml-base.bin';
  static const Set<String> extensions = <String>{'.bin'};

  static Future<WhisperModelManager> open() async {
    final base = await modelDirectory();
    return WhisperModelManager(Directory(p.join(base.path, 'whisper')));
  }

  /// Archivo de voz instalado más reciente, o `null` si no hay ninguno.
  Future<File?> locate() async {
    if (!await rootDir.exists()) return null;
    try {
      final files = rootDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.bin'))
          .toList();
      if (files.isEmpty) return null;
      files.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files.first;
    } on FileSystemException {
      return null;
    }
  }

  /// Ruta donde se instala el modelo predeterminado.
  String get expectedPath => p.join(rootDir.path, defaultFileName);

  /// Descarga [fileName] desde [repo] y lo deja en `whisper/`.
  Future<File> download({
    HfClient? client,
    ModelDownloader? downloader,
    String repo = defaultRepo,
    String fileName = defaultFileName,
    void Function(DownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
    Future<int> Function()? freeBytes,
  }) async {
    final ownedClient = client == null ? HfClient() : null;
    final http = client ?? ownedClient!;
    Directory? staging;
    try {
      await rootDir.create(recursive: true);
      final localDownloader = downloader ?? ModelDownloader(rootDir: rootDir);
      final reference = HfReference(repo: repo, file: fileName);
      final files = await http.resolve(reference, extensions: extensions);
      HfFile? target;
      for (final file in files) {
        if (file.name == fileName) target = file;
      }
      if (target == null) {
        throw const HfClientException(
          'el repositorio no ofrece el archivo de voz pedido',
        );
      }
      final downloaded = await localDownloader.download(
        file: target,
        onProgress: onProgress,
        isCancelled: isCancelled,
        freeBytes: freeBytes,
      );
      staging = downloaded.staging;
      final destination = File(p.join(rootDir.path, p.basename(fileName)));
      if (await destination.exists()) await destination.delete();
      await downloaded.file.rename(destination.path);
      return destination;
    } finally {
      if (staging != null) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          // El archivo ya se movió; la carpeta vacía se limpia en la próxima.
        }
      }
      ownedClient?.close();
    }
  }

  /// Borra todos los modelos de voz instalados.
  Future<int> delete() async {
    if (!await rootDir.exists()) return 0;
    var freed = 0;
    for (final entity in rootDir.listSync(recursive: true)) {
      if (entity is File) {
        try {
          freed += await entity.length();
          await entity.delete();
        } on FileSystemException {
          continue;
        }
      }
    }
    return freed;
  }

  Future<int> usageBytes() async {
    if (!await rootDir.exists()) return 0;
    var total = 0;
    try {
      for (final entity in rootDir.listSync(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
    } on FileSystemException {
      return total;
    }
    return total;
  }
}
