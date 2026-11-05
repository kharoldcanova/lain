import 'package:flutter/services.dart';

/// Error de captura de audio con mensaje para el usuario.
class AudioCaptureException implements Exception {
  const AudioCaptureException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Micrófono nativo: PCM16 mono a 16 kHz, el formato de whisper.cpp.
class AudioCapture {
  static const MethodChannel _channel =
      MethodChannel('com.lain.lain_mobile/audio');

  Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    if (await hasPermission()) return true;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      throw const AudioCaptureException(
          'el micrófono solo está disponible en Android');
    } on PlatformException catch (error) {
      throw AudioCaptureException(
          error.message ?? 'no se pudo pedir el permiso de micrófono');
    }
  }

  Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('start');
    } on MissingPluginException {
      throw const AudioCaptureException(
          'el micrófono solo está disponible en Android');
    } on PlatformException catch (error) {
      throw AudioCaptureException(
          error.message ?? 'no se pudo iniciar la grabación');
    }
  }

  Future<Uint8List> stop() async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('stop');
      return bytes ?? Uint8List(0);
    } on MissingPluginException {
      throw const AudioCaptureException(
          'el micrófono solo está disponible en Android');
    } on PlatformException catch (error) {
      throw AudioCaptureException(
          error.message ?? 'no se pudo detener la grabación');
    }
  }

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on PlatformException {
      // Cancelar nunca debe romper la UI.
    }
  }
}
