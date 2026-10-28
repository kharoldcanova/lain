import 'package:sqflite/sqflite.dart';

import '../../domain/chat/chat_message.dart';
import 'lain_database.dart';

/// Persistencia del historial de conversación.
abstract interface class ChatStore {
  /// Mensajes más recientes en orden cronológico (viejo → nuevo).
  Future<List<ChatMessage>> loadRecent({int limit = 200});

  /// Guarda un turno completo en una sola transacción.
  Future<void> saveTurn({
    required ChatMessage user,
    required ChatMessage lain,
  });

  /// Borra todo el historial.
  Future<void> clear();
}

class SqliteChatStore implements ChatStore {
  SqliteChatStore(this._db);

  final Database _db;

  @override
  Future<List<ChatMessage>> loadRecent({int limit = 200}) async {
    final rows = await _db.query(
      LainDatabase.messagesTable,
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.reversed.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> saveTurn({
    required ChatMessage user,
    required ChatMessage lain,
  }) async {
    await _db.transaction((txn) async {
      await txn.insert(
        LainDatabase.messagesTable,
        _toRow(user),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        LainDatabase.messagesTable,
        _toRow(lain),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<void> clear() async {
    await _db.delete(LainDatabase.messagesTable);
  }

  Map<String, Object?> _toRow(ChatMessage message) => <String, Object?>{
        'role': message.isUser ? 'user' : 'lain',
        'text': message.text,
        'thought': message.thought,
        'created_at': message.createdAt.millisecondsSinceEpoch,
      };

  ChatMessage _fromRow(Map<String, Object?> row) => ChatMessage(
        role: row['role'] == 'user' ? ChatRole.user : ChatRole.lain,
        text: row['text'] as String? ?? '',
        thought: row['thought'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int? ?? 0,
        ),
      );
}
