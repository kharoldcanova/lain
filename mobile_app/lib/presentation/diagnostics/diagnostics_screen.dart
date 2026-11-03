import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/experimental.dart';
import '../../core/theme.dart';
import '../../data/diagnostics/turn_log.dart';
import '../../data/llm/lain_engine.dart';
import '../../data/llm/lain_native.dart';
import '../chat/chat_controller.dart';

/// Pantalla de diagnóstico del motor (solo build experimental).
///
/// Todo se lee del dispositivo: backend cargado, configuración efectiva,
/// mediana/p90 de los últimos turnos y el registro JSONL. No necesita ADB.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  List<Map<String, Object?>> _turns = const <Map<String, Object?>>[];
  TurnStats? _stats;
  LainTurnMetrics? _lastMetrics;
  String? _backend;
  bool _instrumented = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_reload);
  }

  Future<void> _reload() async {
    final turns = await ref.read(turnLogProvider).read(limit: 200);
    final engine = ref.read(lainEngineProvider);
    final source =
        engine is LainMetricsSource ? engine as LainMetricsSource : null;
    if (!mounted) return;
    setState(() {
      _turns = turns;
      _stats = summarizeTurns(turns);
      _lastMetrics = source?.lastMetrics;
      _backend = source?.backendName;
      _instrumented = source?.instrumented ?? false;
      _loading = false;
    });
  }

  Future<void> _copy() async {
    final payload = <String, Object?>{
      'generado': DateTime.now().toUtc().toIso8601String(),
      'backend': _backend,
      'instrumentado': _instrumented,
      'resumen': _stats == null
          ? null
          : <String, Object?>{
              'turnos': _stats!.count,
              'ttft_ms': _metric(_stats!.ttftMs),
              'total_ms': _metric(_stats!.totalMs),
              'tok_per_s': _metric(_stats!.tokensPerSecond),
              'prefill_ms': _metric(_stats!.prefillMs),
              'decode_ms': _metric(_stats!.decodeMs),
            },
      'turnos': _turns,
    };
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)),
    );
    _snack('Registro copiado al portapapeles');
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar el registro de turnos?'),
        content: const Text(
          'Se borra solo el registro de diagnóstico de este dispositivo. '
          'Las conversaciones, los recuerdos y la configuración no se tocan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(turnLogProvider).clear();
    await _reload();
    _snack('Registro borrado');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final lastTurn = _turns.isEmpty ? null : _turns.last;
    final metrics = _lastMetrics;
    final model = lastTurn?['model'] as String?;
    final threads = metrics?.nThreads ?? (lastTurn?['n_threads'] as num?)?.toInt();
    final batch = metrics?.nBatchThreads ??
        (lastTurn?['n_batch_threads'] as num?)?.toInt();
    final ctx = metrics?.nCtx ?? (lastTurn?['n_ctx'] as num?)?.toInt();
    final loadMode = metrics?.loadMode ?? (lastTurn?['load_mode'] as num?)?.toInt();
    final loadMs = metrics?.loadMs ?? (lastTurn?['load_ms'] as num?)?.toInt();
    final nBackend =
        metrics?.nBackend ?? (lastTurn?['n_backend'] as num?)?.toInt();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico'),
        actions: [
          IconButton(
            onPressed: _copy,
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copiar registro',
          ),
          IconButton(
            onPressed: _turns.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Borrar registro',
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _card(theme, 'Motor', <Widget>[
            _row('Build', lainFlavorName),
            _row('Backend', _backend ?? 'desconocido'),
            _row(
              'Instrumentación',
              _instrumented ? 'nativa activa' : 'no disponible (solo Dart)',
            ),
            _row('Modelo', model ?? 'sin turnos'),
            _row('Registros GGML', nBackend?.toString() ?? '—'),
          ]),
          const SizedBox(height: 12),
          _card(theme, 'Configuración efectiva', <Widget>[
            _row('Hilos', threads?.toString() ?? '—'),
            _row('Hilos de batch', batch?.toString() ?? '—'),
            _row('Contexto', ctx == null ? '—' : '$ctx tokens'),
            _row('Carga del modelo', loadMode == null
                ? '—'
                : '${_loadModeLabel(loadMode)} (código $loadMode)'),
            _row('Tiempo de carga', _ms(loadMs)),
          ]),
          const SizedBox(height: 12),
          _card(theme, 'Agregados', <Widget>[
            if (_stats == null || _stats!.count == 0)
              const Text('Sin turnos registrados todavía.')
            else ...[
              Text(
                '${_stats!.count} turnos · medianas y p90 '
                '(se muestran desde 5 muestras)',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              _statsRow('TTFT', _stats!.ttftMs, 'ms'),
              _statsRow('Total', _stats!.totalMs, 'ms'),
              _statsRow('Prefill', _stats!.prefillMs, 'ms'),
              _statsRow('Decode', _stats!.decodeMs, 'ms'),
              _statsRow('Velocidad', _stats!.tokensPerSecond, 'tok/s'),
            ],
          ]),
          const SizedBox(height: 12),
          _card(theme, 'Últimos turnos', <Widget>[
            if (_turns.isEmpty)
              const Text('Sin turnos registrados todavía.')
            else
              for (final turn in _turns.reversed.take(20))
                _turnTile(context, theme, turn),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _card(ThemeData theme, String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LainColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(color: LainColors.textMuted)),
        ],
      ),
    );
  }

  Widget _statsRow(String label, MetricStats? stats, String unit) {
    final value = stats == null
        ? 'pocas muestras'
        : 'mediana ${_num(stats.median)} $unit · p90 ${_num(stats.p90)} $unit';
    return _row(label, value);
  }

  Widget _turnTile(
    BuildContext context,
    ThemeData theme,
    Map<String, Object?> turn,
  ) {
    final ts = turn['ts'] as String?;
    final ttft = (turn['ttft_ms'] as num?)?.toDouble();
    final total = (turn['total_ms'] as num?)?.toDouble();
    final speed = (turn['tok_per_s'] as num?)?.toDouble();
    final prompt = (turn['n_prompt'] as num?)?.toInt();
    final generated = (turn['n_generated'] as num?)?.toInt();
    final error = turn['inference_error'] as String?;
    final time = ts == null
        ? '—'
        : (DateTime.tryParse(ts)?.toLocal().toIso8601String() ?? ts);
    final shortTime = time.length >= 19 ? time.substring(11, 19) : time;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$shortTime · ttft ${_num(ttft)} ms · total ${_num(total)} ms'
            '${speed == null ? '' : ' · ${_num(speed)} tok/s'}',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            '${prompt ?? '?'} tok entrada → ${generated ?? '?'} tok salida'
            '${turn['instrumented'] == true ? '' : ' · sin instrumentación'}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: LainColors.textMuted),
          ),
          if (error != null)
            Text(
              error,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
        ],
      ),
    );
  }

  static Map<String, Object?>? _metric(MetricStats? stats) => stats == null
      ? null
      : <String, Object?>{
          'muestras': stats.count,
          'mediana': double.parse(stats.median.toStringAsFixed(1)),
          'p90': double.parse(stats.p90.toStringAsFixed(1)),
        };

  String _num(double? value) =>
      value == null ? '—' : value.toStringAsFixed(value >= 100 ? 0 : 1);

  String _ms(int? value) => value == null ? '—' : '$value ms';

  String _loadModeLabel(int mode) {
    switch (mode) {
      case -1:
        return 'auto';
      case 0:
        return 'sin mmap';
      case 1:
        return 'mmap';
      case 2:
        return 'mlock';
      case 3:
        return 'mmap + mlock';
      case 4:
        return 'I/O directo';
      default:
        return 'desconocido';
    }
  }
}
