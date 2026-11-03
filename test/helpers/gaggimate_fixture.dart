import 'dart:convert';
import 'dart:typed_data';

// Synthetic wire recordings, assembled independently from the production decoder.
const gaggimateEpoch = 1791121751;
Uint8List gaggimateIndex({int flags = 1, int count = 1}) {
  final bytes = Uint8List(32 + count * 128);
  final b = ByteData.sublistView(bytes);
  b.setUint32(0, 0x58444953, Endian.little);
  b.setUint16(4, 1, Endian.little);
  b.setUint16(6, 128, Endian.little);
  b.setUint32(8, count, Endian.little);
  for (var i = 0; i < count; i++) {
    final offset = 32 + 128 * i;
    b.setUint32(offset, 31 + i, Endian.little);
    b.setUint32(offset + 4, gaggimateEpoch + i, Endian.little);
    b.setUint32(offset + 8, 32000, Endian.little);
    b.setUint16(offset + 12, 365, Endian.little);
    b.setUint8(offset + 15, flags);
    bytes.setRange(
      offset + 48,
      offset + 48 + utf8.encode('Café test').length,
      utf8.encode('Café test'),
    );
  }
  return bytes;
}

Uint8List gaggimateLog({
  int version = 8,
  bool legacyV6 = false,
  bool scale = true,
  bool dropScale = false,
  int peak = 90,
}) {
  final wide = version >= 6 && !legacyV6;
  final fields = version >= 7 ? 14 : 13;
  final size = fields * 2 + (wide ? 2 : 0);
  final header = version < 5 ? 128 : 512;
  final bytes = Uint8List(header + size * 5);
  final b = ByteData.sublistView(bytes);
  b.setUint32(0, 0x544f4853, Endian.little);
  b.setUint8(4, version);
  b.setUint8(5, size);
  b.setUint16(6, header, Endian.little);
  b.setUint16(8, 250, Endian.little);
  b.setUint32(12, (1 << fields) - 1, Endian.little);
  b.setUint32(16, 5, Endian.little);
  b.setUint32(20, 32000, Endian.little);
  b.setUint32(24, gaggimateEpoch, Endian.little);
  final profile = utf8.encode('Café test');
  bytes.setRange(60, 60 + profile.length, profile);
  b.setUint16(
    108,
    450,
    Endian.little,
  ); // Deliberately differs from last scale reading.
  if (version >= 5) {
    b.setUint8(458, 2);
    final pre = utf8.encode('Preinfusion');
    bytes.setRange(114, 114 + pre.length, pre);
    b.setUint16(139, 2, Endian.little);
    bytes.setRange(143, 147, utf8.encode('Brew'));
  }
  const times = [0, 4000, 8000, 30000, 32000];
  const weights = [0, 1, 20, 360, 365];
  for (var i = 0; i < 5; i++) {
    var offset = header + i * size;
    final active = scale && !(dropScale && i == 2);
    final flags =
        (active ? (version >= 8 || legacyV6 ? 0x100 : 4) : 0) |
        (i >= 3 ? 16 : 0);
    final values = [
      wide ? times[i] : times[i] ~/ 250,
      930,
      925,
      90,
      i >= 3 ? 0 : peak,
      300,
      200,
      150,
      120,
      weights[i],
      999,
      1,
      flags,
      500,
    ];
    for (var f = 0; f < fields; f++) {
      if (f == 0 && wide) {
        b.setUint32(offset, values[f], Endian.little);
        offset += 4;
      } else {
        b.setUint16(offset, values[f], Endian.little);
        offset += 2;
      }
    }
  }
  return bytes;
}
