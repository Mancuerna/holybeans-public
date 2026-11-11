import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/ui/labels/label_renderer.dart';
import 'package:image/image.dart' as image;

class _Options extends LabelImageOptions {
  _Options() : super(size: 1, mode: LabelImageMode.photo);
  int reads = 0;
  @override
  double get contrast {
    reads++;
    return super.contrast;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'label pixel conversion leaves UI and preserves rotated output',
    () async {
      final source = image.Image(width: 16, height: 16);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          final gray = x * 16 + y;
          source.setPixelRgba(x, y, gray, gray, gray, 255);
        }
      }
      final codec = await ui.instantiateImageCodec(image.encodePng(source));
      final graphic = (await codec.getNextFrame()).image;
      addTearDown(graphic.dispose);
      addTearDown(codec.dispose);
      final options = _Options();
      final layout = LabelLayout(
        '',
        LabelPaper.mm50x30,
        graphic: graphic,
        imageOptions: options,
      );
      options.reads = 0;
      final bitmap = await layout.rasterize();
      final rotated = await layout.rasterize(upsideDown: true);
      stdout.writeln('LABEL_UI_CONTRAST_READS ${options.reads}');
      expect(options.reads, 0);
      expect(bitmap.pixels.toSet(), {0, 1});
      expect(rotated.pixels, bitmap.pixels.reversed.toList());
      expect(await layout.rasterize(), same(bitmap));
      for (final output in [bitmap, rotated]) {
        final png = image.decodePng(output.png)!;
        expect(png.width, layout.paper.printableWidth);
        expect(png.height, layout.paper.printableHeight);
        for (var y = 0; y < png.height; y++) {
          for (var x = 0; x < png.width; x++) {
            final color = output.pixels[y * png.width + x] == 1 ? 0 : 255;
            final pixel = png.getPixel(x, y);
            expect(
              (pixel.r, pixel.g, pixel.b, pixel.a),
              (color, color, color, 255),
            );
          }
        }
      }
    },
  );
}
