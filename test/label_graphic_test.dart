import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/label_graphic.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:image/image.dart' as img;

void main() {
  test('images are bounded and preserve gray for conversion at print size', () {
    final source = img.Image(width: 1024, height: 256, numChannels: 4);
    img.fillRect(
      source,
      x1: 0,
      y1: 0,
      x2: 255,
      y2: 255,
      color: img.ColorRgba8(0, 0, 0, 255),
    );
    img.fillRect(
      source,
      x1: 256,
      y1: 0,
      x2: 511,
      y2: 255,
      color: img.ColorRgba8(128, 128, 128, 255),
    );
    final encoded = LabelGraphic.prepare(img.encodePng(source));
    final output = img.decodePng(LabelGraphic.bytes(encoded))!;
    expect(output.width, 512);
    expect(output.height, 128);
    expect(output.getPixel(10, 10).r, 0);
    expect(output.getPixel(500, 10).r, 255);
    final gray = [
      for (var y = 10; y < 110; y++)
        for (var x = 140; x < 240; x++) output.getPixel(x, y).r,
    ];
    expect(gray.toSet(), {128});
    expect(
      output.convert(numChannels: 3).every((p) => p.r == p.g && p.g == p.b),
      isTrue,
    );
  });

  test('invalid and oversized inputs cannot become template images', () {
    expect(
      () => LabelGraphic.prepare(Uint8List.fromList([1, 2])),
      throwsFormatException,
    );
    final source = img.encodePng(img.Image(width: 2, height: 2));
    final oversized = Uint8List.fromList(source);
    ByteData.sublistView(oversized).setUint32(16, 100000);
    expect(
      () => LabelGraphic.bytes(base64Encode(oversized)),
      throwsFormatException,
    );
    expect(
      () => const LabelTemplate(
        id: 'x',
        name: 'x',
        kind: LabelKind.coffee,
        body: '',
        imagePng: 'invalid',
      ).validate(),
      throwsFormatException,
    );
    const empty = LabelTemplate(
      id: 'x',
      name: 'x',
      kind: LabelKind.coffee,
      body: '',
    );
    expect(empty.validate, throwsFormatException);
    final imageOnly = LabelTemplate(
      id: 'x',
      name: 'x',
      kind: LabelKind.coffee,
      body: '',
      imagePng: LabelGraphic.prepare(source),
    );
    expect(
      LabelTemplate.fromJson(imageOnly.toJson()).imagePng,
      imageOnly.imagePng,
    );
    expect(
      LabelTemplate.fromJson({
        'id': 'old',
        'name': 'Old',
        'kind': 'coffee',
        'body': '<coffee>',
      }).imagePng,
      isNull,
    );
  });
}
