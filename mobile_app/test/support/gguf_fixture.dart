import 'dart:convert';
import 'dart:typed_data';

/// Construye un GGUF v3 mínimo (sin tensores) con la arquitectura indicada.
///
/// Solo incluye los metadatos que la sonda necesita, para probar
/// `readGgufInfo` sin depender de un archivo real de cientos de MB.
List<int> buildGguf({
  required String architecture,
  bool includeArchitecture = true,
  int version = 3,
}) {
  final out = BytesBuilder();
  final header = ByteData(8)
    ..setUint32(0, 0x46554747, Endian.little) // "GGUF"
    ..setUint32(4, version, Endian.little);
  out.add(header.buffer.asUint8List());

  void u64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void string(String value) {
    final bytes = utf8.encode(value);
    u64(bytes.length);
    out.add(bytes);
  }

  u64(0); // cantidad de tensores
  u64(includeArchitecture ? 2 : 1);

  string('general.name');
  u32(8); // tipo string
  string('modelo de prueba');

  if (includeArchitecture) {
    string('general.architecture');
    u32(8);
    string(architecture);
  }

  return out.toBytes();
}
