import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/voice/audio_capture.dart';
import '../../data/voice/progressive_speech.dart';
import '../../data/voice/stt_native.dart';
import '../../data/voice/stt_service.dart';
import '../../data/voice/tts_engine.dart';
import '../../data/voice/voice_settings.dart';
import '../../data/voice/whisper_model_manager.dart';

/// Micrófono nativo (PCM16 16 kHz).
final audioCaptureProvider = Provider<AudioCapture>((ref) => AudioCapture());

/// Motor whisper.cpp en un isolate propio.
final sttEngineProvider = Provider<SttEngine>((ref) {
  final engine = NativeSttEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Modelo de voz instalado en `<modelos>/whisper/`.
final whisperModelManagerProvider =
    FutureProvider<WhisperModelManager>((ref) => WhisperModelManager.open());

/// Carga diferida del modelo de voz y transcripción.
final sttServiceProvider = FutureProvider<SttService>((ref) async {
  final manager = await ref.read(whisperModelManagerProvider.future);
  return SttService(engine: ref.read(sttEngineProvider), manager: manager);
});

final ttsEngineProvider = Provider<TtsEngine>((ref) => TtsEngine());

/// Voz de la respuesta por oraciones.
final speechEngineProvider = Provider<SpeechEngine>(
  (ref) => ProgressiveSpeech(engine: ref.read(ttsEngineProvider)),
);

final voiceSettingsProvider =
    FutureProvider<VoiceSettings>((ref) => VoiceSettings.open());

/// Preferencia de voz, apagada por defecto.
final ttsEnabledProvider = NotifierProvider<TtsToggle, bool>(TtsToggle.new);

class TtsToggle extends Notifier<bool> {
  @override
  bool build() {
    Future<void>.microtask(_load);
    return false;
  }

  Future<void> _load() async {
    try {
      final settings = await ref.read(voiceSettingsProvider.future);
      state = await settings.readTtsEnabled();
    } on Object {
      state = false;
    }
  }

  Future<void> toggle() async {
    state = !state;
    if (!state) {
      await ref.read(speechEngineProvider).stop();
    }
    try {
      final settings = await ref.read(voiceSettingsProvider.future);
      await settings.writeTtsEnabled(state);
    } on Object {
      // La preferencia no es crítica.
    }
  }

  /// Apaga la voz sin tocar la preferencia guardada.
  Future<void> silence() => ref.read(speechEngineProvider).stop();
}
