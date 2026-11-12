import 'dart:convert';
import 'dart:typed_data';

enum Pm240Failure { unsupported, noStatus, printer, disconnected, busy }

class Pm240Exception implements Exception {
  const Pm240Exception(this.failure);
  final Pm240Failure failure;
  @override
  String toString() => 'PM240: ${failure.name}';
}

// Independent encoder from Labelnize 4.10.0's PM240 command=7 path.
// Promoted from the physically verified Printer Lab integration.
abstract final class Pm240Protocol {
  static const service = '0000ff00-0000-1000-8000-00805f9b34fb';
  static const tx = '0000ff02-0000-1000-8000-00805f9b34fb';
  static const responses = [
    '0000ff01-0000-1000-8000-00805f9b34fb',
    '0000ff03-0000-1000-8000-00805f9b34fb',
  ];
  static bool matchesName(String? name) =>
      name != null &&
      RegExp(
        r'(^|[^a-z0-9])pm[ _-]?240($|[^a-z0-9])',
        caseSensitive: false,
      ).hasMatch(name);
  static const width = 384;
  static const height = 224;
  static Uint8List get statusQuery => Uint8List.fromList([27, 33, 63, 13, 10]);

  static Uint8List job(Uint8List blackPixels) {
    if (blackPixels.length != width * height ||
        blackPixels.any((pixel) => pixel > 1)) {
      throw ArgumentError('Expected a 384 x 224 monochrome raster');
    }
    final raster = Uint8List(width ~/ 8 * height)
      ..fillRange(0, width ~/ 8 * height, 255);
    for (var i = 0; i < blackPixels.length; i++) {
      if (blackPixels[i] == 1) raster[i ~/ 8] &= ~(128 >> (i % 8));
    }
    // Preserve the loaded roll's gap, density and offset. One manual copy.
    // Mode 1 and inverted bits match Labelnize's uncompressed label path.
    return (BytesBuilder(copy: false)
          ..add(
            ascii.encode(
              'SIZE 50 mm,30 mm\r\nDIRECTION 0,0\r\nCLS\r\nBITMAP 0,8,48,224,1,',
            ),
          )
          ..add(raster)
          ..add(ascii.encode('\r\nPRINT 1\r\n')))
        .takeBytes();
  }
}
