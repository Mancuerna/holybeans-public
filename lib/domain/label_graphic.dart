import 'dart:convert';
import 'dart:typed_data';

import 'package:holybeans/domain/label_image_options.dart';
import 'package:image/image.dart' as img;

/// A bounded PNG stored with a label template, independently of journal photos.
class LabelGraphic {
  static const maxDimension = 512;
  static const maxBytes = 256 * 1024;

  static Uint8List bytes(String encoded) {
    if (encoded.length > (maxBytes * 4 / 3).ceil() + 4) {
      throw const FormatException('Label image too large');
    }
    final data = base64Decode(encoded);
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (data.length < 33 || data.length > maxBytes) {
      throw const FormatException('Invalid label image');
    }
    for (var i = 0; i < signature.length; i++) {
      if (data[i] != signature[i]) {
        throw const FormatException('Label image must be PNG');
      }
    }
    final header = ByteData.sublistView(data);
    final width = header.getUint32(16);
    final height = header.getUint32(20);
    if (header.getUint32(8) != 13 ||
        header.getUint32(12) != 0x49484452 ||
        width < 1 ||
        height < 1 ||
        width > maxDimension ||
        height > maxDimension) {
      throw const FormatException('Invalid label image dimensions');
    }
    return data;
  }

  static String prepare(Uint8List source) {
    if (source.length < 16 || source.length > 4 * 1024 * 1024) {
      throw const FormatException('Source image too large');
    }
    final decoder = img.findDecoderForData(source);
    final info = decoder?.startDecode(source);
    if (info == null || info.width * info.height > 16 * 1024 * 1024) {
      throw const FormatException('Unsupported label image');
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) throw const FormatException('Invalid image');
    var oriented = img.bakeOrientation(decoded);
    if (oriented.width > maxDimension || oriented.height > maxDimension) {
      oriented = img.copyResize(
        oriented,
        width: oriented.width >= oriented.height ? maxDimension : null,
        height: oriented.height > oriented.width ? maxDimension : null,
        interpolation: img.Interpolation.average,
      );
    }
    final white = img.Image(width: oriented.width, height: oriented.height);
    img.fill(white, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(white, oriented);
    // Preserve gray levels; threshold/dither only at the final print size.
    final gray = img.Image(
      width: white.width,
      height: white.height,
      numChannels: 1,
    );
    for (final pixel in white) {
      final value = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
          .round();
      gray.setPixelR(pixel.x, pixel.y, value);
    }
    final encoded = base64Encode(img.encodePng(gray));
    bytes(encoded);
    return encoded;
  }

  static Uint8List monochrome({
    required Uint8List rgba,
    required int width,
    required LabelImageOptions options,
    ({int left, int top, int right, int bottom})? graphic,
  }) {
    options.validate();
    if (width < 1 || rgba.length % (width * 4) != 0) {
      throw const FormatException('Invalid label raster');
    }
    final height = rgba.length ~/ (width * 4);
    final pixels = Uint8List(width * height);
    double luminance(int i) =>
        (299 * rgba[i * 4] + 587 * rgba[i * 4 + 1] + 114 * rgba[i * 4 + 2]) /
        1000;
    for (var i = 0; i < pixels.length; i++) {
      pixels[i] = luminance(i) < 180 ? 1 : 0;
    }
    if (graphic == null) return pixels;
    final left = graphic.left.clamp(0, width);
    final right = graphic.right.clamp(left, width);
    final top = graphic.top.clamp(0, height);
    final bottom = graphic.bottom.clamp(top, height);
    var errors = List<double>.filled(right - left + 2, 0);
    for (var y = top; y < bottom; y++) {
      final next = List<double>.filled(errors.length, 0);
      for (var x = left; x < right; x++) {
        final i = y * width + x;
        final column = x - left + 1;
        final gray = ((luminance(i) - 128) * options.contrast + 128).clamp(
          0,
          255,
        );
        final photo = options.mode == LabelImageMode.photo;
        final value = gray + (photo ? errors[column] : 0);
        final black = value < (photo ? 128 : 180);
        pixels[i] = black ? 1 : 0;
        if (photo) {
          final error = value - (black ? 0 : 255);
          errors[column + 1] += error * 7 / 16;
          next[column - 1] += error * 3 / 16;
          next[column] += error * 5 / 16;
          next[column + 1] += error / 16;
        }
      }
      errors = next;
    }
    return pixels;
  }
}
