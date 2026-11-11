import 'dart:typed_data';

import 'package:holybeans/domain/label_graphic.dart';
import 'package:holybeans/domain/label_image_options.dart';

typedef LabelRasterRequest = ({
  Uint8List rgba,
  int width,
  LabelImageOptions options,
  ({int left, int top, int right, int bottom})? graphic,
  bool upsideDown,
});

/// Converts engine RGBA into printer dots and opaque preview pixels.
({Uint8List pixels, Uint8List rgba}) prepareLabelRaster(
  LabelRasterRequest input,
) {
  final converted = LabelGraphic.monochrome(
    rgba: input.rgba,
    width: input.width,
    options: input.options,
    graphic: input.graphic,
  );
  final pixels = input.upsideDown ? Uint8List(converted.length) : converted;
  if (input.upsideDown) {
    for (var i = 0; i < pixels.length; i++) {
      pixels[i] = converted[converted.length - i - 1];
    }
  }
  final rgba = Uint8List(pixels.length * 4);
  for (var i = 0; i < pixels.length; i++) {
    final value = pixels[i] == 1 ? 0 : 255;
    final offset = i * 4;
    rgba[offset] = value;
    rgba[offset + 1] = value;
    rgba[offset + 2] = value;
    rgba[offset + 3] = 255;
  }
  return (pixels: pixels, rgba: rgba);
}
