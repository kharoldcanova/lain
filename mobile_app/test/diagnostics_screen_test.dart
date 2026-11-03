import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/diagnostics/turn_log.dart';
import 'package:lain_mobile/data/llm/lain_engine.dart';
import 'package:lain_mobile/data/llm/lain_native.dart';
import 'package:lain_mobile/presentation/chat/chat_controller.dart';
import 'package:lain_mobile/presentation/diagnostics/diagnostics_screen.dart';

class _FakeEngine implements LainEngine, LainMetricsSource {
  @override
  bool get isReady => true;

  @override
  LainTurnMetrics? get lastMetrics => const LainTurnMetrics(
        loadMs: 4200,
        prefillMs: 1500,
        decodeMs: 2000,
        ttftMs: 1800,
        nPromptTokens: 480,
        nGeneratedTokens: 32,
        nThreads: 4,
        nBatchThreads: 4,
        nCtx: 2048,
        loadMode: -1,
        nBackend: 1,
        instrumented: true,
      );

  @override
  String? get backendName => 'libggml-cpu-android_armv8.2_2.so';

  @override
  bool get instrumented => true;

  @override
  Future<void> loadModel(String path, {int contextSize = 2048, int threads = 4}) async {}

  @override
  Stream<String> generate({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 512,
    double temperature = 0.7,
    double topP = 0.9,
    int seed = 42,
  }) async* {}

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory dir;
  late TurnLog log;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('lain-diag-');
    log = TurnLog(directory: () async => dir);
    for (var i = 1; i <= 6; i++) {
      await log.append(<String, Object?>{
        'ts': '2026-11-03T10:00:0$i.000Z',
        'model': 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
        'backend': 'libggml-cpu-android_armv8.2_2.so',
        'instrumented': true,
        'ttft_ms': i * 100,
        'total_ms': i * 1000,
        'prefill_ms': i * 50,
        'decode_ms': i * 500,
        'n_prompt': 400,
        'n_generated': 30,
        'tok_per_s': i.toDouble(),
        'n_threads': 4,
        'n_batch_threads': 4,
        'n_ctx': 2048,
        'load_mode': -1,
        'rss_mb': 700.5,
      });
    }
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() => ProviderScope(
        overrides: [
          lainEngineProvider.overrideWithValue(_FakeEngine()),
          turnLogProvider.overrideWithValue(log),
        ],
        child: const MaterialApp(home: DiagnosticsScreen()),
      );

  Future<void> settleIo(WidgetTester tester) => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );

  testWidgets('muestra backend, configuración y agregados', (tester) async {
    await tester.runAsync(() async => tester.pumpWidget(app()));
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(find.text('Diagnóstico'), findsOneWidget);
    expect(find.text('libggml-cpu-android_armv8.2_2.so'), findsOneWidget);
    expect(find.text('nativa activa'), findsOneWidget);
    expect(find.text('LFM2.5-1.2B-Instruct-Q4_K_M.gguf'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    expect(find.textContaining('6 turnos'), findsOneWidget);
    expect(find.textContaining('mediana'), findsWidgets);
  });

  testWidgets('borrar el registro pide confirmación y lo elimina', (tester) async {
    await tester.runAsync(() async => tester.pumpWidget(app()));
    await settleIo(tester);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Borrar registro'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('no se tocan'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Borrar'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(await tester.runAsync(() => log.read()), isEmpty);
    expect(find.textContaining('Sin turnos registrados'), findsWidgets);
  });
}
