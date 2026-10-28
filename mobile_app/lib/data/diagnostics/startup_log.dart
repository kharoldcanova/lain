import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Registro de arranque en un archivo legible desde la propia app.
///
/// Sirve para diagnosticar fallos de carga del modelo en un teléfono sin
/// depuración USB. Nunca lanza: un fallo de escritura no debe romper el arranque.
class StartupLog {
  StartupLog._();

  static const String fileName = 'lain_startup.log';

  /// Se desactiva en pruebas: `path_provider` no responde sin plugin.
  static bool enabled = true;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$fileName');
  }

  static Future<void> write(String message) async {
    if (!enabled) return;
    try {
      final file = await _file().timeout(const Duration(seconds: 2));
      await file.writeAsString(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // Silencio deliberado: el diagnóstico no puede romper el arranque.
    }
  }

  static Future<String> read() async {
    if (!enabled) return 'Registro desactivado.';
    try {
      final file = await _file();
      if (!await file.exists()) return 'Sin registro todavía.';
      final text = await file.readAsString();
      return text.isEmpty ? 'Sin registro todavía.' : text;
    } on Object catch (error) {
      return 'No se pudo leer el registro: $error';
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } on Object {
      // Idem.
    }
  }
}
