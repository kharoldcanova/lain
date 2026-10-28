import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_state.dart';
import '../memory/memory_screen.dart';
import 'chat_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final controller = ref.read(chatControllerProvider.notifier);
    final text = _input.text;
    _input.clear();
    controller.send(text);
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar la conversación?'),
        content: const Text(
          'Se elimina el historial guardado en este dispositivo. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(chatControllerProvider.notifier).clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LAIN'),
        actions: [
          if (state.generating)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MemoryScreen()),
            ),
            icon: const Icon(Icons.psychology_outlined),
            tooltip: 'Memoria',
          ),
          if (state.messages.isNotEmpty && !state.generating)
            IconButton(
              onPressed: _confirmClear,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Limpiar conversación',
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: LainColors.surfaceHigh),
        ),
      ),
      body: Column(
        children: [
          if (state.status != EngineStatus.ready) _StatusBanner(state: state),
          Expanded(
            child: state.messages.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: state.messages.length,
                    itemBuilder: (context, index) {
                      final message = state.messages[state.messages.length - 1 - index];
                      return _MessageBubble(message: message);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: state.canSend,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: state.status == EngineStatus.ready
                            ? 'Escribe un mensaje…'
                            : 'Modelo no disponible',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: state.canSend ? _send : null,
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'Enviar',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends ConsumerWidget {
  const _StatusBanner({required this.state});

  final ChatState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final (Widget icon, String title, String detail) = switch (state.status) {
      EngineStatus.starting => (
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          'Iniciando',
          'Preparando el motor local.',
        ),
      EngineStatus.loading => (
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          'Cargando modelo',
          'Qwen2.5-3B-Instruct en memoria. Puede tardar unos segundos.',
        ),
      EngineStatus.preparingModel => (
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          'Preparando el modelo',
          'Copiando el GGUF incluido en la app. Solo ocurre la primera vez.',
        ),
      EngineStatus.missingModel => (
          const Icon(Icons.folder_off_outlined, size: 20, color: LainColors.primary),
          'Falta el modelo',
          'No se pudo preparar el GGUF incluido en la app. '
              'Revisá que queden ~2 GB libres y reinstalá el APK.\n'
              'Ruta esperada: ${state.modelPath ?? "desconocida"}',
        ),
      EngineStatus.unsupported => (
          const Icon(Icons.devices_other, size: 20, color: LainColors.primary),
          'Solo Android',
          'La inferencia local usa dart:ffi; en web o escritorio no está disponible.',
        ),
      EngineStatus.error => (
          const Icon(Icons.error_outline, size: 20, color: Color(0xFFFF6B6B)),
          'Error del motor',
          state.error ?? 'Sin detalle.',
        ),
      EngineStatus.ready => (const SizedBox.shrink(), '', ''),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LainColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                SelectableText(detail, style: theme.textTheme.bodySmall),
                if (state.progress != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: state.progress,
                      minHeight: 6,
                      backgroundColor: LainColors.surfaceHigh,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(state.progress! * 100).toStringAsFixed(0)} %',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.blur_on, size: 48, color: LainColors.primary),
            const SizedBox(height: 16),
            Text('Estoy aquí.', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Todo se queda en tu dispositivo.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final empty = message.text.isEmpty && !message.hasThought;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser ? LainColors.userBubble : LainColors.lainBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: empty
            ? const SizedBox(
                width: 24,
                height: 16,
                child: Center(
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.hasThought)
                    _ThoughtPanel(thought: message.thought!),
                  if (message.text.isNotEmpty)
                    Text(
                      message.text,
                      style: const TextStyle(color: LainColors.textPrimary),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Razonamiento `think` del modelo, colapsado por defecto.
class _ThoughtPanel extends StatefulWidget {
  const _ThoughtPanel({required this.thought});

  final String thought;

  @override
  State<_ThoughtPanel> createState() => _ThoughtPanelState();
}

class _ThoughtPanelState extends State<_ThoughtPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: LainColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Razonamiento',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: LainColors.textMuted,
                      ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(top: 6, bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: LainColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              widget.thought,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
                color: LainColors.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}
