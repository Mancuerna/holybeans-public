import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Longest side, in pixels, of the photos HolyBeans keeps; the camera and
/// gallery picker use the same size.
const photoMaxPixels = 1600;

/// How many photos [shrinkEach] works on at once: the platform decodes
/// them side by side and each JPEG is encoded in its own isolate. A few
/// are enough to keep the cores busy without holding many full-size
/// photos in memory.
const photosInParallel = 3;

/// [bytes] of a photo taken elsewhere, upright, at most [photoMaxPixels]
/// on its longest side and in JPEG, as HolyBeans keeps its own.
///
/// The platform's decoder reads it straight at the size kept (a JPEG
/// decoder then skips most of the work) and turns it upright; the JPEG is
/// encoded off the UI thread. What the platform cannot read goes through
/// the slower Dart decoder, and an image neither reads is returned as it
/// came.
Future<Uint8List> shrinkPhoto(Uint8List bytes) async {
  final pixels = await _decodeScaled(bytes);
  if (pixels == null) return compute(_shrink, bytes);
  return compute(_encode, pixels);
}

/// Shrinks each of [photos] with [shrinkPhoto], [photosInParallel] at a
/// time, and hands it to [keep] as soon as it is ready, so only a few
/// full-size photos are in memory at once.
Future<void> shrinkEach(
  Iterable<MapEntry<String, Uint8List>> photos,
  Future<void> Function(String name, Uint8List shrunk) keep,
) async {
  final queue = photos.iterator;
  Future<void> worker() async {
    while (queue.moveNext()) {
      final MapEntry(:key, :value) = queue.current;
      await keep(key, await shrinkPhoto(value));
    }
  }

  await Future.wait([for (var i = 0; i < photosInParallel; i++) worker()]);
}

typedef _Pixels = ({int width, int height, Uint8List rgba});

/// [bytes] decoded by the platform, upright and scaled to fit
/// [photoMaxPixels]; null when the platform cannot read them.
Future<_Pixels?> _decodeScaled(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    // The descriptor's size already accounts for the EXIF rotation.
    final width = descriptor.width;
    final height = descriptor.height;
    final scale = math.min(1, photoMaxPixels / math.max(width, height));
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (width * scale).round()),
      targetHeight: math.max(1, (height * scale).round()),
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData();
    if (data == null) return null;
    return (
      width: image.width,
      height: image.height,
      rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } on Object {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Uint8List _encode(_Pixels pixels) => img.encodeJpg(
  img.Image.fromBytes(
    width: pixels.width,
    height: pixels.height,
    bytes: pixels.rgba.buffer,
    numChannels: 4,
  ),
  quality: 82,
);

Uint8List _shrink(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    decoded = null;
  }
  if (decoded == null) return bytes;
  // Phones store the camera's rotation in EXIF; bake it into the pixels.
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > photoMaxPixels) {
    image = image.width >= image.height
        ? img.copyResize(image, width: photoMaxPixels)
        : img.copyResize(image, height: photoMaxPixels);
  }
  return img.encodeJpg(image, quality: 82);
}
