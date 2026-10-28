import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Base de datos local de LAIN.
///
/// Usa el SQLite empaquetado por `package:sqlite3` (con FTS5 habilitado) en vez
/// del SQLite del sistema, para que la búsqueda de memoria funcione igual en
/// cualquier versión de Android.
///
/// Esquema:
/// - v1: `messages` (historial de chat).
/// - v2: `sessions`, `observations` + FTS5, `user_prompts` + FTS5 y
///   `memory_relations` (memoria estilo Engram).
class LainDatabase {
  LainDatabase._();

  static const String fileName = 'lain.db';
  static const int version = 2;

  static const String messagesTable = 'messages';
  static const String observationsTable = 'observations';
  static const String observationsFtsTable = 'observations_fts';
  static const String promptsTable = 'user_prompts';
  static const String promptsFtsTable = 'prompts_fts';
  static const String relationsTable = 'memory_relations';
  static const String sessionsTable = 'sessions';

  static Database? _instance;

  /// Abre (o reutiliza) la base de datos de la app.
  static Future<Database> open() async {
    final existing = _instance;
    if (existing != null && existing.userVersion >= version) return existing;

    final dir = await getApplicationSupportDirectory();
    final db = sqlite3.open(p.join(dir.path, fileName));
    migrate(db);
    _instance = db;
    return db;
  }

  /// Aplica el esquema hasta [version]. Público para pruebas en memoria.
  static void migrate(Database db) {
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA foreign_keys = ON');

    final current = db.userVersion;
    if (current >= version) return;
    if (current < 1) _createV1(db);
    if (current < 2) _createV2(db);
    db.userVersion = version;
  }

  static void _createV1(Database db) {
    db.execute('''
      CREATE TABLE $messagesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        text TEXT NOT NULL,
        thought TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute(
      'CREATE INDEX idx_messages_created_at ON $messagesTable (created_at)',
    );
  }

  static void _createV2(Database db) {
    db.execute('''
      CREATE TABLE $sessionsTable (
        id TEXT PRIMARY KEY,
        project TEXT NOT NULL DEFAULT 'lain',
        directory TEXT,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        summary TEXT
      )
    ''');

    db.execute('''
      CREATE TABLE $observationsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        project TEXT NOT NULL DEFAULT 'lain',
        scope TEXT NOT NULL DEFAULT 'project',
        topic_key TEXT,
        normalized_hash TEXT,
        revision_count INTEGER NOT NULL DEFAULT 1,
        duplicate_count INTEGER NOT NULL DEFAULT 1,
        last_seen_at TEXT,
        pinned INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        review_after TEXT,
        expires_at TEXT
      )
    ''');
    db.execute('CREATE INDEX idx_obs_topic ON $observationsTable (topic_key)');
    db.execute('CREATE INDEX idx_obs_type ON $observationsTable (type)');
    db.execute('CREATE INDEX idx_obs_created ON $observationsTable (created_at)');
    db.execute('CREATE INDEX idx_obs_scope ON $observationsTable (scope)');
    db.execute(
      'CREATE UNIQUE INDEX idx_obs_dedupe ON $observationsTable (normalized_hash) '
      'WHERE deleted_at IS NULL AND normalized_hash IS NOT NULL',
    );

    db.execute('''
      CREATE VIRTUAL TABLE $observationsFtsTable USING fts5(
        title, content, type, topic_key,
        tokenize='trigram',
        content='$observationsTable',
        content_rowid='id'
      )
    ''');

    db.execute('''
      CREATE TRIGGER obs_fts_insert AFTER INSERT ON $observationsTable BEGIN
        INSERT INTO $observationsFtsTable(rowid, title, content, type, topic_key)
        VALUES (new.id, new.title, new.content, new.type, coalesce(new.topic_key, ''));
      END
    ''');
    db.execute('''
      CREATE TRIGGER obs_fts_delete AFTER DELETE ON $observationsTable BEGIN
        INSERT INTO $observationsFtsTable($observationsFtsTable, rowid, title, content, type, topic_key)
        VALUES ('delete', old.id, old.title, old.content, old.type, coalesce(old.topic_key, ''));
      END
    ''');
    db.execute('''
      CREATE TRIGGER obs_fts_update AFTER UPDATE ON $observationsTable BEGIN
        INSERT INTO $observationsFtsTable($observationsFtsTable, rowid, title, content, type, topic_key)
        VALUES ('delete', old.id, old.title, old.content, old.type, coalesce(old.topic_key, ''));
        INSERT INTO $observationsFtsTable(rowid, title, content, type, topic_key)
        VALUES (new.id, new.title, new.content, new.type, coalesce(new.topic_key, ''));
      END
    ''');

    db.execute('''
      CREATE TABLE $promptsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT,
        content TEXT NOT NULL,
        project TEXT NOT NULL DEFAULT 'lain',
        created_at TEXT NOT NULL
      )
    ''');
    db.execute('CREATE INDEX idx_prompts_created ON $promptsTable (created_at)');

    db.execute('''
      CREATE VIRTUAL TABLE $promptsFtsTable USING fts5(
        content,
        tokenize='trigram',
        content='$promptsTable',
        content_rowid='id'
      )
    ''');
    db.execute('''
      CREATE TRIGGER prompt_fts_insert AFTER INSERT ON $promptsTable BEGIN
        INSERT INTO $promptsFtsTable(rowid, content) VALUES (new.id, new.content);
      END
    ''');
    db.execute('''
      CREATE TRIGGER prompt_fts_delete AFTER DELETE ON $promptsTable BEGIN
        INSERT INTO $promptsFtsTable($promptsFtsTable, rowid, content)
        VALUES ('delete', old.id, old.content);
      END
    ''');
    db.execute('''
      CREATE TRIGGER prompt_fts_update AFTER UPDATE ON $promptsTable BEGIN
        INSERT INTO $promptsFtsTable($promptsFtsTable, rowid, content)
        VALUES ('delete', old.id, old.content);
        INSERT INTO $promptsFtsTable(rowid, content) VALUES (new.id, new.content);
      END
    ''');

    db.execute('''
      CREATE TABLE $relationsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id INTEGER NOT NULL,
        target_id INTEGER NOT NULL,
        relation TEXT NOT NULL DEFAULT 'pending',
        evidence TEXT,
        confidence REAL,
        judgment_status TEXT NOT NULL DEFAULT 'pending',
        superseded_by_relation_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (source_id) REFERENCES $observationsTable(id) ON DELETE CASCADE,
        FOREIGN KEY (target_id) REFERENCES $observationsTable(id) ON DELETE CASCADE
      )
    ''');
    db.execute(
      'CREATE INDEX idx_memrel_source ON $relationsTable (source_id)',
    );
    db.execute(
      'CREATE INDEX idx_memrel_target ON $relationsTable (target_id)',
    );
    db.execute(
      'CREATE INDEX idx_memrel_status ON $relationsTable (judgment_status)',
    );
  }

  /// Cierra la conexión activa (pruebas y cierre de la app).
  static void close() {
    _instance?.close();
    _instance = null;
  }
}
