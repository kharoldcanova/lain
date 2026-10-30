import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Nombre del GGUF empaquetado en el APK. Se usa como destino de la copia en el
/// primer arranque y como modelo por defecto cuando la carpeta está vacía.
const String modelFileName = 'MiniCPM5-2B.Q4_K_M.gguf';

class ModelLocation {
  const ModelLocation({required this.expectedPath, this.file});

  final String expectedPath;
  final File? file;

  bool get exists => file != null;

  /// Nombre del archivo a cargar (`MiniCPM5-2B.Q4_K_M.gguf`).
  String get fileName => expectedPath.split('/').last;
}

/// Carpeta donde la app busca el modelo. En Android es
/// `/storage/emulated/0/Android/data/<paquete>/files/models`, accesible por adb.
Future<Directory> modelDirectory() async {
  final base = await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/models');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Elige el GGUF a cargar entre los que haya en `models/`.
///
/// Gana el modificado más recientemente: así se cambia de modelo con
/// `adb push` (que marca la hora actual) sin recompilar el APK y se puede
/// comparar uno contra otro en el mismo teléfono.
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

List<File> _ggufFilesIn(Directory dir) {
  try {
    return dir.listSync().whereType<File>().toList();
  } on FileSystemException {
    return <File>[];
  }
}

Future<ModelLocation> locateModel() async {
  final dir = await modelDirectory();
  final installed = pickModelFile(_ggufFilesIn(dir));
  if (installed != null) {
    return ModelLocation(expectedPath: installed.path, file: installed);
  }
  return ModelLocation(expectedPath: '${dir.path}/$modelFileName');
}
