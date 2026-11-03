import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/llm/hf_client.dart';
import 'package:lain_mobile/data/llm/hf_url.dart';
import 'package:lain_mobile/data/llm/model_downloader.dart';
import 'package:lain_mobile/data/llm/model_installer.dart';
import 'package:lain_mobile/data/llm/model_manager.dart';
import 'package:lain_mobile/domain/chat/chat_state.dart';
import 'package:lain_mobile/presentation/chat/chat_controller.dart';
import 'package:lain_mobile/presentation/models/download_providers.dart';
import 'package:lain_mobile/presentation/models/model_catalog_screen.dart';
import 'package:lain_mobile/presentation/models/model_screen.dart';

import 'support/gguf_fixture.dart';

class _FakeChatController extends ChatController {
  @override
  ChatState build() => const ChatState(status: EngineStatus.ready);

  @override
  Future<void> retry() async {}
}

class _FakeInstaller implements ModelInstaller {
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
  }) async =>
      null;
}

class _FakeHfClient extends HfClient {
  final List<HfReference> requests = <HfReference>[];

  @override
  Future<List<HfFile>> resolve(HfReference reference) async {
    requests.add(reference);
    final name = reference.file ?? 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf';
    return <HfFile>[
      HfFile(repo: reference.repo, name: name, sizeBytes: 2048),
    ];
  }
}

class _FakeDownloader extends ModelDownloader {
  _FakeDownloader(this.root) : super(rootDir: root);

  final Directory root;
  final List<String> downloads = <String>[];

  @override
  Future<DownloadedFile> download({
    required HfFile file,
    void Function(DownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
    Future<int> Function()? freeBytes,
  }) async {
    downloads.add(file.name);
    final architecture = file.name.contains('LFM3') ? 'lfm3' : 'lfm2';
    final bytes = buildGguf(architecture: architecture);
    final id =
        file.fileName.replaceAll('.gguf', '').toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9._-]+'),
              '-',
            );
    final staging = Directory('${root.path}/.download-$id')
      ..createSync(recursive: true);
    final target = File('${staging.path}/${file.fileName}')
      ..writeAsBytesSync(bytes);
    onProgress?.call(DownloadProgress(
      receivedBytes: bytes.length,
      totalBytes: bytes.length,
    ));
    return DownloadedFile(
      staging: staging,
      file: target,
      sha256: sha256.convert(bytes).toString(),
      sizeBytes: bytes.length,
    );
  }
}

void main() {
  late Directory root;
  late ModelManager manager;
  late _FakeHfClient client;
  late _FakeDownloader downloader;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lain-cat-');
    manager = ModelManager(root);
    client = _FakeHfClient();
    downloader = _FakeDownloader(root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Widget app() => ProviderScope(
        overrides: [
          modelManagerProvider.overrideWith((ref) async => manager),
          modelInstallerProvider.overrideWithValue(_FakeInstaller()),
          chatControllerProvider.overrideWith(_FakeChatController.new),
          hfClientProvider.overrideWithValue(client),
          modelDownloaderProvider.overrideWith((ref) async => downloader),
        ],
        child: const MaterialApp(home: ModelCatalogScreen()),
      );

  Future<void> settleIo(WidgetTester tester) => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );

  testWidgets('lista el catálogo y marca LFM3 como no activable',
      (tester) async {
    await tester.runAsync(() async => tester.pumpWidget(app()));
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(find.text('LFM2.5-1.2B-Instruct'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('LFM3-1.7B'),
      find.byType(ListView),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(find.text('LFM3-1.7B'), findsOneWidget);
    expect(
      find.textContaining('Requiere una versión nueva del motor'),
      findsWidgets,
    );
  });

  testWidgets('descargar un modelo compatible lo registra y activa',
      (tester) async {
    await tester.runAsync(() async => tester.pumpWidget(app()));
    await settleIo(tester);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Descargar').first);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(downloader.downloads, contains('LFM2.5-1.2B-Instruct-Q4_K_M.gguf'));
    final inventory = (await tester.runAsync(manager.inventory))!;
    expect(inventory.single.id, 'lfm2.5-1.2b-instruct-q4_k_m');
    expect(inventory.single.architecture, 'lfm2');
    expect((await tester.runAsync(manager.activeModelId)),
        'lfm2.5-1.2b-instruct-q4_k_m');
    expect(find.textContaining('instalado y activo'), findsOneWidget);
  });

  testWidgets('descargar LFM3 lo instala sin activarlo', (tester) async {
    await tester.runAsync(() async => tester.pumpWidget(app()));
    await settleIo(tester);
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('LFM3-1.7B'),
      find.byType(ListView),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('LFM3-1.7B'),
            matching: find.byType(Card),
          ),
          matching: find.text('Descargar'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final inventory = (await tester.runAsync(manager.inventory))!;
    expect(inventory.single.architecture, 'lfm3');
    expect(await tester.runAsync(manager.activeModelId), isNull);
    expect(
      find.textContaining('requiere una versión nueva del motor'),
      findsWidgets,
    );
  });

  testWidgets('un modelo instalado se puede eliminar', (tester) async {
    // Instala directamente con el manager antes de abrir la pantalla.
    await tester.runAsync(() async {
      final bytes = buildGguf(architecture: 'lfm2');
      final staging = Directory('${root.path}/.download-lfm2.5-1.2b-instruct-q4_k_m')
        ..createSync(recursive: true);
      final file =
          File('${staging.path}/LFM2.5-1.2B-Instruct-Q4_K_M.gguf')
            ..writeAsBytesSync(bytes);
      await manager.registerDownloaded(
        staging: staging,
        file: file,
        sha256: sha256.convert(bytes).toString(),
      );
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(app());
    });
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(find.text('Instalado'), findsWidgets);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Eliminar modelo').first);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Eliminar'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(await tester.runAsync(manager.inventory), isEmpty);
  });

  testWidgets('descarga por URL desde el diálogo', (tester) async {
    await tester.runAsync(() async => tester.pumpWidget(app()));
    await settleIo(tester);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Descargar desde una URL'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'https://huggingface.co/org/repo/resolve/main/otro-Q4_K_M.gguf',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Buscar'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(client.requests.single.file, 'otro-Q4_K_M.gguf');
    final inventory = (await tester.runAsync(manager.inventory))!;
    expect(inventory.single.id, 'otro-q4_k_m');
  });

  testWidgets('una URL inválida muestra el error en el diálogo', (tester) async {
    await tester.runAsync(() async => tester.pumpWidget(app()));
    await settleIo(tester);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Descargar desde una URL'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'http://huggingface.co/org/repo');
    await tester.runAsync(() async {
      await tester.tap(find.text('Buscar'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('solo se aceptan'), findsOneWidget);
    expect(client.requests, isEmpty);
  });
}
