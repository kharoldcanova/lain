import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'lain_database.dart';

/// Tipos de observación que LAIN guarda hoy.
abstract final class MemoryType {
  static const String turn = 'turn';
  static const String belief = 'belief';
  static const String preference = 'preference';
  static const String fact = 'fact';
  static const String summary = 'summary';
}

/// Relaciones entre observaciones (mismo vocabulario que Engram).
abstract final class RelationKind {
  static const String pending = 'pending';
  static const String related = 'related';
  static const String compatible = 'compatible';
  static const String scoped = 'scoped';
  static const String notConflict = 'not_conflict';
  static const String supersedes = 'supersedes';
  static const String conflictsWith = 'conflicts_with';
}

class Memory {
  const Memory({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.project,
    required this.scope,
    required this.revisionCount,
    required this.duplicateCount,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
    this.topicKey,
    this.lastSeenAt,
    this.reviewAfter,
    this.expiresAt,
    this.deletedAt,
  });

  final int id;
  final String type;
  final String title;
  final String content;
  final String project;
  final String scope;
  final String? topicKey;
  final int revisionCount;
  final int duplicateCount;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSeenAt;
  final DateTime? reviewAfter;
  final DateTime? expiresAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
}

class MemoryRelation {
  const MemoryRelation({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.relation,
    required this.judgmentStatus,
    required this.createdAt,
    this.evidence,
    this.confidence,
  });

  final int id;
  final int sourceId;
  final int targetId;
  final String relation;
  final String judgmentStatus;
  final DateTime createdAt;
  final String? evidence;
  final double? confidence;
}

class SaveOutcome {
  const SaveOutcome({
    required this.memory,
    this.deduplicated = false,
    this.relationId,
  });

  final Memory memory;
  final bool deduplicated;
  final int? relationId;
}

/// Memoria persistente estilo Engram: observaciones con FTS5 trigram,
/// deduplicación por hash, relaciones y revisión.
class MemoryStore {
  MemoryStore(this._db);

  final Database _db;

  // --- Escritura -----------------------------------------------------------

  SaveOutcome save({
    required String type,
    required String title,
    required String content,
    String? topicKey,
    String project = 'lain',
    String scope = 'project',
    String? sessionId,
    DateTime? now,
  }) {
    final at = (now ?? DateTime.now()).toUtc();
    final stamp = at.toIso8601String();
    final hash = normalizedHash('$type|$title|$content');

    final duplicate = _db.select(
      'SELECT id FROM ${LainDatabase.observationsTable} '
      'WHERE normalized_hash = ? AND deleted_at IS NULL LIMIT 1',
      <Object?>[hash],
    );
    if (duplicate.isNotEmpty) {
      final id = duplicate.first['id'] as int;
      _db.execute(
        'UPDATE ${LainDatabase.observationsTable} '
        'SET duplicate_count = duplicate_count + 1, last_seen_at = ?, updated_at = ? '
        'WHERE id = ?',
        <Object?>[stamp, stamp, id],
      );
      return SaveOutcome(memory: byId(id)!, deduplicated: true);
    }

    int? supersededId;
    var revision = 1;
    if (topicKey != null && topicKey.isNotEmpty) {
      final previous = _db.select(
        'SELECT id, content, revision_count FROM ${LainDatabase.observationsTable} '
        'WHERE topic_key = ? AND deleted_at IS NULL '
        'ORDER BY updated_at DESC LIMIT 1',
        <Object?>[topicKey],
      );
      if (previous.isNotEmpty) {
        final previousId = previous.first['id'] as int;
        revision = (previous.first['revision_count'] as int? ?? 1) + 1;
        final previousContent = previous.first['content'] as String? ?? '';
        if (normalizedHash(previousContent) != normalizedHash(content)) {
          supersededId = previousId;
        }
      }
    }

    _db.execute(
      'INSERT INTO ${LainDatabase.observationsTable} '
      '(session_id, type, title, content, project, scope, topic_key, normalized_hash, '
      ' revision_count, duplicate_count, last_seen_at, pinned, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, 0, ?, ?)',
      <Object?>[
        sessionId,
        type,
        title,
        content,
        project,
        scope,
        topicKey,
        hash,
        revision,
        stamp,
        stamp,
        stamp,
      ],
    );
    final id = _db.lastInsertRowId;

    int? relationId;
    if (supersededId != null) {
      _db.execute(
        'INSERT INTO ${LainDatabase.relationsTable} '
        '(source_id, target_id, relation, evidence, judgment_status, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          id,
          supersededId,
          RelationKind.supersedes,
          'mismo topic_key ($topicKey) con contenido distinto',
          'pending',
          stamp,
          stamp,
        ],
      );
      relationId = _db.lastInsertRowId;
    }

