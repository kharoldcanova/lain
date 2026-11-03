import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'model_metadata.dart';
import 'engine_capabilities.dart';
import 'gguf_header.dart';
import 'model_store.dart';

/// Gestor de modelos independiente del modelo concreto.
///
/// Responsabilidades:
/// - inventario de modelos instalados (`models/<id>/model.json`);
/// - importación desde archivos locales con SHA-256, espacio verificado y
///   copia temporal + renombrado atómico (nunca deja archivos incompletos);
/// - selección del modelo activo (`models/active.json`);
/// - eliminación de modelos (solo su carpeta; jamás toca lain.db ni datos).
///
/// La ruta raíz es la que devuelve [modelDirectory] (almacenamiento privado
/// de la app, que sobrevive a las actualizaciones del APK).
class ModelManager {
  ModelManager(this.rootDir);

  /// Carpeta raíz de modelos (`<almacenamiento>/models`).
  final Directory rootDir;

  static const String manifestFileName = 'model.json';
  static const String activeFileName = 'active.json';
  static const String importStage = '.importing';

  /// Prefijo de las descargas en curso (`models/.download-<id>/`).
  static const String downloadStage = '.download';

  /// Abre el gestor sobre la carpeta de modelos de la app.
  static Future<ModelManager> open() async => ModelManager(await modelDirectory());

  Directory _dirFor(String id) => Directory(p.join(rootDir.path, id));

  /// Modelos registrados (carpetas con `model.json`), ordenados por fecha.
  Future<List<ModelMetadata>> inventory() async {
    await _ensureRoot();
    final models = <ModelMetadata>[];
    for (final entry in rootDir.listSync().whereType<Directory>()) {
      if (p.basename(entry.path).startsWith(importStage)) continue;
      final manifest = File(p.join(entry.path, manifestFileName));
      if (!manifest.existsSync()) continue;
      try {
        final json = jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
        final metadata = ModelMetadata.fromJson(json);
        if (metadata.id == p.basename(entry.path)) {
          models.add(metadata);
        }
      } on Object {
        // Manifiesto corrupto: la carpeta cuenta como instalación incompleta.
      }
    }
    models.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return models;
  }

  /// GGUF sueltos directamente en la raíz (modelos anteriores a ModelManager,
  /// instalados por `adb push`). Se conservan como fallback de arranque.
  Future<List<File>> orphanGgufs() async {
    await _ensureRoot();
    try {
      return rootDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.gguf'))
          .toList();
    } on FileSystemException {
      return <File>[];
    }
  }

  /// Instalaciones incompletas: carpetas sin `model.json` o con manifiesto
  /// corrupto, carpetas de importación interrumpida y archivos `.part`.
  /// Nunca se usan para inferir.
  Future<List<String>> incompleteInstallations() async {
    await _ensureRoot();
    final incomplete = <String>[];
    for (final entry in rootDir.listSync().whereType<Directory>()) {
      final name = p.basename(entry.path);
      if (name.startsWith(importStage)) {
        incomplete.add(name);
        continue;
      }
      final manifest = File(p.join(entry.path, manifestFileName));
      if (!manifest.existsSync()) {
        incomplete.add(name);
        continue;
      }
      try {
        final json = jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
        final metadata = ModelMetadata.fromJson(json);
        if (metadata.id != name) {
          incomplete.add(name);
        }
      } on Object {
        incomplete.add(name); // manifiesto corrupto
      }
    }
    for (final file in rootDir.listSync().whereType<File>()) {
      if (file.path.endsWith('.part')) incomplete.add(p.basename(file.path));
    }
    return incomplete;
  }

