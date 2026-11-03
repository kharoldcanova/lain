import 'package:path/path.dart' as p;

/// Metadatos de un modelo instalado, persistidos en `model.json` junto al
/// archivo del modelo, dentro de `models/<id>/`.
///
/// Es agnóstico a la arquitectura del modelo: cualquier GGUF que pueda cargar
/// el motor de inferencia se registra con estos campos.
class ModelMetadata {
  const ModelMetadata({
    required this.id,
    required this.name,
    required this.version,
    required this.architecture,
    required this.format,
    required this.quantization,
    required this.family,
    required this.sizeBytes,
    required this.sha256,
    required this.engineCompat,
    required this.fileName,
    required this.addedAt,
    this.sourceUrl,
  });

  /// Identificador único (nombre saneado del archivo, sin extensión).
  final String id;

  /// Nombre legible del modelo.
  final String name;

  /// Versión declarada, o `desconocida` si no se puede determinar.
  final String version;

  /// Arquitectura (p. ej. `qwen3`), o `desconocida`.
  final String architecture;

  /// Formato del archivo (p. ej. `gguf`).
  final String format;

  /// Cuantización detectada en el nombre (p. ej. `Q4_K_M`), o `desconocida`.
  final String quantization;

  /// Familia funcional: `language`, `vision`, `speech`, `embeddings`, `other`.
  final String family;

  /// Tamaño del archivo en bytes.
  final int sizeBytes;

  /// Hash SHA-256 del archivo.
  final String sha256;

  /// Motor compatible (p. ej. `llama-cpp`).
  final String engineCompat;

  /// Nombre del archivo dentro de `models/<id>/`.
  final String fileName;

  /// Fecha de registro en ISO-8601.
  final String addedAt;

  /// Origen del archivo (URL de Hugging Face cuando se descargó), o `null`
  /// si se importó desde el dispositivo.
  final String? sourceUrl;

  /// Ruta absoluta esperada del archivo del modelo.
  String filePath(String rootPath) => p.join(rootPath, id, fileName);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'version': version,
        'architecture': architecture,
        'format': format,
        'quantization': quantization,
        'family': family,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'engineCompat': engineCompat,
        'fileName': fileName,
        'addedAt': addedAt,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
      };

  factory ModelMetadata.fromJson(Map<String, Object?> json) => ModelMetadata(
        id: json['id'] as String,
        name: json['name'] as String? ?? (json['id'] as String),
        version: json['version'] as String? ?? 'desconocida',
        architecture: json['architecture'] as String? ?? 'desconocida',
        format: json['format'] as String? ?? 'gguf',
        quantization: json['quantization'] as String? ?? 'desconocida',
        family: json['family'] as String? ?? 'other',
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        sha256: json['sha256'] as String? ?? '',
        engineCompat: json['engineCompat'] as String? ?? 'llama-cpp',
        fileName: json['fileName'] as String,
        addedAt: json['addedAt'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String?,
      );

  /// Cuantización detectada en un nombre de archivo (`Q4_K_M`, `Q5_0`, …).
  static String quantizationFromName(String fileName) {
    final match = RegExp(
      r'([Qq]\d(?:_[Kk](?:_[SLM])?)?|iq\d_?[a-z0-9]*|f16|bf16)',
    ).firstMatch(fileName);
    return match?.group(1)?.toUpperCase() ?? 'desconocida';
  }

  /// Identificador saneado a partir de un valor ya sin extensión `.gguf`.
  ///
  /// Solo `[a-z0-9._-]`; devuelve `null` si no queda nada válido.
  static String? sanitizeId(String value) {
    final sanitized = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '-');
    final trimmed = sanitized
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Errores de importación/gestión de modelos, con mensajes para el usuario.
class ModelManagerException implements Exception {
  const ModelManagerException(this.message);

  final String message;

  @override
  String toString() => message;
}
