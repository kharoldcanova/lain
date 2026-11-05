import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/voice/voice_settings.dart';

void main() {
  test('la voz está apagada por defecto', () async {
    final dir = Directory.systemTemp.createTempSync('lain_voice_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final settings = VoiceSettings(File('${dir.path}/voice_settings.json'));

    expect(await settings.readTtsEnabled(), isFalse);
  });

  test('persiste la preferencia de voz', () async {
    final dir = Directory.systemTemp.createTempSync('lain_voice_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final settings = VoiceSettings(File('${dir.path}/voice_settings.json'));

    await settings.writeTtsEnabled(true);

    expect(await settings.readTtsEnabled(), isTrue);
    expect(await File('${dir.path}/voice_settings.json').exists(), isTrue);
  });
}
