import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/label_graphic.dart';
import 'package:holybeans/domain/label_template.dart';

void main() {
  test('image settings round-trip and legacy templates keep their layout', () {
    const options = LabelImageOptions(
      position: LabelImagePosition.right,
      alignment: LabelImageAlignment.end,
      size: 0.25,
      mode: LabelImageMode.photo,
      contrast: 1.6,
      offsetX: -0.35,
      offsetY: 0.6,
    );
    const template = LabelTemplate(
      id: 'x',
      name: 'X',
      kind: LabelKind.coffee,
      body: '<coffee>',
      imageOptions: options,
    );
    expect(
      LabelTemplate.fromJson(template.toJson()).effectiveImageOptions,
      options,
    );
    final legacyOptions = Map<String, dynamic>.of(options.toJson())
      ..remove('offsetX')
      ..remove('offsetY');
    expect(
      LabelImageOptions.fromJson(legacyOptions),
      options.copyWith(offsetX: 0, offsetY: 0),
    );
    for (final invalid in [double.nan, double.infinity, -1.01, 1.01]) {
      expect(
        () => options.copyWith(offsetX: invalid).validate(),
        throwsFormatException,
      );
      expect(
        () => options.copyWith(offsetY: invalid).validate(),
        throwsFormatException,
      );
    }
    final old = Map<String, dynamic>.of(template.toJson())
      ..remove('imageOptions');
    expect(
      LabelTemplate.fromJson(old).effectiveImageOptions,
      const LabelImageOptions(),
    );
    expect(
      const LabelTemplate(
        id: 'x',
        name: 'X',
        kind: LabelKind.coffee,
        body: '',
      ).effectiveImageOptions.size,
      1,
    );
    for (final invalid in [double.nan, double.infinity, -1.0, 0.0, 1.1]) {
      expect(
        () => options.copyWith(size: invalid).validate(),
        throwsFormatException,
      );
    }
    expect(
      () => options.copyWith(contrast: 3).validate(),
      throwsFormatException,
    );
    expect(
      () =>
          LabelImageOptions.fromJson({...options.toJson(), 'mode': 'unknown'}),
      throwsArgumentError,
    );
  });

  test(
    'logo has solid blacks; photo dithers only the image after contrast',
    () {
      final rgba = Uint8List(40 * 20 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba.setRange(i, i + 4, [128, 128, 128, 255]);
      }
      const area = (left: 0, top: 0, right: 20, bottom: 20);
      final logo = LabelGraphic.monochrome(
        rgba: rgba,
        width: 40,
        options: const LabelImageOptions(),
        graphic: area,
      );
      final photo = LabelGraphic.monochrome(
        rgba: rgba,
        width: 40,
        options: const LabelImageOptions(mode: LabelImageMode.photo),
        graphic: area,
      );
      expect(logo.toSet(), {1});
      final imagePixels = [
        for (var y = 0; y < 20; y++) ...photo.sublist(y * 40, y * 40 + 20),
      ];
      expect(
        imagePixels.where((p) => p == 1).length,
        inInclusiveRange(180, 220),
      );
      for (var y = 0; y < 20; y++) {
        expect(photo.sublist(y * 40 + 20, y * 40 + 40).toSet(), {1});
      }
      for (var i = 0; i < rgba.length; i += 4) {
        rgba.setRange(i, i + 4, [170, 170, 170, 255]);
      }
      final contrast = LabelGraphic.monochrome(
        rgba: rgba,
        width: 40,
        options: const LabelImageOptions(contrast: 2),
        graphic: area,
      );
      expect(contrast.first, 0);
      expect(contrast[20], 1); // Contrast must not affect the text region.
    },
  );
}
