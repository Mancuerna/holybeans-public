import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/photo_resizer.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'photos from elsewhere are shrunk to the size HolyBeans keeps',
    () async {
      final wide = img.encodeJpg(img.Image(width: 3200, height: 2400));
      final shrunk = img.decodeJpg(await shrinkPhoto(wide))!;
      expect((shrunk.width, shrunk.height), (1600, 1200));

      final tall = img.encodePng(img.Image(width: 900, height: 2000));
      final upright = img.decodeJpg(await shrinkPhoto(tall))!;
      expect((upright.width, upright.height), (720, 1600));

      final small = img.encodeJpg(img.Image(width: 400, height: 300));
      expect(img.decodeJpg(await shrinkPhoto(small))!.width, 400);

      // A camera photo stored sideways with its rotation in EXIF.
      final sideways = img.Image(width: 3200, height: 1600);
      img.fillRect(
        sideways,
        x1: 0,
        y1: 0,
        x2: 1599,
        y2: 1599,
        color: img.ColorRgb8(255, 0, 0),
      );
      sideways.exif.imageIfd.orientation = 6;
      final turned = img.decodeJpg(await shrinkPhoto(img.encodeJpg(sideways)))!;
      expect((turned.width, turned.height), (800, 1600));
      // Turned clockwise, the red left half ends up on top.
      expect(turned.getPixel(400, 200).r, greaterThan(200));
      expect(turned.getPixel(400, 1400).r, lessThan(60));

      // Something that is not an image is kept as it came.
      final notImage = await shrinkPhoto(Uint8List.fromList([1, 2, 3]));
      expect(notImage, [1, 2, 3]);
    },
  );

  test('several photos are shrunk at once and each is kept once', () async {
    final photos = {
      for (var i = 0; i < 7; i++)
        'photo_$i.jpg': img.encodeJpg(img.Image(width: 2000 + i, height: 1000)),
    };
    var running = 0;
    var most = 0;
    final kept = <String, int>{};
    await shrinkEach(photos.entries, (name, bytes) async {
      most = running + 1 > most ? running + 1 : most;
      running++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      running--;
      kept[name] = img.decodeJpg(bytes)!.width;
    });
    expect(kept.keys, unorderedEquals(photos.keys));
    expect(kept.values, everyElement(1600));
    expect(most, lessThanOrEqualTo(photosInParallel));
  });
}
