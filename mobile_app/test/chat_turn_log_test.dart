import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/diagnostics/turn_log.dart';
import 'package:lain_mobile/data/llm/lain_engine.dart';
import 'package:lain_mobile/data/llm/lain_native.dart';
import 'package:lain_mobile/core/experimental.dart';
import 'package:lain_mobile/data/llm/model_store.dart';
import 'package:lain_mobile/domain/chat/chat_state.dart';
import 'package:lain_mobile/presentation/chat/chat_controller.dart';

class _FakeEngine implements LainEngine, LainMetricsSource {
  _FakeEngine({this.metrics});

  final LainTurnMetrics? metrics;
  bool _ready = false;

  @override
  bool get isReady => _ready;

  @override
  LainTurnMetrics? get lastMetrics => metrics;

  @override
  String? get backendName => 'libggml-cpu-android_armv8.2_2.so';

  @override
  bool get instrumented => metrics?.instrumented ?? false;

  @override
  Future<void> loadModel(String path, {int contextSize = 2048, int threads = 4}) async {
    _ready = true;
  }

  @override
  Stream<String> generate({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 512,
    double temperature = 0.7,
    double topP = 0.9,
    int seed = 42,
  }) async* {
    yield 'Hola';
    yield ' mundo';
  }

  @override
  Future<void> dispose() async {}
}

class _PlainEngine implements LainEngine {
  @override
  bool get isReady => false;

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
  }) async* {
    yield 'respuesta';
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory dir;
  late TurnLog log;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lain-chat-log-');
    log = TurnLog(directory: () async => dir);
    File('${dir.path}/model.gguf').writeAsStringSync('gguf');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  ProviderContainer containerFor(LainEngine engine) {
    final container = ProviderContainer(
      overrides: [
        lainEngineProvider.overrideWithValue(engine),
        experimentalModeProvider.overrideWithValue(true),
        localInferenceProvider.overrideWithValue(true),
        modelLocatorProvider.overrideWithValue(
          () async => ModelLocation(
            expectedPath: '${dir.path}/model.gguf',
            file: File('${dir.path}/model.gguf'),
          ),
        ),
        systemPromptProvider.overrideWith((ref) async => 'sistema'),
        turnLogProvider.overrideWithValue(log),
        chatStoreProvider.overrideWith((ref) async => throw StateError('sin db')),
        memoryStoreProvider.overrideWith((ref) async => throw StateError('sin db')),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> waitReady(ProviderContainer container) async {
    for (var i = 0; i < 100; i++) {
      if (container.read(chatControllerProvider).status == EngineStatus.ready) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('el motor no quedó listo');
  }

  test('un turno con motor instrumentado escribe métricas en el JSONL', () async {
    final engine = _FakeEngine(
      metrics: const LainTurnMetrics(
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
      ),
    );
    final container = containerFor(engine);
    await waitReady(container);

    await container.read(chatControllerProvider.notifier).send('hola');

    final turns = await log.read();
    expect(turns, hasLength(1));
    final turn = turns.single;
    expect(turn['instrumented'], isTrue);
    expect(turn['backend'], 'libggml-cpu-android_armv8.2_2.so');
    expect(turn['model'], 'model.gguf');
    expect(turn['ttft_ms'], 1800);
    expect(turn['prefill_ms'], 1500);
    expect(turn['decode_ms'], 2000);
    expect(turn['n_prompt'], 480);
    expect(turn['n_generated'], 32);
    expect(turn['tok_per_s'], 16.0);
    expect(turn['n_threads'], 4);
    expect(turn['inference_error'], isNull);
    expect(turn['rss_mb'], isA<double>());
  });

  test('sin instrumentación nativa se registra igual el turno', () async {
    final container = containerFor(_PlainEngine());
    await waitReady(container);

    await container.read(chatControllerProvider.notifier).send('hola');

    final turn = (await log.read()).single;
    expect(turn['instrumented'], isFalse);
    expect(turn['backend'], isNull);
    expect(turn['ttft_ms'], isA<int>());
    expect(turn['n_prompt'], isNull);
    expect(turn['total_ms'], isA<int>());
  });

  test('un error de inferencia se registra sin romper el chat', () async {
    final engine = _FailingEngine();
    final container = containerFor(engine);
    await waitReady(container);

    await container.read(chatControllerProvider.notifier).send('hola');

    final turn = (await log.read()).single;
    expect(turn['inference_error'], contains('falló'));
    expect(
      container.read(chatControllerProvider).messages.last.text,
      contains('No pude responder'),
    );
  });
}

class _FailingEngine extends _FakeEngine {
  @override
  Stream<String> generate({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 512,
    double temperature = 0.7,
    double topP = 0.9,
    int seed = 42,
  }) async* {
    throw const LainException('falló el motor');
  }
}
