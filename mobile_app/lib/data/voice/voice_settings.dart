import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Preferencias de voz persistidas en el almacenamiento de la app.
///
/// Archivo pequeño y best-effort: si no se puede leer o escribir, la app sigue
/// funcionando con el valor por defecto (voz apagada).
class VoiceSettings {
  VoiceSettings(this.file);

  final File file;

  static Future<VoiceSettings> open() async {
    final dir = await getApplicationSupportDirectory();
    return VoiceSettings(File(p.join(dir.path, 'voice_settings.json')));
  }

  Future<bool> readTtsEnabled() async {
    try {
      if (!await file.exists()) return false;
      final json = jsonDecode(await file.readAsString());
      if (json is Map && json['tts_enabled'] is bool) {
        return json['tts_enabled'] as bool;
      }
    } on Object {
      // Preferencia ilegible: se usa el valor seguro.
    }
    return false;
  }

  Future<void> writeTtsEnabled(bool enabled) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(<String, Object?>{'tts_enabled': enabled}),
        flush: true,
      );
    } on Object {
      // La preferencia no es crítica para conversar.
    }
  }
}
