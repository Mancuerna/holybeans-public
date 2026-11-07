import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/ui/labels/label_renderer.dart';
import 'package:image/image.dart' as image;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, asset) in [
      ('Plex', 'assets/fonts/IBMPlexSans-Regular.ttf'),
      ('NotoEmoji', 'assets/fonts/NotoEmoji.ttf'),
    ]) {
      final loader = FontLoader(family)..addFont(rootBundle.load(asset));
      await loader.load();
    }
  });
  test(
    'side images leave separate text space and preview equals print bitmap',
    () async {
      final source = image.Image(width: 20, height: 10);
      final codec = await ui.instantiateImageCodec(image.encodePng(source));
      final graphic = (await codec.getNextFrame()).image;
      addTearDown(graphic.dispose);
      addTearDown(codec.dispose);
      for (final model in LabelPrinterModel.values) {
        for (final position in LabelImagePosition.values) {
          final layout = LabelLayout(
            'Café\nBrasil',
            model.defaultPaper,
            graphic: graphic,
            imageOptions: LabelImageOptions(position: position, size: 0.25),
          );
          expect(layout.fitsPaper, isTrue);
          if (position == LabelImagePosition.top) {
            expect(layout.graphicBounds.overlaps(layout.textBounds), isFalse);
          } else {
            for (final line in layout.textLines) {
              expect(layout.graphicBounds.overlaps(line.bounds), isFalse);
            }
          }
          expect(
            layout.graphicBounds.width / layout.graphicBounds.height,
            closeTo(2, 0.1),
          );
          final preview = await layout.previewBitmap;
          expect(await layout.rasterize(), same(preview));
          expect(preview.pixels, contains(1));
        }
      }
      final top = LabelLayout(
        'Coffee',
        LabelPaper.mm50x30,
        graphic: graphic,
        imageOptions: const LabelImageOptions(
          position: LabelImagePosition.left,
          alignment: LabelImageAlignment.start,
          size: 0.25,
        ),
      );
      final bottom = LabelLayout(
        'Coffee',
        LabelPaper.mm50x30,
        graphic: graphic,
        imageOptions: const LabelImageOptions(
          position: LabelImagePosition.left,
          alignment: LabelImageAlignment.end,
          size: 0.25,
        ),
      );
      expect(top.graphicBounds.top, lessThan(bottom.graphicBounds.top));
      final imageOnlyLeft = LabelLayout(
        '',
        LabelPaper.mm50x30,
        graphic: graphic,
        imageOptions: const LabelImageOptions(
          size: 0.25,
          alignment: LabelImageAlignment.start,
        ),
      );
      final imageOnlyRight = LabelLayout(
        '',
        LabelPaper.mm50x30,
        graphic: graphic,
        imageOptions: const LabelImageOptions(
          size: 0.25,
          alignment: LabelImageAlignment.end,
        ),
      );
      expect(imageOnlyLeft.graphicBounds.left, closeTo(4, 0.01));
      expect(imageOnlyRight.graphicBounds.right, closeTo(380, 0.01));
      expect(
        imageOnlyLeft.graphicBounds.width,
        imageOnlyRight.graphicBounds.width,
      );
      final fullWidthImage = LabelLayout(
        'Coffee',
        LabelPaper.mm50x30,
        graphic: graphic,
        imageOptions: const LabelImageOptions(
          position: LabelImagePosition.left,
          alignment: LabelImageAlignment.start,
          size: 1,
        ),
      );
      expect(fullWidthImage.fitsPaper, isTrue);
      expect(
        fullWidthImage.textLines.single.bounds.top,
        greaterThanOrEqualTo(fullWidthImage.graphicBounds.bottom + 4),
      );
      expect((await fullWidthImage.rasterize()).png, isNotEmpty);
    },
  );
  test(
    'image offsets move both axes and keep text clear on every printer',
    () async {
      final source = image.Image(width: 20, height: 10);
      final codec = await ui.instantiateImageCodec(image.encodePng(source));
      final graphic = (await codec.getNextFrame()).image;
      addTearDown(graphic.dispose);
      addTearDown(codec.dispose);
      for (final model in LabelPrinterModel.values) {
        for (final position in LabelImagePosition.values) {
          LabelLayout layout(double x, double y, {String body = 'Coffee'}) =>
              LabelLayout(
                body,
                model.defaultPaper,
                graphic: graphic,
                imageOptions: LabelImageOptions(
                  position: position,
                  size: 0.25,
                  offsetX: x,
                  offsetY: y,
                ),
              );
          final start = layout(-1, -1);
          final end = layout(1, 1);
          expect(start.graphicBounds.left, lessThan(end.graphicBounds.left));
          expect(start.graphicBounds.top, lessThan(end.graphicBounds.top));
          for (final x in [-1.0, -0.4, 0.0, 0.6, 1.0]) {
            for (final y in [-1.0, -0.4, 0.0, 0.6, 1.0]) {
              for (final body in ['Coffee', '']) {
                final shifted = layout(x, y, body: body);
                final rect = shifted.graphicBounds;
                final area = shifted.contentBounds.inflate(0.5 / shifted.scale);
                expect(rect.left, greaterThanOrEqualTo(area.left));
                expect(rect.top, greaterThanOrEqualTo(area.top));
                expect(rect.right, lessThanOrEqualTo(area.right));
                expect(rect.bottom, lessThanOrEqualTo(area.bottom));
                expect(
                  rect.width,
                  closeTo(
                    layout(0, 0, body: body).graphicBounds.width,
                    1 / shifted.scale + 1e-9,
                  ),
                );
                if (position == LabelImagePosition.top) {
                  if (body.isNotEmpty) {
                    expect(rect.overlaps(shifted.textBounds), isFalse);
                  }
                } else {
                  for (final line in shifted.textLines) {
                    expect(rect.overlaps(line.bounds), isFalse);
                  }
                }
              }
            }
          }
          final shifted = layout(-0.4, 0.6, body: '');
          final preview = await shifted.previewBitmap;
          expect(await shifted.rasterize(), same(preview));
          expect(
            preview.pixels,
            isNot((await layout(0, 0, body: '').rasterize()).pixels),
          );
          expect(
            (await shifted.rasterize(upsideDown: true)).pixels,
            preview.pixels.reversed.toList(),
          );
        }
      }
      final overflowing = LabelLayout(
        'Coffee',
        LabelPaper.mm50x30,
        graphic: graphic,
        imageOptions: const LabelImageOptions(offsetY: 1),
      );
      expect(overflowing.fitsPaper, isFalse);
      await expectLater(overflowing.rasterize(), throwsStateError);
    },
  );
  test(
    'emoji clusters render directly in monochrome with distinct glyphs',
    () async {
      final rasters = <String>{};
      for (final emoji in ['☕️', '🍒', '😀', '🇭🇳', '👩🏽‍🌾', '1️⃣']) {
        final layout = LabelLayout(emoji, LabelPaper.mm50x30);
        final recorder = ui.PictureRecorder();
        layout.paint(ui.Canvas(recorder));
        final picture = recorder.endRecording();
        final image = await picture.toImage(384, 240);
        final bytes = (await image.toByteData())!;
        image.dispose();
        picture.dispose();
        for (var i = 0; i < bytes.lengthInBytes; i += 4) {
          expect(bytes.getUint8(i), bytes.getUint8(i + 1));
          expect(bytes.getUint8(i), bytes.getUint8(i + 2));
        }
        final bitmap = await layout.rasterize();
        expect(bitmap.pixels.toSet(), {0, 1});
        rasters.add(bitmap.pixels.join());
      }
      expect(rasters, hasLength(6));
    },
  );
  test(
    'color conversion uses luminance rather than only the red channel',
    () async {
      final source = image.Image(width: 2, height: 1)
        ..setPixelRgb(0, 0, 255, 0, 0)
        ..setPixelRgb(1, 0, 40, 255, 255);
      final codec = await ui.instantiateImageCodec(image.encodePng(source));
      final graphic = (await codec.getNextFrame()).image;
      try {
        final bitmap = await LabelLayout(
          '',
          LabelPaper.mm50x30,
          graphic: graphic,
        ).rasterize();
        expect(bitmap.pixels[120 * 384 + 96], 1);
        expect(bitmap.pixels[120 * 384 + 288], 0);
      } finally {
        graphic.dispose();
        codec.dispose();
      }
    },
  );
  test('300 dpi preserves physical font sizing and rejects overflow', () {
    final base = LabelLayout('Coffee\nRoaster', LabelPaper.mm50x30);
    for (final model in [LabelPrinterModel.b1Pro, LabelPrinterModel.b2Pro]) {
      final pro = LabelLayout('Coffee\nRoaster', model.defaultPaper);
      expect(pro.fontSize, base.fontSize);
      expect(
        pro.fontSize * pro.scale / model.pixelsPerMm,
        closeTo(base.fontSize / 8, 0.001),
      );
      final overflow = LabelLayout(
        List.filled(60, 'Coffee').join('\n'),
        model.defaultPaper,
      );
      expect(overflow.fitsPaper, isFalse);
      expect(overflow.rasterize(), throwsStateError);
    }
  });
  test(
    'B1 image and text raster uses its paper dimensions and preserves aspect',
    () async {
      final source = image.Image(width: 20, height: 10);
      final codec = await ui.instantiateImageCodec(image.encodePng(source));
      final graphic = (await codec.getNextFrame()).image;
      addTearDown(graphic.dispose);
      addTearDown(codec.dispose);
      for (final paper in [
        ...LabelPrinterModel.values
            .where((m) => m != LabelPrinterModel.d110)
            .map((m) => m.defaultPaper),
        LabelPaper.mm40x40,
        LabelPaper.mm15x30,
      ]) {
        final layout = LabelLayout('', paper, graphic: graphic);
        final bitmap = await layout.rasterize();
        final output = image.decodePng(bitmap.png)!;
        expect(output.width, paper.printableWidth);
        expect(output.height, paper.printableHeight);
        expect(bitmap.pixels, contains(1));
        final black = <(int, int)>[];
        for (var y = 0; y < output.height; y++) {
          for (var x = 0; x < output.width; x++) {
            expect(
              output.getPixel(x, y).r,
              bitmap.pixels[y * output.width + x] == 1 ? 0 : 255,
            );
            if (bitmap.pixels[y * output.width + x] == 1) black.add((x, y));
          }
        }
        final width =
            black.map((p) => p.$1).reduce((a, b) => a > b ? a : b) -
            black.map((p) => p.$1).reduce((a, b) => a < b ? a : b) +
            1;
        final height = black.last.$2 - black.first.$2 + 1;
        expect(width / height, closeTo(2, 0.03));
        expect(
          LabelLayout('Coffee', paper, graphic: graphic).fitsPaper,
          isTrue,
        );
        expect(
          LabelLayout(
            List.filled(60, 'Coffee').join('\n'),
            paper,
            graphic: graphic,
          ).fitsPaper,
          isFalse,
        );
      }
    },
  );

  test('three lines fit but excess content is blocked before rasterizing', () {
    expect(
      LabelLayout(
        '**Coffee**\nRoaster\n20/10/2026',
        LabelPaper.mm15x30,
      ).fitsPaper,
      isTrue,
    );
    final overflow = LabelLayout(
      List.filled(20, 'Coffee').join('\n'),
      LabelPaper.mm15x30,
    );
    expect(overflow.fitsPaper, isFalse);
    expect(overflow.rasterize(), throwsStateError);
  });

  test(
    'raster has exact head dimensions, binary dots and matching PNG',
    () async {
      final layout = LabelLayout('**Café**\nTueste 20/10', LabelPaper.mm15x30);
      final bitmap = await layout.rasterize();
      final decoded = image.decodePng(bitmap.png)!;
      expect(decoded.width, 240);
      expect(decoded.height, 96);
      expect(bitmap.pixels, hasLength(240 * 96));
      expect(bitmap.pixels.toSet(), {0, 1});
      for (var y = 0; y < 96; y++) {
        for (var x = 0; x < 240; x++) {
          expect(
            decoded.getPixel(x, y).r,
            bitmap.pixels[y * 240 + x] == 1 ? 0 : 255,
          );
        }
      }
      final rotated = await layout.rasterize(upsideDown: true);
      expect(rotated.pixels, bitmap.pixels.reversed.toList());
    },
  );
}
