import 'package:flutter_test/flutter_test.dart';
import 'package:lain_mobile/data/storage/lain_database.dart';
import 'package:lain_mobile/data/storage/memory_store.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;
  late MemoryStore store;

  setUp(() {
    db = sqlite3.openInMemory();
    LainDatabase.migrate(db);
    store = MemoryStore(db);
  });

  tearDown(() => db.close());

  test('guarda una observación y la recupera por id', () {
    final outcome = store.save(
      type: MemoryType.fact,
      title: 'Ciudad del usuario',
      content: 'Vive en Caracas y le gusta el café.',
    );

    expect(outcome.deduplicated, isFalse);
    final memory = store.byId(outcome.memory.id)!;
    expect(memory.title, 'Ciudad del usuario');
    expect(memory.content, contains('Caracas'));
    expect(memory.revisionCount, 1);
    expect(memory.duplicateCount, 1);
  });

  test('deduplica contenido equivalente y cuenta repeticiones', () {
    final first = store.save(
      type: MemoryType.preference,
      title: 'Café',
      content: 'Prefiere el café sin azúcar.',
    );
    final second = store.save(
      type: MemoryType.preference,
      title: 'Café',
      content: 'Prefiere el  café sin azúcar.',
    );

    expect(second.deduplicated, isTrue);
    expect(second.memory.id, first.memory.id);
    expect(second.memory.duplicateCount, 2);
    expect(store.recent(), hasLength(1));
  });

  test('busca con FTS5 trigram ignorando mayúsculas y tildes', () {
    store.save(
      type: MemoryType.fact,
      title: 'Sobre la luna',
      content: 'La luna simboliza permanencia a través del cambio.',
    );
    store.save(
      type: MemoryType.fact,
      title: 'Sobre el mar',
      content: 'El mar le recuerda a su infancia.',
    );

    final results = store.search('luna');

    expect(results, hasLength(1));
    expect(results.first.title, 'Sobre la luna');
  });

  test('una pregunta completa recupera memorias por términos', () {
    store.save(
      type: MemoryType.fact,
      title: 'Sobre la luna',
      content: 'La luna simboliza permanencia.',
    );
    store.save(
      type: MemoryType.fact,
      title: 'Sobre el mar',
      content: 'El mar le recuerda a su infancia.',
    );

    final results = store.search('¿Qué ves en la luna?');

    expect(results, hasLength(1));
    expect(results.first.title, 'Sobre la luna');
  });

  test('una búsqueda de menos de tres caracteres cae a LIKE', () {
    store.save(
      type: MemoryType.fact,
      title: 'Gato',
      content: 'Tiene un gato llamado Miau.',
    );

    expect(store.search('ga'), hasLength(1));
  });

  test('una consulta con sintaxis inválida para FTS5 no lanza', () {
    store.save(
      type: MemoryType.fact,
      title: 'Prueba',
      content: 'Contenido de prueba.',
    );

    expect(() => store.search('"comillas sin cerrar'), returnsNormally);
  });

  test('context incluye fijadas, coincidencias y recientes sin repetir', () {
    final pinned = store.save(
      type: MemoryType.preference,
      title: 'Trato',
      content: 'Prefiere que le hable con calma.',
    );
    store.pin(pinned.memory.id);

    store.save(
      type: MemoryType.fact,
      title: 'Música',
      content: 'Escucha post-rock mientras trabaja.',
    );

    final context = store.context(query: 'post-rock');

    expect(context.first.id, pinned.memory.id);
    expect(context.map((m) => m.id).toSet(), hasLength(context.length));
    expect(context.any((m) => m.title == 'Música'), isTrue);
  });

  test('context respeta el presupuesto de caracteres', () {
    for (var i = 0; i < 10; i++) {
      store.save(
        type: MemoryType.fact,
        title: 'Dato $i',
        content: 'x' * 200,
      );
    }

    final context = store.context(charBudget: 500);

    expect(context.length, lessThan(10));
    final total = context.fold<int>(0, (sum, m) => sum + m.title.length + m.content.length);
    expect(total, lessThanOrEqualTo(500));
  });

  test('delete es lógico y saca la observación de búsqueda y listado', () {
    final saved = store.save(
      type: MemoryType.fact,
      title: 'Temporal',
      content: 'Esto se va a borrar.',
    );

    store.delete(saved.memory.id);

    expect(store.recent(), isEmpty);
    expect(store.search('borrar'), isEmpty);
    expect(store.byId(saved.memory.id)!.isDeleted, isTrue);
  });

  test('mismo topic_key con contenido distinto crea relación supersedes', () {
    final first = store.save(
      type: MemoryType.belief,
      title: 'Sobre la soledad',
      content: 'La soledad es un problema a resolver.',
      topicKey: 'belief/soledad',
    );
    final second = store.save(
      type: MemoryType.belief,
      title: 'Sobre la soledad',
      content: 'La soledad también puede ser elegida.',
      topicKey: 'belief/soledad',
    );

    expect(second.relationId, isNotNull);
    expect(second.memory.revisionCount, 2);

    final pending = store.relations(status: 'pending');
    expect(pending, hasLength(1));
    expect(pending.first.relation, RelationKind.supersedes);
    expect(pending.first.sourceId, second.memory.id);
    expect(pending.first.targetId, first.memory.id);

    store.judgeRelation(pending.first.id, relation: RelationKind.supersedes);

    expect(store.relations(status: 'pending'), isEmpty);
    expect(store.relations(status: 'judged'), hasLength(1));
  });

  test('mismo topic_key con el mismo contenido no crea relación', () {
    store.save(
      type: MemoryType.belief,
      title: 'Sobre el error',
      content: 'Equivocarse es parte de aprender.',
      topicKey: 'belief/error',
    );
    final again = store.save(
      type: MemoryType.belief,
      title: 'Sobre el error',
      content: 'Equivocarse es parte de aprender.',
      topicKey: 'belief/error',
    );

    expect(again.deduplicated, isTrue);
    expect(store.relations(), isEmpty);
  });

  test('guarda prompts y los busca', () {
    store.savePrompt('¿Qué opinas de la luna?');
    store.savePrompt('Háblame de tu día.');

    final hits = store.searchPrompts('luna');

    expect(hits, hasLength(1));
    expect(hits.first, contains('luna'));
  });
}
