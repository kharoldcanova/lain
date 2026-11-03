import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Datos mínimos de la cabecera de un GGUF que la app necesita.
///
/// Solo se lee lo imprescindible (la arquitectura declarada) para no recorrer
/// metadatos gigantes como el vocabulario del tokenizer.
class GgufInfo {
  const GgufInfo({required this.architecture});

  /// Valor de `general.architecture` (p. ej. `qwen3`, `lfm2`), en minúsculas.
  final String architecture;
}

/// Error de lectura de la cabecera GGUF.
class GgufHeaderException implements Exception {
  const GgufHeaderException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lee `general.architecture` de la cabecera de [file].
///
/// Lanza [GgufHeaderException] si el archivo no es un GGUF v2/v3 válido o si
/// la cabecera no declara su arquitectura. El llamador decide si el fallo es
/// bloqueante: la importación lo trata como best-effort.
Future<GgufInfo> readGgufInfo(File file) async {
  if (!await file.exists()) {
    throw const GgufHeaderException('el archivo no existe');
  }
  final raf = await file.open();
  try {
    final reader = _GgufReader(raf);
    final magic = await reader.uint32();
    if (magic != _ggufMagic) {
      throw const GgufHeaderException('el archivo no es un GGUF válido');
    }
    final version = await reader.uint32();
    if (version != 2 && version != 3) {
      throw GgufHeaderException('versión GGUF no soportada ($version)');
    }
    await reader.uint64(); // cantidad de tensores
    final kvCount = await reader.uint64();
    if (kvCount > _maxMetadataEntries) {
      throw const GgufHeaderException('cabecera GGUF fuera de rango');
    }

    for (var i = 0; i < kvCount; i++) {
      final key = await reader.string();
      final type = await reader.uint32();
      if (key == 'general.architecture') {
        if (type != _typeString) {
          throw const GgufHeaderException(
            'general.architecture no es una cadena',
          );
        }
        final architecture = (await reader.string()).trim().toLowerCase();
        if (architecture.isEmpty) break;
        return GgufInfo(architecture: architecture);
      }
      await reader.skipValue(type);
      if (reader.consumedBytes > _maxMetadataBytes) {
        throw const GgufHeaderException('la cabecera del GGUF es demasiado grande');
      }
    }
    throw const GgufHeaderException('el GGUF no declara su arquitectura');
  } on FileSystemException catch (error) {
    throw GgufHeaderException('no se pudo leer el archivo: ${error.message}');
  } finally {
    await raf.close();
  }
}

const int _ggufMagic = 0x46554747; // "GGUF" little-endian
const int _maxMetadataBytes = 8 * 1024 * 1024;
const int _maxMetadataEntries = 100000;

const int _typeUint8 = 0;
const int _typeInt8 = 1;
const int _typeUint16 = 2;
const int _typeInt16 = 3;
const int _typeUint32 = 4;
const int _typeInt32 = 5;
const int _typeFloat32 = 6;
const int _typeBool = 7;
const int _typeString = 8;
const int _typeArray = 9;
const int _typeUint64 = 10;
const int _typeInt64 = 11;
const int _typeFloat64 = 12;

/// Lector secuencial con búfer sobre el archivo: nunca carga el GGUF entero.
class _GgufReader {
  _GgufReader(this._raf);

  final RandomAccessFile _raf;
  Uint8List _buffer = Uint8List(0);
  int _position = 0;

  /// Bytes consumidos desde el inicio del archivo (para acotar la cabecera).
  int consumedBytes = 0;

  Future<void> _ensure(int count) async {
    if (_buffer.length - _position >= count) return;
    final keep = Uint8List.fromList(_buffer.sublist(_position));
    final next = Uint8List(keep.length + count);
    next.setRange(0, keep.length, keep);
    var filled = keep.length;
    while (filled < next.length) {
      final chunk = await _raf.read(next.length - filled);
      if (chunk.isEmpty) {
        throw const GgufHeaderException('el archivo GGUF está truncado');
      }
      next.setRange(filled, filled + chunk.length, chunk);
      filled += chunk.length;
    }
    _buffer = next;
    _position = 0;
  }

  Future<int> uint32() async {
    await _ensure(4);
    final value =
        ByteData.sublistView(_buffer, _position, _position + 4).getUint32(0, Endian.little);
    _position += 4;
    consumedBytes += 4;
    return value;
  }

  Future<int> uint64() async {
    await _ensure(8);
    final value =
        ByteData.sublistView(_buffer, _position, _position + 8).getUint64(0, Endian.little);
    _position += 8;
    consumedBytes += 8;
    return value;
  }

  Future<String> string() async {
    final length = await uint64();
    if (length < 0 || length > _maxMetadataBytes) {
      throw const GgufHeaderException('la cabecera del GGUF es demasiado grande');
    }
    await _ensure(length);
    final bytes = Uint8List.sublistView(_buffer, _position, _position + length);
    _position += length;
    consumedBytes += length;
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Salta [count] bytes sin materializarlos en memoria.
  Future<void> skip(int count) async {
    if (count <= 0) return;
    final available = _buffer.length - _position;
    if (available >= count) {
      _position += count;
      consumedBytes += count;
      return;
    }
    if (available > 0) {
      _position = _buffer.length;
      consumedBytes += available;
      count -= available;
    }
    _buffer = Uint8List(0);
    _position = 0;
    final position = await _raf.position();
    await _raf.setPosition(position + count);
    consumedBytes += count;
  }

  Future<void> skipValue(int type) async {
    switch (type) {
      case _typeUint8:
      case _typeInt8:
      case _typeBool:
        await skip(1);
      case _typeUint16:
      case _typeInt16:
        await skip(2);
      case _typeUint32:
      case _typeInt32:
      case _typeFloat32:
        await skip(4);
      case _typeUint64:
      case _typeInt64:
      case _typeFloat64:
        await skip(8);
      case _typeString:
        final length = await uint64();
        if (length < 0 || length > _maxMetadataBytes) {
          throw const GgufHeaderException('la cabecera del GGUF es demasiado grande');
        }
        await skip(length);
      case _typeArray:
        final elementType = await uint32();
        final count = await uint64();
        if (elementType == _typeArray) {
          throw const GgufHeaderException('arrays anidados no soportados');
        }
        if (count > _maxMetadataEntries * 100) {
          throw const GgufHeaderException('cabecera GGUF fuera de rango');
        }
        for (var i = 0; i < count; i++) {
          await skipValue(elementType);
        }
      default:
        throw GgufHeaderException('tipo de metadato GGUF desconocido ($type)');
    }
  }
}
