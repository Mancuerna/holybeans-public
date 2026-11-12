import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/pm240_protocol.dart';

void main() {
  test('single label, row order and MSB-first inverted monochrome pixels', () {
    final pixels = Uint8List(384 * 224);
    pixels[0] = 1;
    pixels[7] = 1;
    pixels[8] = 1;
    pixels[384] = 1;
    pixels[pixels.length - 1] = 1;
    final job = Pm240Protocol.job(pixels);
    final header = ascii.encode(
      'SIZE 50 mm,30 mm\r\nDIRECTION 0,0\r\nCLS\r\nBITMAP 0,8,48,224,1,',
    );
    expect(job.take(header.length), header);
    final raster = job.sublist(header.length, header.length + 48 * 224);
    expect(raster[0], 0x7e);
    expect(raster[1], 0x7f);
    expect(raster[47], 0xff);
    expect(raster[48], 0x7f);
    expect(raster.last, 0xfe);
    expect(
      ascii.decode(job.sublist(header.length + raster.length)),
      '\r\nPRINT 1\r\n',
    );
  });
  test('reject malformed raster before any transport operation', () {
    expect(() => Pm240Protocol.job(Uint8List(3)), throwsArgumentError);
    final invalid = Uint8List(384 * 224)..[3] = 2;
    expect(() => Pm240Protocol.job(invalid), throwsArgumentError);
  });
}
