# Memoria persistente estilo Engram en LAIN (Flutter)

Feature: replicar en la app el comportamiento de memoria de Engram (observaciones,
FTS5 trigram, sesiones, prompts, relaciones y revisión) usando solo lo disponible
en Flutter, 100 % offline.

Rama: `main` (commits por slice). Runner: `flutter test` / `flutter analyze`.

## Specs

- **S1 — Motor SQLite propio.** La app usa `package:sqlite3` (SQLite empaquetado con
  `SQLITE_ENABLE_FTS5`) en vez del SQLite del sistema; `sqflite` deja de ser dependencia.
  Las pruebas abren `sqlite3.openInMemory()` y no necesitan emulador.
- **S2 — Esquema de memoria.** Base `lain.db` con `messages` (historial de chat, ya
  existente), `sessions`, `observations`, `observations_fts` (FTS5 `tokenize='trigram'`,
  `content='observations'`), `user_prompts`, `prompts_fts` y `memory_relations`.
  Migración desde la v1 sin perder mensajes (`PRAGMA user_version`).
- **S3 — Guardado con deduplicación.** `MemoryStore.save()` calcula `normalized_hash`
  del contenido normalizado; si ya existe una observación viva con ese hash incrementa
  `duplicate_count` y `last_seen_at` en vez de duplicar; si el mismo `topic_key` cambia
  el contenido, incrementa `revision_count` y actualiza `updated_at`.
- **S4 — Búsqueda.** `MemoryStore.search(query, limit)` usa FTS5 sobre
  `title`, `content`, `type` y `topic_key`, ordenado por relevancia BM25, excluyendo
  `deleted_at` no nulo y respetando `expires_at`.
- **S5 — Contexto para el prompt.** `MemoryStore.context()` devuelve pinned primero,
  luego las observaciones más recientes y luego los `top-k` de la consulta actual, sin
  repetir filas, con un presupuesto de caracteres.
- **S6 — Captura desde el chat.** Cada turno guarda el prompt del usuario
  (`user_prompts`) y, si el bloque `think` trae JSON con `prior_belief` y
  `belief_shift`, una observación tipo `belief` con `topic_key` derivado del título.
  Un JSON inválido no rompe el turno ni impide guardar el mensaje.
- **S7 — Relaciones y conflicto.** Al guardar una observación con el mismo `topic_key`
  cuyo contenido difiere, se registra una relación `supersedes` con
  `judgment_status='pending'`; el usuario puede confirmarla o rechazarla.
- **S8 — Revisión en la app.** Pantalla de memorias: lista con búsqueda, pin/unpin,
  borrado (soft delete) y resolución de relaciones pendientes.

Fuera de alcance (no se replican): sincronización en la nube, tombstones de sync,
chunks/embeddings vectoriales, versiones históricas de observación.

## Tasks

| ID | Spec | Ruta | Estado |
|---|---|---|---|
| T1 | S1 | inline | hecho |
| T2 | S2 | inline | hecho |
| T3 | S3 | inline | hecho |
| T4 | S4 | inline | hecho |
| T5 | S5 | inline | hecho |
| T6 | S6 | inline | hecho |
| T7 | S7 | inline | hecho |
| T8 | S8 | inline | hecho |

## Log

### L1 — Petición original (2026-10-28)

> engram es la solucion, tenemos que replicar ese comportamiento en nuestra app, usando lo que tenemos a nuestra disposicion en flutter

Decisiones del usuario en la misma sesión: migrar a `package:sqlite3` y hacer la
«Réplica completa» (núcleo + recall + relaciones + pantalla de revisión).

### Evidencia: esquema real de Engram 3.4.0 (`~/.engram/engram.db`)

- `observations`: `type, title, content, project, scope, topic_key, normalized_hash,
  revision_count, duplicate_count, last_seen_at, pinned, created_at, updated_at,
  deleted_at, review_after, expires_at, embedding BLOB`.
- `observations_fts`: FTS5 `tokenize='trigram'`, `content='observations'`, con triggers
  de inserción/actualización/borrado.
- `memory_relations`: `source_id, target_id, relation, evidence, confidence,
  judgment_status, superseded_by_relation_id`; relaciones observadas: `related`,
  `not_conflict`, `compatible`, `scoped`, `supersedes`.
- `sessions`, `user_prompts` + `prompts_fts`.
- **Sin embeddings en uso**: 103 observaciones, 0 con `embedding`; la búsqueda es léxica
  (FTS5 trigram), no vectorial.

### Evidencia de cierre (2026-10-28)

- `flutter analyze`: `No issues found!`.
- `flutter test`: 44 pruebas en verde — `chat_store_test` (4), `think_parser_test` (6),
  `memory_store_test` (12), `belief_capture_test` (5), `memory_screen_test` (6),
  `widget_test` (11).
- FTS5 `trigram` verificado contra el SQLite empaquetado por `package:sqlite3`
  (no el del sistema), en pruebas de host.
- Migración v1 → v2 cubierta por `PRAGMA user_version`; los mensajes existentes se
  conservan.
