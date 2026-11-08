import 'dart:typed_data';

enum MarklifePaper { gap, continuous }

enum MarklifeFailure {
  disconnected,
  busy,
  unsupported,
  credits,
  unconfirmed,
  paper,
  cover,
  hot,
  battery,
}

class MarklifeException implements Exception {
  const MarklifeException(this.failure);
  final MarklifeFailure failure;
  @override
  String toString() => 'Marklife: ${failure.name}';
}

class MarklifeProtocol {
  static const service = '0000ff00-0000-1000-8000-00805f9b34fb';
  static const rx = '0000ff01-0000-1000-8000-00805f9b34fb';
  static const tx = '0000ff02-0000-1000-8000-00805f9b34fb';
  static const control = '0000ff03-0000-1000-8000-00805f9b34fb';
  static const headDots = 96;
  static const lengthsMm = [30, 40, 50];

  static bool matchesName(String? name) =>
      name != null &&
      RegExp(
        r'^(?:(?:Pristar|Marklife)[ _-]+)?P12(?:[ _-]|$)',
        caseSensitive: false,
      ).hasMatch(name);

  // Independent L11 encoder from the published wire specification:
  // https://thermal-label.github.io/marklife/protocol/l11
  // The preview is landscape (feed length x 96). Rotate clockwise into
  // 12-byte head rows, MSB first, with one denoting a dark dot.
  static Uint8List job(Uint8List pixels, int lengthMm, MarklifePaper paper) {
    final width = lengthMm * 8;
    if (!lengthsMm.contains(lengthMm) ||
        pixels.length != width * headDots ||
        pixels.any((p) => p > 1)) {
      throw const MarklifeException(MarklifeFailure.unsupported);
    }
    final rows = Uint8List(width * 12);
    for (var y = 0; y < headDots; y++) {
      for (var x = 0; x < width; x++) {
        if (pixels[y * width + x] == 1) {
          final headX = headDots - 1 - y;
          rows[x * 12 + headX ~/ 8] |= 0x80 >> (headX % 8);
        }
      }
    }
    return Uint8List.fromList([
      ...List<int>.filled(15, 0),
      0x10,
      0xff,
      0xf1,
      0x02,
      0x1d,
      0x76,
      0x30,
      0,
      12,
      0,
      width & 255,
      width >> 8,
      ...rows,
      if (paper == MarklifePaper.gap) ...[0x1d, 0x0c] else ...[0x1b, 0x4a, 100],
      0x10,
      0xff,
      0xf1,
      0x45,
    ]);
  }
}