  /// ID del modelo activo, o `null` si nunca se eligió uno.
  Future<String?> activeModelId() async {
    final file = File(p.join(rootDir.path, activeFileName));
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) return null;
      return ModelMetadata.sanitizeId(id);
    } on Object {
      return null;
    }
  }

  /// Metadatos del modelo activo, o `null` si no hay o no está instalado.
  Future<ModelMetadata?> activeModel() async {
    final id = await activeModelId();
    if (id == null) return null;
    final models = await inventory();
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  /// Marca el modelo activo. Lanza [ModelManagerException] si no existe o si
  /// el motor incluido en la app no soporta su arquitectura.
  Future<void> setActiveModel(String id) async {
    final models = await inventory();
    ModelMetadata? model;
    for (final candidate in models) {
      if (candidate.id == id) model = candidate;
    }
    if (model == null) {
      throw ModelManagerException('no hay ningún modelo instalado con el id "$id"');
    }
    _ensureEngineSupports(model);
    await _ensureRoot();
    final file = File(p.join(rootDir.path, activeFileName));
    await file.writeAsString(jsonEncode(<String, Object?>{'id': id}), flush: true);
  }

  /// Rechaza activar un modelo cuya arquitectura GGUF no soporta el motor.
  static void _ensureEngineSupports(ModelMetadata model) {
    if (isArchitectureSupported(model.architecture)) return;
    final arch = model.architecture;
    if (knownUnsupportedArchitectures.contains(arch)) {
      throw ModelManagerException(
        'este modelo usa la arquitectura "$arch", que el motor incluido en '
        'esta app todavía no soporta.\n\nRequiere una versión de LAIN con el '
        'motor actualizado (llama.cpp compilado con soporte para $arch).',
      );
    }
    throw ModelManagerException(
      'este modelo usa la arquitectura "$arch", que el motor incluido en '
      'esta app no reconoce. Probá con otro modelo o actualizá LAIN.',
    );
  }

  /// Importa un GGUF desde [source] a `models/<id>/` de forma atómica.
  ///
  /// - valida extensión `.gguf` y archivo no vacío;
  /// - verifica espacio libre con [freeBytes] cuando se provee (0 = no
  ///   disponible y se omite la comprobación, igual que en el instalador);
  /// - copia a un directorio temporal calculando SHA-256 en el mismo pase;
  /// - si [expectedSha256] viene y no coincide, aborta sin dejar residuos;
  /// - renombra el directorio completo al final (renombrado atómico).
  Future<ModelMetadata> importModel({
    required File source,
    String? expectedSha256,
    String family = 'language',
    String? version,
    String? architecture,
    String? sourceUrl,
    Future<int> Function()? freeBytes,
    void Function(double progress)? onProgress,
  }) async {
    await _ensureRoot();
    if (!await source.exists()) {
      throw ModelManagerException('el archivo de origen no existe');
    }
    if (!source.path.toLowerCase().endsWith('.gguf')) {
      throw ModelManagerException('formato no soportado: se espera un archivo .gguf');
    }
    final size = await source.length();
    if (size <= 0) {
      throw ModelManagerException('el archivo está vacío o es ilegible');
    }
    String? probedArchitecture;
    try {
      probedArchitecture = (await readGgufInfo(source)).architecture;
    } on GgufHeaderException {
      // Best-effort: si la cabecera no se puede leer, el modelo se importa
      // igual; la falta de arquitectura no bloquea la activación.
    }
    final id = ModelMetadata.sanitizeId(p.basenameWithoutExtension(source.path));
    if (id == null) {
      throw ModelManagerException('el nombre del archivo no permite generar un id válido');
    }
    if (_dirFor(id).existsSync()) {
      throw ModelManagerException('ya existe un modelo con el id "$id"');
    }
    if (freeBytes != null) {
      final free = await freeBytes();
      if (free > 0 && free < size) {
        throw ModelManagerException(
          'no hay espacio suficiente: el modelo pesa ${_gigabytes(size)} GB '
          'y quedan ${_gigabytes(free)} GB libres',
        );
      }
    }

    final staging = Directory(p.join(rootDir.path, '$importStage-$id'));
    await staging.create(recursive: true);
    final partFile = File(p.join(staging.path, '${p.basename(source.path)}.part'));
    try {
      final sha256sum = await _copyWithSha256(source, partFile, size, onProgress);
      if (expectedSha256 != null &&
          !sha256sum.toLowerCase().startsWith(expectedSha256.toLowerCase())) {
        throw ModelManagerException(
          'la verificación SHA-256 falló: el archivo no coincide con el hash esperado',
        );
      }

      final finalName = p.basename(source.path);
      final partTarget = File(p.join(staging.path, finalName));
      await partFile.rename(partTarget.path);

      final metadata = ModelMetadata(
        id: id,
        name: p.basenameWithoutExtension(source.path),
        version: version ?? 'desconocida',
        architecture: architecture ?? probedArchitecture ?? 'desconocida',
        format: 'gguf',
        quantization: ModelMetadata.quantizationFromName(source.path),
        family: family,
        sizeBytes: size,
        sha256: sha256sum.toLowerCase(),
        engineCompat: 'llama-cpp',
        fileName: finalName,
        addedAt: DateTime.now().toUtc().toIso8601String(),
        sourceUrl: sourceUrl,
      );
      final manifest = File(p.join(staging.path, manifestFileName));
      await manifest.writeAsString(jsonEncode(metadata.toJson()), flush: true);

      await staging.rename(_dirFor(id).path);
      return metadata;
    } on Object {
      await staging.delete(recursive: true).catchError((_) => staging);
      rethrow;
    }
  }

  /// Elimina SOLO la carpeta `models/<id>/`. No toca lain.db, recuerdos ni
  /// otros modelos. Lanza [ModelManagerException] si el id no está instalado.
  ///
  /// Si el modelo era el activo, primero lo desactiva (borra `active.json`):
  /// la app nunca queda apuntando a un modelo inexistente.
  Future<void> removeModel(String id) async {
    final cleanId = ModelMetadata.sanitizeId(id);
    final dir = cleanId == null ? null : _dirFor(cleanId);
    if (dir == null || !dir.existsSync()) {
      throw ModelManagerException('no hay ningún modelo instalado con el id "$id"');
    }
    // Guarda: solo borrar directorios reales dentro de la raíz.
    final root = p.canonicalize(rootDir.path);
    final target = p.canonicalize(dir.path);
    if (target == root || !target.startsWith('$root${p.separator}')) {
      throw ModelManagerException('ruta de modelo inválida');
    }
    if (await activeModelId() == cleanId) {
      await clearActiveModel();
    }
    await dir.delete(recursive: true);
  }

  /// Quita la selección de modelo activo (borra `active.json`).
  Future<void> clearActiveModel() async {
    final file = File(p.join(rootDir.path, activeFileName));
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Espacio ocupado por los modelos (registrados, sueltos e incompletos).
  ///
  /// Suma todos los archivos bajo `models/`. Es el dato que muestra la
  /// pantalla «Modelos»; no incluye la base de datos ni otros datos de LAIN.
  Future<int> usageBytes() async {
    await _ensureRoot();
    var total = 0;
    try {
      for (final entity in rootDir.listSync(recursive: true)) {
        if (entity is File) {
          try {
            total += entity.lengthSync();
          } on FileSystemException {
            continue;
          }
        }
      }
    } on FileSystemException {
      return total;
    }
    return total;
  }

  /// Elimina un GGUF suelto de la raíz (modelos instalados por `adb push`).
  ///
  /// Solo acepta archivos `.gguf` que estén directamente en `models/`.
  Future<void> removeOrphan(File file) async {
    await _ensureRoot();
    final root = p.canonicalize(rootDir.path);
    final target = p.canonicalize(file.path);
    final isDirectChild = p.dirname(target) == root;
    if (!isDirectChild || !target.toLowerCase().endsWith('.gguf')) {
      throw ModelManagerException('ruta de modelo inválida');
    }
    if (!file.existsSync()) {
      throw ModelManagerException('el archivo ya no existe');
    }
    await file.delete();
  }

  /// Borra instalaciones incompletas (`.importing-*`, `.download-*`, carpetas
  /// sin `model.json` y archivos `.part`). Devuelve los bytes liberados.
  ///
  /// Nunca toca modelos registrados ni archivos ajenos a la carpeta.
  Future<int> purgeIncomplete() async {
    await _ensureRoot();
    var freed = 0;
    for (final entity in rootDir.listSync()) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        final manifest = File(p.join(entity.path, manifestFileName));
        final isStaging = name.startsWith(importStage) ||
            name.startsWith(downloadStage);
        if (isStaging || !manifest.existsSync()) {
          freed += await _directoryBytes(entity);
          await entity.delete(recursive: true);
        }
        continue;
      }
      if (entity is File && entity.path.endsWith('.part')) {
        freed += await _fileBytes(entity);
        await entity.delete();
      }
    }
    return freed;
  }

  /// Borra TODO el almacenamiento de modelos: carpetas registradas, GGUF
  /// sueltos, staging y `active.json`. Devuelve los bytes liberados.
  ///
  /// Las conversaciones, los recuerdos, la configuración y `lain.db` viven
  /// fuera de esta carpeta y no se tocan.
  Future<int> removeAllModels() async {
    await _ensureRoot();
    var freed = 0;
    for (final entity in rootDir.listSync()) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        freed += await _directoryBytes(entity);
        await entity.delete(recursive: true);
        continue;
      }
      if (entity is! File) continue;
      final lower = name.toLowerCase();
      final removable = lower.endsWith('.gguf') ||
          lower.endsWith('.part') ||
          name == activeFileName;
      if (!removable) continue;
      freed += await _fileBytes(entity);
      await entity.delete();
    }
    return freed;
  }

  Future<int> _directoryBytes(Directory dir) async {
    var total = 0;
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) total += await _fileBytes(entity);
      }
    } on FileSystemException {
      return total;
    }
    return total;
  }

  Future<int> _fileBytes(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      return 0;
    }
  }

  Future<void> _ensureRoot() async {
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }
  }

  /// Copia [source] a [target] en bloques, calculando el SHA-256 del contenido
  /// en el mismo pase (una sola lectura) y reportando progreso 0..1.
  Future<String> _copyWithSha256(
    File source,
    File target,
    int totalBytes,
    void Function(double progress)? onProgress,
  ) async {
    final output = _DigestSink();
    final input = sha256.startChunkedConversion(output);
    final raf = source.openRead();
    final sink = target.openWrite();
    var copied = 0;
    try {
      await for (final chunk in raf) {
        final bytes = Uint8List.fromList(chunk);
        input.add(bytes);
        sink.add(bytes);
        copied += bytes.length;
        if (totalBytes > 0) {
          onProgress?.call(copied / totalBytes);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    input.close();
    return output.value.toString();
  }

  String _gigabytes(int bytes) => (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
