import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/niimbot_protocol.dart';

void main() {
  test(
    'Pro rows use head thirds and zero padding for fractional-byte widths',
    () {
      final full = niimbotImageRows(
        Uint8List(576)..fillRange(0, 576, 1),
        576,
        model: LabelPrinterModel.b1Pro,
      ).single;
      expect(full.payload.take(6), [0, 0, 192, 192, 192, 1]);
      expect(full.payload, hasLength(78));
      final narrow = niimbotImageRows(
        Uint8List(354)..fillRange(0, 354, 1),
        354,
        model: LabelPrinterModel.b2Pro,
      ).single;
      expect(narrow.payload.take(6), [0, 0, 192, 162, 0, 1]);
      expect(narrow.payload, hasLength(51));
      expect(narrow.payload.last, 192);
    },
  );

  test('B1 keeps top orientation and full-head thirds on narrower paper', () {
    final pixels = Uint8List(320 * 2);
    pixels[0] = pixels[128] = pixels[256] = pixels[319] = 1;
    final rows = niimbotImageRows(pixels, 320, model: LabelPrinterModel.b1);
    expect(rows.first.payload.take(6), [0, 0, 1, 1, 2, 1]);
    expect(rows.first.payload, hasLength(46));
    expect(rows.first.payload[6], 128);
    expect(rows.first.payload[22], 128);
    expect(rows.first.payload[38], 128);
    expect(rows.first.payload.last, 1);
    expect(rows.last.command, 0x84);
    final black = niimbotImageRows(
      Uint8List(384)..fillRange(0, 384, 1),
      384,
      model: LabelPrinterModel.b1,
    ).single;
    expect(black.payload.take(6), [0, 0, 128, 128, 128, 1]);
    expect(
      () => niimbotImageRows(Uint8List(400), 400, model: LabelPrinterModel.b1),
      throwsFormatException,
    );
    expect(LabelPrinterModel.b1.matchesName('B1-TEST'), isTrue);
    expect(LabelPrinterModel.b1.matchesName('B1'), isTrue);
    for (final name in ['B1_PRO-X', 'B1SE-X', 'D110-X']) {
      expect(LabelPrinterModel.b1.matchesName(name), isFalse);
    }
  });

  test('known wire packets have the prefix, XOR and big-endian size', () {
    expect(NiimbotPacket(0xc1, [1]).encode(), [
      3,
      0x55,
      0x55,
      0xc1,
      1,
      1,
      0xc1,
      0xaa,
      0xaa,
    ]);
    expect(NiimbotPacket(0x13, [0, 240, 0, 96]).encode(), [
      0x55,
      0x55,
      0x13,
      4,
      0,
      240,
      0,
      96,
      0x87,
      0xaa,
      0xaa,
    ]);
  });

  test('decodes fragmented and coalesced replies, recovering from bad XOR', () {
    final good = NiimbotPacket(0x48, [9, 0]).encode();
    final bad = Uint8List.fromList(good)..[6] ^= 1;
    for (var split = 0; split <= good.length; split++) {
      final decoder = NiimbotDecoder();
      final packets = [
        ...decoder.add([0, 4, ...bad, ...good.take(split)]),
        ...decoder.add([
          ...good.skip(split),
          ...NiimbotPacket(0x02, [1]).encode(),
        ]),
      ];
      expect(packets.map((p) => p.command), [0x48, 0x02]);
      expect(packets.first.payload, [9, 0]);
    }
  });

  test('raster turns clockwise with correct dot counts and blank rows', () {
    final pixels = Uint8List(240 * 96);
    pixels[95 * 240] = 1; // bottom left -> first feed row, first dot
    pixels[63 * 240] = 1; // middle third
    pixels[31 * 240] = 1; // last third
    pixels[239] = 1; // top right -> last feed row, last dot
    final rows = niimbotImageRows(pixels, 240);
    expect(rows, hasLength(240));
    expect(rows.first.command, 0x85);
    expect(rows.first.payload.take(6), [0, 0, 1, 1, 1, 1]);
    expect(rows.first.payload.skip(6), [
      128,
      0,
      0,
      0,
      128,
      0,
      0,
      0,
      128,
      0,
      0,
      0,
    ]);
    expect(rows[1].command, 0x84);
    expect(rows[1].payload, [0, 1, 1]);
    expect(rows.last.payload.take(6), [0, 239, 0, 0, 1, 1]);
    expect(rows.last.payload.last, 1);
  });

  test('rejects unsupported models and invalid rasters', () {
    expect(isNiimbotD110('D110-F519042406'), isTrue);
    for (final name in ['D110_M-X', 'D110M-X', 'D11-X', 'B1-X', null]) {
      expect(isNiimbotD110(name), isFalse);
    }
    expect(() => niimbotImageRows(Uint8List(96), 30), throwsFormatException);
    expect(
      () => niimbotImageRows(Uint8List(96)..[0] = 255, 1),
      throwsFormatException,
    );
  });
}