    return SaveOutcome(
      memory: byId(id)!,
      relationId: relationId,
    );
  }

  /// Registra el prompt del usuario para poder recuperarlo después.
  void savePrompt(
    String content, {
    String project = 'lain',
    String? sessionId,
    DateTime? now,
  }) {
    final text = content.trim();
    if (text.isEmpty) return;
    _db.execute(
      'INSERT INTO ${LainDatabase.promptsTable} (session_id, content, project, created_at) '
      'VALUES (?, ?, ?, ?)',
      <Object?>[
        sessionId,
        text,
        project,
        (now ?? DateTime.now()).toUtc().toIso8601String(),
      ],
    );
  }

  // --- Lectura -------------------------------------------------------------

  Memory? byId(int id) {
    final rows = _db.select(
      'SELECT * FROM ${LainDatabase.observationsTable} WHERE id = ?',
      <Object?>[id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Búsqueda léxica con FTS5 trigram ordenada por relevancia.
  List<Memory> search(String query, {int limit = 10}) {
    final text = query.trim();
    if (text.isEmpty) return const <Memory>[];

    final match = _ftsQuery(text);
    if (match == null) {
      return _likeSearch(text, limit);
    }

    try {
      final rows = _db.select(
        'SELECT o.* FROM ${LainDatabase.observationsFtsTable} f '
        'JOIN ${LainDatabase.observationsTable} o ON o.id = f.rowid '
        'WHERE ${LainDatabase.observationsFtsTable} MATCH ? '
        'AND o.deleted_at IS NULL '
        'AND (o.expires_at IS NULL OR o.expires_at > ?) '
        'ORDER BY bm25(${LainDatabase.observationsFtsTable}) '
        'LIMIT ?',
        <Object?>[match, _now(), limit],
      );
      return rows.map(_fromRow).toList(growable: false);
    } on SqliteException {
      // Una consulta con sintaxis no válida para FTS5 no debe romper el chat.
      return _likeSearch(text, limit);
    }
  }

  List<Memory> recent({int limit = 10}) {
    final rows = _db.select(
      'SELECT * FROM ${LainDatabase.observationsTable} '
      'WHERE deleted_at IS NULL AND (expires_at IS NULL OR expires_at > ?) '
      'ORDER BY pinned DESC, updated_at DESC LIMIT ?',
      <Object?>[_now(), limit],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  List<Memory> pinned({int limit = 10}) {
    final rows = _db.select(
      'SELECT * FROM ${LainDatabase.observationsTable} '
      'WHERE deleted_at IS NULL AND pinned = 1 '
      'ORDER BY updated_at DESC LIMIT ?',
      <Object?>[limit],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  /// Contexto para el prompt: fijadas, recientes y coincidencias de [query],
  /// sin repetir y respetando un presupuesto de caracteres.
  List<Memory> context({
    String? query,
    int limit = 10,
    int charBudget = 1500,
  }) {
    final seen = <int>{};
    final result = <Memory>[];
    var used = 0;

    void add(Memory memory) {
      if (!seen.add(memory.id)) return;
      final cost = memory.title.length + memory.content.length;
      if (used + cost > charBudget && result.isNotEmpty) return;
      used += cost;
      result.add(memory);
    }

    pinned(limit: limit).forEach(add);
    if (query != null && query.trim().isNotEmpty) {
      search(query, limit: limit).forEach(add);
    }
    recent(limit: limit).forEach(add);

    return result.take(limit).toList(growable: false);
  }

  /// Prompts previos del usuario que coinciden con [query].
  List<String> searchPrompts(String query, {int limit = 5}) {
    final text = query.trim();
    if (text.isEmpty) return const <String>[];
    try {
      final match = _ftsQuery(text);
      if (match == null) {
        final rows = _db.select(
          'SELECT content FROM ${LainDatabase.promptsTable} '
          'WHERE content LIKE ? ORDER BY created_at DESC LIMIT ?',
          <Object?>['%$text%', limit],
        );
        return rows.map((r) => r['content'] as String).toList(growable: false);
      }
      final rows = _db.select(
        'SELECT p.content FROM ${LainDatabase.promptsFtsTable} f '
        'JOIN ${LainDatabase.promptsTable} p ON p.id = f.rowid '
        'WHERE ${LainDatabase.promptsFtsTable} MATCH ? '
        'ORDER BY bm25(${LainDatabase.promptsFtsTable}) LIMIT ?',
        <Object?>[match, limit],
      );
      return rows.map((r) => r['content'] as String).toList(growable: false);
    } on SqliteException {
      return const <String>[];
    }
  }

  // --- Gestión -------------------------------------------------------------
  void pin(int id, {bool pinned = true}) {
    _db.execute(
      'UPDATE ${LainDatabase.observationsTable} '
      'SET pinned = ?, updated_at = ? WHERE id = ?',
      <Object?>[pinned ? 1 : 0, _now(), id],
    );
  }

  /// Borrado lógico: la observación deja de aparecer y de buscar.
  void delete(int id) {
    _db.execute(
      'UPDATE ${LainDatabase.observationsTable} '
      'SET deleted_at = ?, updated_at = ? WHERE id = ?',
      <Object?>[_now(), _now(), id],
    );
  }

  void setReviewAfter(int id, DateTime? when) {
    _db.execute(
      'UPDATE ${LainDatabase.observationsTable} '
      'SET review_after = ?, updated_at = ? WHERE id = ?',
      <Object?>[when?.toUtc().toIso8601String(), _now(), id],
    );
  }

  // --- Relaciones ----------------------------------------------------------

  List<MemoryRelation> relations({String? status, int limit = 50}) {
    final rows = _db.select(
      'SELECT * FROM ${LainDatabase.relationsTable} '
      '${status == null ? '' : 'WHERE judgment_status = ?'} '
      'ORDER BY created_at DESC LIMIT ?',
      <Object?>[if (status != null) status, limit],
    );
    return rows.map(_relationFromRow).toList(growable: false);
  }

  /// Resuelve una relación pendiente: aceptar (supersedes) o descartar.
  void judgeRelation(
    int relationId, {
    required String relation,
    String? evidence,
    double? confidence,
  }) {
    _db.execute(
      'UPDATE ${LainDatabase.relationsTable} '
      'SET relation = ?, judgment_status = ?, evidence = coalesce(?, evidence), '
      '    confidence = coalesce(?, confidence), updated_at = ? '
      'WHERE id = ?',
      <Object?>[relation, 'judged', evidence, confidence, _now(), relationId],
    );
  }

  // --- Utilidades ----------------------------------------------------------

  /// Hash estable del contenido normalizado (minúsculas, sin espacios extra
  /// ni puntuación) para deduplicar.
  static String normalizedHash(String input) {
    final normalized = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\wáéíóúñü]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  /// Consulta FTS5 por términos significativos (OR), como hace Engram:
  /// una pregunta completa no aparece literalmente en las memorias.
  String? _ftsQuery(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\wáéíóúñü\s]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .take(8)
        .toList();
    if (words.isEmpty) return null;
    return words.map((w) => '"$w"').join(' OR ');
  }

  List<Memory> _likeSearch(String text, int limit) {
    final rows = _db.select(
      'SELECT * FROM ${LainDatabase.observationsTable} '
      'WHERE deleted_at IS NULL AND (title LIKE ? OR content LIKE ?) '
      'ORDER BY updated_at DESC LIMIT ?',
      <Object?>['%$text%', '%$text%', limit],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  String _now() => DateTime.now().toUtc().toIso8601String();

  Memory _fromRow(Row row) => Memory(
        id: row['id'] as int,
        type: row['type'] as String? ?? '',
        title: row['title'] as String? ?? '',
        content: row['content'] as String? ?? '',
        project: row['project'] as String? ?? 'lain',
        scope: row['scope'] as String? ?? 'project',
        topicKey: row['topic_key'] as String?,
        revisionCount: row['revision_count'] as int? ?? 1,
        duplicateCount: row['duplicate_count'] as int? ?? 1,
        pinned: (row['pinned'] as int? ?? 0) == 1,
        createdAt: _parse(row['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: _parse(row['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        lastSeenAt: _parse(row['last_seen_at']),
        reviewAfter: _parse(row['review_after']),
        expiresAt: _parse(row['expires_at']),
        deletedAt: _parse(row['deleted_at']),
      );

  MemoryRelation _relationFromRow(Row row) => MemoryRelation(
        id: row['id'] as int,
        sourceId: row['source_id'] as int,
        targetId: row['target_id'] as int,
        relation: row['relation'] as String? ?? RelationKind.pending,
        judgmentStatus: row['judgment_status'] as String? ?? 'pending',
        evidence: row['evidence'] as String?,
        confidence: (row['confidence'] as num?)?.toDouble(),
        createdAt: _parse(row['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  DateTime? _parse(Object? value) =>
      value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;
}
