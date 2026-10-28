import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/app.dart';
import 'package:lain_mobile/data/llm/lain_engine.dart';
import 'package:lain_mobile/data/llm/model_installer.dart';
import 'package:lain_mobile/data/llm/model_store.dart';
import 'package:lain_mobile/data/storage/chat_store.dart';
import 'package:lain_mobile/data/storage/lain_database.dart';
import 'package:lain_mobile/data/storage/memory_store.dart';
import 'package:lain_mobile/domain/chat/chat_message.dart';
import 'package:lain_mobile/domain/chat/chat_state.dart';
import 'package:lain_mobile/presentation/chat/chat_controller.dart';
import 'package:sqlite3/sqlite3.dart';

class FakeEngine implements LainEngine {
  FakeEngine({this.pieces = const <String>['Hola, ', 'soy LAIN.']});

  final List<String> pieces;
  bool _ready = false;
  final List<String> prompts = <String>[];
  final List<String> systems = <String>[];
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
    systems.add(systemPrompt);
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


class FakeChatStore implements ChatStore {
  FakeChatStore({List<ChatMessage>? initial})
      : messages = List<ChatMessage>.of(initial ?? const <ChatMessage>[]);

  final List<ChatMessage> messages;
  int clears = 0;

  @override
  List<ChatMessage> loadRecent({int limit = 200}) =>
      List<ChatMessage>.of(messages);

  @override
  void saveTurn({required ChatMessage user, required ChatMessage lain}) {
    messages
      ..add(user)
      ..add(lain);
  }

  @override
  void clear() {
    clears++;
    messages.clear();
  }
}

MemoryStore _memoryStore() {
  final db = sqlite3.openInMemory();
  LainDatabase.migrate(db);
  return MemoryStore(db);
}

Widget _app({
  FakeEngine? engine,
  ModelLocation? location,
  ModelInstaller? installer,
  FakeChatStore? store,
  MemoryStore? memory,
}) {
  return ProviderScope(
    overrides: [
      lainEngineProvider.overrideWithValue(engine ?? FakeEngine()),
      chatStoreProvider.overrideWith((ref) async => store ?? FakeChatStore()),
      memoryStoreProvider.overrideWith((ref) async => memory ?? _memoryStore()),
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

  testWidgets('oculta el bloque think y lo muestra al expandir', (tester) async {
    const open = '\u003Cthink>';
    const close = '\u003C/think>';
    final engine = FakeEngine(
      pieces: const <String>['$open{"tono":"calido"}', close, 'Hola, soy LAIN.'],
    );
    await tester.pumpWidget(_app(engine: engine));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hola');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    expect(find.text('Hola, soy LAIN.'), findsOneWidget);
    expect(find.text('{"tono":"calido"}'), findsNothing);
    expect(find.text('Razonamiento'), findsOneWidget);

    await tester.tap(find.text('Razonamiento'));
    await tester.pumpAndSettle();

    expect(find.text('{"tono":"calido"}'), findsOneWidget);
  });

  testWidgets('restaura el historial guardado al abrir', (tester) async {
    final store = FakeChatStore(
      initial: <ChatMessage>[
        ChatMessage(
          role: ChatRole.user,
          text: 'Hola de ayer',
          createdAt: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          role: ChatRole.lain,
          text: 'Hola, soy LAIN.',
          createdAt: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      ],
    );
    await tester.pumpWidget(_app(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Hola de ayer'), findsOneWidget);
    expect(find.text('Hola, soy LAIN.'), findsOneWidget);
  });

  testWidgets('inyecta la memoria recuperada en el system prompt', (tester) async {
    final memory = _memoryStore();
    memory.save(
      type: MemoryType.fact,
      title: 'Sobre la luna',
      content: 'La luna le recuerda a su abuela.',
    );
    final engine = FakeEngine();
    await tester.pumpWidget(_app(engine: engine, memory: memory));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '¿Qué ves en la luna?');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    expect(engine.systems.last, contains('[MEMORIA]'));
    expect(engine.systems.last, contains('Sobre la luna'));
  });

  testWidgets('guarda una creencia desde el bloque think', (tester) async {
    const open = '\u003Cthink>';
    const close = '\u003C/think>';
    final engine = FakeEngine(
      pieces: const <String>[
        '$open{"thought_trace": "El usuario habla de la luna y su abuela.", '
            '"prior_belief": "La luna es solo belleza.", '
            '"belief_shift": "La luna también es memoria familiar.", '
            '"axiom_alignment_check": "Alineado."}$close',
        'Qué bonito recuerdo.',
      ],
    );
    final memory = _memoryStore();
    await tester.pumpWidget(_app(engine: engine, memory: memory));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Mi abuela y la luna');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    final beliefs = memory.search('abuela');
    expect(beliefs, hasLength(1));
    expect(beliefs.first.type, MemoryType.belief);
    expect(beliefs.first.content, contains('memoria familiar'));
    expect(memory.searchPrompts('abuela'), hasLength(1));
  });

  testWidgets('persiste cada turno en el store', (tester) async {
    final store = FakeChatStore();
    await tester.pumpWidget(_app(store: store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hola');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    expect(store.messages, hasLength(2));
    expect(store.messages.first.text, 'Hola');
    expect(store.messages.last.text, 'Hola, soy LAIN.');
  });

  testWidgets('limpiar borra el historial tras confirmar', (tester) async {
    final store = FakeChatStore(
      initial: <ChatMessage>[
        ChatMessage(
          role: ChatRole.user,
          text: 'Hola de ayer',
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    await tester.pumpWidget(_app(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Limpiar conversación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();

    expect(store.clears, 1);
    expect(find.text('Hola de ayer'), findsNothing);
    expect(find.text('Estoy aquí.'), findsOneWidget);
  });

  testWidgets('el controlador ignora mensajes vacíos', (tester) async {    await tester.pumpWidget(_app());
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
        chatStoreProvider.overrideWith((ref) async => FakeChatStore()),
        memoryStoreProvider.overrideWith((ref) async => _memoryStore()),
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
        chatStoreProvider.overrideWith((ref) async => FakeChatStore()),
        memoryStoreProvider.overrideWith((ref) async => _memoryStore()),
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
