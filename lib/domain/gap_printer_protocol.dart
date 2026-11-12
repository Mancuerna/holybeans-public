import 'dart:typed_data';

import 'package:holybeans/domain/marklife_protocol.dart';

enum GapPrinterModel {
  p15('Pristar P15'),
  fichero('Fichero 5836');

  const GapPrinterModel(this.label);
  final String label;
  bool matchesName(String? name) =>
      name != null &&
      RegExp(
        this == p15
            ? r'^(?:(?:Pristar|Marklife)[ _-]+)?P15(?:[ _-]|$)'
            : r'^FICHERO[ _-]5836(?:[ _-]|$)',
        caseSensitive: false,
      ).hasMatch(name);

  Uint8List job(Uint8List pixels, int lengthMm, MarklifePaper media) {
    if (!const [30, 40].contains(lengthMm) || media != MarklifePaper.gap) {
      throw const MarklifeException(MarklifeFailure.unsupported);
    }
    final l11 = MarklifeProtocol.job(pixels, lengthMm, media);
    if (this == p15) return l11;
    // Independent AiYin D11s encoder from the FICHERO_5836 wire reference:
    // https://github.com/0xMH/fichero-printer/blob/main/docs/PROTOCOL.md
    // Reuse only the rotated GS v 0 header/raster, never the L11 commands.
    // Preserve the printer's density and loaded gap-media setting.
    return Uint8List.fromList([
      ...List<int>.filled(12, 0),
      0x10,
      0xff,
      0xfe,
      0x01,
      ...l11.sublist(19, l11.length - 6),
      0x1d,
      0x0c,
      0x10,
      0xff,
      0xfe,
      0x45,
    ]);
  }

  // AiYin reports an error bitmask, unlike the L11 sequential status codes.
  static MarklifeFailure? ficheroError(Uint8List bytes) {
    if (bytes.length != 2 || bytes[0] != 0xff) return null;
    final bits = bytes[1];
    if (bits & 1 != 0) return MarklifeFailure.hot;
    if (bits & 2 != 0) return MarklifeFailure.cover;
    if (bits & 4 != 0) return MarklifeFailure.paper;
    if (bits & 8 != 0) return MarklifeFailure.battery;
    return null;
  }

  static bool ficheroAck(Uint8List bytes) =>
      (bytes.length == 1 && bytes[0] == 0xaa) ||
      (bytes.length == 2 && bytes[0] == 0x4f && bytes[1] == 0x4b);
}
