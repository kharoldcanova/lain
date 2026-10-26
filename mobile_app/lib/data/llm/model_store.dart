import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Nombre esperado del GGUF dentro de `models/`.
const String modelFileName = 'Qwen2.5-3B-Instruct.Q4_K_M.gguf';

class ModelLocation {
  const ModelLocation({required this.expectedPath, this.file});

  final String expectedPath;
  final File? file;

  bool get exists => file != null;
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

Future<ModelLocation> locateModel() async {
  final dir = await modelDirectory();
  final expectedPath = '${dir.path}/$modelFileName';
  final file = File(expectedPath);
  return ModelLocation(
    expectedPath: expectedPath,
    file: await file.exists() ? file : null,
  );
}
