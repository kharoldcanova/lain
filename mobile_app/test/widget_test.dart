import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/app.dart';
import 'package:lain_mobile/data/llm/lain_engine.dart';
import 'package:lain_mobile/data/llm/model_installer.dart';
import 'package:lain_mobile/data/llm/model_store.dart';
import 'package:lain_mobile/domain/chat/chat_state.dart';
import 'package:lain_mobile/presentation/chat/chat_controller.dart';

class FakeEngine implements LainEngine {
  FakeEngine({this.pieces = const <String>['Hola, ', 'soy LAIN.']});

  final List<String> pieces;
  bool _ready = false;
  final List<String> prompts = <String>[];
  final List<String> loadedPaths = <String>[];

  @override
  bool get isReady => _ready;

  @override
  Future<void> loadModel(String path, {int contextSize = 2048, int threads = 4}) async {
    _ready = true;
    loadedPaths.add(path);
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
    prompts.add(userMessage);
    for (final piece in pieces) {
      yield piece;
    }
  }

  @override
  Future<void> dispose() async {}
}

class FakeInstaller implements ModelInstaller {
  FakeInstaller({this.failure, this.copyFile = true});

  final String? failure;
  final bool copyFile;
  final List<String> assets = <String>[];
  final List<String> targets = <String>[];
  final List<double> progress = <double>[];

  @override
  Future<void> install({
    required String assetPath,
    required String targetPath,
    void Function(double progress)? onProgress,
  }) async {
    assets.add(assetPath);
    targets.add(targetPath);
    if (failure != null) {
      throw ModelInstallException(failure!);
    }
    if (copyFile) {
      final file = File(targetPath);
      await file.parent.create(recursive: true);
      await file.writeAsString('gguf simulado');
    }
    if (onProgress != null) {
      await Future<void>.microtask(() => onProgress(1.0));
      progress.add(1.0);
    }
  }
}

Widget _app({
  FakeEngine? engine,
  ModelLocation? location,
  ModelInstaller? installer,
}) {
  return ProviderScope(
    overrides: [
      lainEngineProvider.overrideWithValue(engine ?? FakeEngine()),
      localInferenceProvider.overrideWithValue(true),
      modelInstallerProvider.overrideWithValue(installer ?? FakeInstaller()),
      modelLocatorProvider.overrideWithValue(
        () async =>
            location ??
            ModelLocation(
              expectedPath: '/tmp/model.gguf',
              file: File('/tmp/model.gguf'),
            ),
      ),
      systemPromptProvider.overrideWith((ref) async => 'Eres LAIN.'),
    ],
    child: const LainApp(),
  );
}

void main() {
  testWidgets('arranca en estado vacío cuando el motor está listo', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Estoy aquí.'), findsOneWidget);
    expect(find.text('Escribe un mensaje…'), findsOneWidget);
  });

  testWidgets('enviar un mensaje muestra la respuesta del motor', (tester) async {
    final engine = FakeEngine();
    await tester.pumpWidget(_app(engine: engine));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hola, LAIN');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    expect(find.text('Hola, LAIN'), findsOneWidget);
    expect(find.text('Hola, soy LAIN.'), findsOneWidget);
    expect(engine.prompts, <String>['Hola, LAIN']);
  });

  testWidgets('el controlador ignora mensajes vacíos', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LainApp)),
    );
    await container.read(chatControllerProvider.notifier).send('   ');

    expect(container.read(chatControllerProvider).messages, isEmpty);
  });

  // --- Pruebas del controlador con ProviderContainer (sin widget tree) ---

  test('copia el modelo empaquetado la primera vez y lo carga', () async {
    final dir = await Directory.systemTemp.createTemp('lain-test');
    addTearDown(() => dir.delete(recursive: true));
    final target = '${dir.path}/models/$modelFileName';

    final container = ProviderContainer(
      overrides: [
        lainEngineProvider.overrideWithValue(FakeEngine()),
        localInferenceProvider.overrideWithValue(true),
        modelInstallerProvider.overrideWithValue(FakeInstaller()),
        modelLocatorProvider.overrideWithValue(
          () async => ModelLocation(expectedPath: target),
        ),
        systemPromptProvider.overrideWith((ref) async => 'Eres LAIN.'),
      ],
    );
    addTearDown(container.dispose);

    final engine = container.read(lainEngineProvider) as FakeEngine;
    final installer = container.read(modelInstallerProvider) as FakeInstaller;

    // Espera a que _init() resuelva el estado (loading/preparingModel -> ready/error).
    final state = await _awaitState(container);

    expect(installer.assets, <String>['assets/models/$modelFileName']);
    expect(installer.targets, <String>[target]);
    expect(engine.loadedPaths, <String>[target]);
    expect(state.status, EngineStatus.ready);
  });

  test('si la copia falla muestra error del motor', () async {
    final container = ProviderContainer(
      overrides: [
        lainEngineProvider.overrideWithValue(FakeEngine()),
        localInferenceProvider.overrideWithValue(true),
        modelInstallerProvider.overrideWithValue(
          FakeInstaller(failure: 'sin espacio en el dispositivo'),
        ),
        modelLocatorProvider.overrideWithValue(
          () async => const ModelLocation(
            expectedPath: '/tmp/models/model.gguf',
          ),
        ),
        systemPromptProvider.overrideWith((ref) async => 'Eres LAIN.'),
      ],
    );
    addTearDown(container.dispose);

    final state = await _awaitState(container);

    expect(state.status, EngineStatus.error);
    expect(state.error, contains('sin espacio'));
  });
}

/// Espera hasta que el chat deje de estar en estados transitorios.
Future<ChatState> _awaitState(ProviderContainer container) async {
  final completer = Completer<ChatState>();
  container.listen(chatControllerProvider, (_, next) {
    if (!completer.isCompleted &&
        next.status != EngineStatus.loading &&
        next.status != EngineStatus.preparingModel) {
      completer.complete(next);
    }
  });
  return completer.future.timeout(const Duration(seconds: 10));
}
