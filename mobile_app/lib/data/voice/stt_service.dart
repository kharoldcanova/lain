import 'dart:typed_data';

import 'stt_native.dart';
import 'whisper_model_manager.dart';

/// Carga el modelo de voz bajo demanda y transcribe PCM16.
class SttService {
  SttService({required this.engine, required this.manager});

  final SttEngine engine;
  final WhisperModelManager manager;

  String? _loadedPath;

  Future<String> transcribe(Uint8List pcm16) async {
    final file = await manager.locate();
    if (file == null) {
      throw const SttException(
        'No hay modelo de voz instalado.\n\n'
        'Abrí «Modelos» y descargá Whisper base (ggml-base.bin, ~148 MB).',
      );
    }
    if (_loadedPath != file.path || !engine.isReady) {
      await engine.loadModel(file.path);
      _loadedPath = file.path;
    }
    if (pcm16.lengthInBytes < 2) return '';
    return engine.transcribe(pcm16);
  }

  Future<void> dispose() => engine.dispose();
}
