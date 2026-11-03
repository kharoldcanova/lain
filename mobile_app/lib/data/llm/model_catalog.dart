import 'model_metadata.dart';
import 'hf_url.dart';

/// Entrada curada del catálogo de descargas.
///
/// El tamaño que se muestra es orientativo; el tamaño real y el SHA-256 se
/// piden a la API de Hugging Face al descargar (`HfClient`), así que una
/// diferencia de unos MB no invalida la descarga.
///
/// `architecture` es la que declara el GGUF y decide si el motor incluido la
/// soporta (`engine_capabilities.dart`). `lfm3` se puede descargar pero no
/// activar hasta recompilar llama.cpp.
class ModelCatalogEntry {
  const ModelCatalogEntry({
    required this.id,
    required this.name,
    required this.family,
    required this.repo,
    required this.file,
    required this.architecture,
    required this.quantization,
    required this.sizeLabel,
    required this.languages,
    this.recommended = false,
    this.note,
  });

  /// Identificador estable del catálogo (no el id de instalación).
  final String id;

  final String name;
  final String family;
  final String repo;
  final String file;

  /// Arquitectura declarada en el GGUF (`lfm2`, `lfm3`, `qwen3`, `qwen2`…).
  final String architecture;

  final String quantization;
  final String sizeLabel;
  final String languages;
  final bool recommended;
  final String? note;

  /// Referencia de Hugging Face para resolver tamaño y SHA-256.
  HfReference get reference => HfReference(repo: repo, file: file);

  /// Id con el que se instala (derivado del nombre del archivo).
  String? get installedId =>
      ModelMetadata.sanitizeId(file.split('/').last.replaceAll('.gguf', ''));
}

/// Catálogo de modelos GGUF ofrecidos desde la app.
///
/// Orden: primero los recomendados para el motor actual y después el resto.
const List<ModelCatalogEntry> modelCatalog = <ModelCatalogEntry>[
  ModelCatalogEntry(
    id: 'lfm2.5-1.2b-instruct',
    name: 'LFM2.5-1.2B-Instruct',
    family: 'language',
    repo: 'LiquidAI/LFM2.5-1.2B-Instruct-GGUF',
    file: 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
    architecture: 'lfm2',
    quantization: 'Q4_K_M',
    sizeLabel: '731 MB',
    languages: 'EN, ES, FR, DE, JA, KO, AR, ZH',
    recommended: true,
    note: 'Compatible con el motor actual. Arquitectura híbrida pensada para CPU.',
  ),
  ModelCatalogEntry(
    id: 'lfm2.5-2.6b',
    name: 'LFM2.5-2.6B',
    family: 'language',
    repo: 'LiquidAI/LFM2.5-2.6B-GGUF',
    file: 'LFM2.5-2.6B-Q4_K_M.gguf',
    architecture: 'lfm2',
    quantization: 'Q4_K_M',
    sizeLabel: '1,67 GB',
    languages: 'EN, ES, FR, DE, IT, JA, KO, PT, …',
    note: 'Compatible con el motor actual; más calidad y más peso que el 1.2B.',
  ),
  ModelCatalogEntry(
    id: 'qwen3-1.7b',
    name: 'Qwen3-1.7B',
    family: 'language',
    repo: 'unsloth/Qwen3-1.7B-GGUF',
    file: 'Qwen3-1.7B-Q4_K_M.gguf',
    architecture: 'qwen3',
    quantization: 'Q4_K_M',
    sizeLabel: '1,1 GB',
    languages: 'multilingüe (ES incluido)',
    note: 'Base evaluada para LAIN-ES; buena calidad en español.',
  ),
  ModelCatalogEntry(
    id: 'lfm3-1.7b',
    name: 'LFM3-1.7B',
    family: 'language',
    repo: 'LiquidAI/LFM3-1.7B-GGUF',
    file: 'LFM3-1.7B-Q4_K_M.gguf',
    architecture: 'lfm3',
    quantization: 'Q4_K_M',
    sizeLabel: '1,10 GB',
    languages: 'EN, ES, FR, DE, IT, JA, KO, PT, …',
    note: 'Requiere una versión nueva del motor (llama.cpp con lfm3). '
        'Se puede descargar, pero no activar todavía.',
  ),
  ModelCatalogEntry(
    id: 'qwen2.5-3b-instruct',
    name: 'Qwen2.5-3B-Instruct',
    family: 'language',
    repo: 'Qwen/Qwen2.5-3B-Instruct-GGUF',
    file: 'qwen2.5-3b-instruct-q4_k_m.gguf',
    architecture: 'qwen2',
    quantization: 'Q4_K_M',
    sizeLabel: '1,8 GB',
    languages: 'multilingüe (ES incluido)',
    note: 'Modelo actual en el PC. Pesado para un teléfono de 4 GB.',
  ),
];
