import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/core/theme.dart';
import 'package:lain_mobile/data/storage/lain_database.dart';
import 'package:lain_mobile/data/storage/memory_store.dart';
import 'package:lain_mobile/presentation/chat/chat_controller.dart';
import 'package:lain_mobile/presentation/memory/memory_screen.dart';
import 'package:sqlite3/sqlite3.dart';

MemoryStore _store() {
  final db = sqlite3.openInMemory();
  LainDatabase.migrate(db);
  return MemoryStore(db);
}

Widget _app(MemoryStore store) => ProviderScope(
      overrides: [
        memoryStoreProvider.overrideWith((ref) async => store),
      ],
      child: MaterialApp(theme: lainTheme(), home: const MemoryScreen()),
    );

void main() {
  testWidgets('lista las memorias guardadas', (tester) async {
    final store = _store()
      ..save(type: MemoryType.fact, title: 'Sobre la luna', content: 'Le recuerda a su abuela.');

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    expect(find.text('Sobre la luna'), findsOneWidget);
    expect(find.textContaining('abuela'), findsOneWidget);
  });

  testWidgets('muestra el estado vacío', (tester) async {
    await tester.pumpWidget(_app(_store()));
    await tester.pumpAndSettle();

    expect(find.text('Todavía no hay recuerdos guardados.'), findsOneWidget);
  });

  testWidgets('el buscador filtra por término', (tester) async {
    final store = _store()
      ..save(type: MemoryType.fact, title: 'Sobre la luna', content: 'Contemplación.')
      ..save(type: MemoryType.fact, title: 'Sobre el mar', content: 'Infancia.');

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'luna');
    await tester.pumpAndSettle();

    expect(find.text('Sobre la luna'), findsOneWidget);
    expect(find.text('Sobre el mar'), findsNothing);
  });

  testWidgets('fijar una memoria la mantiene al limpiar el buscador', (tester) async {
    final store = _store()
      ..save(type: MemoryType.preference, title: 'Trato', content: 'Háblale con calma.');

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Fijar'));
    await tester.pumpAndSettle();

    expect(store.recent().first.pinned, isTrue);
  });

  testWidgets('olvidar una memoria la saca de la lista', (tester) async {
    final store = _store()
      ..save(type: MemoryType.fact, title: 'Temporal', content: 'Se borra.');

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Olvidar'));
    await tester.pumpAndSettle();

    expect(find.text('Temporal'), findsNothing);
    expect(find.text('Todavía no hay recuerdos guardados.'), findsOneWidget);
  });

  testWidgets('resuelve una relación pendiente desde la pantalla', (tester) async {
    final store = _store()
      ..save(
        type: MemoryType.belief,
        title: 'Sobre la soledad',
        content: 'Es un problema.',
        topicKey: 'belief/soledad',
      )
      ..save(
        type: MemoryType.belief,
        title: 'Sobre la soledad',
        content: 'También puede ser elegida.',
        topicKey: 'belief/soledad',
      );

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    expect(find.text('Hay una creencia que cambió'), findsOneWidget);

    await tester.tap(find.text('Mantener la nueva'));
    await tester.pumpAndSettle();

    expect(find.text('Hay una creencia que cambió'), findsNothing);
    expect(store.relations(status: 'pending'), isEmpty);
  });
}
