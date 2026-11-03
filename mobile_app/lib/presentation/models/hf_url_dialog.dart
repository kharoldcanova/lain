import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/llm/hf_client.dart';
import '../../data/llm/hf_url.dart';
import 'download_providers.dart';

/// Pide una URL de Hugging Face y devuelve el archivo GGUF elegido.
///
/// Solo acepta HTTPS de `huggingface.co` o `hf.co` (ver [parseHuggingFaceUrl]).
/// Si el enlace apunta a un repositorio se muestran sus `.gguf` para elegir.
Future<HfFile?> showHfUrlDialog(BuildContext context) {
  return showDialog<HfFile>(
    context: context,
    builder: (context) => const HfUrlDialog(),
  );
}

class HfUrlDialog extends ConsumerStatefulWidget {
  const HfUrlDialog({super.key});

  @override
  ConsumerState<HfUrlDialog> createState() => _HfUrlDialogState();
}

class _HfUrlDialogState extends ConsumerState<HfUrlDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  List<HfFile>? _files;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _error = null;
      _files = null;
    });
    try {
      final reference = parseHuggingFaceUrl(_controller.text);
      final files = await ref.read(hfClientProvider).resolve(reference);
      if (!mounted) return;
      if (files.length == 1) {
        Navigator.of(context).pop(files.single);
        return;
      }
      setState(() {
        _files = files;
        _loading = false;
      });
    } on HfUrlException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } on HfClientException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = _files;
    return AlertDialog(
      title: const Text('Descargar desde una URL'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loading ? null : _resolve(),
              decoration: const InputDecoration(
                labelText: 'URL de Hugging Face',
                hintText:
                    'https://huggingface.co/org/repo/resolve/main/modelo.gguf',
                helperText: 'Solo enlaces HTTPS de huggingface.co o hf.co',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (_loading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text('Consultando Hugging Face…', style: theme.textTheme.bodySmall),
            ],
            if (files != null && files.length > 1) ...[
              const SizedBox(height: 12),
              Text('Elegí el archivo', style: theme.textTheme.titleSmall),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final file in files)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(file.name),
                        subtitle: Text(_size(file.sizeBytes)),
                        onTap: () => Navigator.of(context).pop(file),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _resolve,
          child: const Text('Buscar'),
        ),
      ],
    );
  }

  String _size(int bytes) {
    if (bytes <= 0) return 'tamaño desconocido';
    final mib = bytes / (1024 * 1024);
    if (mib >= 1024) return '${(mib / 1024).toStringAsFixed(2)} GiB';
    return '${mib.toStringAsFixed(0)} MiB';
  }
}
