/// Corta el texto visible del modelo en oraciones completas.
///
/// Recibe fragmentos arbitrarios del stream y devuelve solo las oraciones
/// cerradas. Mantiene la cola incompleta hasta el siguiente fragmento o hasta
/// [flush]. No parte decimales (`3.14`) ni signos sin espacio posterior.
class SentenceStreamer {
  final StringBuffer _buffer = StringBuffer();

  /// Añade [delta] y devuelve las oraciones terminadas.
  List<String> add(String delta) {
    if (delta.isEmpty) return const <String>[];
    _buffer.write(delta);
    final text = _buffer.toString();
    if (text.isEmpty) return const <String>[];

    final sentences = <String>[];
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];

      if (char == '\n') {
        final sentence = text.substring(start, i).trim();
        if (sentence.isNotEmpty) sentences.add(sentence);
        start = i + 1;
        continue;
      }

      final isPunctuation =
          char == '.' || char == '!' || char == '?' || char == '…';
      if (!isPunctuation) continue;

      final next = i + 1 < text.length ? text[i + 1] : null;
      if (next == null) {
        // Un punto al final del buffer puede ser un decimal partido
        // (`3.` + `14`): se espera al próximo fragmento. Los signos `? ! …`
        // no son ambiguos y cierran la oración.
        if (char == '.') break;
      } else if (next.trim().isNotEmpty) {
        // Signo pegado a una letra o a un número: no es fin de oración.
        continue;
      }

      final sentence = text.substring(start, i + 1).trim();
      if (sentence.isNotEmpty) sentences.add(sentence);
      start = i + 1;
    }

    final remainder = text.substring(start);
    _buffer
      ..clear()
      ..write(remainder);
    return sentences;
  }

  /// Devuelve el resto pendiente y limpia el buffer.
  List<String> flush() {
    final rest = _buffer.toString().trim();
    _buffer.clear();
    if (rest.isEmpty) return const <String>[];
    return <String>[rest];
  }

  void reset() => _buffer.clear();
}
