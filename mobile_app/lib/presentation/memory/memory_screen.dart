import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/storage/memory_store.dart';
import '../chat/chat_controller.dart';

/// Lista, busca y administra la memoria persistente de LAIN.
class MemoryScreen extends ConsumerWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(memoryStoreProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Memoria')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No se pudo abrir la memoria.\n$error'),
          ),
        ),
        data: (store) => _MemoryBody(store: store),
      ),
    );
  }
}

class _MemoryBody extends StatefulWidget {
  const _MemoryBody({required this.store});

  final MemoryStore store;

  @override
  State<_MemoryBody> createState() => _MemoryBodyState();
}

class _MemoryBodyState extends State<_MemoryBody> {
  final _query = TextEditingController();
  late List<Memory> _items;
  late List<MemoryRelation> _pending;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _reload() {
    final text = _query.text.trim();
    _items = text.isEmpty ? widget.store.recent(limit: 100) : widget.store.search(text);
    _pending = widget.store.relations(status: 'pending');
    setState(() {});
  }

  void _togglePin(Memory memory) {
    widget.store.pin(memory.id, pinned: !memory.pinned);
    _reload();
  }

  void _delete(Memory memory) {
    widget.store.delete(memory.id);
    _reload();
  }

  void _judge(MemoryRelation relation, String kind) {
    widget.store.judgeRelation(relation.id, relation: kind);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _query,
            onChanged: (_) => _reload(),
            decoration: const InputDecoration(
              hintText: 'Buscar en la memoria…',
              prefixIcon: Icon(Icons.search),
              contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ),
        if (_pending.isNotEmpty) _PendingRelations(
          relations: _pending,
          store: widget.store,
          onJudge: _judge,
        ),
        Expanded(
          child: _items.isEmpty
              ? const Center(child: Text('Todavía no hay recuerdos guardados.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final memory = _items[index];
                    return _MemoryCard(
                      memory: memory,
                      onPin: () => _togglePin(memory),
                      onDelete: () => _delete(memory),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.memory,
    required this.onPin,
    required this.onDelete,
  });

  final Memory memory;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      decoration: BoxDecoration(
        color: LainColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: memory.pinned
            ? Border.all(color: LainColors.primary.withValues(alpha: 0.6))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(memory.title, style: theme.textTheme.bodyMedium),
              ),
              Text(
                memory.type,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: LainColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            memory.content,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (memory.duplicateCount > 1)
                Text(
                  'x${memory.duplicateCount}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: LainColors.textMuted,
                  ),
                ),
              const Spacer(),
              IconButton(
                onPressed: onPin,
                icon: Icon(
                  memory.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 18,
                  color: memory.pinned ? LainColors.primary : LainColors.textMuted,
                ),
                tooltip: memory.pinned ? 'Quitar de fijadas' : 'Fijar',
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: LainColors.textMuted,
                ),
                tooltip: 'Olvidar',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingRelations extends StatelessWidget {
  const _PendingRelations({
    required this.relations,
    required this.store,
    required this.onJudge,
  });

  final List<MemoryRelation> relations;
  final MemoryStore store;
  final void Function(MemoryRelation relation, String kind) onJudge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final relation = relations.first;
    final newer = store.byId(relation.sourceId);
    final older = store.byId(relation.targetId);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LainColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            relations.length == 1
                ? 'Hay una creencia que cambió'
                : 'Hay ${relations.length} creencias que cambiaron',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          if (newer != null && older != null) ...[
            Text('Antes: ${older.content}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('Ahora: ${newer.content}', style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => onJudge(relation, RelationKind.supersedes),
                child: const Text('Mantener la nueva'),
              ),
              TextButton(
                onPressed: () => onJudge(relation, RelationKind.notConflict),
                child: const Text('No es un cambio'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
