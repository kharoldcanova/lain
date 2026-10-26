import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/app.dart';
import 'package:lain_mobile/data/llm/lain_engine.dart';
import 'package:lain_mobile/data/llm/model_store.dart';
import 'package:lain_mobile/presentation/chat/chat_controller.dart';

class FakeEngine implements LainEngine {
  FakeEngine({this.pieces = const <String>['Hola, ', 'soy LAIN.']});

  final List<String> pieces;
  bool _ready = false;
  final List<String> prompts = <String>[];

  @override
  bool get isReady => _ready;

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
    prompts.add(userMessage);
    for (final piece in pieces) {
      yield piece;
    }
  }

  @override
  Future<void> dispose() async {}
}

Widget _app({FakeEngine? engine, ModelLocation? location}) {
  return ProviderScope(
    overrides: [
      lainEngineProvider.overrideWithValue(engine ?? FakeEngine()),
      localInferenceProvider.overrideWithValue(true),
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

  testWidgets('sin GGUF avisa de la ruta donde debe copiarse', (tester) async {
    await tester.pumpWidget(_app(
      location: const ModelLocation(expectedPath: '/tmp/models/model.gguf'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Falta el modelo'), findsOneWidget);
    expect(find.textContaining('/tmp/models/model.gguf'), findsOneWidget);
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
}
