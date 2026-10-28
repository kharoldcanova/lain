import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base de datos local de LAIN.
///
/// Hoy guarda el historial del chat. El RAG (chunks + embeddings) entrará en
/// su propia tabla con una migración nueva, no en la v1.
class LainDatabase {
  LainDatabase._();

  static const String fileName = 'lain.db';
  static const int version = 1;

  static const String messagesTable = 'messages';

  static Database? _instance;

  /// Abre (o reutiliza) la base de datos de la app.
  static Future<Database> open() async {
    final existing = _instance;
    if (existing != null && existing.isOpen) return existing;

    final path = p.join(await getDatabasesPath(), fileName);
    final db = await openDatabase(
      path,
      version: version,
      onCreate: createSchema,
    );
    _instance = db;
    return db;
  }

  /// Esquema inicial. Público para poder abrirlo con SQLite real en pruebas.
  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $messagesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        text TEXT NOT NULL,
        thought TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_messages_created_at ON $messagesTable (created_at)',
    );
  }

  /// Cierra la conexión activa (pruebas y cierre de la app).
  static Future<void> close() async {
    await _instance?.close();
    _instance = null;
  }
}
