import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Estadísticas de una métrica sobre un conjunto de turnos.
class MetricStats {
  const MetricStats({
    required this.count,
    required this.median,
    required this.p90,
  });

  final int count;
  final double median;
  final double p90;
}

/// Agregados del registro de turnos. Cada métrica es `null` si no hay
/// suficientes muestras válidas.
class TurnStats {
  const TurnStats({
    required this.count,
    this.ttftMs,
    this.totalMs,
    this.tokensPerSecond,
    this.prefillMs,
    this.decodeMs,
  });

  final int count;
  final MetricStats? ttftMs;
  final MetricStats? totalMs;
  final MetricStats? tokensPerSecond;
  final MetricStats? prefillMs;
  final MetricStats? decodeMs;
}

/// Registro local de turnos de inferencia en JSONL.
///
/// Vive en `getApplicationSupportDirectory()/lain_turns.jsonl`, junto a
/// `lain_startup.log`. Nunca toca `lain.db`, los recuerdos ni la configuración.
/// Cada escritura es best-effort: un fallo de disco no interrumpe el chat.
class TurnLog {
  TurnLog({Future<Directory> Function()? directory, this.enabled = true})
      : _directory = directory ?? getApplicationSupportDirectory;

  static const String fileName = 'lain_turns.jsonl';

  final Future<Directory> Function() _directory;
  final bool enabled;

  Future<File> _file() async {
    final dir = await _directory();
    return File(p.join(dir.path, fileName));
  }

  /// Añade un turno. Silencioso ante cualquier error de E/S.
  Future<void> append(Map<String, Object?> record) async {
    if (!enabled) return;
    try {
      final file = await _file();
      await file.writeAsString(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // La instrumentación nunca debe romper una conversación.
    }
  }

  /// Últimos [limit] turnos, en orden cronológico. Ignora líneas corruptas.
  Future<List<Map<String, Object?>>> read({int limit = 500}) async {
    if (!enabled) return const <Map<String, Object?>>[];
    try {
      final file = await _file();
      if (!await file.exists()) return const <Map<String, Object?>>[];
      final turns = <Map<String, Object?>>[];
      for (final line in (await file.readAsString()).split('\n')) {
        final text = line.trim();
        if (text.isEmpty) continue;
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map<String, Object?>) turns.add(decoded);
        } on FormatException {
          continue; // línea truncada o corrupta
        }
      }
      final start = turns.length > limit ? turns.length - limit : 0;
      return turns.sublist(start);
    } on Object {
      return const <Map<String, Object?>>[];
    }
  }

  /// Borra el registro. No toca ningún otro dato de LAIN.
  Future<void> clear() async {
    if (!enabled) return;
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } on Object {
      // Idem.
    }
  }
}

/// Calcula mediana y p90 de las métricas numéricas de [turns].
///
/// Solo devuelve una métrica cuando hay al menos [minimumSamples] valores
/// válidos: con pocos turnos un percentil no significa nada.
TurnStats summarizeTurns(
  List<Map<String, Object?>> turns, {
  int minimumSamples = 5,
}) {
  MetricStats? statsFor(String key) {
    final values = <double>[];
    for (final turn in turns) {
      final raw = turn[key];
      if (raw is num) values.add(raw.toDouble());
    }
    if (values.length < minimumSamples) return null;
    values.sort();
    final middle = values.length ~/ 2;
    final median = values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
    final index = (0.9 * values.length).ceil() - 1;
    final p90 = values[index.clamp(0, values.length - 1)];
    return MetricStats(count: values.length, median: median, p90: p90);
  }

  return TurnStats(
    count: turns.length,
    ttftMs: statsFor('ttft_ms'),
    totalMs: statsFor('total_ms'),
    tokensPerSecond: statsFor('tok_per_s'),
    prefillMs: statsFor('prefill_ms'),
    decodeMs: statsFor('decode_ms'),
  );
}
