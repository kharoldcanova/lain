import 'package:flutter/services.dart';

/// Canal nativo de Android para operaciones de almacenamiento del modelo.
///
/// Antes copiaba el GGUF empaquetado en el APK; ahora la app no empaqueta
/// modelos (ver `model_manager.dart`). El canal se conserva porque
/// `freeBytes` y la copia con archivo temporal + renombrado se reutilizan
/// para la importación de modelos desde archivos locales.
abstract interface class ModelInstaller {
  /// Espacio libre en bytes del almacenamiento donde se copia el modelo.
  /// Devuelve 0 cuando la plataforma no puede informarlo.
  Future<int> freeBytes();

  Future<void> install({
    required String assetPath,
    required String targetPath,
    void Function(double progress)? onProgress,
  });
}

class AssetModelInstaller implements ModelInstaller {
  AssetModelInstaller({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.lain.lain_mobile/model');

  final MethodChannel _channel;

  @override
  Future<int> freeBytes() async {
    try {
      final bytes = await _channel.invokeMethod<int>('freeBytes');
      return bytes ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  @override
  Future<void> install({
    required String assetPath,
    required String targetPath,
    void Function(double progress)? onProgress,
  }) async {
    if (onProgress != null) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'progress') {
          final progress = call.arguments as Map<Object?, Object?>;
          onProgress((progress['progress'] as num).toDouble());
        }
        return null;
      });
    }

    try {
      await _channel.invokeMethod<String>('copyAsset', <String, String>{
        'asset': assetPath,
        'target': targetPath,
      });
    } on PlatformException catch (error) {
      throw ModelInstallException(error.message ?? 'no se pudo copiar el modelo');
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }
}

class ModelInstallException implements Exception {
  const ModelInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}
