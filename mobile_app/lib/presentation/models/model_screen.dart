import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/llm/model_installer.dart';
import '../../data/llm/model_manager.dart';
import '../../data/llm/model_metadata.dart';
import '../chat/chat_controller.dart';

/// Gestor de modelos de la app, abierto sobre `files/models/`.
final modelManagerProvider = Provider<Future<ModelManager>>((ref) {
  return ModelManager.open();
});

/// Carpeta temporal de importaciones (inyectable para pruebas).
final importCacheDirProvider = Provider<Future<Directory>>((ref) {
  return importCacheDirectory();
});

/// Pantalla de gestión de modelos: inventario, modelo activo, importación
/// desde el selector de archivos y eliminación con confirmación.
class ModelScreen extends ConsumerStatefulWidget {
  const ModelScreen({super.key});

  @override
  ConsumerState<ModelScreen> createState() => _ModelScreenState();
}

enum _ImportPhase { preparando, copiando, verificando, registrando }

const Map<_ImportPhase, String> _importTitles = <_ImportPhase, String>{
  _ImportPhase.preparando: 'Preparando importación',
  _ImportPhase.copiando: 'Copiando modelo',
  _ImportPhase.verificando: 'Verificando integridad',
  _ImportPhase.registrando: 'Registrando modelo',
};

const Map<_ImportPhase, String> _importMessages = <_ImportPhase, String>{
  _ImportPhase.preparando: 'Elegí un archivo .gguf en tu dispositivo.',
  _ImportPhase.copiando: 'Pasando el archivo al almacenamiento de LAIN.',
  _ImportPhase.verificando: 'Calculando SHA-256. Esto puede tardar.',
  _ImportPhase.registrando: 'Guardando metadatos y activando el modelo…',
};

/// Estado de una importación en curso.
class _ImportProgress {
  const _ImportProgress(this.phase, {this.progress});

  final _ImportPhase phase;

  /// Avance 0..1, o `null` cuando el proveedor no informa el tamaño.
  final double? progress;
}

