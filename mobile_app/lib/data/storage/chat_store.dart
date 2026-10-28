import 'package:sqlite3/sqlite3.dart';

import '../../domain/chat/chat_message.dart';
import 'lain_database.dart';

/// Persistencia del historial de conversación.
abstract interface class ChatStore {
  /// Mensajes más recientes en orden cronológico (viejo → nuevo).
  List<ChatMessage> loadRecent({int limit = 200});

  /// Guarda un turno completo en una sola transacción.
  void saveTurn({required ChatMessage user, required ChatMessage lain});

  /// Borra todo el historial.
  void clear();
}

class SqliteChatStore implements ChatStore {
  SqliteChatStore(this._db);

  final Database _db;

  @override
  List<ChatMessage> loadRecent({int limit = 200}) {
    final rows = _db.select(
      'SELECT role, text, thought, created_at FROM ${LainDatabase.messagesTable} '
      'ORDER BY created_at DESC, id DESC LIMIT ?',
      <Object?>[limit],
    );
    return rows.reversed.map(_fromRow).toList(growable: false);
  }

  @override
  void saveTurn({required ChatMessage user, required ChatMessage lain}) {
    _db.execute('BEGIN');
    try {
      _insert(user);
      _insert(lain);
      _db.execute('COMMIT');
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  void clear() {
    _db.execute('DELETE FROM ${LainDatabase.messagesTable}');
  }

  void _insert(ChatMessage message) {
    _db.execute(
      'INSERT INTO ${LainDatabase.messagesTable} (role, text, thought, created_at) '
      'VALUES (?, ?, ?, ?)',
      <Object?>[
        message.isUser ? 'user' : 'lain',
        message.text,
        message.thought,
        message.createdAt.millisecondsSinceEpoch,
      ],
    );
  }

  ChatMessage _fromRow(Row row) => ChatMessage(
        role: row['role'] == 'user' ? ChatRole.user : ChatRole.lain,
        text: row['text'] as String? ?? '',
        thought: row['thought'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int? ?? 0,
        ),
      );
}
