import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/marklife_protocol.dart';

void main() {
  test('P12 discovery excludes different models and ambiguous suffixes', () {
    for (final name in [
      'P12',
      'P12_123_BLE',
      'P12-ABCD',
      'Pristar P12',
      'Marklife P12',
    ]) {
      expect(MarklifeProtocol.matchesName(name), isTrue);
    }
    for (final name in [null, 'P120', 'P12Pro', 'P15', 'D110', 'Other P12']) {
      expect(MarklifeProtocol.matchesName(name), isFalse);
    }
  });
  test('96-dot raster rotates asymmetric corners and packs MSB-first', () {
    final pixels = Uint8List(320 * 96);
    pixels[0] = 1;
    pixels[95 * 320] = 1;
    pixels[7 * 320 + 319] = 1;
    final job = MarklifeProtocol.job(pixels, 40, MarklifePaper.gap);
    expect(job.take(27), [
      ...List.filled(15, 0),
      0x10,
      0xff,
      0xf1,
      2,
      0x1d,
      0x76,
      0x30,
      0,
      12,
      0,
      0x40,
      1,
    ]);
    final rows = job.sublist(27, 27 + 3840);
    expect(rows[0], 0x80);
    expect(rows[11], 0x01);
    expect(rows[319 * 12 + 11], 0x80);
    expect(rows.where((byte) => byte != 0), hasLength(3));
    expect(job.skip(27 + 3840), [0x1d, 0x0c, 0x10, 0xff, 0xf1, 0x45]);
  });
  test('continuous media feeds once and ends once without calibration', () {
    final job = MarklifeProtocol.job(
      Uint8List(240 * 96),
      30,
      MarklifePaper.continuous,
    );
    expect(job.skip(27 + 2880), [0x1b, 0x4a, 100, 0x10, 0xff, 0xf1, 0x45]);
    expect(job.length, 27 + 2880 + 7);
  });
  test('invalid dimensions and nonbinary raster are rejected', () {
    for (final (pixels, length) in [
      (Uint8List(1), 40),
      (Uint8List(800 * 96), 100),
      (Uint8List(320 * 96)..[0] = 2, 40),
    ]) {
      expect(
        () => MarklifeProtocol.job(pixels, length, MarklifePaper.gap),
        throwsA(isA<MarklifeException>()),
      );
    }
  });
}
