import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/model_installer.dart';
import 'package:lain_mobile/data/llm/model_manager.dart';
import 'package:lain_mobile/domain/chat/chat_state.dart';
import 'package:lain_mobile/presentation/chat/chat_controller.dart';
import 'package:lain_mobile/presentation/models/model_screen.dart';

/// Controlador de chat inerte: la pantalla de modelos solo lo usa para
/// recargar el motor tras activar/importar/eliminar.
class _FakeChatController extends ChatController {
  @override
  ChatState build() => const ChatState(status: EngineStatus.ready);

  @override
  Future<void> retry() async {}
}

class _FakeInstaller implements ModelInstaller {
  _FakeInstaller({this.pickedFile});

  final String? pickedFile;

  @override
  Future<int> freeBytes() async => 8 * 1024 * 1024 * 1024;

  @override
  Future<void> install({
    required String assetPath,
    required String targetPath,
    void Function(double progress)? onProgress,
  }) async {}

  @override
  Future<String?> pickAndImport({
    required Directory targetDir,
    void Function(double progress)? onProgress,
  }) async {
    final name = pickedFile;
    if (name == null) return null;
    // Pausa breve para que el diálogo de fases se muestre antes de terminar.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final file = File('${targetDir.path}/$name')..writeAsStringSync('gguf importado');
    return file.path;
  }
}

void main() {
  late Directory root;
  late Directory sources;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lain-pantalla-');
    sources = Directory.systemTemp.createTempSync('lain-pantalla-src-');
  });

  tearDown(() {
    for (final dir in [root, sources]) {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    }
  });

  Widget app(ModelManager manager, {ModelInstaller? installer, Directory? cache}) {
    return ProviderScope(
      overrides: [
        modelManagerProvider.overrideWith((ref) async => manager),
        importCacheDirProvider.overrideWith(
          (ref) async => cache ?? Directory.systemTemp.createTempSync('lain-cache-'),
        ),
        modelInstallerProvider.overrideWithValue(installer ?? _FakeInstaller()),
        chatControllerProvider.overrideWith(_FakeChatController.new),
      ],
      child: const MaterialApp(home: ModelScreen()),
    );
  }

  /// Deja completar el I/O real del ModelManager (los testWidgets corren en
  /// FakeAsync y el I/O de dart:io necesita la zona real).
  Future<void> settleIo(WidgetTester tester) => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );

  Future<ModelManager> managerWithTwo() async {
    final manager = ModelManager(root);
    final a = await manager.importModel(
      source: File('${sources.path}/modelo-a.Q4_K_M.gguf')..writeAsStringSync('a'),
    );
    await manager.importModel(
      source: File('${sources.path}/modelo-b.Q4_K_M.gguf')..writeAsStringSync('b'),
    );
    await manager.setActiveModel(a.id);
    return manager;
  }

  testWidgets('lista los modelos registrados y marca el activo', (tester) async {
    final manager = (await tester.runAsync(managerWithTwo))!;
    await tester.runAsync(() async {
      await tester.pumpWidget(app(manager));
    });
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(find.text('modelo-a.Q4_K_M'), findsOneWidget);
    expect(find.text('modelo-b.Q4_K_M'), findsOneWidget);
    expect(find.text('Activo'), findsOneWidget);
  });

  testWidgets('activar otro modelo lo registra como activo', (tester) async {
    final manager = (await tester.runAsync(managerWithTwo))!;
    await tester.runAsync(() async {
      await tester.pumpWidget(app(manager));
    });
    await settleIo(tester);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Usar').first);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pumpAndSettle();

    final activeId = (await tester.runAsync(manager.activeModelId));
    expect(activeId, 'modelo-b.q4_k_m');
    expect(find.text('Activo'), findsOneWidget);
  });

  testWidgets('eliminar con confirmación borra solo ese modelo', (tester) async {
    final manager = (await tester.runAsync(managerWithTwo))!;
    final memory = File('${root.path}/lain.db')..writeAsStringSync('recuerdos');
    await tester.runAsync(() async {
      await tester.pumpWidget(app(manager));
    });
    await settleIo(tester);
    await tester.pumpAndSettle();

    final tileA = find.ancestor(
      of: find.text('modelo-a.Q4_K_M'),
      matching: find.byType(ListTile),
    );
    await tester.runAsync(() async {
      await tester.tap(
        find.descendant(of: tileA, matching: find.byTooltip('Eliminar modelo')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Eliminar'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(Directory('${root.path}/modelo-a.q4_k_m').existsSync(), isFalse);
    expect(Directory('${root.path}/modelo-b.q4_k_m').existsSync(), isTrue);
    expect(memory.readAsStringSync(), 'recuerdos');
  });

  testWidgets('importar un archivo lo registra y activa', (tester) async {
    final manager = ModelManager(root);
    final cache = Directory.systemTemp.createTempSync('lain-cache-');
    addTearDown(() => cache.deleteSync(recursive: true));
    final installer = _FakeInstaller(pickedFile: 'qwen3-1.7b.Q4_K_M.gguf');

    await tester.runAsync(() async {
      await tester.pumpWidget(app(manager, installer: installer, cache: cache));
    });
    await settleIo(tester);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Importar .gguf'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();
    await settleIo(tester);
    await tester.pumpAndSettle();

    final activeId = (await tester.runAsync(manager.activeModelId));
    expect(activeId, 'qwen3-1.7b.q4_k_m');
    final inventory = (await tester.runAsync(manager.inventory))!;
    expect(inventory.first.name, 'qwen3-1.7b.Q4_K_M');
    // El archivo temporal de la caché no queda suelto.
    expect(cache.listSync(), isEmpty);
    // Confirmación de éxito visible.
    expect(find.textContaining('Modelo importado y activado'), findsOneWidget);
  });

  testWidgets('cancelar la selección no cambia nada', (tester) async {
    final manager = ModelManager(root);
    await tester.runAsync(() async {
      await tester.pumpWidget(app(manager, installer: _FakeInstaller()));
    });
    await settleIo(tester);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Importar .gguf'));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pumpAndSettle();

    expect(await tester.runAsync(manager.inventory), isEmpty);
    expect(await tester.runAsync(manager.activeModelId), isNull);
    expect(find.textContaining('No hay modelos registrados'), findsOneWidget);
    expect(find.text('Importación cancelada'), findsOneWidget);
  });
}
