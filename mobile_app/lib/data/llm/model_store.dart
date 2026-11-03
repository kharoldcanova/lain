import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'model_manager.dart';
import 'engine_capabilities.dart';

class ModelLocation {
  const ModelLocation({required this.expectedPath, this.file});

  final String expectedPath;
  final File? file;

  bool get exists => file != null;

  /// Nombre del archivo a cargar.
  String get fileName => expectedPath.split('/').last;
}

/// Carpeta raíz de modelos de la app. En Android es
/// `/storage/emulated/0/Android/data/<paquete>/files/models` (almacenamiento
/// privado de la app según scoped storage: no es almacenamiento público,
/// sobrevive a las actualizaciones y es accesible por `adb` para pruebas).
/// Se elimina solo al desinstalar la app.
Future<Directory> modelDirectory() async {
  final base = await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/models');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Elige el GGUF a cargar entre los que haya en una carpeta.
///
/// Gana el modificado más recientemente: así se cambia de modelo con
/// `adb push` (que marca la hora actual) sin recompilar el APK y se puede
/// comparar uno contra otro en el mismo teléfono. Es el fallback para los
/// GGUF sueltos anteriores a ModelManager.
File? pickModelFile(List<File> files) {
  final candidates = files
      .where((file) => file.path.toLowerCase().endsWith('.gguf'))
      .toList();
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final byTime = b.statSync().modified.compareTo(a.statSync().modified);
    return byTime != 0 ? byTime : a.path.compareTo(b.path);
  });
  return candidates.first;
}

/// Localiza el modelo que debe cargar el motor de inferencia.
///
/// Orden de preferencia:
/// 1. el modelo activo registrado por ModelManager;
/// 2. el GGUF suelto más reciente en la raíz (modelos por `adb push`);
/// 3. el primer modelo registrado del inventario.
Future<ModelLocation> locateModel() async => locateModelIn(await modelDirectory());

/// Igual que [locateModel] pero sobre una carpeta dada (pruebas).
Future<ModelLocation> locateModelIn(Directory dir) async {
  final manager = ModelManager(dir);

  final active = await manager.activeModel();
  if (active != null && isArchitectureSupported(active.architecture)) {
    final file = File(active.filePath(dir.path));
    if (file.existsSync()) {
      return ModelLocation(expectedPath: file.path, file: file);
    }
  }

  final legacy = pickModelFile(await manager.orphanGgufs());
  if (legacy != null) {
    return ModelLocation(expectedPath: legacy.path, file: legacy);
  }

  final registered = await manager.inventory();
  for (final metadata in registered) {
    if (!isArchitectureSupported(metadata.architecture)) continue;
    final file = File(metadata.filePath(dir.path));
    if (file.existsSync()) {
      return ModelLocation(expectedPath: file.path, file: file);
    }
  }

  return ModelLocation(expectedPath: dir.path);
}
