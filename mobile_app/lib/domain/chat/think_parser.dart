/// Separa el bloque de razonamiento `think` del texto que ve el usuario.
///
/// El stream llega en fragmentos arbitrarios, así que el parser retiene una
/// cola corta que todavía podría ser el inicio de un tag partido.
class ThinkParser {
  static const String openTag = '\u003Cthink>';
  static const String closeTag = '\u003C/think>';

  String _pending = '';
  bool _inside = false;
  final StringBuffer _thought = StringBuffer();
  final StringBuffer _visible = StringBuffer();

  /// Contenido del razonamiento, sin los tags. Puede quedar vacío.
  String get thought => _thought.toString().trim();

  /// Texto que debe mostrarse al usuario, sin el bloque de pensamiento.
  String get visible => _visible.toString();

  /// Acumula un fragmento del stream.
  void add(String chunk) {
    if (chunk.isEmpty) return;
    _pending += chunk;
    _drain(finalChunk: false);
  }

  /// Cierra el stream. Si el bloque quedó abierto no se pierde la respuesta:
  /// el contenido se muestra como texto visible.
  void close() {
    _drain(finalChunk: true);
    if (_inside) {
      _visible.write(_thought.toString());
      _thought.clear();
      _inside = false;
    }
    if (_pending.isNotEmpty) {
      _visible.write(_pending);
      _pending = '';
    }
  }

  void _drain({required bool finalChunk}) {
    while (true) {
      if (!_inside) {
        final open = _pending.indexOf(openTag);
        if (open >= 0) {
          _visible.write(_pending.substring(0, open));
          _pending = _pending.substring(open + openTag.length);
          _inside = true;
          continue;
        }
        _emit(
          target: _visible,
          keep: finalChunk ? 0 : _partialSuffix(_pending, openTag),
        );
        return;
      }

      final close = _pending.indexOf(closeTag);
      if (close >= 0) {
        _thought.write(_pending.substring(0, close));
        _pending = _pending.substring(close + closeTag.length);
        _inside = false;
        continue;
      }
      _emit(
        target: _thought,
        keep: finalChunk ? 0 : _partialSuffix(_pending, closeTag),
      );
      return;
    }
  }

  void _emit({required StringBuffer target, required int keep}) {
    final count = _pending.length - keep;
    if (count <= 0) return;
    target.write(_pending.substring(0, count));
    _pending = _pending.substring(count);
  }

  /// Longitud del sufijo de [buffer] que puede ser el inicio de [tag].
  static int _partialSuffix(String buffer, String tag) {
    final max = buffer.length < tag.length - 1 ? buffer.length : tag.length - 1;
    for (var length = max; length > 0; length--) {
      if (buffer.endsWith(tag.substring(0, length))) return length;
    }
    return 0;
  }
}
