import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/llm/hf_client.dart';
import '../../data/llm/model_downloader.dart';
import '../../data/llm/model_store.dart';

/// Cliente de la API de Hugging Face (inyectable en pruebas).
final hfClientProvider = Provider<HfClient>((ref) {
  final client = HfClient();
  ref.onDispose(client.close);
  return client;
});

/// Descargador sobre la carpeta real de modelos de la app.
final modelDownloaderProvider = FutureProvider<ModelDownloader>((ref) async {
  final dir = await modelDirectory();
  final downloader = ModelDownloader(rootDir: dir);
  ref.onDispose(downloader.close);
  return downloader;
});
