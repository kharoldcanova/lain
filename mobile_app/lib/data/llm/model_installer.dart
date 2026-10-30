import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  /// Abre el selector de archivos de Android y copia el `.gguf` elegido a
  /// [targetDir] con archivo temporal + renombrado. Devuelve la ruta final,
  /// `null` si el usuario cancela la selección, o lanza
  /// [ModelInstallException] si la copia falla. [onProgress] recibe el avance
  /// de la copia (0..1) cuando el proveedor SAF informa el tamaño.
  Future<String?> pickAndImport({
    required Directory targetDir,
    void Function(double progress)? onProgress,
  });
}

/// Carpeta donde aterrizan las importaciones antes de que ModelManager las
/// registre (fuera de `models/` para no crear GGUF huérfanos de fallback).
Future<Directory> importCacheDirectory() async {
  final base = await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'imports'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
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

  @override
  Future<String?> pickAndImport({
    required Directory targetDir,
    void Function(double progress)? onProgress,
  }) async {
    if (onProgress != null) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'progress') {
          final data = call.arguments as Map<Object?, Object?>;
          onProgress((data['progress'] as num).toDouble());
        }
        return null;
      });
    }
    try {
      return await _channel.invokeMethod<String>('pickAndImport', <String, String>{
        'targetDir': targetDir.path,
      });
    } on PlatformException catch (error) {
      if (error.code == 'pick_cancelled') {
        return null;
      }
      throw ModelInstallException(error.message ?? 'no se pudo importar el modelo');
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
