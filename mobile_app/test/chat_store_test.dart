import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/storage/chat_store.dart';
import 'package:lain_mobile/data/storage/lain_database.dart';
import 'package:lain_mobile/domain/chat/chat_message.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;
  late SqliteChatStore store;

  setUp(() {
    db = sqlite3.openInMemory();
    LainDatabase.migrate(db);
    store = SqliteChatStore(db);
  });

  tearDown(() {
    db.close();
  });

  ChatMessage msg(
    ChatRole role,
    String text, {
    String? thought,
    required DateTime at,
  }) =>
      ChatMessage(role: role, text: text, thought: thought, createdAt: at);

  test('guarda un turno y lo devuelve en orden cronológico', () {
    final base = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    store.saveTurn(
      user: msg(ChatRole.user, 'Hola', at: base),
      lain: msg(
        ChatRole.lain,
        'Hola, soy LAIN.',
        thought: '{"tono":"calido"}',
        at: base.add(const Duration(seconds: 1)),
      ),
    );

    final history = store.loadRecent();

    expect(history, hasLength(2));
    expect(history.first.isUser, isTrue);
    expect(history.first.text, 'Hola');
    expect(history.last.isUser, isFalse);
    expect(history.last.text, 'Hola, soy LAIN.');
    expect(history.last.thought, '{"tono":"calido"}');
  });

  test('devuelve solo los mensajes más recientes cuando se limita', () {
    final base = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    for (var i = 0; i < 5; i++) {
      store.saveTurn(
        user: msg(ChatRole.user, 'u$i', at: base.add(Duration(minutes: i))),
        lain: msg(
          ChatRole.lain,
          'l$i',
          at: base.add(Duration(minutes: i, seconds: 1)),
        ),
      );
    }

    final history = store.loadRecent(limit: 4);

    expect(
      history.map((m) => m.text).toList(),
      <String>['u3', 'l3', 'u4', 'l4'],
    );
  });

  test('clear borra todo el historial', () {
    final now = DateTime.now();
    store.saveTurn(
      user: msg(ChatRole.user, 'Hola', at: now),
      lain: msg(ChatRole.lain, 'Hola.', at: now),
    );

    store.clear();

    expect(store.loadRecent(), isEmpty);
  });

  test('thought nulo se conserva como nulo', () {
    final now = DateTime.now();
    store.saveTurn(
      user: msg(ChatRole.user, 'Hola', at: now),
      lain: msg(ChatRole.lain, 'Sin razonamiento', at: now),
    );

    final history = store.loadRecent();

    expect(history.last.thought, isNull);
    expect(history.last.hasThought, isFalse);
  });
}
