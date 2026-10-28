import 'dart:convert';

/// Creencia extraída del bloque `think` de un turno.
class CapturedBelief {
  const CapturedBelief({
    required this.topicKey,
    required this.title,
    required this.content,
  });

  final String topicKey;
  final String title;
  final String content;
}

const Set<String> _stopWords = <String>{
  'de', 'la', 'el', 'los', 'las', 'un', 'una', 'unos', 'unas', 'que', 'en',
  'y', 'o', 'u', 'a', 'al', 'por', 'para', 'con', 'sin', 'su', 'sus', 'se',
  'le', 'les', 'lo', 'es', 'son', 'como', 'pero', 'mas', 'más', 'mi', 'me',
  'te', 'tu', 'tus', 'del', 'esta', 'este', 'esto', 'esa', 'ese', 'eso',
  'muy', 'ya', 'no', 'si', 'sí', 'cuando', 'donde', 'porque', 'sobre',
};

/// Extrae la creencia previa y su cambio del JSON de metacognición.
///
/// Devuelve `null` si el bloque no es JSON válido o no trae ambas claves; el
/// turno nunca se rompe por un formato inesperado.
CapturedBelief? beliefFromThought(String? thought) {
  if (thought == null) return null;
  final json = _extractJson(thought);
  if (json == null) return null;

  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;

  final prior = (decoded['prior_belief'] as String?)?.trim();
  final shift = (decoded['belief_shift'] as String?)?.trim();
  final trace = (decoded['thought_trace'] as String?)?.trim();
  if (prior == null || prior.isEmpty || shift == null || shift.isEmpty) {
    return null;
  }

  final content = '$prior → $shift';
  return CapturedBelief(
    topicKey: 'belief/${_slug(trace ?? prior)}',
    title: _title(prior),
    content: content,
  );
}

String? _extractJson(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  return raw.substring(start, end + 1);
}

String _title(String prior) {
  final clean = prior.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= 60) return clean;
  return '${clean.substring(0, 57)}…';
}

/// Slug estable a partir de las palabras significativas del texto.
String _slug(String text) {
  final words = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\wáéíóúñü\s]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 3 && !_stopWords.contains(w))
      .take(5)
      .toList();
  if (words.isEmpty) return 'general';
  return words.join('-');
}