class _ModelScreenState extends ConsumerState<ModelScreen> {
  List<ModelMetadata> _models = <ModelMetadata>[];
  List<File> _orphans = <File>[];
  List<String> _incomplete = <String>[];
  String? _activeId;
  int? _freeBytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_refresh);
  }

  Future<ModelManager> _manager() async => ref.read(modelManagerProvider);

  Future<void> _refresh() async {
    try {
      final manager = await _manager();
      final installer = ref.read(modelInstallerProvider);
      final results = await Future.wait<Object?>([
        manager.inventory(),
        manager.orphanGgufs(),
        manager.incompleteInstallations(),
        manager.activeModelId(),
        installer.freeBytes().catchError((Object _) => 0),
      ]);
      if (!mounted) return;
      setState(() {
        _models = results[0] as List<ModelMetadata>;
        _orphans = results[1] as List<File>;
        _incomplete = results[2] as List<String>;
        _activeId = results[3] as String?;
        _freeBytes = results[4] as int?;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('No se pudo leer la carpeta de modelos: $error');
    }
  }

  Future<void> _activate(String id) async {
    final manager = await _manager();
    try {
      await manager.setActiveModel(id);
      await _refresh();
      // Recarga el motor con el nuevo modelo activo (libera el anterior).
      await ref.read(chatControllerProvider.notifier).retry();
    } on Object catch (error) {
      if (mounted) _snack('$error');
    }
  }

  Future<void> _confirmDelete(ModelMetadata model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar ${model.name}?'),
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

    final manager = await _manager();
    final wasActive = _activeId == model.id;
    try {
      await manager.removeModel(model.id);
      await _refresh();
      if (wasActive) {
        await ref.read(chatControllerProvider.notifier).retry();
      }
    } on Object catch (error) {
      if (mounted) _snack('$error');
    }
  }

  Future<void> _importModel() async {
    final installer = ref.read(modelInstallerProvider);
    final cacheDir = await ref.read(importCacheDirProvider);
    final manager = await _manager();

    final progress = ValueNotifier<_ImportProgress>(
      const _ImportProgress(_ImportPhase.preparando),
    );
    ModelMetadata? imported;
    Object? importError;
    var cancelled = false;

    // La importación arranca de inmediato; el diálogo muestra cada fase.
    final done = () async {
      try {
        String? picked;
        try {
          picked = await installer.pickAndImport(
            targetDir: cacheDir,
            onProgress: (value) {
              progress.value = _ImportProgress(_ImportPhase.copiando, progress: value);
            },
          );
        } on ModelInstallException catch (error) {
          importError = error;
          return;
        }
        if (picked == null) {
          cancelled = true;
          return;
        }
        final pickedPath = picked;

        progress.value = const _ImportProgress(_ImportPhase.verificando);
        imported = await manager.importModel(
          source: File(pickedPath),
          family: 'language',
          freeBytes: installer.freeBytes,
          onProgress: (value) {
            progress.value = _ImportProgress(_ImportPhase.verificando, progress: value);
          },
        );
        await File(pickedPath).delete().catchError((Object _) => File(pickedPath));
      } on Object catch (error) {
        importError = error;
      }

      if (imported != null) {
        progress.value = const _ImportProgress(_ImportPhase.registrando);
        try {
          await manager.setActiveModel(imported!.id);
          await _refresh();
          await ref.read(chatControllerProvider.notifier).retry();
        } on Object catch (error) {
          importError = error;
        }
      }
    }();

    if (!mounted) return;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ValueListenableBuilder<_ImportProgress>(
        valueListenable: progress,
        builder: (context, value, _) => AlertDialog(
          title: Text(_importTitles[value.phase]!),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_importMessages[value.phase]!),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: value.progress),
              if (value.progress != null) ...[
                const SizedBox(height: 4),
                Text('${(value.progress! * 100).toStringAsFixed(0)} %'),
              ],
            ],
          ),
        ),
      ),
    );
    await done;
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    await dialogFuture;

    if (cancelled) {
      if (mounted) _snack('Importación cancelada');
      return;
    }
    if (imported == null) {
      if (importError != null && mounted) _snack('$importError');
      return;
    }
    if (importError != null) {
      // El modelo quedó importado pero el registro/activación falló.
      if (mounted) {
        _snack('Modelo importado, pero no se pudo activar: $importError');
      }
      return;
    }
    if (mounted) _snack('Modelo importado y activado: ${imported!.name}');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modelos'),
        actions: [
          IconButton(
            onPressed: _importModel,
            icon: const Icon(Icons.add),
            tooltip: 'Importar .gguf',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _storageCard(theme),
                  const SizedBox(height: 16),
                  Text('Modelos registrados', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  if (_models.isEmpty)
                    const _EmptyModels()
                  else
                    ..._models.map(
                      (model) => _ModelTile(
                        model: model,
                        active: model.id == _activeId,
                        onActivate: () => _activate(model.id),
                        onDelete: () => _confirmDelete(model),
                      ),
                    ),
                  if (_orphans.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Modelos sueltos (adb push)', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    ..._orphans.map(
                      (file) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(file.uri.pathSegments.last),
                        subtitle: const Text('Se usa como fallback si no hay modelo activo.'),
                      ),
                    ),
                  ],
                  if (_incomplete.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Instalaciones incompletas', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    for (final name in _incomplete)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.warning_amber_outlined),
                        title: Text(name),
                        subtitle: const Text('Importación interrumpida; no se usa.'),
                      ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _storageCard(ThemeData theme) {
    final free = _freeBytes;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LainColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Almacenamiento', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            free == null ? 'Espacio libre: desconocido' : 'Espacio libre: ${_gigabytes(free)} GB',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _gigabytes(int bytes) => (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.active,
    required this.onActivate,
    required this.onDelete,
  });

  final ModelMetadata model;
  final bool active;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(
          active ? Icons.check_circle : Icons.circle_outlined,
          color: active ? LainColors.primary : LainColors.textMuted,
        ),
        title: Text(model.name),
        subtitle: Text(
          '${model.quantization} · ${_size(model.sizeBytes)} · ${model.family}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!active)
              TextButton(onPressed: onActivate, child: const Text('Usar')),
            if (active)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('Activo', style: theme.textTheme.bodySmall),
              ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar modelo',
            ),
          ],
        ),
      ),
    );
  }

  String _size(int bytes) {
    final mib = bytes / (1024 * 1024);
    if (mib >= 1024) return '${(mib / 1024).toStringAsFixed(2)} GiB';
    return '${mib.toStringAsFixed(0)} MiB';
  }
}

class _EmptyModels extends StatelessWidget {
  const _EmptyModels();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LainColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'No hay modelos registrados. Tocá el botón + para importar un archivo '
        '.gguf desde tu dispositivo, o copialo con adb:\n'
        'adb push tu-modelo.gguf /storage/emulated/0/Android/data/'
        'com.lain.lain_mobile/files/models/',
      ),
    );
  }
}
