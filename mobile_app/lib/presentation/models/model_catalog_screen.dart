import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/llm/engine_capabilities.dart';
import '../../data/llm/hf_client.dart';
import '../../data/llm/model_catalog.dart';
import '../../data/llm/model_downloader.dart';
import '../../data/llm/model_metadata.dart';
import '../chat/chat_controller.dart';
import 'download_providers.dart';
import 'hf_url_dialog.dart';
import 'model_screen.dart';

/// Catálogo de modelos GGUF descargables desde Hugging Face.
///
/// Descargar no exige que el modelo sea compatible con el motor; activar sí.
/// Los modelos incompatibles se marcan y se pueden borrar igual.
class ModelCatalogScreen extends ConsumerStatefulWidget {
  const ModelCatalogScreen({super.key});

  @override
  ConsumerState<ModelCatalogScreen> createState() => _ModelCatalogScreenState();
}

class _ModelCatalogScreenState extends ConsumerState<ModelCatalogScreen> {
  final Map<String, double> _progress = <String, double>{};
  final Map<String, List<bool>> _cancelFlags = <String, List<bool>>{};
  final Map<String, String> _errors = <String, String>{};
  Set<String> _installed = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_refresh);
  }

  Future<void> _refresh() async {
    try {
      final manager = await ref.read(modelManagerProvider);
      final models = await manager.inventory();
      if (!mounted) return;
      setState(() {
        _installed = models.map((model) => model.id).toSet();
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('No se pudo leer la carpeta de modelos: $error');
    }
  }

  Future<void> _downloadEntry(ModelCatalogEntry entry) async {
    final id = entry.installedId;
    if (id == null) {
      _snack('el nombre del archivo no permite generar un id válido');
      return;
    }
    if (_cancelFlags.containsKey(id)) return;
    final cancel = <bool>[false];
    _cancelFlags[id] = cancel;
    _errors.remove(id);
    setState(() => _progress[id] = -1);
    try {
      final client = ref.read(hfClientProvider);
      final files = await client.resolve(entry.reference);
      if (!mounted || cancel[0]) return;
      var target = files.first;
      for (final file in files) {
        if (file.name == entry.file) target = file;
      }
      await _downloadFile(
        target: target,
        label: entry.name,
        id: id,
        cancel: cancel,
      );
    } on DownloadCancelled {
      _snack('Descarga cancelada; se reanuda al reintentar');
    } on Object catch (error) {
      if (mounted) setState(() => _errors[id] = '$error');
      _snack('$error');
    } finally {
      _cancelFlags.remove(id);
      if (mounted) setState(() => _progress.remove(id));
    }
  }

  Future<void> _downloadFromUrl() async {
    final target = await showHfUrlDialog(context);
    if (target == null || !mounted) return;
    final id = ModelMetadata.sanitizeId(
      target.fileName.replaceAll('.gguf', ''),
    );
    if (id == null) {
      _snack('el nombre del archivo no permite generar un id válido');
      return;
    }
    if (_cancelFlags.containsKey(id)) return;
    final cancel = <bool>[false];
    _cancelFlags[id] = cancel;
    _errors.remove(id);
    setState(() => _progress[id] = -1);
    try {
      await _downloadFile(
        target: target,
        label: target.fileName,
        id: id,
        cancel: cancel,
      );
    } on DownloadCancelled {
      _snack('Descarga cancelada; se reanuda al reintentar');
    } on Object catch (error) {
      if (mounted) setState(() => _errors[id] = '$error');
      _snack('$error');
    } finally {
      _cancelFlags.remove(id);
      if (mounted) setState(() => _progress.remove(id));
    }
  }

  Future<void> _downloadFile({
    required HfFile target,
    required String label,
    required String id,
    required List<bool> cancel,
  }) async {
    final manager = await ref.read(modelManagerProvider);
    final downloader = await ref.read(modelDownloaderProvider.future);
    final installer = ref.read(modelInstallerProvider);
    final downloaded = await downloader.download(
      file: target,
      freeBytes: installer.freeBytes,
      isCancelled: () => cancel[0],
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _progress[id] = progress.fraction ?? -1;
        });
      },
    );
    final metadata = await manager.registerDownloaded(
      staging: downloaded.staging,
      file: downloaded.file,
      sha256: downloaded.sha256,
      sourceUrl: target.downloadUri.toString(),
    );
    await _refresh();
    if (!mounted) return;
    if (isArchitectureSupported(metadata.architecture)) {
      await manager.setActiveModel(metadata.id);
      await ref.read(chatControllerProvider.notifier).retry();
      if (mounted) _snack('$label instalado y activo');
    } else {
      _snack(
        '$label descargado, pero requiere una versión nueva del motor: '
        'no se puede activar todavía',
      );
    }
  }

  Future<void> _confirmDelete(String id, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar $label?'),
        content: const Text(
          'Se borra el archivo del modelo de este dispositivo. '
          'Las conversaciones, los recuerdos y la configuración no se tocan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final manager = await ref.read(modelManagerProvider);
      await manager.removeModel(id);
      await _refresh();
      await ref.read(chatControllerProvider.notifier).retry();
      _snack('Modelo eliminado');
    } on Object catch (error) {
      _snack('$error');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final others = <String>[];
    for (final id in _installed) {
      final known = modelCatalog.any((entry) => entry.installedId == id);
      if (!known) others.add(id);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Descargar modelos'),
        actions: [
          IconButton(
            onPressed: _downloadFromUrl,
            icon: const Icon(Icons.link),
            tooltip: 'Descargar desde una URL',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              'Los modelos se descargan directo de Hugging Face y se guardan '
              'en el almacenamiento de LAIN. Se pueden borrar cuando quieras.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ...modelCatalog.map((entry) => _entryCard(entry, theme)),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Otros modelos instalados', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final id in others)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(id),
                  trailing: IconButton(
                    onPressed: () => _confirmDelete(id, id),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Eliminar modelo',
                  ),
                ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _entryCard(ModelCatalogEntry entry, ThemeData theme) {
    final id = entry.installedId;
    final installed = id != null && _installed.contains(id);
    final downloading = id != null && _progress.containsKey(id);
    final progress = id == null ? null : _progress[id];
    final error = id == null ? null : _errors[id];
    final compatible = isArchitectureSupported(entry.architecture);
    final installedId = installed ? id : null;
    final cancelId = downloading ? id : null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(entry.name, style: theme.textTheme.titleMedium),
                ),
                if (entry.recommended)
                  const Chip(
                    label: Text('Recomendado'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${entry.quantization} · ${entry.sizeLabel} · ${entry.architecture}',
              style: theme.textTheme.bodySmall,
            ),
            Text(entry.languages, style: theme.textTheme.bodySmall),
            if (entry.note != null) ...[
              const SizedBox(height: 4),
              Text(
                entry.note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: compatible ? LainColors.textMuted : theme.colorScheme.error,
                ),
              ),
            ],
            if (downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (progress ?? -1) < 0 ? null : progress,
              ),
              const SizedBox(height: 4),
              Text(
                (progress ?? -1) < 0
                    ? 'Descargando…'
                    : '${((progress ?? 0) * 100).toStringAsFixed(0)} %',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(
                error,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (installedId != null) ...[
                    Text('Instalado', style: theme.textTheme.bodySmall),
                    IconButton(
                      onPressed: () => _confirmDelete(installedId, entry.name),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Eliminar modelo',
                    ),
                  ] else if (cancelId != null) ...[
                    TextButton(
                      onPressed: () {
                        final flag = _cancelFlags[cancelId];
                        if (flag != null) flag[0] = true;
                      },
                      child: const Text('Cancelar'),
                    ),
                  ] else
                    FilledButton.tonal(
                      onPressed: () => _downloadEntry(entry),
                      child: const Text('Descargar'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
