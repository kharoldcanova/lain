/// Validación de URLs de modelos alojados en Hugging Face.
///
/// Solo se aceptan enlaces HTTPS de `huggingface.co` o `hf.co`: repositorios
/// completos o archivos `.gguf` concretos. La misma política se usa para
/// validar el destino final de cada redirección antes de descargar.
library;

/// Hosts aceptados por defecto.
const Set<String> defaultHuggingFaceHosts = <String>{
  'huggingface.co',
  'hf.co',
};

/// Reglas de aceptación de URLs.
///
/// Las pruebas inyectan su propio servidor local; en la app siempre se usa la
/// política por defecto (solo HTTPS y solo hosts de Hugging Face).
class HfUrlPolicy {
  const HfUrlPolicy({
    this.allowedHosts = defaultHuggingFaceHosts,
    this.requireHttps = true,
  });

  final Set<String> allowedHosts;
  final bool requireHttps;

  /// `true` si [uri] usa un esquema y un host permitidos.
  bool allows(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (requireHttps && scheme != 'https') return false;
    if (!requireHttps && scheme != 'https' && scheme != 'http') return false;
    if (uri.host.isEmpty) return false;
    return allowedHosts.contains(uri.host.toLowerCase());
  }
}

/// Error de validación de una URL de Hugging Face.
class HfUrlException implements Exception {
  const HfUrlException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Referencia a un repositorio o a un archivo dentro de Hugging Face.
class HfReference {
  const HfReference({required this.repo, this.file, this.revision = 'main'});

  /// `org/repo`.
  final String repo;

  /// Archivo `.gguf` dentro del repositorio, o `null` si es el repo completo.
  final String? file;

  /// Revisión (rama, tag o commit) del enlace.
  final String revision;

  /// `true` cuando el enlace apunta a un repositorio, no a un archivo.
  bool get isRepoOnly => file == null;

  /// URL canónica de descarga del archivo.
  Uri resolveUri() {
    final target = file;
    if (target == null) {
      throw const HfUrlException('el enlace apunta a un repositorio, no a un archivo');
    }
    return Uri.https(
      'huggingface.co',
      '/$repo/resolve/$revision/$target',
    );
  }

  /// URL canónica del repositorio.
  Uri get repoUri => Uri.https('huggingface.co', '/$repo');

  @override
  String toString() => file == null ? repo : '$repo:$file';
}

final RegExp _namePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

/// Valida [input] y devuelve la referencia a descargar.
///
/// Acepta:
/// - `https://huggingface.co/org/repo`
/// - `https://huggingface.co/org/repo/resolve/main/archivo.gguf`
/// - `https://huggingface.co/org/repo/blob/main/archivo.gguf`
/// - lo mismo con `hf.co`
///
/// Lanza [HfUrlException] con un mensaje para el usuario si el enlace no
/// cumple la política.
HfReference parseHuggingFaceUrl(
  String input, {
  HfUrlPolicy policy = const HfUrlPolicy(),
}) {
  final text = input.trim();
  if (text.isEmpty) {
    throw const HfUrlException('pegá la URL del modelo en Hugging Face');
  }
  final uri = Uri.tryParse(text);
  if (uri == null) {
    throw const HfUrlException('la URL no es válida');
  }
  if (uri.userInfo.isNotEmpty) {
    throw const HfUrlException('la URL no puede incluir usuario ni contraseña');
  }
  if (!policy.allows(uri)) {
    throw HfUrlException(
      'solo se aceptan enlaces HTTPS de ${policy.allowedHosts.join(' o ')}',
    );
  }

  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (segments.length < 2) {
    throw const HfUrlException(
      'el enlace debe incluir el repositorio: /organización/repositorio',
    );
  }
  final org = segments[0];
  final repoName = segments[1];
  if (!_namePattern.hasMatch(org) || !_namePattern.hasMatch(repoName)) {
    throw const HfUrlException('el nombre del repositorio no es válido');
  }
  final repo = '$org/$repoName';

  if (segments.length == 2) {
    return HfReference(repo: repo);
  }

  final kind = segments[2];
  if (kind != 'resolve' && kind != 'blob') {
    throw const HfUrlException(
      'el enlace debe apuntar a un repositorio o a un archivo .gguf',
    );
  }
  if (segments.length < 5) {
    throw const HfUrlException(
      'al enlace del archivo le falta la revisión o el nombre del archivo',
    );
  }
  final revision = segments[3];
  final file = segments.skip(4).join('/');
  if (revision.contains('..') || folderUnsafe(revision)) {
    throw const HfUrlException('la revisión del enlace no es válida');
  }
  if (!file.toLowerCase().endsWith('.gguf')) {
    throw const HfUrlException('el archivo debe ser un .gguf');
  }
  if (file.split('/').any(folderUnsafe)) {
    throw const HfUrlException('el nombre del archivo no es válido');
  }
  return HfReference(repo: repo, file: file, revision: revision);
}

/// `true` si el segmento no es seguro para usarlo como ruta local.
bool folderUnsafe(String segment) {
  if (segment.isEmpty || segment == '.' || segment == '..') return true;
  if (segment.contains('\\')) return true;
  return !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]*$').hasMatch(segment);
}
